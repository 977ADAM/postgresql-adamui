//
//  SQLScript.swift
//  postgresql-adamui
//
//  Разбор SQL-скрипта на отдельные инструкции.
//

import Foundation

/// Разбивает SQL-скрипт на инструкции.
///
/// PostgreSQL через расширенный протокол принимает только одну инструкцию
/// за запрос, поэтому скрипт из редактора нужно выполнять по частям. Разбор
/// учитывает строковые литералы, кавычки-идентификаторы, комментарии и
/// dollar-quoting (`$$ … $$`), чтобы не разрезать текст по «случайной» `;`.
enum SQLScript {

    /// Возвращает непустые инструкции скрипта без завершающих `;`.
    static func split(_ script: String) -> [String] {
        var statements: [String] = []
        var current = ""
        var index = script.startIndex

        while index < script.endIndex {
            let character = script[index]

            // Однострочный комментарий.
            if character == "-", peek(script, index, offset: 1) == "-" {
                let end = endOfLine(script, from: index)
                current += script[index..<end]
                index = end
                continue
            }

            // Блочный комментарий с поддержкой вложенности.
            if character == "/", peek(script, index, offset: 1) == "*" {
                let end = endOfBlockComment(script, from: index)
                current += script[index..<end]
                index = end
                continue
            }

            // Строковый литерал: удвоенная кавычка — экранирование.
            if character == "'" {
                let end = endOfQuoted(script, from: index, quote: "'")
                current += script[index..<end]
                index = end
                continue
            }

            // Идентификатор в двойных кавычках.
            if character == "\"" {
                let end = endOfQuoted(script, from: index, quote: "\"")
                current += script[index..<end]
                index = end
                continue
            }

            // Dollar-quoting: $tag$ … $tag$.
            if character == "$", let end = endOfDollarQuoted(script, from: index) {
                current += script[index..<end]
                index = end
                continue
            }

            if character == ";" {
                append(statement: current, to: &statements)
                current = ""
                index = script.index(after: index)
                continue
            }

            current.append(character)
            index = script.index(after: index)
        }

        append(statement: current, to: &statements)
        return statements
    }

    // MARK: - Private

    /// Добавляет инструкцию, если после удаления комментариев в ней что-то осталось.
    private static func append(statement: String, to statements: inout [String]) {
        let trimmed = statement.trimmed
        guard !trimmed.isEmpty, !isCommentOnly(trimmed) else { return }
        statements.append(trimmed)
    }

    /// `true`, если текст состоит только из комментариев и пробелов.
    private static func isCommentOnly(_ text: String) -> Bool {
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if character == "-", peek(text, index, offset: 1) == "-" {
                index = endOfLine(text, from: index)
                continue
            }
            if character == "/", peek(text, index, offset: 1) == "*" {
                index = endOfBlockComment(text, from: index)
                continue
            }
            return false
        }
        return true
    }

    /// Позиция конца строки. Проверяем `isNewline`, так как CRLF в Swift — один `Character`.
    private static func endOfLine(_ text: String, from index: String.Index) -> String.Index {
        var cursor = index
        while cursor < text.endIndex, !text[cursor].isNewline {
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private static func peek(_ text: String, _ index: String.Index, offset: Int) -> Character? {        var cursor = index
        for _ in 0..<offset {
            guard cursor < text.endIndex else { return nil }
            cursor = text.index(after: cursor)
        }
        return cursor < text.endIndex ? text[cursor] : nil
    }

    /// Конец литерала в кавычках с учётом удвоения кавычки внутри.
    private static func endOfQuoted(_ text: String, from start: String.Index, quote: Character) -> String.Index {
        var index = text.index(after: start)
        while index < text.endIndex {
            if text[index] == quote {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == quote {
                    index = text.index(after: next)
                    continue
                }
                return next
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    /// Конец блочного комментария с учётом вложенных `/* */`.
    private static func endOfBlockComment(_ text: String, from start: String.Index) -> String.Index {
        var index = text.index(start, offsetBy: 2)
        var depth = 1

        while index < text.endIndex {
            if text[index] == "/", peek(text, index, offset: 1) == "*" {
                depth += 1
                index = text.index(index, offsetBy: 2)
                continue
            }
            if text[index] == "*", peek(text, index, offset: 1) == "/" {
                depth -= 1
                index = text.index(index, offsetBy: 2)
                if depth == 0 { return index }
                continue
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    /// Конец dollar-quoted строки (`$$…$$` или `$tag$…$tag$`), либо `nil`,
    /// если `$` не начинает такую конструкцию.
    private static func endOfDollarQuoted(_ text: String, from start: String.Index) -> String.Index? {
        var index = text.index(after: start)
        var tag = ""

        while index < text.endIndex, isTagCharacter(text[index]) {
            tag.append(text[index])
            index = text.index(after: index)
        }

        guard index < text.endIndex, text[index] == "$" else { return nil }

        let delimiter = "$\(tag)$"
        let bodyStart = text.index(after: index)

        guard let range = text.range(of: delimiter, range: bodyStart..<text.endIndex) else {
            return text.endIndex
        }
        return range.upperBound
    }

    private static func isTagCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
