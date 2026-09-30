// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucidMic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LucidMic", targets: ["LucidMic"])],
    targets: [
        .target(
            name: "CRNNoise",
            exclude: ["COPYING"],
            cSettings: [.unsafeFlags(["-O3", "-w"])]
        ),
        .target(
            name: "LucidEngine",
            dependencies: ["CRNNoise"],
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .executableTarget(
            name: "LucidMic",
            dependencies: ["LucidEngine"],
            linkerSettings: [
                .linkedFramework("CoreAudio"), .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "LucidEngineTests", dependencies: ["LucidEngine"]),
    ]
)
