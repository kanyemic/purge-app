import Foundation
import SwiftUI

enum NodePackageManager: String, Hashable, Sendable {
    case npm
    case pnpm
    case yarn

    nonisolated var installCommand: String {
        switch self {
        case .npm: return "npm install"
        case .pnpm: return "pnpm install"
        case .yarn: return "yarn install"
        }
    }

    nonisolated static func detect(in projectDirectory: URL) -> NodePackageManager {
        if FileManager.default.fileExists(atPath: projectDirectory.appendingPathComponent("pnpm-lock.yaml").path) {
            return .pnpm
        }
        if FileManager.default.fileExists(atPath: projectDirectory.appendingPathComponent("yarn.lock").path) {
            return .yarn
        }
        if FileManager.default.fileExists(atPath: projectDirectory.appendingPathComponent("package-lock.json").path)
            || FileManager.default.fileExists(atPath: projectDirectory.appendingPathComponent("npm-shrinkwrap.json").path) {
            return .npm
        }
        return .npm
    }
}

nonisolated enum ProjectType: String, Hashable, Sendable, CaseIterable {
    case node
    case rust
    case flutter
    case xcode
    case python
    case androidGradle
    case elixir
    case swiftPackage
    case maven
    case gradleJVM
    case sbt
    case dotnet
    case composer
    case bundler
    case haskellStack
    case haskellCabal
    case zig
    case ocamlDune
    case cmake
    case terraform
    case godot
    case unity
    case unreal

    var displayName: String {
        switch self {
        case .node: return "Node"
        case .rust: return "Rust"
        case .flutter: return "Flutter"
        case .xcode: return "Xcode"
        case .python: return "Python"
        case .androidGradle: return "Android"
        case .elixir: return "Elixir"
        case .swiftPackage: return "Swift Package"
        case .maven: return "Maven"
        case .gradleJVM: return "Gradle"
        case .sbt: return "sbt"
        case .dotnet: return ".NET"
        case .composer: return "PHP"
        case .bundler: return "Ruby"
        case .haskellStack: return "Haskell（Stack）"
        case .haskellCabal: return "Haskell（Cabal）"
        case .zig: return "Zig"
        case .ocamlDune: return "OCaml"
        case .cmake: return "CMake"
        case .terraform: return "Terraform"
        case .godot: return "Godot"
        case .unity: return "Unity"
        case .unreal: return "Unreal"
        }
    }
}

