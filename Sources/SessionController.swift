import Foundation

enum SessionState: Equatable {
    case idle, checking, starting, running, stopping, failed(String)
    var busy: Bool {
        switch self { case .checking, .starting, .running, .stopping: return true; default: return false }
    }
}

final class SessionController {
    var onChange: (() -> Void)?
    private(set) var state: SessionState = .idle
    private(set) var devices: [USBDevice] = []
    private(set) var scanning = false
    private(set) var detail = "Connect your Galaxy with a USB-C data cable, then click Find phone."
    private(set) var windowing = "Not started"
    private(set) var frameRate: Int?
    private(set) var hostPipeline: String?
    private(set) var transferBusy = false
    private(set) var transferStatus = "Files move only when you choose Send files or Browse phone."
    var canTransfer: Bool {
        !preview && !scanning && !transferBusy && settings.fileTransfer && settings.inputControl &&
        selectedDevice?.isAuthorized == true && (!state.busy || state == .running)
    }
    private(set) var recentLines: [String] = []
    var selectedSerial: String?
    var selectedDevice: USBDevice? { devices.first { $0.serial == selectedSerial } }
    var settings = DisplaySettings.load()
    private(set) var bridge: USBBridge?
    private(set) var log: SessionLog?
    let preview: Bool
    private let persistSettings: Bool
    private let worker = DispatchQueue(label: "com.cabledex.usb-commands", qos: .userInitiated)
    private let fileWorker = DispatchQueue(label: "com.cabledex.file-transfer", qos: .utility)
    private let transferGroup = DispatchGroup()
    private var transferToken: Cancellation?
    private var video: VideoProcess?
    private var sessionID: UUID?
    private var cancellation: Cancellation?
    private var activeDevice: USBDevice?
    private var activeSettings: DisplaySettings?
    private var displayID: Int?
    private var didRequestStop = false
    private var stopCompletions: [() -> Void] = []

    init(preview: Bool = false, bridge injectedBridge: USBBridge? = nil, persistSettings: Bool = true) {
        self.preview = preview
        self.persistSettings = persistSettings
        if preview {
            detail = "Preview · no phone or USB bridge is accessed."
            return
        }
        if let injectedBridge { bridge = injectedBridge; return }
        do { bridge = try USBBridge(); log = try SessionLog() }
        catch { state = .failed(error.localizedDescription); detail = error.localizedDescription }
    }

    private func changed() { onChange?() }

    func refresh() {
        guard !state.busy, !scanning, !transferBusy else { return }
        if preview {
            devices = [USBDevice(serial: "CABLEDEX_DEMO", name: "Galaxy S24 Ultra (preview)", state: "device", transportID: 1)]
            selectedSerial = devices.first?.serial
            detail = "Preview device only. Connect is disabled in preview mode."
            changed(); return
        }
        guard let bridge else { return }
        scanning = true; detail = "Looking for a phone connected by USB…"; changed()
        worker.async { [weak self] in
            let result: Result<[USBDevice], Error> = Result {
                try bridge.verifyTools()
                return try bridge.devices()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                switch result {
                case .success(let found):
                    self.devices = found
                    if !found.contains(where: { $0.serial == self.selectedSerial }) { self.selectedSerial = found.first?.serial }
                    self.state = .idle
                    self.detail = found.isEmpty ? "No USB phone found. Unlock it, enable USB debugging, and check the data cable." :
                        found.contains(where: { $0.isAuthorized }) ? "Your USB phone is ready. Choose a mode and connect." :
                        "Unlock your phone and accept Allow USB debugging, then click Find phone again."
                case .failure(let error): self.state = .failed(error.localizedDescription); self.detail = error.localizedDescription
                }
                self.changed()
            }
        }
    }

