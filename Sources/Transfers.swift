import Foundation

struct PhoneFile: Equatable {
    let name: String
    let path: String
    let isDirectory: Bool
}

enum TransferPolicy {
    static let downloads = "/sdcard/Download"
    static let uploadRoot = "/sdcard/Download/CableDeX"

    static func sharedPath(_ value: String) throws -> String {
        guard value.count <= 4096, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              value == "/sdcard" || value.hasPrefix("/sdcard/") || value == "/storage/emulated/0" || value.hasPrefix("/storage/emulated/0/") else {
            throw CableError.message("Choose a file in the phone’s shared storage.")
        }
        var path = value
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func quote(_ value: String) throws -> String {
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CableError.message("This filename contains unsupported control characters.")
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func fileName(_ value: String) throws -> String {
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"), value.utf8.count <= 240 else {
            throw CableError.message("This filename is not supported.")
        }
        _ = try quote(value)
        return value
    }

    static func listing(_ output: String, directory: String) -> [PhoneFile] {
        var entries = output.split(whereSeparator: \.isNewline).prefix(2000).compactMap { line -> PhoneFile? in
            let raw = String(line)
            let directoryEntry = raw.hasSuffix("/")
            let name = directoryEntry ? String(raw.dropLast()) : raw
            guard (try? fileName(name)) != nil, let path = try? sharedPath(directory + "/" + name) else { return nil }
            return PhoneFile(name: name, path: path, isDirectory: directoryEntry)
        }
        entries.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return entries
    }
}

extension USBBridge {
    private func transferDevice(_ expected: USBDevice) throws -> USBDevice {
        try verifyTools()
        guard let fresh = try devices().first(where: { $0.serial == expected.serial && $0.transportID == expected.transportID && $0.isAuthorized }) else {
            throw CableError.message("The USB connection changed. Click Find phone and try again.")
        }
        return fresh
    }

    private func checked(_ device: USBDevice, _ args: [String], token: Cancellation, timeout: TimeInterval = 15) throws -> CommandResult {
        let result = try CommandRunner.run(adb, ["-t", String(device.transportID)] + args, environment: environment,
                                           timeout: timeout, cancellation: token)
        guard result.status == 0 else {
            throw CableError.message("File transfer failed: " + String(result.output.suffix(1200)))
        }
        return result
    }

    func listFiles(at path: String, device: USBDevice, token: Cancellation) throws -> [PhoneFile] {
        let path = try TransferPolicy.sharedPath(path)
        let fresh = try transferDevice(device)
        let result = try checked(fresh, ["shell", "ls -1ap -- " + TransferPolicy.quote(path)], token: token)
        return TransferPolicy.listing(result.output, directory: path)
    }

    func upload(_ urls: [URL], device: USBDevice, token: Cancellation) throws -> String {
        guard !urls.isEmpty, urls.count <= 100 else { throw CableError.message("Choose between 1 and 100 files.") }
        var names = Set<String>()
        for url in urls {
            guard url.isFileURL, try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
                throw CableError.message("Choose regular files, not folders or symbolic links.")
            }
            let name = try TransferPolicy.fileName(url.lastPathComponent)
            guard names.insert(name).inserted else { throw CableError.message("Files with the same name must be sent separately.") }
        }
        let fresh = try transferDevice(device)
        let folder = TransferPolicy.uploadRoot + "/Transfer-" + UUID().uuidString
        _ = try checked(fresh, ["shell", "mkdir -p -- " + TransferPolicy.quote(folder)], token: token)
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let target = folder + "/" + url.lastPathComponent
            let partial = folder + "/.partial-" + UUID().uuidString
            _ = try checked(fresh, ["push", url.path, partial], token: token, timeout: 300)
            _ = try checked(fresh, ["shell", "mv -- " + TransferPolicy.quote(partial) + " " + TransferPolicy.quote(target)], token: token)
        }
        return folder
    }

    func download(_ remote: String, to destination: URL, replaceExisting: Bool, device: USBDevice, token: Cancellation) throws {
        let remote = try TransferPolicy.sharedPath(remote)
        guard destination.isFileURL else { throw CableError.message("Choose a local destination file.") }
        let fm = FileManager.default
        let existing = try? fm.attributesOfItem(atPath: destination.path)
        if let existing {
            guard replaceExisting, existing[.type] as? FileAttributeType == .typeRegular else {
                throw CableError.message("The destination exists. Choose a different name or explicitly approve replacement.")
            }
        }
        let fresh = try transferDevice(device)
        _ = try checked(fresh, ["shell", "test -f " + TransferPolicy.quote(remote)], token: token)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".cabledex-" + UUID().uuidString + ".partial")
        defer { try? fm.removeItem(at: staging) }
        _ = try checked(fresh, ["pull", remote, staging.path], token: token, timeout: 300)
        if token.isCancelled { throw CableError.cancelled }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        if let existing {
            let current = try fm.attributesOfItem(atPath: destination.path)
            guard (current[.modificationDate] as? Date) == (existing[.modificationDate] as? Date),
                  (current[.size] as? NSNumber) == (existing[.size] as? NSNumber) else {
                throw CableError.message("The destination changed during transfer. Save under a new name.")
            }
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else { try fm.moveItem(at: staging, to: destination) }
    }
}
