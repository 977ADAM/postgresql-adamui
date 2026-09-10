//
//  AppErrors.swift
//  postgresql-adamui
//
//  Централизованные ошибки приложения.
//

import Foundation

/// Ошибки, которые приложение показывает пользователю.
enum AppError: LocalizedError {
    case noPassword
    case notConnected
    case connectionFailed(String)
    case queryFailed(String)
    case invalidData
    case validation(String)
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noPassword:
            return "Пароль не указан"
        case .notConnected:
            return "Нет активного подключения"
        case .connectionFailed(let reason):
            return "Не удалось подключиться к базе данных: \(reason)"
        case .queryFailed(let message):
            return "Ошибка выполнения запроса: \(message)"
        case .invalidData:
            return "Неверный формат данных"
        case .validation(let message):
            return message
        case .keychainFailure(let status):
            return "Ошибка доступа к связке ключей (код \(status))"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noPassword:
            return "Введите пароль пользователя и повторите попытку."
        case .notConnected:
            return "Откройте подключение в списке слева."
        case .connectionFailed:
            return "Проверьте хост, порт, имя пользователя и доступность сервера PostgreSQL."
        case .queryFailed:
            return "Проверьте синтаксис SQL-запроса."
        case .invalidData:
            return "Попробуйте выполнить операцию ещё раз."
        case .validation(let message):
            return message
        case .keychainFailure:
            return "Разрешите приложению доступ к связке ключей."
        }
    }
}

extension Error {
    /// Приводит любую ошибку к тексту, пригодному для показа в UI.
    var displayMessage: String {
        if let appError = self as? AppError {
            return appError.errorDescription ?? appError.localizedDescription
        }
        return localizedDescription
    }
}