    func start() {
        guard !preview, !state.busy, !scanning, !transferBusy, let bridge, let device = selectedDevice, device.isAuthorized else { return }
        let chosen: DisplaySettings
        do { chosen = try settings.validated() }
        catch { state = .failed(error.localizedDescription); changed(); return }
        if persistSettings { chosen.save() }
        let id = UUID()
        let token = Cancellation()
        sessionID = id; cancellation = token; activeDevice = device; activeSettings = chosen
        didRequestStop = false; displayID = nil; frameRate = nil; hostPipeline = nil
        state = .checking; detail = "Checking the selected USB connection…"; windowing = chosen.mode == .desktop ? "Waiting for desktop" : "Phone screen"
        recentLines.removeAll(); appendLog("Starting \(chosen.mode.title), \(chosen.width)×\(chosen.height), \(chosen.codec.rawValue), \(chosen.fps) fps, \(chosen.bitrate) Mbps. USB only.")
        changed()
        worker.async { [weak self] in
            let result: Result<USBDevice, Error> = Result {
                try bridge.verifyTools()
                guard !token.isCancelled else { throw CableError.message("Connection cancelled.") }
                // Revalidate the transport immediately before launching; a saved serial is insufficient.
                let fresh = try bridge.devices()
                guard let current = fresh.first(where: { $0.serial == device.serial && $0.transportID == device.transportID && $0.isAuthorized }) else {
                    throw CableError.message("The selected USB phone is no longer ready. Reconnect it and click Find phone.")
                }
                return current
            }
            DispatchQueue.main.async {
                guard let self, self.sessionID == id, !token.isCancelled else { return }
                switch result {
                case .success(let current): self.launch(bridge: bridge, device: current, settings: chosen, id: id)
                case .failure(let error): self.finish(status: -1, id: id, error: error.localizedDescription)
                }
            }
        }
    }

