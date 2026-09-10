//
//  DatabaseService.swift
//  postgresql-adamui
//
//  Слой доступа к PostgreSQL поверх PostgresNIO.
//

import Foundation
import PostgresNIO

/// Единая точка работы с базой данных: подключение, запросы и метаданные схемы.
///
/// Сервис владеет пулом соединений `PostgresClient`, который запускается в
/// отдельной задаче. Пара «клиент + задача» регистрируется в `ConnectionManager`,
/// чтобы её можно было корректно остановить.
final class DatabaseService {

    static let shared = DatabaseService()

    // MARK: - Зависимости

    private let connectionManager: ConnectionManager
    private let logger: Logger

    // MARK: - Состояние

    /// Идентификатор подключения, с которым сейчас работает сервис.
    private(set) var activeConnectionID: UUID?

    private init(
        connectionManager: ConnectionManager = .shared,
        logger: Logger = Logger(label: "adamlab.postgresql-adamui.database")
    ) {
        self.connectionManager = connectionManager
        self.logger = logger
    }

    // MARK: - Состояние подключения

    /// `true`, если есть активный клиент для текущего подключения.
    var isConnected: Bool {
        guard let activeConnectionID else { return false }
        return connectionManager.isActive(activeConnectionID)
    }

    // MARK: - Подключение

    /// Устанавливает соединение и проверяет его реальным запросом.
    ///
    /// - Parameter password: пароль из формы. Если `nil`, берётся значение из Keychain.
    func connect(with connection: Connection, password: String? = nil) async throws {
        // Предыдущее соединение больше не нужно.
        disconnect()

        let secret = resolvePassword(connection, override: password)
        let (client, runTask) = await makeClient(for: connection, password: secret)
        connectionManager.addConnection(client, runTask: runTask, for: connection.id)

        do {
            // Пул соединяется лениво, поэтому именно первый запрос проверяет
            // доступность сервера, логин и пароль.
            _ = try await fetch(client: client, sql: "SELECT 1")
            activeConnectionID = connection.id
        } catch {
            connectionManager.removeConnection(for: connection.id)
            throw Self.map(error, passwordWasEmpty: (secret ?? "").isEmpty)
        }
    }

    /// Закрывает текущее соединение.
    func disconnect() {
        guard let activeConnectionID else { return }
        connectionManager.removeConnection(for: activeConnectionID)
        self.activeConnectionID = nil
    }

    /// Проверяет подключение, не затрагивая уже открытое соединение.
    func testConnection(with connection: Connection, password: String? = nil) async throws {
        let secret = resolvePassword(connection, override: password)
        let (client, runTask) = await makeClient(for: connection, password: secret)
        defer { runTask.cancel() }

        do {
            _ = try await fetch(client: client, sql: "SELECT 1")
        } catch {
            throw Self.map(error, passwordWasEmpty: (secret ?? "").isEmpty)
        }
    }

    // MARK: - Запросы

    /// Выполняет SQL из редактора.
    ///
    /// Расширенный протокол PostgreSQL принимает только одну инструкцию за
    /// запрос, поэтому скрипт разбивается и выполняется по частям. Возвращается
    /// результат последней инструкции, вернувшей строки, иначе — последний
    /// результат; тег команды суммирует все выполненные инструкции.
    func executeQuery(_ sql: String) async throws -> QueryOutcome {
        let client = try requireClient()

        let statements = SQLScript.split(sql)
        guard !statements.isEmpty else { throw AppError.queryFailed("Пустой запрос") }

        var outcomes: [QueryOutcome] = []
        for statement in statements {
            outcomes.append(try await run(statement, on: client))
        }

        return Self.merge(outcomes)
    }

    /// Выполняет одну инструкцию.
    private func run(_ sql: String, on client: PostgresClient) async throws -> QueryOutcome {
        let started = Date()
        do {
            let result = try await fetch(client: client, sql: sql)
            return QueryOutcome(
                columns: Self.columnNames(of: result.rows.first),
                rows: result.rows.map(Self.render(row:)),
                commandTag: result.metadata.command,
                affectedRows: result.metadata.rows,
                executionTime: Date().timeIntervalSince(started)
            )
        } catch {
            throw Self.map(error, passwordWasEmpty: false)
        }
    }

