import CrapCore
import Foundation

struct XcodeCoverageCompactor {
    func compact(_ data: Data, sources: Set<String>) throws -> Data {
        let value = try JSONSerialization.jsonObject(with: data)
        guard var document = value as? [String: Any],
              let values = document["data"] as? [Any]
        else {
            throw XcodeNativeCoverageExportError.invalidEvidence("LLVM coverage has invalid document structure")
        }
        document["data"] = try values.map { value in
            guard var unit = value as? [String: Any],
                  let files = unit["files"] as? [Any],
                  let functions = unit["functions"] as? [Any]
            else {
                throw XcodeNativeCoverageExportError.invalidEvidence("LLVM coverage has invalid unit structure")
            }
            unit["files"] = try files.filter { try selectedFile($0, sources: sources) }
            unit["functions"] = try functions.filter { try selectedFunction($0, sources: sources) }
            unit.removeValue(forKey: "totals")
            return unit
        }
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    private func selectedFile(_ value: Any, sources: Set<String>) throws -> Bool {
        guard let file = value as? [String: Any], let filename = file["filename"] as? String else {
            throw XcodeNativeCoverageExportError.invalidEvidence("LLVM coverage has invalid file structure")
        }
        return try sources.contains(CanonicalPath().resolve(filename))
    }

    private func selectedFunction(_ value: Any, sources: Set<String>) throws -> Bool {
        guard let function = value as? [String: Any],
              let values = function["filenames"] as? [Any],
              !values.isEmpty
        else {
            throw XcodeNativeCoverageExportError.invalidEvidence("LLVM coverage has invalid function structure")
        }
        let filenames = try values.map { value -> String in
            guard let filename = value as? String else {
                throw XcodeNativeCoverageExportError.invalidEvidence("LLVM coverage has invalid function filename")
            }
            return try CanonicalPath().resolve(filename)
        }
        return !sources.isDisjoint(with: filenames)
    }
}
