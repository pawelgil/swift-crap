import CrapApplication
import CrapCore
import Foundation

struct BaselineTrustValidator {
    private let fileReader: any FileReading

    init(fileReader: any FileReading = LocalFileReader()) {
        self.fileReader = fileReader
    }

    func validate(path: String?, buildIdentity: String?) throws -> ValidatedBaseline? {
        guard let path else { return nil }
        let data: Data
        do {
            data = try fileReader.read(at: path)
        } catch {
            throw ProvenanceError.invalid("cannot read baseline: \(path)")
        }
        guard let buildIdentity else {
            return ValidatedBaseline(path: path, data: data)
        }
        let report: AnalysisReport
        do {
            report = try JSONDecoder().decode(AnalysisReport.self, from: data)
        } catch {
            throw ProvenanceError.invalid("cannot read baseline: \(path)")
        }
        guard report.verification == "captured" else {
            throw ProvenanceError.invalid("captured analysis requires a captured baseline: \(path)")
        }
        guard let baselineIdentity = report.buildIdentity else {
            throw ProvenanceError.invalid("captured baseline has no build identity: \(path)")
        }
        guard baselineIdentity == buildIdentity else {
            throw ProvenanceError.invalid("captured baseline build identity differs: \(path)")
        }
        return ValidatedBaseline(path: path, data: data)
    }
}