    private func launch(bridge: USBBridge, device: USBDevice, settings: DisplaySettings, id: UUID) {
        let stream = VideoProcess()
        do {
            try stream.start(bridge: bridge, settings: settings, arguments: settings.arguments(for: device), onLine: { [weak self] line in
                guard let self, self.sessionID == id else { return }
                self.handle(line, id: id)
            }, onExit: { [weak self] status in self?.finish(status: status, id: id) })
            video = stream
            state = .starting; detail = "Opening your phone display in a new window…"; changed()
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.sessionID == id, self.state == .starting else { return }
                self.detail = "Still waiting for video. Check the phone for an authorization prompt, or disconnect and try Phone screen mode."
                self.changed()
            }
        } catch { finish(status: -1, id: id, error: error.localizedDescription) }
    }

    private func handle(_ line: String, id: UUID) {
        appendLog(line)
        switch StreamEvent.parse(line) {
        case .display(let number):
            displayID = number
            guard activeSettings?.mode == .desktop, activeSettings?.resizableWindows == true,
                  let bridge, let device = activeDevice, let token = cancellation, !token.isCancelled else { changed(); return }
            windowing = "Enabling resizable windows…"
            worker.async { [weak self] in
                guard !token.isCancelled else { return }
                let result = try? bridge.setWindowingMode(5, display: number, device: device)
                DispatchQueue.main.async {
                    guard let self, self.sessionID == id, !token.isCancelled else { return }
                    if let result, result.status == 0, !result.output.lowercased().contains("error"), !result.output.lowercased().contains("unknown") {
                        self.windowing = "Resizable windows requested"
                        self.appendLog("Requested freeform windows on this session's display \(number).")
                    } else {
                        self.windowing = "Windowing unavailable on this firmware"
                        self.appendLog("The phone did not accept the windowing request. " + (result?.output ?? "USB command failed."))
                    }
                    self.changed()
                }
            }
        case .frameReady:
            if !didRequestStop { state = .running; detail = "USB display connected. Use the separate display window to control your phone." }
        case .fps(let fps): frameRate = fps
        case .hostPipeline(let mean, let maximum, _):
            hostPipeline = String(format: "Mac pipeline %.1f ms avg / %.1f ms max", mean, maximum)
        case .softwareDecoder: appendLog("Hardware decoding was unavailable; scrcpy is using software decoding.")
        default: break
        }
        changed()
    }

    func stop(completion: (() -> Void)? = nil) {
        if let completion { stopCompletions.append(completion) }
        guard state.busy, sessionID != nil else { completeStops(); return }
        guard !didRequestStop else { return }
        cancelTransfer()
        didRequestStop = true; cancellation?.cancel()
        state = .stopping; detail = "Closing the USB session…"; changed()
        let id = sessionID
        // Clear only our newly-created secondary display's override, before scrcpy removes the display.
        let bridge = self.bridge, device = activeDevice, display = displayID
        worker.async { [weak self] in
            if let bridge, let device, let display { _ = try? bridge.setWindowingMode(0, display: display, device: device) }
            DispatchQueue.main.async {
                guard let self, self.sessionID == id else { return }
                if let video = self.video { video.stop() }
                else if let id { self.finish(status: 0, id: id) }
            }
        }
    }

    private func finish(status: Int32, id: UUID, error: String? = nil) {
        guard sessionID == id else { return }
        let expected = didRequestStop || status == 0
        cancellation?.cancel(); cancellation = nil; sessionID = nil; video = nil
        activeDevice = nil; activeSettings = nil; displayID = nil; frameRate = nil; hostPipeline = nil; windowing = "Not started"
        if expected {
            state = .idle; detail = "Session closed. Your Mac display settings have not changed."
        } else {
            let message = error ?? "The USB session ended unexpectedly. Check the cable and phone, or try Phone screen mode. Details are in the session log."
            state = .failed(message); detail = message
        }
        appendLog(expected ? "Session closed." : "Session ended (\(status)).")
        changed(); completeStops()
    }

    private func completeStops() {
        let callbacks = stopCompletions; stopCompletions.removeAll(); callbacks.forEach { $0() }
    }

    func shutdown(completion: @escaping () -> Void) {
        cancelTransfer()
        stop { [weak self] in
            guard let self else { completion(); return }
            let bridge = self.bridge
            self.transferGroup.notify(queue: self.worker) {
                bridge?.shutdown()
                DispatchQueue.main.async { completion() }
            }
        }
    }

    private func fileTask<T>(_ label: String, operation: @escaping (USBBridge, USBDevice, Cancellation) throws -> T,
                             completion: @escaping (Result<T, Error>) -> Void) {
        guard canTransfer, let bridge, let device = selectedDevice else {
            completion(.failure(CableError.message("Connect an authorized USB phone and enable file transfer first."))); return
        }
        let token = Cancellation()
        transferToken = token; transferBusy = true; transferStatus = label; changed()
        let group = transferGroup
        group.enter()
        fileWorker.async { [weak self] in
            let result = Result { try operation(bridge, device, token) }
            group.leave()
            DispatchQueue.main.async {
                guard let self, self.transferToken === token else { return }
                self.transferToken = nil; self.transferBusy = false
                switch result {
                case .success: self.transferStatus = "Transfer complete."
                case .failure(let error): self.transferStatus = error.localizedDescription
                }
                self.changed(); completion(result)
            }
        }
    }

    func listPhoneFiles(_ path: String, completion: @escaping (Result<[PhoneFile], Error>) -> Void) {
        fileTask("Reading phone folder…", operation: { try $0.listFiles(at: path, device: $1, token: $2) }) { [weak self] result in
            if case .success = result { self?.transferStatus = "Phone folder ready."; self?.changed() }
            completion(result)
        }
    }

    func sendFiles(_ urls: [URL], completion: @escaping (Result<String, Error>) -> Void) {
        fileTask("Sending \(urls.count) file(s) over USB…", operation: { try $0.upload(urls, device: $1, token: $2) }) { [weak self] result in
            if case .success(let folder) = result {
                self?.transferStatus = "Sent \(urls.count) file(s) to Download/CableDeX/\(folder.split(separator: "/").last ?? "")."
                self?.changed()
            }
            completion(result)
        }
    }

    func receiveFile(_ path: String, destination: URL, replaceExisting: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        fileTask("Receiving file over USB…", operation: { bridge, device, token in
            try bridge.download(path, to: destination, replaceExisting: replaceExisting, device: device, token: token)
        }) { [weak self] result in
            if case .success = result { self?.transferStatus = "Received \(destination.lastPathComponent)."; self?.changed() }
            completion(result)
        }
    }

    func cancelTransfer() { transferToken?.cancel() }

    private func appendLog(_ line: String) {
        let safeLine = String(line.prefix(3000))
        recentLines.append(safeLine)
        if recentLines.count > 250 { recentLines.removeFirst(recentLines.count - 250) }
        log?.write(safeLine)
    }
}
