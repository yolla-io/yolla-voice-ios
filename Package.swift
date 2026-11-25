// swift-tools-version: 5.9
// Copyright (c) 2026 Yolla Calls International OÜ. All rights reserved.
// The Yolla Voice SDK binary is proprietary software of Yolla Calls International OÜ, used only under a commercial license
// agreement with Yolla Calls International OÜ; see the LICENSE file. The example app in Examples/ is under the MIT License.
import PackageDescription

let package = Package(
    name: "YollaVoiceSDK",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "YollaVoiceSDK", targets: ["YollaVoiceSDK", "YollaVoiceSDKDependencies"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "155.0.0"),
    ],
    targets: [
        .binaryTarget(name: "YollaVoiceSDK", url: "https://github.com/yolla-io/yolla-voice-ios/releases/download/0.1.0/YollaVoiceSDK.xcframework.zip", checksum: "d287c06fa7edd5850359ad6f2e466838f6f3bd1999adce56bd0052a9aac7a219"),
        // A binary target cannot declare dependencies; this empty target brings WebRTC, which the binary links to.
        .target(name: "YollaVoiceSDKDependencies", dependencies: [.product(name: "WebRTC", package: "WebRTC")]),
    ]
)
