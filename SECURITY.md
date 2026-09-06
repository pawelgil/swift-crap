# Security

Treat source manifests, SwiftPM packages, build commands and compiler contexts as executable inputs. Only run capture or package/Xcode inspection on projects you trust. SwiftPM evaluates `Package.swift`; Xcode may load project plugins or resolve build metadata. Capture executes exactly the command supplied after `--`, with the caller's permissions and environment. There is no sandbox or privilege separation inside this tool.

`analyze` does not run the analyzed project's tests or fetch data over the network. Metadata tools are asked to disable automatic package resolution. Coverage and receipt files are validated, but this is not a hardened parser for adversarial multi-gigabyte input. Run untrusted workloads in an isolated environment without credentials.

Capture receipts protect against accidental stale or mismatched inputs. They are not signed attestations and do not prove that a malicious command actually built or tested the recorded source. Anyone able to alter a receipt can forge its contents. Keep receipts and coverage artifacts under the same access controls as CI build artifacts. Receipts contain absolute local paths and the supplied command; do not put secrets on that command line or publish receipts without inspection. The analyzer has no telemetry.

Do not report a suspected security vulnerability in a public issue. Use the repository's private vulnerability reporting feature when enabled, or contact the repository owner privately through GitHub before sharing reproduction details. Private reporting must be enabled before public release. No response-time SLA is promised.
