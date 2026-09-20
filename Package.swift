// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "DecisionModels",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DecisionModels", targets: ["DecisionModels"]),
        .library(name: "DecisionModelsTypeSafe", targets: ["DecisionModelsTypeSafe"]),
        .library(name: "DecisionModelsApple", targets: ["DecisionModelsApple"]),
        .library(name: "DecisionModelsTesting", targets: ["DecisionModelsTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        .macro(
            name: "DecisionModelsMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "DecisionModels", dependencies: ["DecisionModelsMacros"]),
        .target(name: "DecisionModelsTypeSafe", dependencies: ["DecisionModels"]),
        .target(name: "DecisionModelsApple", dependencies: ["DecisionModels"]),
        .target(name: "DecisionModelsTesting", dependencies: ["DecisionModels"]),
        .target(name: "DecisionModelsTestSupport", dependencies: ["DecisionModels"]),
        .testTarget(
            name: "DecisionModelsTests",
            dependencies: ["DecisionModels", "DecisionModelsTestSupport"]
        ),
        .testTarget(
            name: "DecisionModelsMacrosTests",
            dependencies: [
                "DecisionModels",
                "DecisionModelsMacros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "DecisionModelsTypeSafeTests",
            dependencies: ["DecisionModelsTypeSafe", "DecisionModelsTestSupport"]
        ),
        .testTarget(name: "DecisionModelsAppleTests", dependencies: ["DecisionModelsApple"]),
        .testTarget(name: "DecisionModelsTestingTests", dependencies: ["DecisionModelsTesting"]),
    ],
    swiftLanguageModes: [.v6]
)
