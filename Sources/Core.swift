// CableDeX — derived from dex-for-mac, MIT license. See Upstream/ and LICENSE.
import Foundation
import Darwin

enum DisplayMode: String, Codable, CaseIterable {
    case desktop, mirror
    var title: String { self == .desktop ? "Desktop" : "Phone screen" }
}

enum VideoCodec: String, Codable, CaseIterable {
    case h264, h265
    var title: String { self == .h264 ? "H.264 · lower latency" : "HEVC · higher compression" }
}

struct DisplaySettings: Codable, Equatable {
    var mode: DisplayMode = .desktop
    var width = 2560
    var height = 1440
    var dpi = 200
    var codec: VideoCodec = .h264
    var bitrate = 30
    var fps = 60
    var audio = true
    var clipboard = true
    var fileTransfer = true
    var sharingProfileVersion = 1
    var resizableWindows = true
    var fullscreen = false
    var phoneScreenOff = false
    var inputControl = true

    init() {}
    private enum CodingKeys: String, CodingKey {
        case mode, width, height, dpi, codec, bitrate, fps, audio, clipboard, fileTransfer, sharingProfileVersion, resizableWindows, fullscreen, phoneScreenOff, inputControl
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(DisplayMode.self, forKey: .mode) ?? .desktop
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 2560
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 1440
        dpi = try c.decodeIfPresent(Int.self, forKey: .dpi) ?? 200
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .h264
        bitrate = try c.decodeIfPresent(Int.self, forKey: .bitrate) ?? 30
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? 60
        // The user requested these three features when upgrading from the restricted build.
        sharingProfileVersion = try c.decodeIfPresent(Int.self, forKey: .sharingProfileVersion) ?? 1
        let hasSharingPreferences = c.contains(.sharingProfileVersion)
        audio = hasSharingPreferences ? try c.decodeIfPresent(Bool.self, forKey: .audio) ?? true : true
        clipboard = hasSharingPreferences ? try c.decodeIfPresent(Bool.self, forKey: .clipboard) ?? true : true
        fileTransfer = try c.decodeIfPresent(Bool.self, forKey: .fileTransfer) ?? true
        resizableWindows = try c.decodeIfPresent(Bool.self, forKey: .resizableWindows) ?? true
        fullscreen = try c.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? false
        phoneScreenOff = try c.decodeIfPresent(Bool.self, forKey: .phoneScreenOff) ?? false
        inputControl = try c.decodeIfPresent(Bool.self, forKey: .inputControl) ?? true
    }

    static let resolutions = [(1920, 1080), (2560, 1440), (2880, 1800)]
    static let densities = [160, 200, 240, 284]
    static let bitrates = [16, 24, 30, 40, 60]

    func validated() throws -> DisplaySettings {
        guard Self.resolutions.contains(where: { $0.0 == width && $0.1 == height }),
              Self.densities.contains(dpi), Self.bitrates.contains(bitrate),
              [30, 60].contains(fps) else {
            throw CableError.message("Invalid display settings. Choose a supported preset.")
        }
        return self
    }

    func arguments(for device: USBDevice) throws -> [String] {
        _ = try validated()
        guard device.isAuthorized, USBDevice.safeSerial(device.serial) else {
            throw CableError.message("Select an authorized USB device first.")
        }
        var args = ["--serial=\(device.serial)", "--video-codec=\(codec.rawValue)",
                    "--video-bit-rate=\(bitrate)M", "--max-fps=\(fps)",
                    "--video-buffer=0", "--hwdec=auto", "--window-title=CableDeX — \(device.name)",
                    "--no-terminal-title", "--print-fps", "--keep-active"]
        if audio { args += ["--audio-source=output", "--audio-codec=raw", "--audio-buffer=50"] }
        else { args.append("--no-audio") }
        if !clipboard || !inputControl { args.append("--no-clipboard-autosync") }
        if mode == .desktop {
            args += ["--new-display=\(width)x\(height)/\(dpi)", "--no-vd-destroy-content"]
        } else {
            args += ["--max-size=\(max(width, height))"]
        }
        if inputControl {
            args += ["--keyboard=sdk", "--mouse=sdk", "--mouse-bind=++++:++++"]
            if phoneScreenOff { args.append("--turn-screen-off") }
        } else { args.append("--no-control") }
        if fullscreen { args.append("--fullscreen") }
        return args
    }

    static func load(from defaults: UserDefaults = .standard) -> DisplaySettings {
        guard let data = defaults.data(forKey: "displaySettings"),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              let valid = try? value.validated() else { return Self() }
        return valid
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(try validated()) { defaults.set(data, forKey: "displaySettings") }
    }
}

struct USBDevice: Equatable {
    let serial: String
    let name: String
    let state: String
    let transportID: Int
    var isAuthorized: Bool { state == "device" }
    var label: String {
        "\(name) · …\(serial.suffix(4))" + (isAuthorized ? "" : " · \(state)")
    }

