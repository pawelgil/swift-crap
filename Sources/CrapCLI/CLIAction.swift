import CrapApplication

enum CLIAction {
    case analyze(AnalysisRequest, OutputFormat)
    case help
    case version
}
