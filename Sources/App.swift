import AppKit

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let controller = SessionController(preview: CommandLine.arguments.contains("--preview"))
    private var window: NSWindow!
    private var logWindow: NSWindow?
    private var logText: NSTextView?
    private var isQuitting = false
    private let device = NSPopUpButton()
    private let mode = NSSegmentedControl(labels: ["Desktop", "Phone screen"], trackingMode: .selectOne, target: nil, action: nil)
    private let resolution = NSPopUpButton(), density = NSPopUpButton(), codec = NSPopUpButton()
    private let bitrate = NSPopUpButton(), fps = NSPopUpButton()
    private let inputControl = NSButton(checkboxWithTitle: "Allow keyboard and mouse control", target: nil, action: nil)
    private let phoneScreenOff = NSButton(checkboxWithTitle: "Turn phone display off while connected", target: nil, action: nil)
    private let audio = NSButton(checkboxWithTitle: "Play phone audio on this Mac", target: nil, action: nil)
    private let clipboard = NSButton(checkboxWithTitle: "Share text clipboard", target: nil, action: nil)
    private let fileTransfer = NSButton(checkboxWithTitle: "Allow selected file transfers", target: nil, action: nil)
    private let sendButton = NSButton(title: "Send files…", target: nil, action: nil)
    private let browseButton = NSButton(title: "Browse phone…", target: nil, action: nil)
    private let cancelFileButton = NSButton(title: "Cancel transfer", target: nil, action: nil)
    private let transferStatus = NSTextField(wrappingLabelWithString: "")
    private let sharingNote = NSTextField(wrappingLabelWithString: "")
    private var fileBrowser: PhoneFileBrowser?
    private let windows = NSButton(checkboxWithTitle: "Enable resizable desktop windows", target: nil, action: nil)
    private let fullscreen = NSButton(checkboxWithTitle: "Open display in full screen", target: nil, action: nil)
    private let statusTitle = NSTextField(labelWithString: "Ready when you are")
    private let statusDetail = NSTextField(wrappingLabelWithString: "")
    private let statusDot = NSView()
    private let statusFooter = NSTextField(wrappingLabelWithString: "")
    private let modeDetail = NSTextField(wrappingLabelWithString: "")
    private let refreshButton = NSButton(title: "Find phone", target: nil, action: nil)
    private let connectButton = NSButton(title: "Connect display", target: nil, action: nil)
    private let stopButton = NSButton(title: "Disconnect", target: nil, action: nil)
    private var settingControls: [NSControl] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = controller.preview ? "CableDeX · Preview" : "CableDeX"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = .windowBackgroundColor
        buildContent()
        controller.onChange = { [weak self] in self?.update() }
        update()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About CableDeX", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide CableDeX", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CableDeX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Connect your Galaxy", action: #selector(setupHelp), keyEquivalent: "?")
        help.addItem(withTitle: "Session log", action: #selector(showLog), keyEquivalent: "l")
        helpItem.submenu = help
        NSApp.mainMenu = main
    }

    private func buildContent() {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = FlippedView()
        scroll.documentView = document
        let container = NSView()
        let footer = NSView()
        window.contentView = container
        container.addSubview(scroll); container.addSubview(footer)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 84)
        ])
        document.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let body = NSStackView()
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 20
        body.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            body.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])

        let icon = NSImageView(image: NSImage(systemSymbolName: "display", accessibilityDescription: nil)!)
        icon.contentTintColor = .systemBlue
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let title = label("CableDeX", size: 29, weight: .bold)
        let subtitle = label("Your Galaxy desktop, over one cable.", size: 13, color: .secondaryLabelColor)
        let titleStack = column([title, subtitle], spacing: 3)
        let badge = label("USB ONLY", size: 10, weight: .bold, color: .systemBlue)
        let heading = row([icon, titleStack, NSView(), badge], spacing: 12)
        add(heading, to: body)

        statusDot.wantsLayer = true; statusDot.layer?.cornerRadius = 4
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        statusTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        statusDetail.font = .systemFont(ofSize: 12)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.maximumNumberOfLines = 3
        statusDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let statusRow = row([statusDot, statusTitle, NSView()], spacing: 8)
        device.addItem(withTitle: "No USB phone selected")
        device.target = self; device.action = #selector(selectDevice)
        device.setAccessibilityLabel("USB phone")
        device.setContentHuggingPriority(.defaultLow, for: .horizontal)
        refreshButton.target = self; refreshButton.action = #selector(refresh)
        refreshButton.bezelStyle = .rounded
        let deviceRow = row([device, refreshButton], spacing: 10)
        statusFooter.font = .systemFont(ofSize: 11, weight: .medium)
        statusFooter.maximumNumberOfLines = 3
        statusFooter.textColor = .secondaryLabelColor
        add(card(column([statusRow, statusDetail, deviceRow, statusFooter], spacing: 12)), to: body)

        mode.selectedSegment = controller.settings.mode == .desktop ? 0 : 1
        mode.target = self; mode.action = #selector(settingsChanged)
        mode.segmentStyle = .rounded
        mode.setAccessibilityLabel("Display mode")
        modeDetail.font = .systemFont(ofSize: 12)
        modeDetail.textColor = .secondaryLabelColor
        modeDetail.maximumNumberOfLines = 2
        let displayHeader = row([label("Display", size: 15, weight: .semibold), NSView(), mode], spacing: 12)
        resolution.addItems(withTitles: ["1920 × 1080 · Full HD", "2560 × 1440 · QHD", "2880 × 1800 · 16:10"])
        resolution.selectItem(at: DisplaySettings.resolutions.firstIndex { $0.0 == controller.settings.width && $0.1 == controller.settings.height } ?? 1)
        density.addItems(withTitles: DisplaySettings.densities.map { "\($0) DPI" })
        density.selectItem(at: DisplaySettings.densities.firstIndex(of: controller.settings.dpi) ?? 1)
        codec.addItems(withTitles: VideoCodec.allCases.map(\.title)); codec.selectItem(at: controller.settings.codec == .h264 ? 0 : 1)
        bitrate.addItems(withTitles: DisplaySettings.bitrates.map { "\($0) Mbps" })
        bitrate.selectItem(at: DisplaySettings.bitrates.firstIndex(of: controller.settings.bitrate) ?? 2)
        fps.addItems(withTitles: ["30 fps", "60 fps"]); fps.selectItem(at: controller.settings.fps == 30 ? 0 : 1)
        for (control, name) in [(resolution, "Resolution"), (density, "Interface size"), (codec, "Video codec"), (bitrate, "Video quality"), (fps, "Frame rate")] {
            control.target = self; control.action = #selector(settingsChanged); control.setAccessibilityLabel(name)
        }
        let first = equalRow([field("RESOLUTION", resolution), field("INTERFACE SIZE", density)])
        let second = equalRow([field("ENCODING", codec), field("VIDEO QUALITY", bitrate)])
        let third = equalRow([field("FRAME RATE", fps), column([label("VIDEO BUFFER", size: 10, weight: .semibold, color: .secondaryLabelColor), label("0 ms added", size: 13)], spacing: 7)])
        let divider = NSBox(); divider.boxType = .separator
        windows.state = controller.settings.resizableWindows ? .on : .off
        fullscreen.state = controller.settings.fullscreen ? .on : .off
        phoneScreenOff.state = controller.settings.phoneScreenOff ? .on : .off
        phoneScreenOff.toolTip = "Turns off the panel without locking Android. Use this instead of the phone's power button; locking Android may suspend the session."
        for control in [windows, fullscreen, phoneScreenOff] { control.target = self; control.action = #selector(settingsChanged) }
        let screenOffNote = NSTextField(wrappingLabelWithString: "Use this option instead of locking the phone. Android must remain unlocked for an interactive desktop.")
        screenOffNote.font = .systemFont(ofSize: 11); screenOffNote.textColor = .secondaryLabelColor
        add(card(column([displayHeader, modeDetail, first, second, third, divider, windows, fullscreen, phoneScreenOff, screenOffNote], spacing: 14)), to: body)

        inputControl.state = controller.settings.inputControl ? .on : .off
        inputControl.target = self; inputControl.action = #selector(settingsChanged)
        audio.state = controller.settings.audio ? .on : .off
        clipboard.state = controller.settings.clipboard ? .on : .off
        fileTransfer.state = controller.settings.fileTransfer ? .on : .off
        for control in [audio, clipboard, fileTransfer] { control.target = self; control.action = #selector(settingsChanged) }
        let privacyTitle = row([label("USB sharing", size: 15, weight: .semibold), NSView(), label("YOUR CHOICE", size: 10, weight: .medium, color: .systemBlue)])
        sharingNote.font = .systemFont(ofSize: 11); sharingNote.textColor = .secondaryLabelColor
        sharingNote.maximumNumberOfLines = 3
        sendButton.target = self; sendButton.action = #selector(sendFiles); sendButton.bezelStyle = .rounded
        browseButton.target = self; browseButton.action = #selector(browsePhone); browseButton.bezelStyle = .rounded
        cancelFileButton.target = self; cancelFileButton.action = #selector(cancelFiles); cancelFileButton.bezelStyle = .inline
        transferStatus.font = .systemFont(ofSize: 11); transferStatus.textColor = .secondaryLabelColor; transferStatus.maximumNumberOfLines = 3
        let transferButtons = row([sendButton, browseButton, NSView(), cancelFileButton], spacing: 10)
        add(card(column([privacyTitle, inputControl, audio, clipboard, fileTransfer, sharingNote, transferButtons, transferStatus], spacing: 12)), to: body)

        let note = label("Only your phone’s stream changes size. Your Mac display stays as it is.", size: 11, color: .secondaryLabelColor)
        let help = NSButton(title: "Setup guide", target: self, action: #selector(setupHelp))
        help.bezelStyle = .inline
        let log = NSButton(title: "Session log", target: self, action: #selector(showLog))
        log.bezelStyle = .inline
        connectButton.bezelStyle = .rounded
        connectButton.bezelColor = .controlAccentColor
        connectButton.keyEquivalent = "\r"
        connectButton.target = self; connectButton.action = #selector(connect)
        stopButton.bezelStyle = .rounded
        stopButton.target = self; stopButton.action = #selector(stop)
        let footerContent = column([note, row([help, log, NSView(), stopButton, connectButton], spacing: 12)], spacing: 10)
        footer.addSubview(footerContent); footerContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            footerContent.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 28),
            footerContent.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -28),
            footerContent.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        settingControls = [mode, resolution, density, codec, bitrate, fps, inputControl, phoneScreenOff, windows, fullscreen, audio, clipboard, fileTransfer]
    }

    private func label(_ title: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let view = NSTextField(labelWithString: title)
        view.font = .systemFont(ofSize: size, weight: weight); view.textColor = color
        return view
    }
    private func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.spacing = spacing; stack.alignment = .centerY
        return stack
    }
    private func equalRow(_ views: [NSView]) -> NSStackView {
        let stack = row(views, spacing: 20); stack.distribution = .fillEqually; return stack
    }
    private func column(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.spacing = spacing; stack.alignment = .leading
        for view in views { view.translatesAutoresizingMaskIntoConstraints = false; view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }
    private func field(_ title: String, _ control: NSControl) -> NSView {
        column([label(title, size: 10, weight: .semibold, color: .secondaryLabelColor), control], spacing: 6)
    }
    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func card(_ content: NSView) -> NSView {
        let view = NSView(); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = 14
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        view.layer?.borderWidth = 0.5
        view.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
        return view
    }

    private func update() {
        let selected = controller.selectedSerial
        device.removeAllItems()
        if controller.devices.isEmpty { device.addItem(withTitle: "No USB phone selected") }
        else {
            device.addItems(withTitles: controller.devices.map(\.label))
            if let i = controller.devices.firstIndex(where: { $0.serial == selected }) { device.selectItem(at: i) }
        }
        let busy = controller.state.busy
        let editable = !busy && !controller.transferBusy
        for control in settingControls { control.isEnabled = editable }
        device.isEnabled = editable && !controller.scanning && !controller.devices.isEmpty
        refreshButton.isEnabled = editable && !controller.scanning
        refreshButton.title = controller.scanning ? "Finding…" : "Find phone"
        connectButton.isEnabled = editable && !controller.scanning && controller.selectedDevice?.isAuthorized == true && !controller.preview
        connectButton.isHidden = busy
        stopButton.isHidden = !busy
        stopButton.isEnabled = busy && controller.state != .stopping
        statusDetail.stringValue = controller.detail
        let color: NSColor
        switch controller.state {
        case .idle:
            statusTitle.stringValue = controller.scanning ? "Finding your phone" : controller.selectedDevice?.isAuthorized == true ? "Ready to connect" : "Connect your Galaxy"
            color = controller.selectedDevice?.isAuthorized == true ? .systemGreen : .tertiaryLabelColor
        case .checking: statusTitle.stringValue = "Checking USB"; color = .systemOrange
        case .starting: statusTitle.stringValue = "Opening display"; color = .systemOrange
        case .running: statusTitle.stringValue = "USB display connected"; color = .systemGreen
        case .stopping: statusTitle.stringValue = "Disconnecting"; color = .systemOrange
        case .failed: statusTitle.stringValue = "Connection needs attention"; color = .systemRed
        }
        statusDot.layer?.backgroundColor = color.cgColor
        if controller.state == .running {
            let frames = controller.frameRate.map { " · \($0) fps captured" } ?? ""
            statusFooter.stringValue = controller.windowing + frames + (controller.hostPipeline.map { "\n" + $0 + " · excludes phone/USB/display delay" } ?? "")
        } else {
            statusFooter.stringValue = controller.preview ? "PREVIEW · no device access" : "USB only · no Wi-Fi fallback · works without internet"
        }
        let desktop = controller.settings.mode == .desktop
        density.isEnabled = editable && desktop
        windows.isEnabled = editable && desktop
        phoneScreenOff.isEnabled = editable && controller.settings.inputControl
        clipboard.isEnabled = editable && controller.settings.inputControl
        fileTransfer.isEnabled = editable && controller.settings.inputControl
        sendButton.isEnabled = controller.canTransfer; browseButton.isEnabled = controller.canTransfer
        cancelFileButton.isHidden = !controller.transferBusy
        transferStatus.stringValue = controller.transferStatus
        sharingNote.stringValue = controller.settings.inputControl ?
            "Clipboard text moves between devices. Files move only when you select them. APK installation and recording stay blocked. Some apps block audio capture." :
            "Keyboard control is off; clipboard and file transfer are paused. Audio playback can remain enabled."
        modeDetail.stringValue = desktop ? "A separate workspace on your Galaxy. Newer One UI may use Android-style window controls." : "Mirror your phone’s existing screen. Resolution limits the stream; it does not change the phone’s screen settings."
        logText?.string = controller.recentLines.isEmpty ? "No session activity yet." : controller.recentLines.joined(separator: "\n")
    }

    @objc private func refresh() { controller.refresh() }
    @objc private func selectDevice() {
        let index = device.indexOfSelectedItem
        if controller.devices.indices.contains(index) { controller.selectedSerial = controller.devices[index].serial }
        update()
    }
    @objc private func settingsChanged() {
        guard !controller.state.busy else { return }
        var value = controller.settings
        value.mode = mode.selectedSegment == 0 ? .desktop : .mirror
        let size = DisplaySettings.resolutions[resolution.indexOfSelectedItem]
        value.width = size.0; value.height = size.1
        value.dpi = DisplaySettings.densities[density.indexOfSelectedItem]
        value.codec = codec.indexOfSelectedItem == 0 ? .h264 : .h265
        value.bitrate = DisplaySettings.bitrates[bitrate.indexOfSelectedItem]
        value.fps = fps.indexOfSelectedItem == 0 ? 30 : 60
        value.audio = audio.state == .on; value.clipboard = clipboard.state == .on
        value.fileTransfer = fileTransfer.state == .on
        value.phoneScreenOff = phoneScreenOff.state == .on; value.inputControl = inputControl.state == .on
        value.resizableWindows = windows.state == .on; value.fullscreen = fullscreen.state == .on
        controller.settings = value
        if !controller.preview { value.save() }
        update()
    }
    @objc private func connect() { controller.start() }
    @objc private func stop() { controller.stop() }
    @objc private func sendFiles() {
        guard controller.canTransfer else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose files to send to your phone"
        panel.message = "Files are copied into a new folder under Download/CableDeX. Existing phone files are not overwritten."
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let self else { return }
            self.controller.sendFiles(panel.urls) { [weak self] result in
                if case .failure(let error) = result { self?.showTransferError(error) }
            }
        }
    }
    @objc private func browsePhone() {
        guard controller.canTransfer else { return }
        let browser = PhoneFileBrowser(controller: controller)
        browser.onChoose = { [weak self] file in self?.savePhoneFile(file) }
        fileBrowser = browser; browser.show()
    }
    private func savePhoneFile(_ file: PhoneFile) {
        fileBrowser = nil
        let panel = NSSavePanel()
        panel.title = "Save phone file on this Mac"; panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        window.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let destination = panel.url, let self else { return }
            let replace = FileManager.default.fileExists(atPath: destination.path)
            let access = destination.startAccessingSecurityScopedResource()
            self.controller.receiveFile(file.path, destination: destination, replaceExisting: replace) { [weak self] result in
                if access { destination.stopAccessingSecurityScopedResource() }
                if case .failure(let error) = result { self?.showTransferError(error) }
            }
        }
    }
    private func showTransferError(_ error: Error) {
        if case CableError.cancelled = error { return }
        let alert = NSAlert(); alert.messageText = "File transfer could not finish"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window)
    }
    @objc private func cancelFiles() { controller.cancelTransfer() }
    @objc private func setupHelp() {
        let alert = NSAlert()
        alert.messageText = "Connect your Galaxy over USB"
        alert.informativeText = "1. Enable USB debugging on your Galaxy, attach a USB-C data cable, and unlock the phone.\n\n2. Click Find phone, accept the phone's debugging prompt, and click Find phone again.\n\n3. Choose Desktop or Phone screen and connect. Use Turn phone display off instead of locking Android with its power button.\n\nUSB sharing: audio plays on the Mac, text clipboard sharing supports copy/paste, and Send files / Browse phone copy explicitly selected files. Sharing settings apply to the next display session. Right-click is forwarded; Command+B sends Android Back.\n\nUploads use a new folder under Download/CableDeX. Receive files with Browse phone, then choose a Mac save location. Direct file drops into the viewer and APK installation remain blocked.\n\nADB still grants broad access to this Mac. The temporary mirroring server is not an installed APK. Revoke debugging authorization when no longer needed."
        alert.addButton(withTitle: "Got it")
        alert.beginSheetModal(for: window)
    }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "CableDeX", .applicationVersion: "0.3.0",
            .credits: NSAttributedString(string: "USB-only desktop and screen mirroring.\nBased on dex-for-mac (MIT).\nPowered by scrcpy 5.0.1 and ADB.\nNot affiliated with Samsung or Genymobile.")
        ])
    }
    @objc private func showLog() {
        if let logWindow { logWindow.makeKeyAndOrderFront(nil); return }
        let logWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 380), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        logWindow.title = "CableDeX · Session log"; logWindow.isReleasedWhenClosed = false
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let text = NSTextView(); text.isEditable = false; text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textContainerInset = NSSize(width: 14, height: 14)
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; logWindow.contentView = scroll
        self.logWindow = logWindow; logText = text
        update(); logWindow.center(); logWindow.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window { NSApp.terminate(nil); return false }; return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isQuitting else { return .terminateLater }
        isQuitting = true
        controller.shutdown { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

@main
enum CableDeXApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
