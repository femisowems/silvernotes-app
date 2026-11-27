import XCTest
@testable import SilverNotes

/// Store/count consistency and lifecycle, driven entirely through
/// NoteStore's public API against a throwaway directory (the
/// `baseDirectory` init seam). The logic tests never call `load()`,
/// so the store starts empty and seed content cannot leak into the
/// expectations; the persistence tests call `load()` explicitly and
/// track their own note IDs.
final class NoteStoreTests: XCTestCase {

    private var baseDirectory: URL!
    private var store: NoteStore!

    override func setUp() {
        super.setUp()
        baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SilverNotesTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        store = NoteStore(baseDirectory: baseDirectory)
    }

    override func tearDown() {
        store = nil
        if let baseDirectory = baseDirectory {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        baseDirectory = nil
        super.tearDown()
    }

    // MARK: Counts

    func testCountsAgreeAcrossFolders() {
        let a = store.createFolder(name: "A")
        let b = store.createFolder(name: "B")
        for _ in 0..<3 { store.createNote(in: a.id, body: "note") }
        for _ in 0..<2 { store.createNote(in: b.id, body: "note") }

        XCTAssertEqual(store.notes(in: a.id).count, 3)
        XCTAssertEqual(store.notes(in: b.id).count, 2)
        // The two query paths must never disagree — that disagreement
        // (counts right, lists wrong) is the v0.1.1–v0.5.0 failure
        // shape at the store layer.
        for folder in store.folders {
            XCTAssertEqual(store.noteCount(in: folder.id), store.notes(in: folder.id).count,
                           "noteCount disagrees with notes(in:) for folder \(folder.name)")
        }
        XCTAssertEqual(store.allNotes.count, 5)
        XCTAssertEqual(store.allNotes.count,
                       store.folders.reduce(0) { $0 + store.noteCount(in: $1.id) })
    }

    // MARK: Trash lifecycle

    func testTrashRestoreAndDeletePermanently() {
        let a = store.createFolder(name: "A")
        let note = store.createNote(in: a.id, body: "doomed")

        store.moveToTrash(id: note.id)
        XCTAssertTrue(store.notes(in: a.id).isEmpty)
        XCTAssertFalse(store.allNotes.contains { $0.id == note.id })
        XCTAssertTrue(store.trashedNotes.contains { $0.id == note.id })

        store.restoreFromTrash(id: note.id)
        XCTAssertTrue(store.notes(in: a.id).contains { $0.id == note.id })
        XCTAssertTrue(store.trashedNotes.isEmpty)

        store.moveToTrash(id: note.id)
        store.deletePermanently(id: note.id)
        XCTAssertNil(store.note(id: note.id))
        XCTAssertTrue(store.trashedNotes.isEmpty)
        XCTAssertTrue(store.allNotes.isEmpty)
    }

    /// The 30-day purge runs inside `load()`. The scenario is built
    /// through the store's own persistence: trash two notes, backdate
    /// their `deletedAt` in the on-disk document (31 and 29 days),
    /// then reload through a second store instance over the same
    /// directory.
    func testPurgeRemovesNotesTrashedOverThirtyDaysAgo() throws {
        store.load()
        let folder = try XCTUnwrap(store.folders.first)
        let old = store.createNote(in: folder.id, body: "old")
        let recent = store.createNote(in: folder.id, body: "recent")
        store.moveToTrash(id: old.id)
        store.moveToTrash(id: recent.id)

        let fileURL = store.storeFileURL
        let raw = try Data(contentsOf: fileURL)
        var data = try JSONDecoder.storeDecoder.decode(StoreData.self, from: raw)
        let oldIndex = try XCTUnwrap(data.notes.firstIndex { $0.id == old.id })
        let recentIndex = try XCTUnwrap(data.notes.firstIndex { $0.id == recent.id })
        data.notes[oldIndex].deletedAt = Date().addingTimeInterval(-31 * 24 * 3600)
        data.notes[recentIndex].deletedAt = Date().addingTimeInterval(-29 * 24 * 3600)
        try JSONEncoder.storeEncoder.encode(data).write(to: fileURL)

        let reloaded = NoteStore(baseDirectory: baseDirectory)
        reloaded.load()

        XCTAssertNil(reloaded.note(id: old.id),
                     "a note trashed 31 days ago must be purged at load")
        XCTAssertNotNil(reloaded.note(id: recent.id),
                        "a note trashed 29 days ago must survive the purge")
        XCTAssertTrue(reloaded.trashedNotes.contains { $0.id == recent.id })
        XCTAssertFalse(reloaded.trashedNotes.contains { $0.id == old.id })
    }

    // MARK: Ordering

    func testPinnedNotesSortFirst() {
        let a = store.createFolder(name: "A")
        let first = store.createNote(in: a.id, body: "first created")
        let second = store.createNote(in: a.id, body: "second created")

        // New notes land on top of their folder.
        XCTAssertEqual(store.notes(in: a.id).map(\.id), [second.id, first.id])

        store.toggleNotePin(id: first.id)
        XCTAssertEqual(store.notes(in: a.id).map(\.id), [first.id, second.id],
                       "a pinned note must sort ahead of unpinned notes")
        XCTAssertEqual(store.allNotes.first?.id, first.id)
        XCTAssertEqual(store.pinnedNotes.map(\.id), [first.id])
    }

    // MARK: First-run flag

    func testUserCreatedNoteFlag() {
        XCTAssertFalse(store.hasUserCreatedNote)
        let a = store.createFolder(name: "A")
        XCTAssertFalse(store.hasUserCreatedNote,
                       "creating a folder must not flip the first-run flag")
        _ = store.createNote(in: a.id, body: "mine")
        XCTAssertTrue(store.hasUserCreatedNote)
    }

    func testSeededStoreHasNoUserCreatedNote() {
        store.load()
        XCTAssertFalse(store.folders.isEmpty, "load() on a fresh directory must seed")
        XCTAssertFalse(store.hasUserCreatedNote,
                       "seed content is not the user creating a note")
    }

    // MARK: Fold state (v0.6.0: notes load expanded)

    /// Folded state is session-only: a note folded in one run must
    /// come back expanded after a reload, and the reset must be
    /// persisted so the on-disk document agrees.
    func testNotesLoadExpandedByDefault() throws {
        // load() first — as the app does at launch: it creates the
        // store directory that save() writes into. Without it the
        // saves below silently land nowhere and the reload can only
        // seed. (The logic tests above skip load() because they never
        // cross store instances.)
        store.load()
        let a = store.createFolder(name: "A")
        let note = store.createNote(in: a.id, body: "fold me")
        store.setNoteFolded(id: note.id, folded: true)
        XCTAssertEqual(store.note(id: note.id)?.isFolded, true,
                       "folding must still work within the session")

        let reloaded = NoteStore(baseDirectory: baseDirectory)
        reloaded.load()

        XCTAssertEqual(reloaded.note(id: note.id)?.isFolded, false,
                       "a note folded last session must load expanded")
        let raw = try Data(contentsOf: store.storeFileURL)
        let onDisk = try JSONDecoder.storeDecoder.decode(StoreData.self, from: raw)
        XCTAssertEqual(onDisk.notes.first { $0.id == note.id }?.isFolded, false,
                       "the load-time reset must be written back to disk")
    }

    // MARK: Duplicate

    func testDuplicateNoteCopiesFieldsAndLandsBelowOriginal() throws {
        let a = store.createFolder(name: "A")
        let bottom = store.createNote(in: a.id, body: "bottom")
        let middle = store.createNote(in: a.id, body: "middle")
        let top = store.createNote(in: a.id, body: "top")
        store.setNoteColor(id: middle.id, color: .blue)
        store.setNoteMode(id: middle.id, mode: .code)
        store.toggleNotePin(id: middle.id)
        store.setNoteFolded(id: middle.id, folded: true)

        let copy = try XCTUnwrap(store.duplicateNote(id: middle.id))

        XCTAssertNotEqual(copy.id, middle.id)
        XCTAssertEqual(copy.folderID, a.id)
        XCTAssertEqual(copy.body, "middle")
        XCTAssertEqual(copy.mode, .code)
        XCTAssertEqual(copy.color, .blue)
        XCTAssertTrue(copy.isPinned, "the copy keeps the original's pin")
        XCTAssertFalse(copy.isFolded, "a duplicate always starts expanded")
        XCTAssertNil(copy.deletedAt)

        // Directly below the original: the copy's sortIndex sits
        // strictly between the original's and the next note down's,
        // and the folder's live order by sortIndex reflects that.
        XCTAssertGreaterThan(copy.sortIndex, middle.sortIndex)
        XCTAssertLessThan(copy.sortIndex, bottom.sortIndex)
        let byOrder = store.notes(in: a.id).sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
        XCTAssertEqual(byOrder, [top.id, middle.id, copy.id, bottom.id])

        XCTAssertNil(store.duplicateNote(id: UUID()),
                     "duplicating an unknown id returns nil")
    }

    func testDuplicateNoteCopiesEmbeddedImageFile() throws {
        let a = store.createFolder(name: "A")
        let note = store.createNote(in: a.id, body: "with attachments")

        // A real 1×1 PNG on disk, attached the way a dropped image
        // is: embedded — copied into the note's Attachments directory.
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="))
        let imageURL = baseDirectory.appendingPathComponent("photo.png")
        try png.write(to: imageURL)
        let embedded = try XCTUnwrap(store.addAttachment(noteID: note.id, from: imageURL))
        XCTAssertTrue(embedded.isImage)
        XCTAssertFalse(embedded.isLinked)

        // A non-image file is LINKED instead: the record points at
        // the original, which stays where it lives.
        let textURL = baseDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: textURL, atomically: true, encoding: .utf8)
        let linked = try XCTUnwrap(store.addAttachment(noteID: note.id, from: textURL))
        XCTAssertTrue(linked.isLinked)

        let copy = try XCTUnwrap(store.duplicateNote(id: note.id))
        XCTAssertEqual(copy.attachments.count, 2)

        let copiedImage = try XCTUnwrap(copy.attachments.first { $0.isImage })
        XCTAssertNotEqual(copiedImage.id, embedded.id)
        XCTAssertTrue(copiedImage.relativePath.hasPrefix("\(copy.id.uuidString)/"),
                      "the copy's embedded file must live under the copy's own directory")
        XCTAssertTrue(store.attachmentFileExists(copiedImage),
                      "the duplicated image file must actually be copied")
        XCTAssertNotEqual(store.attachmentURL(copiedImage), store.attachmentURL(embedded),
                          "original and copy must not share one file")

        let copiedLink = try XCTUnwrap(copy.attachments.first { $0.isLinked })
        XCTAssertNotEqual(copiedLink.id, linked.id)
        XCTAssertEqual(copiedLink.linkedPath, linked.linkedPath,
                       "a linked attachment is copied as a record, unchanged")
        XCTAssertEqual(copiedLink.relativePath, "")
    }