    /// Сводит результаты нескольких инструкций в один.
    private static func merge(_ outcomes: [QueryOutcome]) -> QueryOutcome {
        guard let last = outcomes.last else {
            return QueryOutcome(columns: [], rows: [], commandTag: nil, affectedRows: nil, executionTime: 0)
        }

        let total = outcomes.reduce(0.0) { $0 + $1.executionTime }
        let tags = outcomes.compactMap(\.commandTag)
        // Уникальные теги в порядке появления: `CREATE TABLE, INSERT, SELECT`.
        var uniqueTags: [String] = []
        for tag in tags where !uniqueTags.contains(tag) {
            uniqueTags.append(tag)
        }

        // Показываем строки последней инструкции, которая их вернула.
        let rowsSource = outcomes.last(where: { !$0.columns.isEmpty }) ?? last
        let affected = outcomes.compactMap(\.affectedRows).reduce(0, +)

        return QueryOutcome(
            columns: rowsSource.columns,
            rows: rowsSource.rows,
            commandTag: uniqueTags.isEmpty ? last.commandTag : uniqueTags.joined(separator: ", "),
            affectedRows: affected > 0 ? affected : rowsSource.affectedRows,
            executionTime: total
        )
    }

    // MARK: - Метаданные схемы

    /// Пользовательские схемы базы данных.
    func fetchSchemas() async throws -> [String] {
        try await singleColumn(
            sql: """
                SELECT n.nspname
                FROM pg_catalog.pg_namespace AS n
                WHERE n.nspname NOT LIKE 'pg\\_%'
                  AND n.nspname <> 'information_schema'
                ORDER BY n.nspname
                """
        )
    }

    /// Базы данных, доступные текущему пользователю.
    func fetchDatabases() async throws -> [String] {
        try await singleColumn(
            sql: """
                SELECT d.datname
                FROM pg_catalog.pg_database AS d
                WHERE d.datallowconn
                ORDER BY d.datname
                """
        )
    }

    /// Таблицы, представления и материализованные представления.
    func fetchTables(schema: String?) async throws -> [DatabaseObject] {
        let schemaFilter = schema.map { "AND n.nspname = '\($0.sqlEscaped)'" } ?? ""
        let outcome = try await executeQuery(
            """
            SELECT n.nspname AS schema_name,
                   c.relname AS object_name,
                   c.relkind AS kind
            FROM pg_catalog.pg_class AS c
            JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
              AND n.nspname NOT LIKE 'pg\\_%'
              AND n.nspname <> 'information_schema'
              \(schemaFilter)
            ORDER BY n.nspname, c.relname
            """
        )

        return outcome.rows.compactMap { row in
            guard let name = row.element(at: 1) else { return nil }
            let schemaName = row.element(at: 0)
            let isView = row.element(at: 2) == "v" || row.element(at: 2) == "m"
            return DatabaseObject(name: name, schema: schemaName, type: isView ? .view : .table)
        }
    }

    /// Колонки таблицы или представления.
    func fetchColumns(schema: String, table: String) async throws -> [ColumnInfo] {
        let outcome = try await executeQuery(
            """
            SELECT a.attname AS column_name,
                   pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
                   a.attnotnull AS not_null,
                   pg_catalog.pg_get_expr(d.adbin, d.adrelid) AS default_value,
                   COALESCE(pk.is_primary, false) AS is_primary_key
            FROM pg_catalog.pg_attribute AS a
            JOIN pg_catalog.pg_class AS c ON c.oid = a.attrelid
            JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            LEFT JOIN pg_catalog.pg_attrdef AS d
                   ON d.adrelid = a.attrelid AND d.adnum = a.attnum
            LEFT JOIN (
                SELECT i.indrelid, unnest(i.indkey) AS attnum, true AS is_primary
                FROM pg_catalog.pg_index AS i
                WHERE i.indisprimary
            ) AS pk ON pk.indrelid = a.attrelid AND pk.attnum = a.attnum
            WHERE n.nspname = '\(schema.sqlEscaped)'
              AND c.relname = '\(table.sqlEscaped)'
              AND a.attnum > 0
              AND NOT a.attisdropped
            ORDER BY a.attnum
            """
        )

        return outcome.rows.compactMap { row in
            guard let name = row.element(at: 0) else { return nil }
            return ColumnInfo(
                name: name,
                dataType: row.element(at: 1) ?? "unknown",
                isNullable: !isTrue(row.element(at: 2)),
                defaultValue: row.element(at: 3),
                isPrimaryKey: isTrue(row.element(at: 4))
            )
        }
    }

