// swift-tools-version: 6.0
import PackageDescription

// Strict DDD layering, enforced by the module graph:
//
//   Domain        →  (no dependencies — pure model + ports)
//   Application   →  Domain
//   Infrastructure→  Domain          (implements Domain ports)
//   Presentation  →  Domain, Application
//
// The app target (in the Xcode project) is the composition root: it is the only
// place allowed to import Infrastructure and wire concrete adapters into the
// use cases. A layer that tries to import "upward" simply won't compile.
let package = Package(
    name: "ClaudometerKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ClaudometerKit",
            targets: ["Domain", "Application", "Infrastructure", "Presentation"]
        )
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Application", dependencies: ["Domain"]),
        .target(name: "Infrastructure", dependencies: ["Domain"]),
        .target(name: "Presentation", dependencies: ["Domain", "Application"]),
    ],
    swiftLanguageModes: [.v5]
)
