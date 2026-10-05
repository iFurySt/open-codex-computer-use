// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OpenComputerUsePower", platforms: [.macOS(.v14)], products: [
    .library(name: "PowerCore", targets: ["PowerCore"]),
    .executable(name: "OCUPowerHost", targets: ["PowerHost"]),
    .executable(name: "OCUPowerHelper", targets: ["PowerHelper"]),
    .executable(name: "OCUPowerGUIFixture", targets: ["PowerGUIFixture"])
], targets: [
    .target(name: "PowerNative", publicHeadersPath: "include", cSettings: [.define("OCU_POWER_DEV", .when(configuration: .debug))], linkerSettings: [.linkedFramework("Security"), .linkedFramework("Foundation")]),
    .target(name: "PowerCore", dependencies: ["PowerNative"], linkerSettings: [.linkedFramework("IOKit")]),
    .executableTarget(name: "PowerHost", dependencies: ["PowerCore"]),
    .executableTarget(name: "PowerHelper", dependencies: ["PowerCore"]),
    .executableTarget(name: "PowerGUIFixture"),
    .testTarget(name: "PowerCoreTests", dependencies: ["PowerCore"])
], swiftLanguageModes: [.v5])
