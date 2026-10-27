import Foundation
import CryptoKit

@main
enum TransferTests {
    static var checks = 0
    static func check(_ value: Bool, _ message: String) {
        checks += 1
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func rejects(_ operation: () throws -> Void, _ message: String) {
        do { try operation(); check(false, message) } catch { check(true, message) }
    }
    static func wait(_ condition: () -> Bool) {
        let end = Date().addingTimeInterval(10)
        while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(condition(), "Asynchronous file operation completed")
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cabledex-transfer-tests-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("Fixture.bundle")
        let resources = bundleURL.appendingPathComponent("Contents/Resources")
        let tools = resources.appendingPathComponent("Tools")
        try fm.createDirectory(at: tools, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.cabledex.transferfixture", "CFBundlePackageType": "BNDL"], format: .xml, options: 0).write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        let adb = #"""
        #!/usr/bin/python3
        import sys, pathlib, json, shlex, shutil, time
        base = pathlib.Path(__file__).parent
        phone = base / 'phone'
        args = sys.argv[1:]
        with (base / 'commands.jsonl').open('a') as f: f.write(json.dumps(args) + '\n')
        if args == ['devices', '-l']:
            tid = '9' if (base / 'changed').exists() else '7'
            print('TEST_USB device usb:1 model:Galaxy_S24_Ultra transport_id:' + tid)
            sys.exit(0)
        if args == ['kill-server']: sys.exit(0)
        assert args[:2] == ['-t', '7'], args
        args = args[2:]
        def remote(p):
            assert p.startswith('/sdcard/') and '..' not in pathlib.PurePosixPath(p).parts, p
            return phone / p.lstrip('/')
        if args[0] == 'shell':
            cmd = shlex.split(args[1])
            if cmd[:3] == ['ls', '-1ap', '--']:
                print('./\n../')
                for p in remote(cmd[3]).iterdir(): print(p.name + ('/' if p.is_dir() else ''))
            elif cmd[:3] == ['mkdir', '-p', '--']: remote(cmd[3]).mkdir(parents=True, exist_ok=False)
            elif cmd[:2] == ['mv', '--']: remote(cmd[2]).rename(remote(cmd[3]))
            elif cmd[:2] == ['test', '-f']: sys.exit(0 if remote(cmd[2]).is_file() else 1)
            else: raise RuntimeError(cmd)
        elif args[0] == 'push': shutil.copyfile(args[1], remote(args[2]))
        elif args[0] == 'pull':
            if (base / 'slow').exists():
                pathlib.Path(args[2]).write_text('partial')
                time.sleep(10)
            shutil.copyfile(remote(args[1]), args[2])
        else: raise RuntimeError(args)
        """#
        var hashes: [String: String] = [:]
        for (name, source) in [("adb", adb), ("scrcpy", "fixture"), ("scrcpy-server", "fixture")] {
            let data = Data((source + "\n").utf8)
            let url = tools.appendingPathComponent(name)
            try data.write(to: url); try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            hashes[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        try JSONSerialization.data(withJSONObject: ["scrcpyVersion": "test", "files": hashes]).write(to: resources.appendingPathComponent("ToolManifest.json"))
        let bridge = try USBBridge(bundle: Bundle(url: bundleURL)!)
        let device = USBDevice(serial: "TEST_USB", name: "Test phone", state: "device", transportID: 7)
        let phoneDownloads = tools.appendingPathComponent("phone/sdcard/Download")
        try fm.createDirectory(at: phoneDownloads, withIntermediateDirectories: true)
        try fm.createDirectory(at: phoneDownloads.appendingPathComponent("Folder"), withIntermediateDirectories: false)
        let name = "résumé ' $(touch injected); &.txt"
        let quoted = try TransferPolicy.quote(name)
        let shellRoundTrip = try CommandRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf '%s' " + quoted], environment: [:])
        check(shellRoundTrip.status == 0 && shellRoundTrip.output == name, "Actual shell quoting preserves metacharacters without evaluation")
        let data = Data((0..<10000).map { UInt8($0 % 251) })
        let source = root.appendingPathComponent(name)
        try data.write(to: source)
        check(try TransferPolicy.sharedPath("/sdcard/Download/") == "/sdcard/Download", "Normalize a shared-storage folder")
        for bad in ["/data/local/tmp/private", "/sdcard/../data", "/sdcardevil/file", "/storage/emulated/01/file", "/sdcard/a\nb", "/sdcard/a\u{0}b"] {
            rejects({ _ = try TransferPolicy.sharedPath(bad) }, "Reject non-shared/traversal/control path")
        }
        for bad in ["", ".", "..", "a/b", "line\nname", String(repeating: "é", count: 121)] {
            rejects({ _ = try TransferPolicy.fileName(bad) }, "Reject unsafe or unsupported filename")
        }
        let folder = try bridge.upload([source], device: device, token: Cancellation())
        check(folder.hasPrefix("/sdcard/Download/CableDeX/Transfer-"), "Upload uses a fresh dedicated folder")
        let uploaded = tools.appendingPathComponent("phone" + folder + "/" + name)
        check(try Data(contentsOf: uploaded) == data, "Exact bytes survive quoted Unicode/metacharacter filename")
        check(!fm.fileExists(atPath: tools.appendingPathComponent("injected").path), "Filename cannot execute shell code")
        let listed = try bridge.listFiles(at: folder, device: device, token: Cancellation())
        check(listed == [PhoneFile(name: name, path: folder + "/" + name, isDirectory: false)], "List selected folder without dot entries")
        let folders = try bridge.listFiles(at: "/sdcard/Download", device: device, token: Cancellation())
        check(folders.count == 2 && folders.allSatisfy(\.isDirectory), "Directory navigation preserves entry types")
        let destination = root.appendingPathComponent("received.bin")
        try bridge.download(folder + "/" + name, to: destination, replaceExisting: false, device: device, token: Cancellation())
        check(try Data(contentsOf: destination) == data, "Phone-to-Mac transfer preserves bytes")
        check((try fm.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Received file has private permissions")
        rejects({ try bridge.download(folder + "/" + name, to: destination, replaceExisting: false, device: device, token: Cancellation()) }, "Do not replace without explicit choice")
        try Data("old".utf8).write(to: destination)
        try bridge.download(folder + "/" + name, to: destination, replaceExisting: true, device: device, token: Cancellation())
        check(try Data(contentsOf: destination) == data, "Explicitly approved regular file replacement works")
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: source)
        rejects({ _ = try bridge.upload([link], device: device, token: Cancellation()) }, "Reject local symlink upload")
        rejects({ try bridge.download(folder + "/" + name, to: link, replaceExisting: true, device: device, token: Cancellation()) }, "Reject symlink destination")
        rejects({ _ = try bridge.upload([source, source], device: device, token: Cancellation()) }, "Reject duplicate upload names")
        rejects({ _ = try bridge.upload([root], device: device, token: Cancellation()) }, "Reject directory upload")
        try Data().write(to: tools.appendingPathComponent("changed"))
        rejects({ _ = try bridge.upload([source], device: device, token: Cancellation()) }, "Reject changed USB transport before transfer")
        try fm.removeItem(at: tools.appendingPathComponent("changed"))
        try Data().write(to: tools.appendingPathComponent("slow"))
        let token = Cancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) { token.cancel() }
        let cancelledDest = root.appendingPathComponent("cancelled.bin")
        let started = Date()
        rejects({ try bridge.download(folder + "/" + name, to: cancelledDest, replaceExisting: false, device: device, token: token) }, "Cancel an active receive")
        check(Date().timeIntervalSince(started) < 4 && !fm.fileExists(atPath: cancelledDest.path), "Cancelled receive publishes no partial file")
        check(try fm.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".partial") }, "Staging file removed after cancellation")
        try fm.removeItem(at: tools.appendingPathComponent("slow"))
        let controller = SessionController(bridge: bridge, persistSettings: false)
        controller.settings = DisplaySettings()
        check(!controller.canTransfer, "No transfer before USB discovery")
        controller.refresh(); wait { !controller.scanning }
        check(controller.canTransfer, "Discovered USB enables explicit transfer controls")
        controller.settings.fileTransfer = false
        check(!controller.canTransfer, "File switch blocks transfer")
        controller.settings.fileTransfer = true; controller.settings.inputControl = false
        check(!controller.canTransfer, "View-only blocks transfer")
        controller.settings.inputControl = true
        var completed = false
        controller.sendFiles([source]) { result in
            if case .success = result { completed = true }
        }
        check(controller.transferBusy && !controller.canTransfer, "Only one transfer at a time")
        wait { completed && !controller.transferBusy }
        check(controller.transferStatus.hasPrefix("Sent 1 file"), "Successful send reaches UI state")
        let commandLog = try String(contentsOf: tools.appendingPathComponent("commands.jsonl"))
        check(!commandLog.contains("install") && !commandLog.contains("tcpip") && !commandLog.contains("connect"), "Transfers issue no install or network commands")
        print("Passed \(checks) transfer checks using a local fake phone: quoting, shared-storage boundaries, exact bytes, overwrite control, cancellation, and UI state. No phone was accessed.")
    }
}
