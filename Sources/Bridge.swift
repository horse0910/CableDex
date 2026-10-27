import Foundation
import CryptoKit

struct ToolManifest: Decodable {
    let scrcpyVersion: String
    let files: [String: String]
}

struct USBBridge {
    let tools: URL
    let socketDirectory: URL
    let manifest: ToolManifest
    var adb: URL { tools.appendingPathComponent("adb") }
    var scrcpy: URL { tools.appendingPathComponent("scrcpy") }

    init(bundle: Bundle = .main) throws {
        guard let resources = bundle.resourceURL else { throw CableError.message("App resources are missing.") }
        tools = resources.appendingPathComponent("Tools", isDirectory: true)
        manifest = try JSONDecoder().decode(ToolManifest.self, from: Data(contentsOf: resources.appendingPathComponent("ToolManifest.json")))
        socketDirectory = URL(fileURLWithPath: "/private/tmp/cabledex-\(getuid())", isDirectory: true)
        try Self.preparePrivateDirectory(socketDirectory)
    }

    static func preparePrivateDirectory(_ directory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let attributes = try fm.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw CableError.message("The private USB bridge folder has unsafe permissions. Remove \(directory.path) and try again.")
        }
    }

    var environment: [String: String] {
        // Whitelist rather than inherit server addresses, injected libraries, external tools, or proxy settings.
        var env = ["PATH": tools.path + ":/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
                   "ADB": adb.path, "SCRCPY_SERVER_PATH": tools.appendingPathComponent("scrcpy-server").path,
                   "SCRCPY_ICON_PATH": tools.appendingPathComponent("scrcpy.png").path,
                   "ADB_SERVER_SOCKET": "localfilesystem:" + socketDirectory.appendingPathComponent("adb.sock").path,
                   "ADB_MDNS": "0", "ADB_MDNS_AUTO_CONNECT": "0", "ADB_EMU": "0", "ADB_USB": "1",
                   "ANDROID_ADB_LOG_PATH": socketDirectory.appendingPathComponent("bridge.log").path,
                   "ADB_LOCAL_TRANSPORT_MAX_PORT": "0"]
        // Preserve the real user home: ADB uses its standard ~/.android authorization keys.
        if let home = ProcessInfo.processInfo.environment["HOME"] { env["HOME"] = home }
        if let temp = ProcessInfo.processInfo.environment["TMPDIR"] { env["TMPDIR"] = temp }
        return env
    }

    func environment(for settings: DisplaySettings) -> [String: String] {
        var env = environment
        env["CABLEDEX_AUDIO"] = settings.audio ? "1" : "0"
        env["CABLEDEX_CLIPBOARD"] = settings.clipboard && settings.inputControl ? "1" : "0"
        return env
    }

    func verifyTools() throws {
        for name in ["adb", "scrcpy", "scrcpy-server"] {
            let file = tools.appendingPathComponent(name)
            let hash = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            guard manifest.files[name] == hash else {
                throw CableError.message("The bundled \(name) tool has changed. Rebuild or replace CableDeX from a trusted copy.")
            }
        }
    }

    func devices() throws -> [USBDevice] {
        let result = try CommandRunner.run(adb, ["devices", "-l"], environment: environment)
        guard result.status == 0 else { throw CableError.message("USB bridge failed: " + String(result.output.suffix(1000))) }
        return USBDevice.parse(result.output)
    }

    func setWindowingMode(_ mode: Int, display: Int, device: USBDevice) throws -> CommandResult {
        guard [0, 5].contains(mode), display > 0, display <= 65535, device.isAuthorized else {
            throw CableError.message("Refusing to change the phone's primary display.")
        }
        return try CommandRunner.run(adb, ["-t", String(device.transportID), "shell", "wm", "set-display-windowing-mode", "-d", String(display), String(mode)], environment: environment, timeout: 5)
    }

    func shutdown() {
        _ = try? CommandRunner.run(adb, ["kill-server"], environment: environment, timeout: 3)
    }
}

final class SessionLog {
    let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    init() throws {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("CableDeX", isDirectory: true)
        try USBBridge.preparePrivateDirectory(directory)
        url = directory.appendingPathComponent("session.log")
        if fm.fileExists(atPath: url.path) {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CableError.message("The session log is not a regular file.") }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else {
            guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CableError.message("Cannot create the private session log.") }
        }
        handle = try FileHandle(forWritingTo: url)
        try handle?.truncate(atOffset: 0)
    }
    func write(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return }
        if (try? handle.offset()) ?? 0 > 1_048_576 { try? handle.truncate(atOffset: 0); try? handle.seek(toOffset: 0) }
        try? handle.write(contentsOf: Data((text + "\n").utf8))
    }
}

final class VideoProcess {
    private let process = Process()
    private let pipe = Pipe()

    func start(bridge: USBBridge, settings: DisplaySettings, arguments: [String], onLine: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) throws {
        process.executableURL = bridge.scrcpy
        process.arguments = arguments
        process.environment = bridge.environment(for: settings)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        try? pipe.fileHandleForWriting.close()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var pending = Data()
            while let data = PipeReader.chunk(from: pipe.fileHandleForReading) {
                pending.append(data)
                while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    let line = String(decoding: pending[..<end], as: UTF8.self)
                    pending.removeSubrange(...end)
                    if !line.isEmpty { DispatchQueue.main.async { onLine(line) } }
                }
                if pending.count > 65536 { pending.removeFirst(pending.count - 65536) }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                DispatchQueue.main.async { onLine(line) }
            }
            try? pipe.fileHandleForReading.close()
            process.waitUntilExit()
            let status = process.terminationStatus
            DispatchQueue.main.async { onExit(status) }
        }
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
