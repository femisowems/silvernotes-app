import Foundation

// MARK: - Note rendering mode (Decision 6/7 context: mode is a *rendering*
// choice only. Switching mode never mutates the stored source text.)

enum NoteMode: String, Codable, CaseIterable {
    case standard   // Hidden Markdown
    case plain      // Plain text, no interpretation
    case code       // Monospaced, substitutions off

    var displayName: String {
        switch self {
        case .standard: return "Standard (Markdown)"
        case .plain: return "Plain Text"
        case .code: return "Code"
        }
    }
}

// MARK: - Note colour tokens (named tokens, not raw hex, so themes can remap)

enum NoteColorToken: String, Codable, CaseIterable {
    case none
    case yellow
    case orange
    case pink
    case purple
    case blue
    case green
    case gray

    var displayName: String {
        switch self {
        case .none: return "Default"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        // The design package calls #FFC9C2 "Red" (audit 2.18). Only the
        // user-visible label changes: the stored raw value stays "pink",
        // so existing notes decode identically.
        case .pink: return "Red"
        case .purple: return "Purple"
        case .blue: return "Blue"
        case .green: return "Green"
        case .gray: return "Gray"
        }
    }

    /// The 7 swatches shown in the gear menu's Color row (excludes .none,
    /// which is offered as a separate "Default" menu item).
    static var swatches: [NoteColorToken] {
        [.yellow, .orange, .pink, .purple, .blue, .green, .gray]
    }

    /// Gear-menu swatch order (audit 4.14): the package's six first —
    /// Default, Yellow, Red, Green, Blue, Purple — then the app's extra
    /// Orange and Gray last (kept: existing notes use them).
    static var gearMenuOrder: [NoteColorToken] {
        [.none, .yellow, .pink, .green, .blue, .purple, .orange, .gray]
    }
}

// MARK: - Folder (Decision 2: flat for MVP; parentFolderID reserved)

struct SNFolder: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var color: NoteColorToken
    /// Reserved for future nesting. Always nil in the MVP UI; carried in the
    /// schema from day one so nesting needs no data migration later.
    var parentFolderID: UUID?
    var sortIndex: Double
    var isPinned: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         color: NoteColorToken = .none,
         parentFolderID: UUID? = nil,
         sortIndex: Double = 0,
         isPinned: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.parentFolderID = parentFolderID
        self.sortIndex = sortIndex
        self.isPinned = isPinned
        self.createdAt = createdAt
    }
}

// MARK: - Attachment (embedded copy for images; linked for other files —
// see NoteStore. Audit 6.11: dropped files are linked, not copied;
// images are still embedded.)

struct SNAttachment: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    /// Path relative to the app's Attachments directory. Empty for a
    /// LINKED attachment, whose file stays at `linkedPath`.
    var relativePath: String
    var isImage: Bool
    var addedAt: Date
    /// Provenance label for the file card's meta line (audit 4.25), e.g.
    /// "dropped in from Finder". Optional: attachments recorded before
    /// v0.4.0 have no origin and show no provenance segment — one is
    /// never fabricated for them. (Optional so old stores decode.)
    var origin: String? = nil
    /// Absolute path of the original file for a LINKED attachment
    /// (audit 6.11). Nil for embedded copies. Optional for the same
    /// backward-compatibility reason as `origin`.
    var linkedPath: String? = nil

    init(id: UUID = UUID(), fileName: String, relativePath: String, isImage: Bool, addedAt: Date = Date(),
         origin: String? = nil, linkedPath: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.relativePath = relativePath
        self.isImage = isImage
        self.addedAt = addedAt
        self.origin = origin
        self.linkedPath = linkedPath
    }

    var isLinked: Bool { linkedPath != nil }
}

// MARK: - Note

struct SNNote: Codable, Identifiable, Equatable {
    var id: UUID
    var folderID: UUID
    /// The note's source text. In Standard mode this is Markdown source;
    /// rendering is always derived from it and never rewrites it.
    var body: String
    var mode: NoteMode
    var color: NoteColorToken
    var isPinned: Bool
    var isFolded: Bool
    var sortIndex: Double
    var createdAt: Date
    var updatedAt: Date
    /// Decision 1: soft-delete. Non-nil means the note is in the Trash;
    /// it is purged permanently once it is 30 days old.
    var deletedAt: Date?
    var attachments: [SNAttachment]

    init(id: UUID = UUID(),
         folderID: UUID,
         body: String = "",
         mode: NoteMode = .standard,
         color: NoteColorToken = .none,
         isPinned: Bool = false,
         isFolded: Bool = false,
         sortIndex: Double = 0,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         deletedAt: Date? = nil,
         attachments: [SNAttachment] = []) {
        self.id = id
        self.folderID = folderID
        self.body = body
        self.mode = mode
        self.color = color
        self.isPinned = isPinned
        self.isFolded = isFolded
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.attachments = attachments
    }

    var isTrashed: Bool { deletedAt != nil }

    /// Title = first non-empty line, with leading Markdown decoration removed.
    var title: String {
        for rawLine in body.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            while line.hasPrefix("#") || line.hasPrefix(">") || line.hasPrefix("-") {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[ ]") || line.hasPrefix("[x]") || line.hasPrefix("[X]") {
                    line = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            }
            line = line.replacingOccurrences(of: "**", with: "")
                       .replacingOccurrences(of: "::", with: "")
                       .replacingOccurrences(of: "`", with: "")
            return line.isEmpty ? "Untitled note" : line
        }
        return "Untitled note"
    }

    /// (done, total) task counts parsed from `- [ ]` / `- [x]` lines.
    var taskProgress: (done: Int, total: Int) {
        var done = 0, total = 0
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [ ]") { total += 1 }
            else if t.hasPrefix("- [x]") || t.hasPrefix("- [X]") { total += 1; done += 1 }
        }
        return (done, total)
    }
}

// MARK: - On-disk store document

struct StoreData: Codable {
    var schemaVersion: Int
    var folders: [SNFolder]
    var notes: [SNNote]
    /// True once the user has created a note of their own (v0.5.0).
    /// Seeded notes do NOT count. Until this flips, an empty folder
    /// shows the first-run welcome variant of the empty state instead
    /// of "Nothing in <folder> yet" (design package; Nov 26 audit
    /// 4.44). Stores written before v0.5.0 carry no such key and must
    /// decode it as false — hence the custom decoder below, the same
    /// backward-compatibility pattern SNAttachment's optional fields
    /// rely on.
    var userCreatedNote: Bool = false

    static let currentSchemaVersion = 1
    static var empty: StoreData { StoreData(schemaVersion: currentSchemaVersion, folders: [], notes: []) }

    init(schemaVersion: Int, folders: [SNFolder], notes: [SNNote], userCreatedNote: Bool = false) {
        self.schemaVersion = schemaVersion
        self.folders = folders
        self.notes = notes
        self.userCreatedNote = userCreatedNote
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, folders, notes, userCreatedNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        folders = try container.decode([SNFolder].self, forKey: .folders)
        notes = try container.decode([SNNote].self, forKey: .notes)
        userCreatedNote = try container.decodeIfPresent(Bool.self, forKey: .userCreatedNote) ?? false
    }
}
