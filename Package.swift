// swift-tools-version: 6.2
import PackageDescription

// One product per layer, on purpose. A consumer who wants the scales but not the frame clock
// must be able to depend on the scales alone; without `products` the split degrades into
// folders and stops being enforceable.
//
// `.unsafeFlags` appears nowhere in this file. A package carrying them cannot be resolved as a
// versioned dependency at all, which would make every product above unusable from outside.
let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
]

// Drawing layers default to the main actor; data layers must not. Ring buffers, scales and
// downsampling are built to run off the display thread, and inheriting main-actor isolation
// there would serialise the exact work this package exists to measure.
let strictMainActor: [SwiftSetting] = strict + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "RenderBench",
    // A single minimum for the whole package: `platforms` is a package property, and no
    // per-target equivalent exists. iOS 18 is the floor because `Mutex` and `Atomic` from
    // `Synchronization` arrive there, and the frame slot is built on them. Anything newer is
    // reached through `@available` naming the specific symbol — see Docs/adr/0001.
    //
    // macOS is listed so the Foundation-only layers build and test on the runner host without
    // a simulator, which is the fastest failure signal available.
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "BenchCore", targets: ["BenchCore"]),
        .library(name: "BenchScales", targets: ["BenchScales"]),
        .library(name: "BenchDownsampling", targets: ["BenchDownsampling"]),
        .library(name: "BenchGenerators", targets: ["BenchGenerators"]),
        .library(name: "BenchRuntime", targets: ["BenchRuntime"]),
        .library(name: "BenchTestSupport", targets: ["BenchTestSupport"]),
        .library(name: "BenchHost", targets: ["BenchHost"]),
        .library(name: "CanvasBackend", targets: ["CanvasBackend"]),
        .library(name: "CoreAnimationBackend", targets: ["CoreAnimationBackend"]),
        .library(name: "MetalBackend", targets: ["MetalBackend"]),
    ],
    targets: [
        // MARK: Layers

        .target(name: "BenchCore", swiftSettings: strict),

        .target(
            name: "BenchScales",
            dependencies: ["BenchCore"],
            swiftSettings: strict
        ),

        .target(
            name: "BenchDownsampling",
            dependencies: ["BenchCore", "BenchScales"],
            swiftSettings: strict
        ),

        .target(
            name: "BenchGenerators",
            dependencies: ["BenchCore"],
            swiftSettings: strict
        ),

        // The only layer allowed to touch QuartzCore, Metal and Synchronization: the display
        // link, the GPU timestamps and the frame slot all live here so that the layers above
        // can keep the no-system-frameworks rule.
        .target(
            name: "BenchRuntime",
            dependencies: ["BenchCore", "BenchScales", "BenchDownsampling"],
            swiftSettings: strict
        ),

        // Fixtures shared by test targets. Deliberately not importing `Testing`: SwiftPM links
        // the testing library into test targets only, so a plain library that imports it fails
        // to build. Assertions stay in the test targets; only data lives here.
        .target(
            name: "BenchTestSupport",
            dependencies: ["BenchCore", "BenchScales"],
            swiftSettings: strict
        ),

        // The only layer below the backends allowed to import SwiftUI. `ChartRenderer.surface`
        // is `AnyView`, and that alone would force every layer beneath it to carry SwiftUI;
        // splitting this out keeps `BenchRuntime` free of UI frameworks, which `CheckImports`
        // enforces on its behalf.
        .target(
            name: "BenchHost",
            dependencies: ["BenchCore", "BenchRuntime"],
            swiftSettings: strictMainActor
        ),

        // MARK: Backends

        // First of nine. The remaining eight are added once the renderer and metrics protocols
        // are frozen; adding them empty now would only buy CI time to compile placeholders that
        // are certain to be rewritten.
        .target(
            name: "CanvasBackend",
            dependencies: ["BenchRuntime", "BenchHost"],
            swiftSettings: strictMainActor
        ),

        // Second of the nine. Retained geometry: one shape layer per series, paths rebuilt each
        // frame. It does not own a display link — the scene's clock is shared, or the two
        // backends would be timed on different work.
        // Not main-actor by default, unlike the Canvas backend: `CALayer` declares its
        // initialisers outside any actor, so a subclass cannot isolate them. The layer inherits
        // CALayer's own contract — use it from the main thread — which the compiler does not
        // express either way.
        .target(
            name: "CoreAnimationBackend",
            dependencies: ["BenchRuntime", "BenchHost"],
            swiftSettings: strict
        ),

        // Third of the nine, and the first that does not rasterise through Core Graphics. Its
        // shader is compiled from source at startup rather than shipped as a `.metallib`:
        // SwiftPM 6.2 does not compile `.metal` files at all — see `MetalShaderSource`.
        .target(
            name: "MetalBackend",
            dependencies: ["BenchRuntime", "BenchHost"],
            swiftSettings: strict
        ),

        // MARK: Tooling

        // The dependency rule is machine-checked because nothing else enforces it: SwiftPM does
        // not restrict which system frameworks a target may import.
        .executableTarget(
            name: "CheckImports",
            path: "Scripts/CheckImports",
            swiftSettings: strict
        ),

        // Documentation drifts silently; this makes one class of drift loud. It cannot verify that
        // a method page is *right*, only that it still describes symbols that exist.
        .executableTarget(
            name: "CheckMethodDocs",
            path: "Scripts/CheckMethodDocs",
            swiftSettings: strict
        ),

        // The bench-guard. A results file in the repository has passed this, so a reader does not
        // have to wonder whether the run behind a number was valid.
        .executableTarget(
            name: "CheckBenchmarkResults",
            dependencies: ["BenchRuntime"],
            path: "Scripts/CheckBenchmarkResults",
            swiftSettings: strict
        ),

        // The README quickstart is compiled, not quoted. A quickstart that no longer builds is
        // the fastest way to lose a reader permanently.
        .target(
            name: "Examples",
            dependencies: ["BenchCore", "BenchScales", "BenchDownsampling", "BenchRuntime"],
            path: "Examples",
            swiftSettings: strict
        ),

        // MARK: Tests

        .testTarget(name: "BenchCoreTests", dependencies: ["BenchCore"], swiftSettings: strict),
        .testTarget(name: "BenchScalesTests", dependencies: ["BenchScales", "BenchTestSupport"], swiftSettings: strict),
        .testTarget(name: "BenchDownsamplingTests", dependencies: ["BenchDownsampling", "BenchTestSupport"], swiftSettings: strict),
        .testTarget(name: "BenchGeneratorsTests", dependencies: ["BenchGenerators"], swiftSettings: strict),
        .testTarget(name: "BenchRuntimeTests", dependencies: ["BenchRuntime", "BenchTestSupport"], swiftSettings: strict),
        .testTarget(name: "BenchTestSupportTests", dependencies: ["BenchTestSupport"], swiftSettings: strict),
        .testTarget(name: "BenchHostTests", dependencies: ["BenchHost", "BenchRuntime"], swiftSettings: strictMainActor),
        .testTarget(
            name: "CanvasBackendTests",
            dependencies: ["CanvasBackend", "BenchHost", "BenchTestSupport"],
            swiftSettings: strictMainActor
        ),
        .testTarget(
            name: "MetalBackendTests",
            dependencies: ["MetalBackend", "BenchHost", "BenchScales", "BenchTestSupport"],
            swiftSettings: strictMainActor
        ),
        .testTarget(
            name: "CoreAnimationBackendTests",
            dependencies: ["CoreAnimationBackend", "CanvasBackend", "BenchHost", "BenchTestSupport"],
            swiftSettings: strictMainActor
        ),
    ]
)
