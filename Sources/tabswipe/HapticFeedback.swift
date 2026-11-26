import AppKit
import Darwin
import Foundation
import IOKit

/// Triggers crisp Taptic Engine detent clicks on Force Touch trackpads from a headless daemon.
///
/// Uses dynamic loading (`dlopen`/`dlsym`) of `MultitouchSupport.framework` (`MTActuator*`) with
/// `IOKit` device discovery so haptics work reliably even when running under
/// `NSApplication.ActivationPolicy.prohibited`. Falls back to `NSHapticFeedbackManager` if
/// `MultitouchSupport` is unavailable.
final class HapticFeedback {
    private typealias ActuatorCreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias ActuatorOpenFn = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuatorCloseFn = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuatorActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    /// Taptic Engine actuation pattern:
    /// - 3: light alignment detent tick (crisp for scrubbing across tabs)
    /// - 4: medium tick
    /// - 6: firm click
    let actuationID: Int32

    /// Actuation pattern used for the rapid wall-bump burst at the first/last tab.
    let wallActuationID: Int32

    private var frameworkHandle: UnsafeMutableRawPointer?
    private var mtCreate: ActuatorCreateFn?
    private var mtOpen: ActuatorOpenFn?
    private var mtClose: ActuatorCloseFn?
    private var mtActuate: ActuatorActuateFn?

    private var actuators: [CFTypeRef] = []
    private var lastWallBumpTime: TimeInterval = 0
    private let wallBumpCooldown: TimeInterval = 0.25

    init(actuationID: Int32 = 3, wallActuationID: Int32 = 3) {
        self.actuationID = actuationID
        self.wallActuationID = wallActuationID
        loadMultitouchFramework()
    }

    deinit {
        closeActuators()
        if let handle = frameworkHandle {
            dlclose(handle)
        }
    }

    /// Fires a single trackpad Taptic Engine click.
    func tap() {
        performActuation(id: actuationID)
    }

    /// Fires a rapid 3-click Taptic Engine burst to signify hitting the first or last tab.
    func wallBump() {
        let now = ProcessInfo.processInfo.systemUptime
        guard (now - lastWallBumpTime) >= wallBumpCooldown else { return }
        lastWallBumpTime = now

        let burstCount = 3
        let spacingSeconds = 0.025
        for i in 0..<burstCount {
            let delay = Double(i) * spacingSeconds
            if i == 0 {
                performActuation(id: wallActuationID)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    self.performActuation(id: self.wallActuationID)
                }
            }
        }
    }

    private func performActuation(id: Int32) {
        if actuateMultitouch(id: id) {
            return
        }

        // Re-discover once in case a trackpad reconnected (e.g., after sleep or Bluetooth wake).
        closeActuators()
        if openActuators(), actuateMultitouch(id: id) {
            return
        }

        // Safe public fallback.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func loadMultitouchFramework() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }

        guard let createSym = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let openSym = dlsym(handle, "MTActuatorOpen"),
              let closeSym = dlsym(handle, "MTActuatorClose"),
              let actuateSym = dlsym(handle, "MTActuatorActuate")
        else {
            dlclose(handle)
            return
        }

        frameworkHandle = handle
        mtCreate = unsafeBitCast(createSym, to: ActuatorCreateFn.self)
        mtOpen = unsafeBitCast(openSym, to: ActuatorOpenFn.self)
        mtClose = unsafeBitCast(closeSym, to: ActuatorCloseFn.self)
        mtActuate = unsafeBitCast(actuateSym, to: ActuatorActuateFn.self)
    }

    @discardableResult
    private func openActuators() -> Bool {
        guard let createFn = mtCreate, let openFn = mtOpen else { return false }

        var opened: [CFTypeRef] = []
        for deviceID in discoverMultitouchDeviceIDs() {
            guard let unmanaged = createFn(deviceID) else { continue }
            let actuator = unmanaged.takeRetainedValue()
            if openFn(actuator) == kIOReturnSuccess {
                opened.append(actuator)
            }
        }

        actuators = opened
        return !actuators.isEmpty
    }

    private func closeActuators() {
        if let closeFn = mtClose {
            for actuator in actuators {
                _ = closeFn(actuator)
            }
        }
        actuators.removeAll()
    }

    private func actuateMultitouch(id: Int32) -> Bool {
        guard let actuateFn = mtActuate else { return false }
        if actuators.isEmpty {
            guard openActuators() else { return false }
        }

        var anySucceeded = false
        for actuator in actuators {
            if actuateFn(actuator, id, 0, 0.0, 0.0) == kIOReturnSuccess {
                anySucceeded = true
            }
        }
        return anySucceeded
    }

    private func discoverMultitouchDeviceIDs() -> [UInt64] {
        var ids: [UInt64] = []
        var iterator: io_iterator_t = 0

        guard let matching = IOServiceMatching("AppleMultitouchDevice"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            return ids
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            if let prop = IORegistryEntryCreateCFProperty(
                service,
                "Multitouch ID" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? NSNumber {
                ids.append(prop.uint64Value)
            }
        }

        return ids
    }
}
