import XCTest
import AppKit
@testable import SilverNotes

/// THE headline regression guard for the v0.1.1–v0.5.0 bug: Standard
/// note lists rendered empty while the store counts stayed correct,
/// because the diffed card population aborted silently partway.
///
/// These tests are black-box: they build the real
/// PanelContentController against a seeded temporary store (via the
/// controller's `store` init seam), navigate with its own public
/// navigation methods, and assert on the resulting view hierarchy —
/// how many arranged subviews the card stack actually holds, and
/// what the bottom bar reads. No private state is touched.
final class PopulationTests: XCTestCase {

    private var baseDirectory: URL!
    private var store: NoteStore!
    private var controller: PanelContentController!
    private var folderA: SNFolder!
    private var folderB: SNFolder!
    private var emptyFolder: SNFolder!

    private var savedDensity: PanelDensity!
    private var savedWidth: PanelWidth!
    private var savedSortMode: NoteSortMode!

    override func setUp() {
        super.setUp()
        // Preferences are UserDefaults-backed and shared by the whole
        // test process: pin the ones the controller reads, and restore
        // them in tearDown so tests stay order-independent.
        Preferences.registerDefaults()
        savedDensity = Preferences.density
        savedWidth = Preferences.panelWidth
        savedSortMode = Preferences.sortMode
        Preferences.density = .standard
        Preferences.panelWidth = .standard
        Preferences.sortMode = .manual

        baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SilverNotesTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        store = NoteStore(baseDirectory: baseDirectory)

        // Seed BEFORE the controller loads its view (its viewDidLoad
        // wires the store's onStructuralChange to reload()): 3 notes
        // in A, 1 in B, 1 trashed out of A — 4 live notes in total.
        folderA = store.createFolder(name: "Folder A")
        folderB = store.createFolder(name: "Folder B")
        emptyFolder = store.createFolder(name: "Empty")
        for i in 1...3 { store.createNote(in: folderA.id, body: "A note \(i)") }
        store.createNote(in: folderB.id, body: "B note")
        let trashed = store.createNote(in: folderA.id, body: "trashed")
        store.moveToTrash(id: trashed.id)

        controller = PanelContentController(store: store)
        _ = controller.view // loadView + viewDidLoad; initial reload is the folder home
    }

    override func tearDown() {
        controller = nil
        store = nil
        Preferences.density = savedDensity
        Preferences.panelWidth = savedWidth
        Preferences.sortMode = savedSortMode
        if let baseDirectory = baseDirectory {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        baseDirectory = nil
        super.tearDown()
    }

    // MARK: Hierarchy helpers

    private func allDescendants(of view: NSView) -> [NSView] {
        var result: [NSView] = []
        for subview in view.subviews {
            result.append(subview)
            result.append(contentsOf: allDescendants(of: subview))
        }
        return result
    }

    /// The card stack is the NSStackView that is a direct subview of
    /// the panel scroll view's document view. (Cards and empty states
    /// contain stack views of their own, but never in that position,
    /// and the folder rail's stack lives outside the scroll view.)
    private func findCardStack() -> NSStackView? {
        for view in allDescendants(of: controller.view) {
            guard let scrollView = view as? NSScrollView,
                  let documentView = scrollView.documentView else { continue }
            if let stack = documentView.subviews.first(where: { $0 is NSStackView }) as? NSStackView {
                return stack
            }
        }
        return nil
    }

    /// Every text field's current string in the panel — the bottom
    /// bar's count is asserted by membership, so the test does not
    /// depend on which label the controller happens to show for the
    /// current density.
    private func allFieldTexts() -> [String] {
        allDescendants(of: controller.view)
            .compactMap { $0 as? NSTextField }
            .map { $0.stringValue }
    }

    private func assertBottomBar(_ expected: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        XCTAssertTrue(allFieldTexts().contains(expected),
                      "bottom bar should read \"\(expected)\"; fields saw: \(allFieldTexts())",
                      file: file, line: line)
    }

    // MARK: Folder home

    func testFolderHomePopulatesRowsAndCount() throws {
        let stack = try XCTUnwrap(findCardStack())
        // All Notes row + Pinned row + one row per folder + Trash row.
        XCTAssertEqual(stack.arrangedSubviews.count, 6)
        assertBottomBar("3 folders · flat list")
    }

    // MARK: Standard density (the v0.5.1 regression)

    func testStandardAllNotesPopulatesEveryLiveNote() throws {
        controller.openAllNotes()
        let stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 4,
                       "All Notes must hold one card per live note")
        XCTAssertTrue(stack.arrangedSubviews.allSatisfy { $0 is NoteCardView },
                      "Standard density populates full note cards")
        assertBottomBar("4 notes")
    }

    func testStandardFolderPopulatesItsNotes() throws {
        controller.openFolder(folderA.id)
        let stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 3)
        assertBottomBar("3 notes")
    }

    func testTrashPopulatesTrashedNotes() throws {
        controller.openTrash()
        let stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 1,
                       "Trash must hold one entry per trashed note")
        assertBottomBar("Notes are permanently deleted after 30 days")
    }

    func testEmptyFolderShowsEmptyState() throws {
        controller.openFolder(emptyFolder.id)
        let stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 1,
                       "an empty folder shows exactly the empty state")
        XCTAssertFalse(stack.arrangedSubviews.first is NoteCardView,
                       "the empty state is not a note card")
        assertBottomBar("0 notes")
    }

    // MARK: Compact density

    func testCompactAllNotesPopulatesRows() throws {
        Preferences.density = .compact
        controller.openAllNotes()
        let stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 4,
                       "Compact All Notes must hold one row per live note")
        assertBottomBar("4 notes")
    }
}
