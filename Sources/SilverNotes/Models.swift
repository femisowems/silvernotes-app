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
        case .pink: return "Pink"
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

// MARK: - Attachment (embedded copy — see NoteStore for the storage choice)

struct SNAttachment: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    /// Path relative to the app's Attachments directory.
    var relativePath: String
    var isImage: Bool
    var addedAt: Date

    init(id: UUID = UUID(), fileName: String, relativePath: String, isImage: Bool, addedAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.relativePath = relativePath
        self.isImage = isImage
        self.addedAt = addedAt
    }
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

    static let currentSchemaVersion = 1
    static var empty: StoreData { StoreData(schemaVersion: currentSchemaVersion, folders: [], notes: []) }
}
