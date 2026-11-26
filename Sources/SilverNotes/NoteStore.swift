import Foundation
import AppKit

/// Local-first persistence for SilverNotes v0.1.0.
///
/// Storage choice (documented deviation from the research register, which
/// recommended SQLite via a third-party dependency): this first build is
/// deliberately dependency-free, so the store is a single versioned JSON
/// document (`store.json`, `schemaVersion` field) in Application Support,
/// written atomically, with rotating backup snapshots alongside. The Codable
/// models are storage-agnostic, so migrating this document into SQLite later
/// is a store-layer change only — no view or editor code depends on JSON.
///
/// Attachments choice: every dropped file is copied (embedded) into the
/// app's Attachments directory. The register's alternative — security-scoped
/// bookmarks pointing at the original — was not chosen for the MVP because
/// embedded copies can never go stale or break when the original moves.
/// The trade-off (disk use) is documented in the README.
final class NoteStore {

    static let shared = NoteStore()

    private(set) var data: StoreData = .empty

    /// Called after *structural* changes (folder/note create, delete, pin,
    /// fold, colour, mode, trash, restore). Body edits from typing do NOT
    /// fire this — the editing card already has the text; a full reload
    /// mid-typing would destroy the editor state.
    var onStructuralChange: (() -> Void)?

    // MARK: Locations

    let rootDirectory: URL
    var storeFileURL: URL { rootDirectory.appendingPathComponent("store.json") }
    var attachmentsDirectory: URL { rootDirectory.appendingPathComponent("Attachments", isDirectory: true) }
    var backupsDirectory: URL { rootDirectory.appendingPathComponent("Backups", isDirectory: true) }

