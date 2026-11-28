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

    func testDuplicateNoteAddsOneCard() throws {
        controller.openFolder(folderA.id)
        var stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.filter { $0 is NoteCardView }.count, 3)
        let original = try XCTUnwrap(store.notes(in: folderA.id).first)
        store.duplicateNote(id: original.id)
        // duplicateNote fires onStructuralChange, which viewDidLoad
        // wired to the controller's reload().
        stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 4)
        XCTAssertEqual(stack.arrangedSubviews.filter { $0 is NoteCardView }.count, 4,
                       "duplicating a note in the open folder adds exactly one card")
        assertBottomBar("4 notes")
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

    func testCompactAllNotesPopulatesCards() throws {
        Preferences.density = .compact
        controller.openAllNotes()
        let stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 4,
                       "Compact All Notes must hold one card per live note")
        assertBottomBar("4 notes")
    }

    func testCompactOpensWithEveryNoteExpanded() throws {
        Preferences.density = .compact
        controller.openAllNotes()
        var stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 4,
                       "Compact All Notes must hold one entry per live note")
        XCTAssertTrue(stack.arrangedSubviews.allSatisfy { $0 is NoteCardView },
                      "every note renders expanded as a full card on open")
        controller.openFolder(folderA.id)
        stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 3,
                       "Compact folder view must hold one entry per live note")
        XCTAssertTrue(stack.arrangedSubviews.allSatisfy { $0 is NoteCardView },
                      "every note renders expanded on open, including after switching views")
        controller.openAllNotes()
        stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 4,
                       "Compact All Notes must hold one entry per live note")
        XCTAssertTrue(stack.arrangedSubviews.allSatisfy { $0 is NoteCardView },
                      "every note renders expanded on open, including after switching back")
    }

    func testCompactFoldedNoteRendersAsRow() throws {
        Preferences.density = .compact
        controller.openAllNotes()
        let note = try XCTUnwrap(store.allNotes.first)
        store.setNoteFolded(id: note.id, folded: true)
        controller.openAllNotes()
        let stack = try XCTUnwrap(findCardStack())
        XCTAssertEqual(stack.arrangedSubviews.count, 4,
                       "Compact All Notes must hold one entry per live note")
        XCTAssertEqual(stack.arrangedSubviews.filter { $0 is NoteCardView }.count, 3,
                       "unfolded notes keep rendering as full cards")
        // CompactRowView is private to PanelContentController.swift,
        // so the folded note's row is counted as the non-card remainder.
        XCTAssertEqual(stack.arrangedSubviews.filter { !($0 is NoteCardView) }.count, 1,
                       "the manually folded note renders as a one-line row")
    }

    // MARK: Appearance changes

    /// Regression guard for the Nov 27 folder-home bug: row surfaces
    /// are layer-baked CGColors resolved from dynamic theme colors.
    /// A row built under the light appearance kept its white card
    /// surface when the system flipped to dark, while its name — an
    /// NSTextField textColor, which re-resolves live — flipped to
    /// near-white: white on white. The row must re-bake its surfaces
    /// when its effective appearance changes.
    func testFolderRowSurfaceFollowsAppearance() throws {
        let stack = try XCTUnwrap(findCardStack())
        // Folder home is showing (the initial presentation). Find
        // Folder A's row black-box: the arranged subview holding a
        // text field with the folder's name.
        let row = try XCTUnwrap(stack.arrangedSubviews.first { arranged in
            allDescendants(of: arranged).contains {
                ($0 as? NSTextField)?.stringValue == folderA.name
            }
        })
        let before = try XCTUnwrap(row.layer?.backgroundColor)

        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        var darkCard: CGColor?
        var lightCard: CGColor?
        var darkTile: CGColor?
        darkAppearance.performAsCurrentDrawingAppearance {
            darkCard = SNTheme.cardBackground.cgColor
            darkTile = SNTheme.accentSoftBackground.cgColor
        }
        lightAppearance.performAsCurrentDrawingAppearance {
            lightCard = SNTheme.cardBackground.cgColor
        }
        let darkCardColor = try XCTUnwrap(darkCard)
        let lightCardColor = try XCTUnwrap(lightCard)
        // The two variants really are different colors, so the
        // assertions below cannot pass vacuously.
        XCTAssertNotEqual(darkCardColor, lightCardColor,
                          "the card surface must differ between light and dark")
        XCTAssertTrue(before == darkCardColor || before == lightCardColor,
                      "the row surface starts as a theme card color")

        // Flip the row to dark. Setting `appearance` should dispatch
        // viewDidChangeEffectiveAppearance; it is also invoked
        // directly (the re-apply is idempotent) so the production
        // override is exercised even if the windowless setter does
        // not dispatch it in the test host. Both run inside the dark
        // drawing appearance, so a re-baked CGColor resolves its
        // dark variant.
        darkAppearance.performAsCurrentDrawingAppearance {
            row.appearance = darkAppearance
            row.viewDidChangeEffectiveAppearance()
        }

        let after = try XCTUnwrap(row.layer?.backgroundColor)
        XCTAssertEqual(after, darkCardColor,
                       "the row surface must re-bake to the dark card color")
        XCTAssertNotEqual(after, lightCardColor,
                          "the row surface must not keep the light card color")

        // The icon tile bakes the accent-soft surface the same way.
        // Black-box: it is the first arranged subview of the row's
        // left stack, which is the row's first subview.
        let leftStack = try XCTUnwrap(row.subviews.first as? NSStackView)
        let tile = try XCTUnwrap(leftStack.arrangedSubviews.first)
        let tileColor = try XCTUnwrap(tile.layer?.backgroundColor)
        XCTAssertEqual(tileColor, try XCTUnwrap(darkTile),
                       "the row tile must re-bake to the dark accent-soft color")
    }

    /// The Compact row's styling bakes the same dynamic colors: the
    /// unselected row is the card surface at 65% alpha, the selected
    /// row the solid card surface — either way it must re-bake on an
    /// appearance flip (v0.7.1).
    func testCompactRowSurfaceFollowsAppearance() throws {
        Preferences.density = .compact
        let note = try XCTUnwrap(store.allNotes.first)
        store.setNoteFolded(id: note.id, folded: true)
        controller.openAllNotes()
        let stack = try XCTUnwrap(findCardStack())
        // CompactRowView is private, so the folded note's row is the
        // non-card arranged subview holding its title text field.
        let row = try XCTUnwrap(stack.arrangedSubviews.first { arranged in
            !(arranged is NoteCardView) && allDescendants(of: arranged).contains {
                ($0 as? NSTextField)?.stringValue == note.title
            }
        })
        let before = try XCTUnwrap(row.layer?.backgroundColor)

        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        var darkSolid: CGColor?
        var lightSolid: CGColor?
        var darkWash: CGColor?
        var lightWash: CGColor?
        darkAppearance.performAsCurrentDrawingAppearance {
            darkSolid = SNTheme.cardBackground.cgColor
            darkWash = SNTheme.cardBackground.withAlphaComponent(0.65).cgColor
        }
        lightAppearance.performAsCurrentDrawingAppearance {
            lightSolid = SNTheme.cardBackground.cgColor
            lightWash = SNTheme.cardBackground.withAlphaComponent(0.65).cgColor
        }
        let darkColors = [try XCTUnwrap(darkSolid), try XCTUnwrap(darkWash)]
        let lightColors = [try XCTUnwrap(lightSolid), try XCTUnwrap(lightWash)]
        XCTAssertTrue(lightColors.contains(before),
                      "the row starts as a light card surface (solid or 65% wash)")

        darkAppearance.performAsCurrentDrawingAppearance {
            row.appearance = darkAppearance
            row.viewDidChangeEffectiveAppearance()
        }

        let after = try XCTUnwrap(row.layer?.backgroundColor)
        XCTAssertTrue(darkColors.contains(after),
                      "the row surface must re-bake to a dark card surface")
        XCTAssertFalse(lightColors.contains(after),
                       "the row surface must not keep a light card surface")
    }

    /// The note card's override also re-applies its footer rule and
    /// its colour (v0.7.1): a yellow note's tint and the hairline
    /// rule must both follow an appearance flip, with no surface
    /// left holding a light variant.
    func testCardTintAndRuleFollowAppearance() throws {
        for note in store.notes(in: folderA.id) {
            store.setNoteColor(id: note.id, color: .yellow)
        }
        controller.openFolder(folderA.id)
        let stack = try XCTUnwrap(findCardStack())
        let card = try XCTUnwrap(stack.arrangedSubviews.first { $0 is NoteCardView })

        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        var darkTint: CGColor?
        var lightTint: CGColor?
        var darkRule: CGColor?
        var lightRule: CGColor?
        darkAppearance.performAsCurrentDrawingAppearance {
            darkTint = SNTheme.tint(for: .yellow).cgColor
            darkRule = SNTheme.hairline.cgColor
        }
        lightAppearance.performAsCurrentDrawingAppearance {
            lightTint = SNTheme.tint(for: .yellow).cgColor
            lightRule = SNTheme.hairline.cgColor
        }
        let darkTintColor = try XCTUnwrap(darkTint)
        let lightTintColor = try XCTUnwrap(lightTint)
        let darkRuleColor = try XCTUnwrap(darkRule)
        let lightRuleColor = try XCTUnwrap(lightRule)
        XCTAssertNotEqual(darkTintColor, lightTintColor,
                          "the yellow tint must differ between light and dark")
        XCTAssertNotEqual(darkRuleColor, lightRuleColor,
                          "the hairline must differ between light and dark")

        // allDescendants excludes the card itself, whose layer
        // carries the tint in full-card colour style — include it.
        func layerColors(of view: NSView) -> [CGColor] {
            ([view] + allDescendants(of: view)).compactMap { $0.layer?.backgroundColor }
        }
        let beforeColors = layerColors(of: card)
        XCTAssertTrue(beforeColors.contains(lightTintColor) || beforeColors.contains(darkTintColor),
                      "the card carries the yellow tint before the flip")
        XCTAssertTrue(beforeColors.contains(lightRuleColor) || beforeColors.contains(darkRuleColor),
                      "the card carries the hairline rule before the flip")

        darkAppearance.performAsCurrentDrawingAppearance {
            card.appearance = darkAppearance
            card.viewDidChangeEffectiveAppearance()
        }

        let afterColors = layerColors(of: card)
        XCTAssertTrue(afterColors.contains(darkTintColor),
                      "the yellow tint must re-bake to its dark variant")
        XCTAssertFalse(afterColors.contains(lightTintColor),
                       "no card surface may keep the light tint")
        XCTAssertTrue(afterColors.contains(darkRuleColor),
                      "the footer rule must re-bake to the dark hairline")
        XCTAssertFalse(afterColors.contains(lightRuleColor),
                       "no card surface may keep the light hairline")
    }
}
