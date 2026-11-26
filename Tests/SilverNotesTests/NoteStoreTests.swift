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
