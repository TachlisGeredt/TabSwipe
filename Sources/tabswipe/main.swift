import Foundation

private func printUsage() {
    print("""
    TabSwipe — hold ⌘ Command and 3-finger swipe to switch browser tabs on macOS.

    Usage:
      tabswipe install     Install and start the background LaunchAgent (~/.local/bin/tabswipe)
      tabswipe uninstall   Stop and remove the background LaunchAgent
      tabswipe status      Show daemon status and recent logs
      tabswipe run         Run the daemon in the foreground (used by launchd)
      tabswipe --help      Show this help message
    """)
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "run"

do {
    switch command {
    case "install":
        try LaunchAgentManager.install()
    case "uninstall":
        try LaunchAgentManager.uninstall()
    case "status":
        LaunchAgentManager.status()
    case "run":
        DaemonRunner().run()
    case "-h", "--help", "help":
        printUsage()
    default:
        fputs("Unknown command: \(command)\n\n", stderr)
        printUsage()
        exit(1)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
