enum HelpText {
    static let value = """
    Usage:
      swift-crap analyze --project ROOT --coverage FILE [options]
      swift-crap analyze --package DIR [--target NAME] --coverage FILE [options]
      swift-crap analyze --file PATH [--root ROOT] --coverage FILE [options]
      swift-crap analyze --sources-manifest FILE --target NAME --coverage FILE [options]

    Options:
      --baseline FILE          Compare against a schemaVersion 1 baseline
      --coverage FILE          LLVM or xccov JSON; repeatable
      --exclude PREFIX         Exclude a root-relative component prefix; repeatable
      --format json|text       Output format (default: text)
      --missing error|zero     Missing coverage policy (default: error)
      --root ROOT              Stable root for package or file scope
      --sources-manifest FILE  Explicit Xcode/custom-build target membership (v1)
      --target NAME            Exact package or sources-manifest target
      --threshold NUMBER       Gate threshold (default: 30)
      --help                   Show help
      --version                Show version
    """
}
