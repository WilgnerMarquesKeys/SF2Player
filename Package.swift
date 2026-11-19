// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "SF2Player",
    platforms: [
        .macOS(.v10_15)   // compatível com macOS 10.15 Catalina ou superior
    ],
    products: [
        .executable(name: "SF2Player", targets: ["SF2Player"])
    ],
    targets: [
        .executableTarget(
            name: "SF2Player",
            path: "Sources/SF2Player"
        )
    ]
)