    /// Версия сервера, например `PostgreSQL 18.6`.
    func fetchServerVersion() async throws -> String {
        let outcome = try await executeQuery("SELECT version()")
        guard let full = outcome.rows.first?.first ?? nil else { return "unknown" }
        return full.components(separatedBy: " on ").first ?? full
    }

    // MARK: - Изменение схемы

    /// Создаёт таблицу по описанию.
    @discardableResult
    func createTable(_ definition: TableDefinition, dropIfExists: Bool = false) async throws -> QueryOutcome {
        if let problem = definition.validationError {
            throw problem
        }

        let client = try requireClient()
        var outcomes: [QueryOutcome] = []

        if dropIfExists {
            outcomes.append(try await run(definition.dropSQL, on: client))
        }
        outcomes.append(try await run(definition.createSQL, on: client))
        return Self.merge(outcomes)
    }

    /// `true`, если таблица существует.
    func tableExists(schema: String, table: String) async throws -> Bool {
        let outcome = try await executeQuery(
            """
            SELECT EXISTS (
                SELECT 1
                FROM pg_catalog.pg_class AS c
                JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
                WHERE n.nspname = '\(schema.sqlEscaped)'
                  AND c.relname = '\(table.sqlEscaped)'
                  AND c.relkind IN ('r', 'p')
            )
            """
        )
        return (outcome.rows.first?.first ?? nil) == "true"
    }

    /// Число строк в таблице.
    func rowCount(schema: String, table: String) async throws -> Int {
        let outcome = try await executeQuery(
            "SELECT count(*) FROM \"\(schema.sqlEscaped)\".\"\(table.sqlEscaped)\""
        )
        guard let value = outcome.rows.first?.first ?? nil else { return 0 }
        return Int(value) ?? 0
    }

    // MARK: - Массовая загрузка данных

