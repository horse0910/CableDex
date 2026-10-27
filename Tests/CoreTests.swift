import Foundation
import CryptoKit

@main
enum CoreTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func rejects(_ work: () throws -> Void, _ message: String) {
        do { try work(); check(false, message) } catch { check(true, message) }
    }
    static func main() throws {
        let fixture = """
        List of devices attached
        R5CX1234ABC device usb:336592896X product:e3qxxx model:SM_S928B device:e3q transport_id:7
        R5CX1234XYZ unauthorized usb:336592897X transport_id:8
        192.168.1.2:5555 device product:e3q model:Wireless transport_id:9
        adb-R5CX-abc._adb-tls-connect._tcp device model:TLS transport_id:10
        emulator-5554 device usb:spoofed transport_id:11
        $(touch_evil) device usb:spoofed transport_id:12
        missing_usb device model:Unknown transport_id:13
        no_transport device usb:123
        malformed device usb:123 transport_id:bad
        """
        let devices = USBDevice.parse(fixture)
        check(devices.count == 2, "Only physical USB transports are accepted")
        check(devices[0].transportID == 7 && devices[0].name == "SM S928B", "Parse model and transport ID")
        check(!devices[1].isAuthorized, "Unauthorized phone cannot start")
        let defaults = DisplaySettings()
        let args = try defaults.arguments(for: devices[0])
        check(args.contains("--serial=R5CX1234ABC"), "Pin exact USB phone")
        check(args.contains("--new-display=2560x1440/200"), "Create separate QHD display")
        check(args.contains("--video-buffer=0"), "No added video buffer")
        check(args.contains("--video-codec=h264") && args.contains("--video-bit-rate=30M"), "Default low-latency video profile")
        check(args.contains("--audio-source=output") && args.contains("--audio-codec=raw") && args.contains("--audio-buffer=50"), "Phone output audio uses PCM over USB")
        check(!args.contains("--no-clipboard-autosync") && defaults.fileTransfer, "Requested sharing features enabled")
        check(args.contains("--no-vd-destroy-content"), "Preserve apps when closing desktop")
        check(!args.contains(where: { $0.contains("tcpip") || $0.contains("tunnel-host") }), "No wireless launch path")
        rejects({ _ = try defaults.arguments(for: devices[1]) }, "Reject unauthorized transport")
        let injected = USBDevice(serial: "x;whoami", name: "Name", state: "device", transportID: 1)
        rejects({ _ = try defaults.arguments(for: injected) }, "Reject shell syntax in serial")
        var mirror = defaults
        mirror.mode = .mirror; mirror.audio = true; mirror.clipboard = true; mirror.codec = .h265
        let mirrorArgs = try mirror.arguments(for: devices[0])
        check(!mirrorArgs.contains(where: { $0.contains("new-display") }), "Mirror does not create a display")
        check(mirrorArgs.contains("--max-size=2560"), "Mirror only limits the stream size")
        check(!mirrorArgs.contains("--no-audio") && !mirrorArgs.contains("--no-clipboard-autosync"), "Sharing works in mirror mode")
        check(mirrorArgs.contains("--video-codec=h265"), "HEVC selectable")
        var bad = defaults; bad.width = 99999
        rejects({ _ = try bad.validated() }, "Reject invalid stored resolution")
        bad = defaults; bad.bitrate = -1
        rejects({ _ = try bad.validated() }, "Reject invalid bitrate")
        check(StreamEvent.parse("[server] INFO: New display: 2560x1440/200 (id=2)") == .display(2), "Identify only new secondary display")
        check(StreamEvent.parse("[server] INFO: New display: 2560x1440/200 (id=0)") == nil, "Never target primary display")
        check(StreamEvent.parse("New display: 2560x1440/200 (id=2)") == nil, "Require server marker")
        check(StreamEvent.parse("INFO: Texture: 2560x1440") == .frameReady, "Observe video initialization")
        check(StreamEvent.parse("INFO: Texture (VideoToolbox): 2560x1440") == .frameReady, "Recognize actual hardware-decoder startup")
        check(StreamEvent.parse("INFO: CDX_METRIC host_ms avg=2.250 max=4.500 n=60") == .hostPipeline(2.25, 4.5, 60), "Parse measured Mac pipeline time")
        check(StreamEvent.parse("INFO: 58 fps (+0 frames skipped)") == .fps(58), "Read actual capture FPS")
        var panelOff = defaults; panelOff.phoneScreenOff = true
        let panelArgs = try panelOff.arguments(for: devices[0])
        check(panelArgs.contains("--turn-screen-off") && panelArgs.contains("--keep-active"), "Turn panel off without a persistent stay-awake setting")
        check(!panelArgs.contains("--stay-awake"), "Do not change global charging/wake preference")
        panelOff.inputControl = false
        let viewArgs = try panelOff.arguments(for: devices[0])
        check(viewArgs.contains("--no-control") && !viewArgs.contains("--turn-screen-off"), "View-only mode disables device input and power control")
        let legacy = Data(#"{"mode":"desktop","width":2560,"height":1440,"dpi":200,"codec":"h264","bitrate":30,"fps":60,"audio":true,"clipboard":true,"resizableWindows":true,"fullscreen":false}"#.utf8)
        let migrated = try JSONDecoder().decode(DisplaySettings.self, from: legacy)
        check(migrated.audio && migrated.clipboard && migrated.fileTransfer && migrated.inputControl, "Upgrade restricted settings to requested sharing features")
        var privateSettings = defaults
        privateSettings.audio = false; privateSettings.clipboard = false; privateSettings.fileTransfer = false
        let saved = try JSONDecoder().decode(DisplaySettings.self, from: JSONEncoder().encode(privateSettings))
        check(saved == privateSettings, "Remember explicit sharing opt-outs after upgrade")
        let privateArgs = try saved.arguments(for: devices[0])
        check(privateArgs.contains("--no-audio") && privateArgs.contains("--no-clipboard-autosync"), "Switches disable audio and clipboard")

        let result = try CommandRunner.run(URL(fileURLWithPath: "/usr/bin/head"), ["-c", "2097152", "/dev/zero"], environment: [:])
        check(result.status == 0 && result.output.utf8.count == 1_048_576, "Drain large output without deadlock and cap retained logs")
        let started = Date()
        rejects({ _ = try CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["3"], environment: [:], timeout: 0.05) }, "Timeout terminates a stalled command")
        check(Date().timeIntervalSince(started) < 2.5, "Timeout stays bounded")
        let cancelled = Cancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancelled.cancel() }
        let cancelStarted = Date()
        rejects({ _ = try CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], environment: [:], timeout: 20, cancellation: cancelled) }, "Cancel a running command")
        check(Date().timeIntervalSince(cancelStarted) < 2.5, "Cancellation terminates promptly")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cabledex-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("Fixture.bundle")
        let resources = bundleURL.appendingPathComponent("Contents/Resources")
        let tools = resources.appendingPathComponent("Tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.cabledex.testfixture", "CFBundlePackageType": "BNDL"], format: .xml, options: 0)
        try plist.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        var hashes: [String: String] = [:]
        for name in ["adb", "scrcpy", "scrcpy-server"] {
            let data = Data("fixture-\(name)".utf8)
            try data.write(to: tools.appendingPathComponent(name))
            hashes[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let manifest: [String: Any] = ["scrcpyVersion": "test", "files": hashes]
        try JSONSerialization.data(withJSONObject: manifest).write(to: resources.appendingPathComponent("ToolManifest.json"))
        let bridge = try USBBridge(bundle: Bundle(url: bundleURL)!)
        try bridge.verifyTools()
        check(bridge.environment["ADB_SERVER_SOCKET"]?.hasPrefix("localfilesystem:") == true, "Use private local Unix socket")
        check(bridge.environment["ADB_MDNS"] == "0" && bridge.environment["ADB_MDNS_AUTO_CONNECT"] == "0", "Disable mDNS and wireless autoconnection")
        check(bridge.environment["ADB_EMU"] == "0" && bridge.environment["ADB_USB"] == "1", "Disable emulator network discovery and keep USB enabled")
        check(bridge.environment["ADB"] == bridge.adb.path, "Use bundled ADB, not PATH fallback")
        check(bridge.environment["SCRCPY_SERVER_PATH"] == tools.appendingPathComponent("scrcpy-server").path, "Pin matching Android server")
        check(bridge.environment(for: defaults)["CABLEDEX_AUDIO"] == "1" && bridge.environment(for: defaults)["CABLEDEX_CLIPBOARD"] == "1", "Pass explicit feature gates to backend")
        check(bridge.environment(for: privateSettings)["CABLEDEX_AUDIO"] == "0" && bridge.environment(for: privateSettings)["CABLEDEX_CLIPBOARD"] == "0", "Disable backend features when switched off")
        var viewOnly = defaults; viewOnly.inputControl = false
        check(bridge.environment(for: viewOnly)["CABLEDEX_CLIPBOARD"] == "0", "View-only cannot read or write clipboard")
        rejects({ _ = try bridge.setWindowingMode(5, display: 0, device: devices[0]) }, "Refuse mutation of main phone display")
        rejects({ _ = try bridge.setWindowingMode(7, display: 2, device: devices[0]) }, "Refuse unsupported windowing mutation")
        try Data("tampered".utf8).write(to: tools.appendingPathComponent("scrcpy"))
        rejects({ try bridge.verifyTools() }, "Detect modified bundled executable")
        let token = Cancellation(); token.cancel()
        check(token.isCancelled, "Cancellation observed")
        print("Passed \(count) checks: USB filtering, safe launch configuration, stream parsing, output draining, timeout, integrity verification, and display isolation.")
    }
}