/// High-level grouping of removable folders tied to one project directory.
nonisolated enum DeletableArtifactKind: String, Hashable, Sendable, CaseIterable {
    case nodeModules = "node_modules"
    case venv
    case dotGradle = ".gradle"
    case target
    case pods = "Pods"
    case dartTool = ".dart_tool"
    case flutterBuild = "flutter-build"
    case elixirBuild = "_build"
    case elixirDeps = "deps"
    case nextBuild = ".next"
    case nuxtBuild = ".nuxt"
    case nuxtOutput = ".output"
    case svelteKitBuild = ".svelte-kit"
    case astroBuild = ".astro"
    case angularCache = ".angular"
    case turboCache = ".turbo"
    case parcelCache = ".parcel-cache"
    case viteCache = ".vite"
    case pytestCache = ".pytest_cache"
    case mypyCache = ".mypy_cache"
    case ruffCache = ".ruff_cache"
    case toxEnvironments = ".tox"
    case swiftPMBuild = ".build"
    case mavenTarget = "maven-target"
    case gradleBuild = "gradle-build"
    case sbtTarget = "sbt-target"
    case dotnetBin = "bin"
    case dotnetObj = "obj"
    case composerVendor = "vendor"
    case bundlerVendor = "bundler-vendor"
    case stackWork = ".stack-work"
    case cabalDist = "dist-newstyle"
    case zigCache = "zig-cache"
    case zigOut = "zig-out"
    case duneBuild = "dune-build"
    case cmakeBuild = "cmake-build"
    case terraformPlugins = ".terraform"
    case godotCache = ".godot"
    case unityLibrary = "unity-library"
    case unityTemp = "unity-temp"
    case unrealIntermediate = "unreal-intermediate"
    case unrealDerivedData = "unreal-derived-data"

    /// `explanations.json` lookup key, and the short label shown under a row.
    ///
    /// Held as a table rather than two switch statements so that adding an ecosystem
    /// means adding data in one place. A kind missing from the table still resolves,
    /// falling back to its raw value, so a typo degrades to a plain label instead of
    /// failing to compile or crashing.
    private static let metadata: [DeletableArtifactKind: (explanationKey: String, rowTag: String)] = [
        .nodeModules: ("node_modules", "依赖"),
        .venv: ("venv", "Python 环境"),
        .dotGradle: ("gradle-cache", "Gradle"),
        .target: ("target", "Rust 构建产物"),
        .pods: ("Pods", "Pods"),
        .dartTool: ("dart-tool", "Dart 工具缓存"),
        .flutterBuild: ("flutter-cache", "Flutter 构建产物"),
        .elixirBuild: ("elixir-build", "Elixir 构建产物"),
        .elixirDeps: ("elixir-deps", "Elixir 依赖"),
        .nextBuild: ("next-build", "Next.js 构建产物"),
        .nuxtBuild: ("nuxt-build", "Nuxt 构建产物"),
        .nuxtOutput: ("nuxt-output", "Nuxt 输出"),
        .svelteKitBuild: ("sveltekit-build", "SvelteKit 构建产物"),
        .astroBuild: ("astro-build", "Astro 构建产物"),
        .angularCache: ("angular-cache", "Angular 缓存"),
        .turboCache: ("turbo-cache", "Turborepo 缓存"),
        .parcelCache: ("parcel-cache", "Parcel 缓存"),
        .viteCache: ("vite-cache", "Vite 缓存"),
        .pytestCache: ("pytest-cache", "pytest 缓存"),
        .mypyCache: ("mypy-cache", "mypy 缓存"),
        .ruffCache: ("ruff-cache", "ruff 缓存"),
        .toxEnvironments: ("tox-environments", "tox 环境"),
        .swiftPMBuild: ("swiftpm-build", "Swift 构建产物"),
        .mavenTarget: ("maven-target", "Maven 构建产物"),
        .gradleBuild: ("gradle-build", "Gradle 构建产物"),
        .sbtTarget: ("sbt-target", "sbt 构建产物"),
        .dotnetBin: ("dotnet-bin", ".NET 构建产物"),
        .dotnetObj: ("dotnet-obj", ".NET 中间文件"),
        .composerVendor: ("composer-vendor", "PHP 依赖包"),
        .bundlerVendor: ("bundler-vendor", "Ruby gem"),
        .stackWork: ("stack-work", "Stack 构建产物"),
        .cabalDist: ("cabal-dist", "Cabal 构建产物"),
        .zigCache: ("zig-cache", "Zig 缓存"),
        .zigOut: ("zig-out", "Zig 输出"),
        .duneBuild: ("dune-build", "Dune 构建产物"),
        .cmakeBuild: ("cmake-build", "CMake 构建产物"),
        .terraformPlugins: ("terraform-plugins", "Terraform 插件"),
        .godotCache: ("godot-cache", "Godot 缓存"),
        .unityLibrary: ("unity-library", "Unity Library"),
        .unityTemp: ("unity-temp", "Unity Temp"),
        .unrealIntermediate: ("unreal-intermediate", "Unreal 中间文件"),
        .unrealDerivedData: ("unreal-derived-data", "Unreal 缓存"),
    ]

    nonisolated var explanationKey: String {
        Self.metadata[self]?.explanationKey ?? rawValue
    }

    nonisolated var rowTag: String {
        Self.metadata[self]?.rowTag ?? rawValue
    }
}

/// One folder under a detected project shown in lists and selectable for deletion.
nonisolated struct ProjectCacheArtifact: Identifiable, Hashable {
    var id: String { path.path }

    let kind: DeletableArtifactKind
    /// Path to delete.
    let path: URL
    let projectRoot: URL
    let sizeBytes: Int64
    let lastModified: Date
    var isSelected: Bool
    /// Initial SafetyInfo headline comes from explanations; reinstall command varies by artifact.
    /// Mutable so manual user overrides and recategorize results can update it in place.
    var safetyInfo: SafetyInfo

    /// Filled asynchronously after filesystem scan completes.
    var reinstallSafety: ReinstallSafetyStatus

    /// Per-session Git cleanliness for the enclosing repo (`unknown` until resolved).
    var gitStatus: GitWorktreeStatus

    var formattedSize: String { formatBytes(sizeBytes) }
}

/// A collapsible Dev Tools group: multiple artifacts under one project root.
nonisolated struct ProjectGroup: Identifiable, Hashable {
    var id: String { rootPath.path }

    let displayName: String
    let rootPath: URL
    let inferredTypes: [ProjectType]

    /// Sorted by descending size elsewhere.
    var artifacts: [ProjectCacheArtifact]

    var totalBytes: Int64 {
        artifacts.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }
}
