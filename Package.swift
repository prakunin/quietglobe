// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QuietGlobe",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QuietGlobe", targets: ["QuietGlobe"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        // Pure logic (no AppKit/CoreGraphics): word buffer and the Globe/Fn key state machine.
        .target(name: "QuietGlobeCore"),
        .executableTarget(
            name: "QuietGlobe",
            dependencies: [
                "QuietGlobeCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                // The app bundle keeps Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "QuietGlobeCoreTests",
            dependencies: ["QuietGlobeCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
