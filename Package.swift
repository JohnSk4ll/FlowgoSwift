// swift-tools-version: 5.9
import PackageDescription
import Foundation

var targets: [Target] = [
    .target(name: "FlowCore", resources: [.copy("Templates")]),
    .executableTarget(name: "FlowgoSwift", dependencies: ["FlowCore"], resources: [.copy("Icons")]),
    .executableTarget(name: "FlowCLI", dependencies: ["FlowCore"])
]

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
for (name, dependencies) in [
    ("FlowCoreTests", ["FlowCore"]),
    ("FlowUITests", ["FlowgoSwift", "FlowCore"])
] {
    if FileManager.default.fileExists(atPath: packageDirectory.appendingPathComponent("Tests/\(name)").path) {
        targets.append(.testTarget(name: name, dependencies: dependencies.map { .byName(name: $0) }))
    }
}

let package = Package(
    name: "FlowgoSwift",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FlowgoSwift", targets: ["FlowgoSwift"]),
        .executable(name: "flow", targets: ["FlowCLI"])
    ],
    targets: targets
)
