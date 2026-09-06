enum HelpText {
    static let value = """
    Usage:
      swift-crap analyze --project ROOT --coverage FILE [options]
      swift-crap analyze --package DIR [--target NAME] --coverage FILE [options]
      swift-crap analyze --file PATH [--root ROOT] --coverage FILE [options]
      swift-crap analyze --sources-manifest FILE --target NAME --coverage FILE [options]
      swift-crap analyze --xcode-project PATH --scheme NAME --target NAME --coverage FILE [options]
      swift-crap capture --root ROOT --output RECEIPT --coverage NEW_ARTIFACT --build-description FILE -- COMMAND...
      swift-crap capture --root ROOT --output RECEIPT --coverage NEW_ARTIFACT --build-context FILE -- COMMAND...
      swift-crap capture --root ROOT --output RECEIPT --coverage NEW_RESULT.xcresult --xcode-project PATH --scheme NAME --target NAME -- COMMAND...

    Options:
      --baseline FILE          Compare against a schemaVersion 1 baseline
      --build-description FILE Capture compiler contexts from a SwiftPM build description
      --build-context FILE     Capture compiler contexts from an explicit JSON manifest
      --configuration NAME     Xcode build configuration (default: Debug)
      --coverage FILE          LLVM/xccov JSON or .xcresult; repeatable
      --destination VALUE      Xcode destination (default: platform=macOS)
      --exclude PREFIX         Exclude a root-relative component prefix; repeatable
      --format json|text       Output format (default: text)
      --missing error|zero     Missing coverage policy (default: error)
      --output RECEIPT         New capture receipt path (must not already exist)
      --provenance RECEIPT      Require captured source/build/coverage fingerprints
      --trust-coverage unverified  Explicitly allow an unverified legacy import
      --root ROOT              Stable root for package or file scope
      --sources-manifest FILE  Explicit custom-build target membership
      --scheme NAME            Shared Xcode scheme
      --target NAME            Exact package, manifest, or Xcode target
      --threshold NUMBER       Gate threshold (default: 30)
      --xcode-project PATH     Xcode project with resolved target membership
      --help                   Show help
      --version                Show version
    """
}
