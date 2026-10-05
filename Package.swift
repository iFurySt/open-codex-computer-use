// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenComputerUse",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "OpenComputerUseGuardian", targets: ["OpenComputerUseGuardian"]),
        .library(
            name: "OpenComputerUseKit",
            targets: ["OpenComputerUseKit"]
        ),
        .executable(
            name: "OpenComputerUse",
            targets: ["OpenComputerUse"]
        ),
        .executable(
            name: "OpenComputerUseFixture",
            targets: ["OpenComputerUseFixture"]
        ),
        .executable(
            name: "OpenComputerUseSmokeSuite",
            targets: ["OpenComputerUseSmokeSuite"]
        ),
        .executable(
            name: "CursorMotion",
            targets: ["CursorMotion"]
        ),
        .executable(
            name: "StandaloneCursor",
            targets: ["StandaloneCursor"]
        ),
    ],
    targets: [
        .target(
            name: "LockedUseNative",
            path: "packages/LockedUseNative",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("bsm")]
        ),
        .executableTarget(
            name: "OpenComputerUseGuardian",
            dependencies: ["OpenComputerUseKit"],
            path: "experiments/LockedUse/Sources/Guardian"
        ),
        .target(
            name: "OpenComputerUseKit",
            dependencies: ["LockedUseNative"],
            path: "packages/OpenComputerUseKit/Sources/OpenComputerUseKit"
        ),
        .executableTarget(
            name: "OpenComputerUse",
            dependencies: ["OpenComputerUseKit"],
            path: "apps/OpenComputerUse/Sources/OpenComputerUse"
        ),
        .executableTarget(
            name: "OpenComputerUseFixture",
            dependencies: ["OpenComputerUseKit"],
            path: "apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture"
        ),
        .executableTarget(
            name: "OpenComputerUseSmokeSuite",
            dependencies: ["OpenComputerUseKit"],
            path: "apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite"
        ),
        .executableTarget(
            name: "CursorMotion",
            path: "experiments/CursorMotion/Sources/CursorMotion"
        ),
        .target(
            name: "StandaloneCursorSupport",
            path: "experiments/StandaloneCursor/Sources/StandaloneCursorSupport"
        ),
        .executableTarget(
            name: "StandaloneCursor",
            dependencies: ["StandaloneCursorSupport"],
            path: "experiments/StandaloneCursor/Sources/StandaloneCursor"
        ),
        .testTarget(
            name: "OpenComputerUseKitTests",
            dependencies: ["OpenComputerUseKit"],
            path: "packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests"
        ),
        .testTarget(
            name: "StandaloneCursorSupportTests",
            dependencies: ["StandaloneCursorSupport"],
            path: "experiments/StandaloneCursor/Tests/StandaloneCursorSupportTests"
        ),
    ]
)
