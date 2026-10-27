import AppKit

final class PhoneFileBrowser: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let controller: SessionController
    private let window: NSWindow
    private let table = NSTableView()
    private let pathLabel = NSTextField(labelWithString: TransferPolicy.downloads)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let up = NSButton(title: "Up", target: nil, action: nil)
    private let receive = NSButton(title: "Receive file…", target: nil, action: nil)
    private var entries: [PhoneFile] = []
    private var path = TransferPolicy.downloads
    private var loading = false
    private var closed = false
    var onChoose: ((PhoneFile) -> Void)?

    init(controller: SessionController) {
        self.controller = controller
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Receive from phone · Shared storage"
        window.isReleasedWhenClosed = false; window.delegate = self
        let content = NSView(); window.contentView = content
        let layout = NSStackView(); layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 12
        content.addSubview(layout); layout.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            layout.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            layout.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            layout.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        up.target = self; up.action = #selector(goUp); up.bezelStyle = .rounded
        pathLabel.lineBreakMode = .byTruncatingMiddle; pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let heading = NSStackView(views: [up, pathLabel]); heading.orientation = .horizontal; heading.spacing = 10
        layout.addArrangedSubview(heading)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")); column.title = "Name"
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 29
        table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(openSelection)
        table.allowsMultipleSelection = false
        table.setAccessibilityLabel("Files in phone shared storage")
        scroll.documentView = table
        layout.addArrangedSubview(scroll)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.maximumNumberOfLines = 2
        layout.addArrangedSubview(status)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel)); cancel.bezelStyle = .rounded
        receive.target = self; receive.action = #selector(choose); receive.bezelStyle = .rounded; receive.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), cancel, receive]); footer.orientation = .horizontal; footer.spacing = 10
        layout.addArrangedSubview(footer)
        for view in [heading, scroll, status, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
        }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
    }

    func show() { window.center(); window.makeKeyAndOrderFront(nil); load(path) }
    private func load(_ destination: String) {
        guard !loading, let checked = try? TransferPolicy.sharedPath(destination) else { return }
        path = checked; pathLabel.stringValue = checked; loading = true
        status.stringValue = "Reading folder…"; receive.isEnabled = false; up.isEnabled = false
        controller.listPhoneFiles(checked) { [weak self] result in
            guard let self, !self.closed else { return }
            self.loading = false
            switch result {
            case .success(let files):
                self.entries = files
                self.status.stringValue = files.isEmpty ? "This folder is empty." : "Double-click a folder to open it. Select a file to save it on your Mac."
            case .failure(let error): self.entries = []; self.status.stringValue = error.localizedDescription
            }
            self.table.reloadData(); self.up.isEnabled = self.path != "/sdcard" && self.path != "/storage/emulated/0"
            self.receive.isEnabled = false
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let item = entries[row]
        let label = NSTextField(labelWithString: (item.isDirectory ? "▸  " : "     ") + item.name)
        label.font = .systemFont(ofSize: 13); label.lineBreakMode = .byTruncatingMiddle
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        receive.isEnabled = !loading && entries.indices.contains(row) && !entries[row].isDirectory
    }
    @objc private func goUp() { load((path as NSString).deletingLastPathComponent) }
    @objc private func openSelection() {
        let row = table.selectedRow
        guard !loading, entries.indices.contains(row) else { return }
        if entries[row].isDirectory { load(entries[row].path) } else { choose() }
    }
    @objc private func choose() {
        let row = table.selectedRow
        guard !loading, entries.indices.contains(row), !entries[row].isDirectory else { return }
        closed = true; window.close(); onChoose?(entries[row])
    }
    @objc private func cancel() { controller.cancelTransfer(); closed = true; window.close() }
    func windowWillClose(_ notification: Notification) { if !closed { controller.cancelTransfer() }; closed = true }
}
