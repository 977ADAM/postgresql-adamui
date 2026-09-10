//
//  CSVTypeInference.swift
//  postgresql-adamui
//
//  Определение типов PostgreSQL по значениям из CSV.
//

import Foundation

/// Подбирает тип колонки PostgreSQL по образцу значений.
///
/// Проверяются только непустые значения: пустые считаются пропусками (NULL).
/// Если хотя бы одно значение не подходит под тип, берётся более общий тип,
/// вплоть до `text`.
enum CSVTypeInference {

    /// Типы, предлагаемые в интерфейсе (в порядке от частых к редким).
    static let suggestedTypes: [String] = [
        "text",
        "integer",
        "bigint",
        "numeric",
        "double precision",
        "boolean",
        "date",
        "timestamp",
        "timestamp with time zone",
        "uuid",
        "jsonb"
    ]

    /// Сколько значений анализировать на колонку.
    private static let sampleLimit = 1000

    // MARK: - Определение типа

    /// Тип для набора значений одной колонки.
    static func infer(from values: [String]) -> String {
        let sample = values
            .prefix(sampleLimit)
            .map(\.trimmed)
            .filter { !$0.isEmpty }

        guard !sample.isEmpty else { return "text" }

        if sample.allSatisfy(isInteger) {
            return sample.contains(where: exceedsInt32) ? "bigint" : "integer"
        }
        if sample.allSatisfy(isNumeric) {
            return "numeric"
        }
        if sample.allSatisfy(isBoolean) {
            return "boolean"
        }
        if sample.allSatisfy(isDate) {
            return "date"
        }
        if sample.allSatisfy(isTimestamp) {
            return sample.contains(where: hasTimeZoneOffset) ? "timestamp with time zone" : "timestamp"
        }
        if sample.allSatisfy(isUUID) {
            return "uuid"
        }
        return "text"
    }

    /// Типы для всех колонок матрицы.
    static func inferColumns(rows: [[String]], columnCount: Int) -> [String] {
        (0..<columnCount).map { column in
            infer(from: rows.map { $0.count > column ? $0[column] : "" })
        }
    }

    // MARK: - Проверки типов

    static func isInteger(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var body = Substring(value)
        if body.first == "+" || body.first == "-" {
            body = body.dropFirst()
        }
        guard !body.isEmpty, body.count <= 19 else { return false }
        return body.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func exceedsInt32(_ value: String) -> Bool {
        guard let number = Int64(value) else { return true }
        return number > Int64(Int32.max) || number < Int64(Int32.min)
    }

    static func isNumeric(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 40 else { return false }
        var body = Substring(value)
        if body.first == "+" || body.first == "-" {
            body = body.dropFirst()
        }

        // Отделяем экспоненту.
        if let exponentIndex = body.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let exponent = body[body.index(after: exponentIndex)...]
            var digits = Substring(exponent)
            if digits.first == "+" || digits.first == "-" {
                digits = digits.dropFirst()
            }
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
            body = body[..<exponentIndex]
        }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        let digits = parts.joined()
        guard !digits.isEmpty else { return false }
        return digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func isBoolean(_ value: String) -> Bool {
        switch value.lowercased() {
        case "true", "false", "t", "f", "yes", "no":
            return true
        default:
            return false
        }
    }

    static func isDate(_ value: String) -> Bool {
        guard matches(value, #"^\d{4}-\d{2}-\d{2}$"#) else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value) != nil
    }

    static func isTimestamp(_ value: String) -> Bool {
        matches(value, #"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}(:?\d{2})?)?$"#)
    }

    private static func hasTimeZoneOffset(_ value: String) -> Bool {
        // PostgreSQL принимает и короткий вид смещения — «+03».
        matches(value, #"(Z|[+-]\d{2}(:?\d{2})?)$"#)
    }

    static func isUUID(_ value: String) -> Bool {
        guard value.count == 36 else { return false }
        return matches(value, #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#)
    }

    // MARK: - Private

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
