// swift-tools-version: 5.7
// SilverNotes v0.1.0 MVP — first build. macOS 13+, Universal (runs on
// Apple silicon and Intel; a Swift Package has no architecture pinning).
import PackageDescription

let package = Package(
    name: "SilverNotes",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SilverNotes", targets: ["SilverNotes"])
    ],
    targets: [
        .executableTarget(
            name: "SilverNotes",
            path: "Sources/SilverNotes"
        )
    ]
)
