// swift-tools-version: 6.0
// DailyCommandKit — everything in the Daily Command app that is not UI.
//
// DailyCommandCore: the client for ExecClone's client API (mobile-bootstrap
// `planner*` actions), email-code sign-in, Keychain session storage, the
// planner models, date/phase math, task parsing, the quarter scorecard and the
// journal encryption that matches the web app byte for byte.
//
// It builds for iOS and macOS, so `swift test` covers it on a Mac (CI).
import PackageDescription

let package = Package(
    name: "DailyCommandKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DailyCommandCore", targets: ["DailyCommandCore"]),
    ],
    targets: [
        .target(name: "DailyCommandCore"),
        .testTarget(name: "DailyCommandCoreTests", dependencies: ["DailyCommandCore"]),
    ]
)
