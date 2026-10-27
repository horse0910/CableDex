import Foundation
import CryptoKit

@main
enum SessionTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func wait(_ condition: () -> Bool, timeout: TimeInterval = 8) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(condition(), "Asynchronous operation completed")
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cabledex-session-tests-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("Fixture.bundle")
        let resources = bundleURL.appendingPathComponent("Contents/Resources")
        let tools = resources.appendingPathComponent("Tools")
        try fm.createDirectory(at: tools, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.cabledex.sessionfixture", "CFBundlePackageType": "BNDL"], format: .xml, options: 0)
        try plist.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        let adb = #"""
        #!/bin/sh
        if [ "$1" = "devices" ]; then
          printf 'List of devices attached\nTEST_USB device usb:1 model:Galaxy_S24_Ultra transport_id:7\n192.168.1.2:5555 device model:Wireless transport_id:8\n'
        elif [ "$1" = "-t" ]; then
          printf '%s\n' "$*" >> "$(dirname "$0")/commands.log"
        elif [ "$1" = "kill-server" ]; then
          printf 'shutdown\n' >> "$(dirname "$0")/commands.log"
        else
          exit 1
        fi
        """#
        let scrcpy = #"""
        #!/bin/sh
        printf '%s\n' "$@" > "$(dirname "$0")/arguments.log"
        desktop=0
        for arg in "$@"; do
          case "$arg" in
            --video-codec=h265) printf 'ERROR: Simulated encoder failure\n'; exit 7 ;;
            --new-display=*) desktop=1 ;;
          esac
        done
        if [ "$desktop" = 1 ]; then printf '[server] INFO: New display: 2560x1440/200 (id=2)\n'; fi
        printf 'INFO: Texture (VideoToolbox): 2560x1440\nINFO: 60 fps (+0 frames skipped)\nINFO: CDX_METRIC host_ms avg=2.250 max=4.500 n=60\n'
        exec /bin/sleep 8
        """#
        var files: [String: String] = [:]
        for (name, source) in [("adb", adb), ("scrcpy", scrcpy), ("scrcpy-server", "fixture")] {
            let data = Data((source + "\n").utf8)
            let path = tools.appendingPathComponent(name)
            try data.write(to: path)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            files[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        try JSONSerialization.data(withJSONObject: ["scrcpyVersion": "test", "files": files]).write(to: resources.appendingPathComponent("ToolManifest.json"))
        let bridge = try USBBridge(bundle: Bundle(url: bundleURL)!)
        let controller = SessionController(bridge: bridge, persistSettings: false)
        controller.settings = DisplaySettings()
        controller.refresh()
        wait { !controller.scanning }
        check(controller.devices.count == 1, "Session UI excludes wireless device")
        controller.start()
        wait { controller.state == .running && controller.windowing == "Resizable windows requested" }
        check(controller.frameRate == 60, "Actual FPS event reaches the controller")
        check(controller.hostPipeline?.contains("2.2 ms avg") == true || controller.hostPipeline?.contains("2.3 ms avg") == true, "Mac timing reaches the UI without being labeled total latency")
        var commands = try String(contentsOf: tools.appendingPathComponent("commands.log"))
        check(commands.contains("-t 7 shell wm set-display-windowing-mode -d 2 5"), "Apply freeform only to selected transport and secondary display")
        let arguments = try String(contentsOf: tools.appendingPathComponent("arguments.log"))
        check(arguments.contains("--serial=TEST_USB"), "Launch pins the validated USB device")
        controller.stop()
        wait { !controller.state.busy }
        check(controller.state == .idle, "Clean stop returns to idle")
        commands = try String(contentsOf: tools.appendingPathComponent("commands.log"))
        check(commands.contains("-d 2 0"), "Restore only the temporary display override before exit")
        controller.settings.mode = .mirror
        controller.start()
        wait { controller.state == .running }
        let mirrorArguments = try String(contentsOf: tools.appendingPathComponent("arguments.log"))
        check(!mirrorArguments.contains("--new-display"), "Phone mirror does not create desktop")
        controller.stop()
        wait { !controller.state.busy }
        controller.settings.codec = .h265
        controller.start()
        wait { !controller.state.busy }
        if case .failed = controller.state { check(true, "Encoder error is surfaced") }
        else { check(false, "Encoder error is surfaced") }
        controller.settings.codec = .h264
        controller.start(); controller.stop()
        wait { !controller.state.busy }
        check(controller.state == .idle, "Cancel during preflight does not launch a session later")
        var shutdown = false
        controller.shutdown { shutdown = true }
        wait { shutdown }
        commands = try String(contentsOf: tools.appendingPathComponent("commands.log"))
        check(commands.contains("shutdown"), "Shutdown stops only the private bridge")
        print("Passed \(checks) session checks: USB validation, desktop windowing, live events, cleanup, mirror mode, encoder failure, cancellation, and shutdown. No phone was contacted.")
    }
}
