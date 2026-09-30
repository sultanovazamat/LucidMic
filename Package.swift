// swift-tools-version: 6.0
import PackageDescription

// sherpa-onnx (DPDFNet runtime) is fetched into build/deps by scripts/fetch-deps.sh.
let deps = Context.packageDirectory + "/build/deps/sherpa"

let package = Package(
    name: "LucidMic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LucidMic", targets: ["LucidMic"])],
    targets: [
        .target(
            name: "LucidEngine",
            cSettings: [.unsafeFlags(["-I\(deps)/include", "-O2"])],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .unsafeFlags([
                    "-L\(deps)/lib", "-lsherpa-onnx-c-api",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",  // inside LucidMic.app
                    "-Xlinker", "-rpath", "-Xlinker", "\(deps)/lib",  // swift run / swift test
                ]),
            ]
        ),
        .executableTarget(
            name: "LucidMic",
            dependencies: ["LucidEngine"],
            linkerSettings: [
                .linkedFramework("CoreAudio"), .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(name: "lucidmic-file", dependencies: ["LucidEngine"]),
        .testTarget(name: "LucidEngineTests", dependencies: ["LucidEngine"]),
        .testTarget(name: "LucidMicUITests", dependencies: ["LucidMic"]),
    ]
)