    /// Загружает строки в таблицу через `COPY … FROM STDIN`.
    ///
    /// Это самый быстрый способ залить данные: PostgreSQL разбирает текстовые
    /// значения сам, поэтому конвертация типов не выполняется на клиенте.
    ///
    /// - Parameters:
    ///   - schema: Схема таблицы. Задаётся через `SET LOCAL search_path`, так как
    ///     `copyFrom` подставляет имя таблицы в запрос целиком и не принимает
    ///     квалифицированное имя.
    ///   - columns: Колонки в порядке значений в каждой строке.
    ///   - rows: Значения строк; `nil` в ячейке означает SQL `NULL`.
    ///   - emptyAsNull: Считать ли пустое значение строкой `NULL`.
    ///   - progress: Вызывается по мере отправки данных с числом записанных строк.
    @discardableResult
    func copyRows(
        schema: String,
        table: String,
        columns: [String],
        rows: [[String?]],
        emptyAsNull: Bool = true,
        progress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> Int {
        let client = try requireClient()

        do {
            return try await client.withConnection { connection -> Int in
                // Важно: `PostgresQuery` — это ExpressibleByStringInterpolation, и
                // интерполяция `\(…)` прямо в вызове query() превращается в bind-параметр
                // (`$1`). Для DDL и SET это неверно, поэтому SQL собирается в String и
                // передаётся как `unsafeSQL`.
                try await connection.query(PostgresQuery(unsafeSQL: "BEGIN"), logger: self.logger)
                do {
                    let setSearchPath = "SET LOCAL search_path TO \"\(schema.sqlEscaped)\""
                    try await connection.query(PostgresQuery(unsafeSQL: setSearchPath), logger: self.logger)

                    try await connection.copyFrom(
                        table: table,
                        columns: columns,
                        logger: self.logger
                    ) { writer in
                        try await Self.stream(
                            rows: rows,
                            into: writer,
                            emptyAsNull: emptyAsNull,
                            progress: progress
                        )
                    }
                    try await connection.query(PostgresQuery(unsafeSQL: "COMMIT"), logger: self.logger)
                    return rows.count
                } catch {
                    _ = try? await connection.query(PostgresQuery(unsafeSQL: "ROLLBACK"), logger: self.logger)
                    throw error
                }
            }
        } catch {
            throw Self.map(error, passwordWasEmpty: false)
        }
    }

    /// Отправляет строки в COPY-поток порциями.
    private static func stream(
        rows: [[String?]],
        into writer: PostgresCopyFromWriter,
        emptyAsNull: Bool,
        progress: (@Sendable (Int) -> Void)?
    ) async throws {
        let chunkSize = 500
        var buffer = ByteBufferAllocator().buffer(capacity: 128 * 1024)
        var written = 0

        for row in rows {
            for (index, value) in row.enumerated() {
                if index > 0 { buffer.writeString("\t") }
                buffer.writeString(copyText(value, emptyAsNull: emptyAsNull))
            }
            buffer.writeString("\n")
            written += 1

            if written % chunkSize == 0 {
                try await writer.write(buffer)
                buffer.clear()
                progress?(written)
                try Task.checkCancellation()
            }
        }

        if buffer.readableBytes > 0 {
            try await writer.write(buffer)
        }
        progress?(written)
    }

    /// Кодирует значение для текстового формата `COPY`.
    private static func copyText(_ value: String?, emptyAsNull: Bool) -> String {
        guard let value else { return "\\N" }
        if emptyAsNull && value.isEmpty { return "\\N" }

        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\": escaped += "\\\\"
            case "\t": escaped += "\\t"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    // MARK: - Private: транспорт

    /// Создаёт клиент пула и дожидается, пока пул начнёт работу.
    private func makeClient(for connection: Connection, password: String?) async -> (PostgresClient, Task<Void, Never>) {
        var configuration = PostgresClient.Configuration(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: (password?.isEmpty ?? true) ? nil : password,
            database: connection.database.isEmpty ? nil : connection.database,
            tls: connection.isSSLEnabled ? .prefer(.makeClientConfiguration()) : .disable
        )
        configuration.options.connectTimeout = .seconds(AppConstants.Timeouts.connectSeconds)

        let client = PostgresClient(configuration: configuration, backgroundLogger: logger)

        // run() не возвращается, пока пул не остановят отменой задачи. Хендшейк
        // через AsyncStream гарантирует, что пул уже запущен до первого запроса.
        let (ready, continuation) = AsyncStream<Void>.makeStream()
        let runTask = Task {
            continuation.yield()
            continuation.finish()
            await client.run()
        }
        var iterator = ready.makeAsyncIterator()
        _ = await iterator.next()

        return (client, runTask)
    }

    /// Пароль из формы имеет приоритет, иначе используется сохранённый в Keychain.
    private func resolvePassword(_ connection: Connection, override: String?) -> String? {
        if let override, !override.isEmpty { return override }
        guard let stored = connection.password, !stored.isEmpty else { return nil }
        return stored
    }

    private func requireClient() throws -> PostgresClient {
        guard let activeConnectionID,
              let client = connectionManager.getConnection(for: activeConnectionID) else {
            throw AppError.notConnected
        }
        return client
    }

    /// Выполняет запрос и возвращает строки вместе с тегом команды.
    private func fetch(client: PostgresClient, sql: String) async throws -> PostgresQueryResult {
        let future = try await client.withConnection { connection -> EventLoopFuture<PostgresQueryResult> in
            connection.query(sql)
        }
        return try await future.get()
    }

    private func singleColumn(sql: String) async throws -> [String] {
        let outcome = try await executeQuery(sql)
        return outcome.rows.compactMap { $0.first ?? nil }
    }

    private func isTrue(_ value: String?) -> Bool {
        value == "true" || value == "t"
    }

    // MARK: - Private: разбор результата

    private static func columnNames(of row: PostgresRow?) -> [String] {
        guard let row else { return [] }
        return row.makeRandomAccess().map(\.columnName)
    }

    private static func render(row: PostgresRow) -> [String?] {
        row.makeRandomAccess().map(value(of:))
    }

    // MARK: - Private: ошибки

    /// Переводит ошибку драйвера в понятное пользователю сообщение.
    ///
    /// PostgresNIO отдаёт ошибки двумя типами: современный `PSQLError`
    /// (структурированный, с `serverInfo`) и совместимостный `PostgresError`,
    /// который приходит из API, возвращающих тег команды.
    private static func map(_ error: Error, passwordWasEmpty: Bool) -> AppError {
        if let appError = error as? AppError { return appError }

        if let psql = error as? PSQLError {
            switch psql.code {
            case .authMechanismRequiresPassword, .unsupportedAuthMechanism, .saslError:
                return passwordWasEmpty
                    ? .noPassword
                    : .connectionFailed("сервер отклонил логин или пароль")
            case .connectionError, .clientClosedConnection, .serverClosedConnection,
                 .uncleanShutdown, .poolClosed, .sslUnsupported, .failedToAddSSLHandler:
                return .connectionFailed("сервер недоступен по указанному адресу")
            default:
                if let message = psql.serverInfo?[.message] {
                    return .queryFailed(message)
                }
                return .queryFailed(psql.code.description)
            }
        }

        if let postgresError = error as? PostgresError {
            switch postgresError {
            case .server(let serverError):
                return .queryFailed(serverError.fields[.message] ?? serverError.description)
            case .connectionClosed:
                return .connectionFailed("соединение закрыто сервером")
            case .protocol(let message):
                return .queryFailed(message)
            }
        }

        return .connectionFailed(error.localizedDescription)
    }
}

// MARK: - Преобразование значений PostgreSQL в текст

extension DatabaseService {

    /// Приводит ячейку результата к строке; `nil` означает SQL `NULL`.
    ///
    /// PostgresNIO всегда запрашивает результаты в бинарном формате, поэтому
    /// значения декодируются по типу колонки. Для типов, которые приложение
    /// не умеет разбирать, показывается hex-представление, а не искажённый текст.
    static func value(of cell: PostgresCell) -> String? {
        guard let bytes = cell.bytes else { return nil }

        switch cell.dataType {
        case .bool:
            return (try? cell.decode(Bool.self)).map { $0 ? "true" : "false" }
        case .int2, .int4, .int8, .oid:
            return (try? cell.decode(Int.self)).map(String.init)
        case .money:
            return (try? cell.decode(Int64.self)).map { String(format: "%.2f", Double($0) / 100) }
        case .float4, .float8:
            return (try? cell.decode(Double.self)).map(Self.format(double:))
        case .numeric:
            return (try? cell.decode(Decimal.self)).map { "\($0)" }
        case .date:
            return (try? cell.decode(Date.self)).map { Self.format(date: $0, style: .dateOnly) }
        case .timestamp:
            return (try? cell.decode(Date.self)).map { Self.format(date: $0, style: .dateTime) }
        case .timestamptz:
            return (try? cell.decode(Date.self)).map { Self.format(date: $0, style: .dateTimeWithZone) }
        case .uuid:
            return (try? cell.decode(UUID.self)).map(\.uuidString)
        case .bytea:
            return "\\x" + Self.hex(of: bytes)
        case .interval:
            return Self.decodeInterval(bytes)
        case .inet, .cidr:
            return Self.decodeInet(bytes)
        default:
            break
        }

        if let array = Self.decodeArray(cell) {
            return array
        }

        if cell.format == .text {
            return bytes.getString(at: bytes.readerIndex, length: bytes.readableBytes) ?? ""
        }
        if Self.textLikeTypes.contains(cell.dataType), let text = try? cell.decode(String.self) {
            return text
        }
        return "\\x" + Self.hex(of: bytes)
    }

    // MARK: Массивы

    private static func decodeArray(_ cell: PostgresCell) -> String? {
        switch cell.dataType {
        case .int2Array:
            return (try? cell.decode([Int16].self)).map(format(array:))
        case .int4Array:
            return (try? cell.decode([Int32].self)).map(format(array:))
        case .int8Array:
            return (try? cell.decode([Int64].self)).map(format(array:))
        case .float4Array, .float8Array:
            return (try? cell.decode([Double].self)).map(format(array:))
        case .boolArray:
            return (try? cell.decode([Bool].self)).map(format(array:))
        case .uuidArray:
            return (try? cell.decode([UUID].self)).map { format(array: $0.map(\.uuidString)) }
        case .textArray, .varcharArray, .bpcharArray, .nameArray, .jsonArray, .jsonbArray:
            return (try? cell.decode([String].self)).map(format(array:))
        default:
            return nil
        }
    }

    private static func format<T>(array values: [T]) -> String {
        "{" + values.map { "\($0)" }.joined(separator: ",") + "}"
    }

    // MARK: Вспомогательные преобразования

    /// Типы, которые в бинарном формате действительно являются UTF-8 текстом.
    static let textLikeTypes: Set<PostgresDataType> = [
        .text, .varchar, .bpchar, .name, .char, .json, .jsonb, .xml, .unknown
    ]

    enum DateStyle {
        case dateOnly
        case dateTime
        case dateTimeWithZone
    }

    static func format(date: Date, style: DateStyle) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        switch style {
        case .dateOnly: formatter.dateFormat = "yyyy-MM-dd"
        case .dateTime: formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        case .dateTimeWithZone: formatter.dateFormat = "yyyy-MM-dd HH:mm:ssxxx"
        }
        return formatter.string(from: date)
    }

    static func format(double value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(format: "%.0f", value)
            : String(value)
    }

    static func hex(of buffer: ByteBuffer) -> String {
        guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else {
            return ""
        }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// `interval`: int64 микросекунды, int32 дни, int32 месяцы.
    static func decodeInterval(_ buffer: ByteBuffer) -> String? {
        var copy = buffer
        guard let micros = copy.readInteger(as: Int64.self),
              let days = copy.readInteger(as: Int32.self),
              let months = copy.readInteger(as: Int32.self) else { return nil }

        var parts: [String] = []
        let years = Int(months) / 12
        let restMonths = Int(months) % 12
        if years != 0 { parts.append("\(years) y") }
        if restMonths != 0 { parts.append("\(restMonths) mon") }
        if days != 0 { parts.append("\(days) d") }

        if micros != 0 {
            let seconds = Double(micros) / 1_000_000
            let sign = seconds < 0 ? "-" : ""
            let absolute = abs(seconds)
            let hours = Int(absolute) / 3600
            let minutes = (Int(absolute) % 3600) / 60
            let rest = absolute - Double(hours * 3600 + minutes * 60)
            let whole = Int(rest)
            let fraction = rest == rest.rounded() ? "" : String(format: ".%02d", Int((rest - Double(whole)) * 100))
            parts.append(String(format: "%@%02d:%02d:%02d%@", sign, hours, minutes, whole, fraction))
        }

        return parts.isEmpty ? "00:00:00" : parts.joined(separator: " ")
    }

    /// `inet` / `cidr`: семейство, длина префикса, признак cidr, длина адреса, адрес.
    static func decodeInet(_ buffer: ByteBuffer) -> String? {
        var copy = buffer
        guard let family = copy.readInteger(as: UInt8.self),
              let bits = copy.readInteger(as: UInt8.self),
              let isCIDR = copy.readInteger(as: UInt8.self),
              let length = copy.readInteger(as: UInt8.self),
              let address = copy.readBytes(length: Int(length)) else { return nil }

        let text: String?
        switch family {
        case 2 where address.count == 4:
            text = address.map(String.init).joined(separator: ".")
        case 3 where address.count == 16:
            let groups = stride(from: 0, to: 16, by: 2).map { offset in
                UInt16(address[offset]) << 8 | UInt16(address[offset + 1])
            }
            text = compress(ipv6: groups)
        default:
            text = nil
        }

        guard let text else { return nil }
        let fullPrefix = family == 2 ? bits == 32 : bits == 128
        return (isCIDR == 1 && !fullPrefix) ? "\(text)/\(bits)" : text
    }

    /// Сжимает IPv6-адрес, заменяя самую длинную последовательность нулей на `::`.
    static func compress(ipv6 groups: [UInt16]) -> String {
        var bestStart = -1
        var bestLength = 0
        var currentStart = -1
        var currentLength = 0

        for (index, group) in groups.enumerated() {
            if group == 0 {
                if currentStart == -1 { currentStart = index }
                currentLength += 1
                if currentLength > bestLength {
                    bestStart = currentStart
                    bestLength = currentLength
                }
            } else {
                currentStart = -1
                currentLength = 0
            }
        }

        guard bestLength > 1 else {
            return groups.map { String($0, radix: 16) }.joined(separator: ":")
        }

        let head = groups[..<bestStart].map { String($0, radix: 16) }.joined(separator: ":")
        let tail = groups[(bestStart + bestLength)...].map { String($0, radix: 16) }.joined(separator: ":")
        return head + "::" + tail
    }
}
