import AppKit
import Foundation
import TabSwipeCore

/// Manages installing, uninstalling, and inspecting the `com.tabswipe.agent` LaunchAgent.
enum LaunchAgentManager {
    static let label = "com.tabswipe.agent"

    private static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var installBinaryURL: URL {
        homeDirectory.appendingPathComponent(".local/bin/tabswipe")
    }

    static var plistURL: URL {
        homeDirectory.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var logURL: URL {
        homeDirectory.appendingPathComponent("Library/Logs/tabswipe.log")
    }

    private static var guiDomain: String {
        "gui/\(getuid())"
    }

    private static var serviceTarget: String {
        "\(guiDomain)/\(label)"
    }

    static func install() throws {
        let fm = FileManager.default
        let currentBinaryPath = resolveCurrentExecutablePath()
        let currentBinaryURL = URL(fileURLWithPath: currentBinaryPath).standardizedFileURL
        let destinationURL = installBinaryURL.standardizedFileURL

        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Unload existing service before replacing the binary.
        _ = runProcess("/bin/launchctl", arguments: ["bootout", serviceTarget])

        if currentBinaryURL.path != destinationURL.path {
            let tempURL = destinationURL.appendingPathExtension("tmp")
            try? fm.removeItem(at: tempURL)
            try fm.copyItem(at: currentBinaryURL, to: tempURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
            _ = try fm.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        }

        // Sign with a local Code Signing certificate if present (keeps Accessibility permission
        // across rebuilds); otherwise fall back to ad-hoc signing.
        var usedIdentity: String? = nil
        if let identity = preferredCodesignIdentity() {
            let signResult = runProcess(
                "/usr/bin/codesign",
                arguments: ["--force", "--sign", identity, "--identifier", label, destinationURL.path]
            )
            if signResult.exitCode == 0 {
                usedIdentity = identity
            }
        }
        if usedIdentity == nil {
            _ = runProcess("/usr/bin/codesign", arguments: ["--force", "--sign", "-", destinationURL.path])
        }

        let plistData = makeLaunchAgentPlist(binaryPath: destinationURL.path, logPath: logURL.path)
        try plistData.write(to: plistURL, options: .atomic)

        let bootstrapResult = runProcess("/bin/launchctl", arguments: ["bootstrap", guiDomain, plistURL.path])
        if bootstrapResult.exitCode != 0 {
            throw NSError(
                domain: "TabSwipe",
                code: Int(bootstrapResult.exitCode),
                userInfo: [NSLocalizedDescriptionKey: "launchctl bootstrap failed: \(bootstrapResult.stderr)"]
            )
        }

        print("TabSwipe installed and started.")
        print("  Binary:      \(destinationURL.path)")
        print("  Signing:     \(usedIdentity ?? "ad-hoc (rebuilds may require re-granting Accessibility)")")
        print("  LaunchAgent: \(plistURL.path)")
        print("  Log:         \(logURL.path)")
        print("")
        print("Grant Accessibility permission if prompted:")
        print("  1. Click 'Open System Settings' on the macOS prompt and enable 'tabswipe'.")
        print("  2. TabSwipe will activate automatically within 5 seconds.")
        print("     (If 'tabswipe' doesn't appear in the list, click '+' and add: \(destinationURL.path))")
    }

    static func uninstall() throws {
        let fm = FileManager.default
        _ = runProcess("/bin/launchctl", arguments: ["bootout", serviceTarget])

        if fm.fileExists(atPath: plistURL.path) {
            try fm.removeItem(at: plistURL)
        }
        if fm.fileExists(atPath: installBinaryURL.path) {
            try fm.removeItem(at: installBinaryURL)
        }

        print("TabSwipe uninstalled and stopped.")
    }

    static func status() {
        let fm = FileManager.default
        let plistExists = fm.fileExists(atPath: plistURL.path)
        let binaryExists = fm.fileExists(atPath: installBinaryURL.path)
        let launchctlResult = runProcess("/bin/launchctl", arguments: ["print", serviceTarget])
        let isLoaded = launchctlResult.exitCode == 0

        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontBundle = frontApp?.bundleIdentifier ?? "unknown"
        let isBrowser = BrowserRegistry.isSupportedBrowser(frontBundle)

        print("TabSwipe Status")
        print("  Installed binary: \(binaryExists ? installBinaryURL.path : "not installed")")
        print("  LaunchAgent:      \(plistExists ? (isLoaded ? "running" : "installed (not loaded)") : "not installed")")
        print("  Supported browsers built-in: \(BrowserRegistry.browsers.count)")
        print("  Frontmost app:    \(frontApp?.localizedName ?? "unknown") (\(frontBundle)) — \(isBrowser ? "supported browser" : "not a browser")")
        if fm.fileExists(atPath: logURL.path),
           let logText = try? String(contentsOf: logURL, encoding: .utf8) {
            let recentLines = logText.split(separator: "\n").suffix(5)
            if !recentLines.isEmpty {
                print("  Recent log:")
                for line in recentLines {
                    print("    \(line)")
                }
            }
        }
    }

    private static func preferredCodesignIdentity() -> String? {
        let candidate = ProcessInfo.processInfo.environment["TABSWIPE_CODESIGN_IDENTITY"] ?? "TabSwipe"
        // Omit `-v` so newly created local self-signed certs are detected even before marking Always Trust.
        let result = runProcess("/usr/bin/security", arguments: ["find-identity", "-p", "codesigning"])
        guard result.exitCode == 0, result.stdout.contains("\"\(candidate)\"") else {
            return nil
        }
        return candidate
    }

    private static func makeLaunchAgentPlist(binaryPath: String, logPath: String) -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binaryPath, "run"],
            "LimitLoadToSessionType": "Aqua",
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    private static func resolveCurrentExecutablePath() -> String {
        let raw = CommandLine.arguments[0]
        if let resolved = realpath(raw, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return URL(fileURLWithPath: raw).standardizedFileURL.path
    }

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    @discardableResult
    private static func runProcess(_ executable: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