    // MARK: Note kinds / creation mode

    func testCreateNoteWithModePersists() {
        store.load()
        let a = store.createFolder(name: "A")
        let note = store.createNote(in: a.id, body: "let x = 1", mode: .code)
        XCTAssertEqual(store.note(id: note.id)?.mode, .code)

        let reloaded = NoteStore(baseDirectory: baseDirectory)
        reloaded.load()
        XCTAssertEqual(reloaded.note(id: note.id)?.mode, .code,
                       "a note created in Code mode must reload in Code mode")
    }

    func testNoteKindMappingsAndChecklistSeed() {
        XCTAssertEqual(NoteKind.allCases.count, 4)
        XCTAssertEqual(NoteKind.text.displayName, "Text Note")
        XCTAssertEqual(NoteKind.checklist.displayName, "Checklist Note")
        XCTAssertEqual(NoteKind.code.displayName, "Code Note")
        XCTAssertEqual(NoteKind.plainText.displayName, "Plain Text Note")
        XCTAssertEqual(NoteKind.text.mode, .standard)
        XCTAssertEqual(NoteKind.checklist.mode, .standard)
        XCTAssertEqual(NoteKind.code.mode, .code)
        XCTAssertEqual(NoteKind.plainText.mode, .plain)

        let a = store.createFolder(name: "A")
        let note = store.createNote(in: a.id,
                                    body: NoteKind.checklist.seedBody,
                                    mode: NoteKind.checklist.mode)
        XCTAssertEqual(note.taskProgress.total, 3,
                       "the checklist seed must parse as three tasks")
        XCTAssertEqual(note.taskProgress.done, 0)
    }

    // MARK: Persistence

    func testPersistenceRoundTrip() {
        store.load()
        let a = store.createFolder(name: "Trips")
        let n1 = store.createNote(in: a.id, body: "one")
        _ = store.createNote(in: a.id, body: "two")
        store.moveToTrash(id: n1.id)

        let expectedFolders = store.folders.count
        let expectedAll = store.allNotes.count
        let expectedInA = store.noteCount(in: a.id)
        let expectedTrash = store.trashedNotes.count

        let reloaded = NoteStore(baseDirectory: baseDirectory)
        reloaded.load()

        XCTAssertEqual(reloaded.folders.count, expectedFolders)
        XCTAssertEqual(reloaded.allNotes.count, expectedAll)
        XCTAssertEqual(reloaded.noteCount(in: a.id), expectedInA)
        XCTAssertEqual(reloaded.trashedNotes.count, expectedTrash)
        XCTAssertTrue(reloaded.hasUserCreatedNote)
    }
}
