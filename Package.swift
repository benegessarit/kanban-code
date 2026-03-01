// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kanban",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "Kanban", targets: ["Kanban"]),
        .executable(name: "clawd", targets: ["Clawd"]),
        .library(name: "KanbanCore", targets: ["KanbanCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "Kanban",
            dependencies: ["KanbanCore", "SwiftTerm", .product(name: "MarkdownUI", package: "swift-markdown-ui")],
            path: "Sources/Kanban",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "Clawd",
            path: "Sources/Clawd"
        ),
        .target(
            name: "KanbanCore",
            path: "Sources/KanbanCore"
        ),
        .testTarget(
            name: "KanbanCoreTests",
            dependencies: ["KanbanCore"],
            path: "Tests/KanbanCoreTests"
        ),
    ]
)
