import CoreFoundation
import Foundation

enum CoverageJSON {
    static func document(from data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CoverageDecodingError.malformedInput
        }
        return try dictionary(value)
    }

    static func dictionary(_ value: Any?) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw CoverageDecodingError.malformedInput
        }
        return dictionary
    }

    static func dictionaries(_ value: Any?) throws -> [[String: Any]] {
        try array(value).map(dictionary)
    }

    static func array(_ value: Any?) throws -> [Any] {
        guard let array = value as? [Any] else {
            throw CoverageDecodingError.malformedInput
        }
        return array
    }

    static func string(_ value: Any?) throws -> String {
        guard let string = value as? String, !string.isEmpty else {
            throw CoverageDecodingError.malformedInput
        }
        return string
    }

    static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            throw CoverageDecodingError.malformedInput
        }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max)
        else {
            throw CoverageDecodingError.malformedInput
        }
        return number.intValue
    }

    static func double(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            throw CoverageDecodingError.malformedInput
        }
        return number.doubleValue
    }
}
