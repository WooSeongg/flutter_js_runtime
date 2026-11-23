// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_js_runtime",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "flutter-js-runtime", targets: ["flutter_js_runtime"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_js_runtime",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            linkerSettings: [
                // The Dart side opens JavaScriptCore through dart:ffi.
                .linkedFramework("JavaScriptCore")
            ]
        )
    ]
)
