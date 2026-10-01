// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "gba-swift-workshop",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "Application", targets: ["Application"])
    ],
    targets: [
        .target(
            name: "Startup",
            publicHeadersPath: "include"
        ),
        .target(
            name: "HeapAllocator",
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .enableExperimentalFeature("Extern"),
            ]
        ),
        .target(
            name: "IntegerArithmetic",
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
            ]
        ),
        .target(
            name: "HasherSeed",
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
            ]
        ),
        .target(
            name: "SoftFloat",
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
            ]
        ),
        .target(
            name: "MemoryPrimitives",
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .enableExperimentalFeature("Extern"),
                .unsafeFlags([
                    "-Xllvm", "-disable-loop-idiom-memcpy",
                    "-Xllvm", "-disable-loop-idiom-memset",
                ]),
            ]
        ),
        .executableTarget(
            name: "Application",
            dependencies: [
                "Startup",
                "MemoryPrimitives",
                "HeapAllocator",
                "IntegerArithmetic",
                "SoftFloat",
                "HasherSeed",
            ],
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .enableExperimentalFeature("Extern"),
                .enableExperimentalFeature("Volatile"),
                // GBAはシングルコアで並行処理がないので、グローバル変数を
                // 並行性チェックなしで使えるSwift 5モードにする
                .swiftLanguageMode(.v5),
                // ビデオメモリは8bit単位で書けないので、書き込みループが
                // memset/memcpy (8bit単位で書く) に置き換えられないようにする
                .unsafeFlags([
                    "-Xllvm", "-disable-loop-idiom-memcpy",
                    "-Xllvm", "-disable-loop-idiom-memset",
                ]),
            ]
        ),
    ]
)