    static func safeSerial(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && !value.hasPrefix("emulator-") &&
        value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil &&
        !value.contains("_adb-") && !value.contains("_tcp")
    }

    // Require a physical USB transport; do not infer USB from the absence of an IP address.
    static func parse(_ output: String) -> [USBDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 3, safeSerial(parts[0]),
                  ["device", "unauthorized", "offline"].contains(parts[1]),
                  parts.contains(where: { $0.hasPrefix("usb:") }),
                  let tid = parts.first(where: { $0.hasPrefix("transport_id:") }),
                  let id = Int(tid.dropFirst("transport_id:".count)), id > 0 else { return nil }
            let model = parts.first(where: { $0.hasPrefix("model:") })?
                .dropFirst("model:".count).replacingOccurrences(of: "_", with: " ") ?? "Android phone"
            return USBDevice(serial: parts[0], name: model, state: parts[1], transportID: id)
        }
    }
}

enum StreamEvent: Equatable {
    case display(Int), frameReady, fps(Int), hardwareDecoder, softwareDecoder
    case hostPipeline(Double, Double, Int)

    static func parse(_ line: String) -> StreamEvent? {
        if line.contains("[server]"), line.contains("New display:"),
           let range = line.range(of: #"\(id=([0-9]+)\)"#, options: .regularExpression),
           let id = Int(line[range].dropFirst(4).dropLast()), (1...65535).contains(id) {
            return .display(id)
        }
        if line.range(of: #"Texture(?: \([^)]*\))?: [0-9]+x[0-9]+"#, options: .regularExpression) != nil { return .frameReady }
        if let range = line.range(of: #"CDX_METRIC host_ms avg=([0-9.]+) max=([0-9.]+) n=([0-9]+)"#, options: .regularExpression) {
            let fields = line[range].split(separator: " ")
            if fields.count == 5, let mean = Double(fields[2].dropFirst(4)),
               let maximum = Double(fields[3].dropFirst(4)), let count = Int(fields[4].dropFirst(2)),
               mean.isFinite, maximum.isFinite, mean >= 0, maximum >= mean, count > 0 {
                return .hostPipeline(mean, maximum, count)
            }
        }
        if let r = line.range(of: #"\b[0-9]+(?= fps\b)"#, options: .regularExpression), let fps = Int(line[r]) {
            return .fps(fps)
        }
        let lower = line.lowercased()
        if lower.contains("videotoolbox") && (lower.contains("decoder") || lower.contains("decoding")) { return .hardwareDecoder }
        if lower.contains("software decoding") { return .softwareDecoder }
        return nil
    }
}

enum CableError: LocalizedError {
    case message(String), timeout, cancelled
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .timeout: return "The USB bridge did not respond in time. Reconnect the cable, unlock your phone, and try again."
        case .cancelled: return "Transfer cancelled."
        }
    }
}

struct CommandResult {
    let status: Int32
    let output: String
}

final class LockedBuffer {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        bytes.append(data)
        // Keep a bounded tail, while continuing to drain the pipe.
        if bytes.count > 1_048_576 { bytes.removeFirst(bytes.count - 1_048_576) }
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: bytes, as: UTF8.self) }
}

enum PipeReader {
    // FileHandle.read(upToCount:) may wait to fill its buffer. POSIX read returns
    // as soon as any bytes arrive, which is essential for live startup events.
    static func chunk(from handle: FileHandle) -> Data? {
        var bytes = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
            if count > 0 { return Data(bytes.prefix(count)) }
            if count == 0 { return nil }
            if errno != EINTR { return nil }
        }
    }
}

enum CommandRunner {
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String], timeout: TimeInterval = 8, cancellation: Cancellation? = nil) throws -> CommandResult {
        if cancellation?.isCancelled == true { throw CableError.cancelled }
        let process = Process()
        let pipe = Pipe()
        let done = DispatchSemaphore(value: 0)
        let drained = DispatchSemaphore(value: 0)
        let buffer = LockedBuffer()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        try? pipe.fileHandleForWriting.close()
        DispatchQueue.global(qos: .utility).async {
            defer { try? pipe.fileHandleForReading.close(); drained.signal() }
            while let data = PipeReader.chunk(from: pipe.fileHandleForReading) { buffer.append(data) }
        }
        let deadline = Date().addingTimeInterval(timeout)
        var stopError: CableError?
        while true {
            if cancellation?.isCancelled == true { stopError = .cancelled; break }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { stopError = .timeout; break }
            if done.wait(timeout: .now() + min(remaining, 0.1)) == .success { break }
        }
        if stopError != nil {
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                _ = done.wait(timeout: .now() + 1)
            }
        }
        _ = drained.wait(timeout: .now() + 1)
        if let stopError { throw stopError }
        return CommandResult(status: process.terminationStatus, output: buffer.text)
    }
}

final class Cancellation {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