    private var saveTimer: Timer?
    private var lastBackupAt: Date = .distantPast

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        rootDirectory = base.appendingPathComponent("SilverNotes", isDirectory: true)
    }

    // MARK: Load / save

    func load() {
        let fm = FileManager.default
        try? fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        // Only write the store back at the end if something actually
        // changed (seeded, restored from backup, or trash purged) — a
        // clean load of an existing store leaves the file untouched.
        var changed = false
        if let raw = try? Data(contentsOf: storeFileURL),
           let decoded = try? JSONDecoder.storeDecoder.decode(StoreData.self, from: raw) {
            data = decoded
        } else if fm.fileExists(atPath: storeFileURL.path) {
            // Corrupt store: quarantine it, never delete it, then try the
            // newest backup before falling back to seed content.
            let quarantine = rootDirectory.appendingPathComponent("store-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.moveItem(at: storeFileURL, to: quarantine)
            if !restoreNewestBackup() {
                seedIfNeeded()
            }
            changed = true
        } else {
            seedIfNeeded()
            changed = true
        }
        let noteCountBeforePurge = data.notes.count
        purgeExpiredTrash()
        if data.notes.count != noteCountBeforePurge { changed = true }
        if changed { save() }
    }

    /// Atomic write of the whole document. Small data, called on a debounce
    /// for typing and immediately for structural changes.
    func save() {
        guard let raw = try? JSONEncoder.storeEncoder.encode(data) else { return }
        try? raw.write(to: storeFileURL, options: [.atomic])
        makeBackupIfDue()
    }

    /// Debounced save used by the editor while typing.
    func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.save()
        }
    }

    private func makeBackupIfDue() {
        let now = Date()
        guard now.timeIntervalSince(lastBackupAt) > 3600 else { return }
        lastBackupAt = now
        let name = "store-backup-\(Int(now.timeIntervalSince1970)).json"
        let dest = backupsDirectory.appendingPathComponent(name)
        try? FileManager.default.copyItem(at: storeFileURL, to: dest)
        // Keep the 7 newest snapshots. Backup file names embed the epoch
        // second, so sorting by name sorts by age.
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsDirectory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let sorted = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in sorted.dropFirst(7) { try? FileManager.default.removeItem(at: old) }
    }

    @discardableResult
    private func restoreNewestBackup() -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsDirectory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let sorted = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in sorted {
            if let raw = try? Data(contentsOf: file),
               let decoded = try? JSONDecoder.storeDecoder.decode(StoreData.self, from: raw) {
                data = decoded
                return true
            }
        }
        return false
    }

    // MARK: Queries

    var folders: [SNFolder] {
        data.folders.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.sortIndex < b.sortIndex
        }
    }

    func folder(id: UUID) -> SNFolder? { data.folders.first { $0.id == id } }

    func notes(in folderID: UUID) -> [SNNote] {
        data.notes
            .filter { $0.folderID == folderID && $0.deletedAt == nil }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.sortIndex < b.sortIndex
            }
    }

    func note(id: UUID) -> SNNote? { data.notes.first { $0.id == id } }

    func noteCount(in folderID: UUID) -> Int {
        data.notes.filter { $0.folderID == folderID && $0.deletedAt == nil }.count
    }

    var trashedNotes: [SNNote] {
        data.notes.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// Search across all folders, title matches first, then body matches.
    func search(_ query: String) -> [SNNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let live = data.notes.filter { $0.deletedAt == nil }
        let titleHits = live.filter { $0.title.lowercased().contains(q) }
        let bodyHits = live.filter { !$0.title.lowercased().contains(q) && $0.body.lowercased().contains(q) }
        return titleHits + bodyHits
    }

    // MARK: Folder mutations

    @discardableResult
    func createFolder(name: String) -> SNFolder {
        let nextIndex = (data.folders.map(\.sortIndex).max() ?? 0) + 1
        let folder = SNFolder(name: name, sortIndex: nextIndex)
        data.folders.append(folder)
        save(); onStructuralChange?()
        return folder
    }

    func renameFolder(id: UUID, to name: String) {
        guard let i = data.folders.firstIndex(where: { $0.id == id }) else { return }
        data.folders[i].name = name
        save(); onStructuralChange?()
    }

    func toggleFolderPin(id: UUID) {
        guard let i = data.folders.firstIndex(where: { $0.id == id }) else { return }
        data.folders[i].isPinned.toggle()
        save(); onStructuralChange?()
    }

    /// Deleting a folder moves its live notes to the Trash (recoverable)
    /// rather than destroying them.
    func deleteFolder(id: UUID) {
        let now = Date()
        for i in data.notes.indices where data.notes[i].folderID == id && data.notes[i].deletedAt == nil {
            data.notes[i].deletedAt = now
        }
        data.folders.removeAll { $0.id == id }
        save(); onStructuralChange?()
    }

    // MARK: Note mutations

    /// New notes land at the TOP of their folder.
    @discardableResult
    func createNote(in folderID: UUID, body: String = "") -> SNNote {
        let topIndex = (data.notes.filter { $0.folderID == folderID }.map(\.sortIndex).min() ?? 1) - 1
        let note = SNNote(folderID: folderID, body: body, sortIndex: topIndex)
        data.notes.append(note)
        save(); onStructuralChange?()
        return note
    }

    /// Body edits from typing: persist (debounced) without a structural
    /// reload, and without touching sort order.
    func updateNoteBody(id: UUID, body: String) {
        guard let i = data.notes.firstIndex(where: { $0.id == id }) else { return }
        data.notes[i].body = body
        data.notes[i].updatedAt = Date()
        scheduleSave()
    }

    func setNoteMode(id: UUID, mode: NoteMode) {
        guard let i = data.notes.firstIndex(where: { $0.id == id }) else { return }
        // Mode is rendering-only: body is deliberately untouched here.
        data.notes[i].mode = mode
        save(); onStructuralChange?()
    }

    func setNoteColor(id: UUID, color: NoteColorToken) {
        guard let i = data.notes.firstIndex(where: { $0.id == id }) else { return }
        data.notes[i].color = color
        save(); onStructuralChange?()
    }

    func toggleNotePin(id: UUID) {
        guard let i = data.notes.firstIndex(where: { $0.id == id }) else { return }
        data.notes[i].isPinned.toggle()
        save(); onStructuralChange?()
    }

    func setNoteFolded(id: UUID, folded: Bool) {
        guard let i = data.notes.firstIndex(where: { $0.id == id }) else { return }
        data.notes[i].isFolded = folded
        save()
    }

    // MARK: Trash (Decision 1: 30-day retention)

    func moveToTrash(id: UUID) {
        guard let i = data.notes.firstIndex(where: { $0.id == id }) else { return }
        data.notes[i].deletedAt = Date()
        save(); onStructuralChange?()
    }

    func restoreFromTrash(id: UUID) {
        guard let i = data.notes.firstIndex(where: { $0.id == id }) else { return }
        data.notes[i].deletedAt = nil
        // If the note's folder was deleted while it sat in Trash, give it a home.
        if folder(id: data.notes[i].folderID) == nil {
            if let inbox = data.folders.first {
                data.notes[i].folderID = inbox.id
            } else {
                let recreated = createFolder(name: "Notes")
                data.notes[i].folderID = recreated.id
            }
        }
        save(); onStructuralChange?()
    }

    func deletePermanently(id: UUID) {
        guard let note = note(id: id) else { return }
        for attachment in note.attachments { removeAttachmentFile(attachment) }
        data.notes.removeAll { $0.id == id }
        save(); onStructuralChange?()
    }

    func emptyTrash() {
        for note in trashedNotes {
            for attachment in note.attachments { removeAttachmentFile(attachment) }
        }
        data.notes.removeAll { $0.deletedAt != nil }
        save(); onStructuralChange?()
    }

    /// Auto-purge anything that has been in Trash for 30+ days.
    func purgeExpiredTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let expired = data.notes.filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        guard !expired.isEmpty else { return }
        for note in expired {
            for attachment in note.attachments { removeAttachmentFile(attachment) }
        }
        let expiredIDs = Set(expired.map(\.id))
        data.notes.removeAll { expiredIDs.contains($0.id) }
    }

    // MARK: Attachments (embedded copies)

    /// Copies the file at `url` into Attachments/<noteID>/ and records it.
    @discardableResult
    func addAttachment(noteID: UUID, from url: URL) -> SNAttachment? {
        guard let i = data.notes.firstIndex(where: { $0.id == noteID }) else { return nil }
        let noteDir = attachmentsDirectory.appendingPathComponent(noteID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)

        var destination = noteDir.appendingPathComponent(url.lastPathComponent)
        // Avoid clobbering a same-named file.
        if FileManager.default.fileExists(atPath: destination.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            destination = noteDir.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970)).\(ext)")
        }
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            return nil
        }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp"]
        let attachment = SNAttachment(
            fileName: url.lastPathComponent,
            relativePath: "\(noteID.uuidString)/\(destination.lastPathComponent)",
            isImage: imageExtensions.contains(url.pathExtension.lowercased())
        )
        if attachment.isImage {
            makeThumbnail(for: attachment)
        }
        data.notes[i].attachments.append(attachment)
        data.notes[i].updatedAt = Date()
        save(); onStructuralChange?()
        return attachment
    }

    func removeAttachment(noteID: UUID, attachmentID: UUID) {
        guard let i = data.notes.firstIndex(where: { $0.id == noteID }),
              let j = data.notes[i].attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
        let attachment = data.notes[i].attachments[j]
        removeAttachmentFile(attachment)
        data.notes[i].attachments.remove(at: j)
        save(); onStructuralChange?()
    }

    func attachmentURL(_ attachment: SNAttachment) -> URL {
        attachmentsDirectory.appendingPathComponent(attachment.relativePath)
    }

    /// Downscaled preview written beside an image attachment when it is
    /// added, so cards display (and decode) the small file instead of the
    /// full-resolution original. Attachments added before v0.1.1 have no
    /// thumbnail; callers fall back to the original for those.
    func thumbnailURL(for attachment: SNAttachment) -> URL {
        attachmentsDirectory.appendingPathComponent(attachment.relativePath + ".thumb.png")
    }

    private func makeThumbnail(for attachment: SNAttachment) {
        let source = attachmentURL(attachment)
        guard let image = NSImage(contentsOf: source),
              image.size.width > 0, image.size.height > 0 else { return }
        // Cards render images ~110 pt tall in a ~256 pt-wide slot; 220 px
        // of height (and a 440 px width cap) covers Retina at that size.
        let scale = min(1, min(440 / image.size.width, 220 / image.size.height))
        let target = NSSize(width: max(1, (image.size.width * scale).rounded()),
                            height: max(1, (image.size.height * scale).rounded()))
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1)
        thumb.unlockFocus()
        guard let tiff = thumb.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: thumbnailURL(for: attachment), options: [.atomic])
    }

    private func removeAttachmentFile(_ attachment: SNAttachment) {
        try? FileManager.default.removeItem(at: attachmentURL(attachment))
        try? FileManager.default.removeItem(at: thumbnailURL(for: attachment))
    }

    // MARK: Seed content (all original, written for SilverNotes)

    private func seedIfNeeded() {
        guard data.folders.isEmpty && data.notes.isEmpty else { return }
        let notes = createFolder(name: "Notes")
        let projects = createFolder(name: "Projects")
        let personal = createFolder(name: "Personal")
        data.folders[0].isPinned = false
        _ = personal

        let welcome = """
        # Welcome to SilverNotes

        This panel lives at the edge of your screen. Push your pointer to the edge and hold a beat, press the global shortcut, or click the sliver — your notes slide in over whatever you are doing, and slide away when you click elsewhere.

        A few things worth trying:
        - Type ::around a phrase:: to highlight it
        - Make a word **bold** or *italic* just by typing the marks
        - Start a line with - [ ] to make a checklist item you can tick
        - Drag any file onto a note to keep a copy inside it
        - Double-click a note's bottom strip to fold it down to one line

        Everything is stored on this Mac, in your Application Support folder. No account, no server, nothing leaves the machine.
        """
        let welcomeNote = createNote(in: notes.id, body: welcome)
        _ = welcomeNote

        let checklist = """
        SilverNotes build checklist
        - [x] Panel slides in from the right edge
        - [x] Notes save themselves as you type
        - [ ] Test the panel over a full-screen app
        - [ ] Tune the edge trigger until it stops surprising me
        - [ ] Show it to someone and watch where they get stuck
        """
        _ = createNote(in: projects.id, body: checklist)

        let coffee = """
        Coffee, my way

        Small double-double, grabbed on the way home. Two sugars, two creams — sweet enough to think with, strong enough to start.

        Rule for late work: one cup to begin, water after that.
        """
        _ = createNote(in: notes.id, body: coffee)

        let ideas = """
        Back burner

        - A reading queue that lives at the screen edge, one card per article
        - Recipe cards, folded until the step I am on
        - A tiny "parking lot" folder for thoughts that interrupt deep work
        """
        _ = createNote(in: projects.id, body: ideas)
        save()
    }
}

// MARK: - Coders

extension JSONEncoder {
    static var storeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Compact output: the store file is machine-read only, and
        // pretty-printing + key sorting are the encoder's most expensive
        // formatting options. (Files written by v0.1.0 still decode —
        // formatting is not part of the format.)
        return encoder
    }
}

extension JSONDecoder {
    static var storeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
