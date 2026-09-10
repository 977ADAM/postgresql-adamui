//
//  Connection.swift
//  postgresql-adamui
//
//  Модель подключения к PostgreSQL.
//

import Foundation

/// Описание подключения к серверу PostgreSQL.
///
/// Пароль в самой модели не хранится: он читается и пишется напрямую в Keychain
/// через вычисляемое свойство `password`, чтобы секрет никогда не попадал
/// в `UserDefaults` и в логи.
struct Connection: Identifiable, Codable, Hashable {

    // MARK: - Свойства

    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var database: String
    var isSSLEnabled: Bool
    var isConnected: Bool
    var lastConnected: Date?

    /// Пароль хранится только в Keychain и адресуется по `id` подключения.
    var password: String? {
        get { KeychainService.shared.getPassword(for: id) }
        set { KeychainService.shared.savePassword(newValue, for: id) }
    }

    // MARK: - Инициализация

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        username: String,
        database: String,
        password: String? = nil,
        isSSLEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.isSSLEnabled = isSSLEnabled
        self.isConnected = false
        self.lastConnected = nil
        if let password {
            self.password = password
        }
    }

    // MARK: - Codable

    /// Пароль не кодируется: он живёт в Keychain, а не в `UserDefaults`.
    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, database, isSSLEnabled, isConnected, lastConnected
    }

    // MARK: - Удобные представления

    /// `localhost:5432` для подписи в списке подключений.
    var endpoint: String {
        "\(host):\(port)"
    }

    /// `postgres@localhost:5432/postgres` — краткое описание для заголовков.
    var summary: String {
        "\(username)@\(endpoint)/\(database)"
    }

    /// Значение для строки статуса.
    var statusText: String {
        if isConnected { return "Подключено" }
        guard let lastConnected else { return "Нет соединения" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.unitsStyle = .short
        return "Был подключён " + formatter.localizedString(for: lastConnected, relativeTo: Date())
    }

    // MARK: - Валидация

    /// Ошибка валидации формы или `nil`, если данные корректны.
    var validationError: AppError? {
        if name.isBlank {
            return .validation("Укажите имя подключения")
        }
        if host.isBlank {
            return .validation("Укажите хост сервера")
        }
        if !(1...65535).contains(port) {
            return .validation("Порт должен быть в диапазоне 1…65535")
        }
        if username.isBlank {
            return .validation("Укажите имя пользователя")
        }
        if database.isBlank {
            return .validation("Укажите имя базы данных")
        }
        return nil
    }

    /// Готова ли форма к отправке.
    var isValid: Bool {
        validationError == nil
    }

    /// Создаёт копию подключения по умолчанию для кнопки «Добавить».
    static func makeDefault() -> Connection {
        Connection(
            name: AppConstants.ConnectionDefaults.name,
            host: AppConstants.ConnectionDefaults.host,
            port: AppConstants.ConnectionDefaults.port,
            username: AppConstants.ConnectionDefaults.username,
            database: AppConstants.ConnectionDefaults.database,
            isSSLEnabled: AppConstants.ConnectionDefaults.sslEnabled
        )
    }
}
