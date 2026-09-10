//
//  AppConstants.swift
//  postgresql-adamui
//
//  Константы приложения.
//

import CoreGraphics
import Foundation

enum AppConstants {

    // MARK: - Приложение

    enum App {
        static let name = "PostgreSQL AdamUI"
        static let bundleIdentifier = "adamlab.postgresql-adamui"
        /// Идентификатор сервиса в Keychain (все пароли хранятся в одной записи-сервисе).
        static let keychainService = "adamlab.postgresql-adamui.connections"
    }

    // MARK: - Значения по умолчанию для формы подключения

    enum ConnectionDefaults {
        static let name = "Локальная БД"
        static let host = "localhost"
        static let port = 5432
        static let username = "postgres"
        static let database = "postgres"
        static let sslEnabled = false
    }

    // MARK: - Хранилище

    enum Storage {
        static let connectionsKey = "savedConnections"
    }

    // MARK: - Ограничения

    enum Limits {
        /// Сколько запросов хранить в истории.
        static let queryHistoryCount = 100
        /// Сколько строк результата показывать в таблице (защита от гигантских выборок).
        static let visibleResultRows = 1_000
        /// Максимальная длина значения в ячейке результата.
        static let cellPreviewLength = 512
    }

    // MARK: - Таймауты

    enum Timeouts {
        /// Сколько ждать установления соединения/выполнения пробного запроса.
        static let connectSeconds: Int64 = 10
        /// Таймаут на выполнение пользовательского запроса.
        static let querySeconds: Int64 = 60
    }

    // MARK: - Размеры UI

    enum Layout {
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarIdealWidth: CGFloat = 260
        static let formMinWidth: CGFloat = 400
        static let windowMinWidth: CGFloat = 900
        static let windowMinHeight: CGFloat = 600
    }
}
