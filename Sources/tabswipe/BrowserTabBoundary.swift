import ApplicationServices
import Foundation
import TabSwipeCore

/// Inspects the focused browser window via macOS Accessibility (`AXUIElement`) to detect
/// whether the active tab is already at the leftmost or rightmost edge of the tab bar.
///
/// Uses an O(1) check on only the first or last tab in `AXTabGroup`, so latency stays under
/// ~1 ms even when hundreds of tabs are open. Gracefully returns `false` for browsers whose
/// tab bars do not expose `AXTabGroup` (e.g., Firefox/Arc), falling back to normal wrapping.
final class BrowserTabBoundary {
    private let maxSearchDepth = 6
    private let maxVisitedNodes = 80
    private let skippedRoles: Set<String> = [
        "AXWebArea",
        "AXScrollArea",
        "AXTextArea",
        "AXTextField",
        "AXTable",
        "AXOutline",
        "AXMenuBar",
    ]

    /// Returns `true` if performing `action` would wrap past the first or last tab.
    func isAtEdge(for action: SwipeAction, pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = copyElementAttribute(appElement, kAXFocusedWindowAttribute as CFString),
              let tabGroup = findTabGroup(in: window)
        else {
            return false
        }

        let tabs = extractTabs(from: tabGroup)
        guard !tabs.isEmpty else { return false }

        let edgeTab: AXUIElement
        switch action {
        case .previousTab:
            edgeTab = tabs[0]
        case .nextTab:
            edgeTab = tabs[tabs.count - 1]
        }

        if isTabSelected(edgeTab) {
            return true
        }

        // Some browsers expose the selected tab directly as AXTabGroup's AXValue.
        if let selectedFromGroup = copyElementAttribute(tabGroup, kAXValueAttribute as CFString),
           CFEqual(selectedFromGroup, edgeTab) {
            return true
        }

        return false
    }

    private func findTabGroup(in root: AXUIElement) -> AXUIElement? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0
        var visited = 0

        while index < queue.count && visited < maxVisitedNodes {
            let current = queue[index]
            index += 1
            visited += 1

            let role = copyStringAttribute(current.element, kAXRoleAttribute as CFString)
            if role == (kAXTabGroupRole as String) {
                return current.element
            }

            if let role = role, skippedRoles.contains(role) {
                continue
            }

            guard current.depth < maxSearchDepth,
                  let children = copyElementArrayAttribute(current.element, kAXChildrenAttribute as CFString)
            else {
                continue
            }

            for child in children {
                queue.append((child, current.depth + 1))
            }
        }

        return nil
    }

    private func extractTabs(from tabGroup: AXUIElement) -> [AXUIElement] {
        if let tabs = copyElementArrayAttribute(tabGroup, kAXTabsAttribute as CFString), !tabs.isEmpty {
            return tabs
        }

        guard let children = copyElementArrayAttribute(tabGroup, kAXChildrenAttribute as CFString) else {
            return []
        }

        return children.filter { child in
            let role = copyStringAttribute(child, kAXRoleAttribute as CFString)
            return role == (kAXRadioButtonRole as String) || role == "AXTab"
        }
    }

    private func isTabSelected(_ tab: AXUIElement) -> Bool {
        if copyBoolOrIntAttribute(tab, kAXValueAttribute as CFString) == true {
            return true
        }
        if copyBoolOrIntAttribute(tab, kAXSelectedAttribute as CFString) == true {
            return true
        }
        return false
    }

    private func copyElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let cfValue = value,
              CFGetTypeID(cfValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (cfValue as! AXUIElement)
    }

    private func copyElementArrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [AXUIElement]
        else {
            return nil
        }
        return array
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyBoolOrIntAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let number = value as? NSNumber
        else {
            return nil
        }
        return number.intValue != 0
    }
}
