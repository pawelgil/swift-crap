import CrapApplication

enum CLIAction {
    case analyze(AnalysisRequest, OutputFormat)
    case capture(CaptureRequest)
    case help
    case version
}
