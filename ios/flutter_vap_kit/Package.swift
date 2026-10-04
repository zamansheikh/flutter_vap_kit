// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_vap_kit",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(name: "flutter-vap-kit", targets: ["flutter_vap_kit"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        // The Flutter plugin itself.
        .target(
            name: "flutter_vap_kit",
            dependencies: [
                "flutter_vap_kit_player",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        // Tencent's VAP player (Objective-C). Swift Package Manager does not
        // allow Swift and Objective-C in one target, hence the split.
        .target(
            name: "flutter_vap_kit_player",
            exclude: ["LICENSE.txt"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("OpenGLES"),
                .linkedFramework("GLKit"),
            ]
        ),
    ]
)
