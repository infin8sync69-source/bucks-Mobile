// swift-tools-version:5.10
import PackageDescription

// BucksCore: Foundation-only logic (models, Supabase REST, dispatch state machine). BucksUI: the SwiftUI screens.
// Both build on macOS as well as iOS so they can be compiled and tested without an iOS SDK. The app target (ios/App)
// adds Firebase sign-in and the iOS entry point; see ios/README.md.
let package = Package(
    name: "Bucks",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BucksCore", targets: ["BucksCore"]),
        .library(name: "BucksUI", targets: ["BucksUI"]),
    ],
    targets: [
        .target(name: "BucksCore"),
        .target(name: "BucksUI", dependencies: ["BucksCore"], resources: [.process("Resources")]),
        // macOS-only harness: runs the real screens against an in-process fake Supabase so they can be exercised and screenshotted without Xcode.
        .executableTarget(name: "BucksMacPreview", dependencies: ["BucksCore", "BucksUI"]),
        .testTarget(name: "BucksCoreTests", dependencies: ["BucksCore"]),
    ]
)
