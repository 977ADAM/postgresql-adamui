//
//  ImportCSVView.swift
//  postgresql-adamui
//
//  Мастер импорта данных из CSV.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportCSVView: View {

    @ObservedObject var viewModel: ImportViewModel
    let onFinish: (CSVImportReport) -> Void
    let onCancel: () -> Void

    @State private var showingFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fileSection
                    if viewModel.hasFile {
                        parseOptionsSection
                        destinationSection
                        if viewModel.mode == .createNew {
                            columnsSection
                        }
                        previewSection
                    }
                    if let report = viewModel.report {
                        successBanner(report)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider()
            footer
        }
        .frame(width: 880, height: 680)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.choose(url: url)
                }
            case .failure(let error):
                viewModel.error = error.localizedDescription
                viewModel.showError = true
            }
        }
        .errorAlert(message: $viewModel.error)
    }

    // MARK: - Заголовок

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Импорт данных из CSV")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Данные будут загружены через COPY — это самый быстрый способ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Файл

    private var fileSection: some View {
        section(title: "Файл", systemImage: "doc.text") {
            HStack(spacing: 12) {
                Image(systemName: viewModel.hasFile ? "doc.badge.checkmark" : "doc")
                    .font(.system(size: 20))
                    .foregroundStyle(viewModel.hasFile ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.fileURL?.lastPathComponent ?? "Файл не выбран")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let summary = viewModel.fileSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Выберите .csv файл с данными")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Выбрать файл…") { showingFilePicker = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Параметры разбора

    private var parseOptionsSection: some View {
        section(title: "Разбор файла", systemImage: "slider.horizontal.3") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Разделитель")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewModel.delimiterOption) {
                        ForEach(ImportViewModel.DelimiterOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Заголовки")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Первая строка — заголовки", isOn: $viewModel.hasHeaderRow)
                }

                Spacer()

                if viewModel.isLoadingFile {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .onChange(of: viewModel.delimiterOption) { _, _ in viewModel.reload() }
            .onChange(of: viewModel.hasHeaderRow) { _, _ in viewModel.reload() }
        }
    }

    // MARK: - Назначение

    private var destinationSection: some View {
        section(title: "Назначение", systemImage: "square.and.arrow.down") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $viewModel.mode) {
                    ForEach(ImportViewModel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if viewModel.mode == .createNew {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Схема")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $viewModel.schema) {
                                ForEach(viewModel.schemas, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Имя таблицы")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("users", text: $viewModel.tableName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                        }

                        Spacer()
                    }

                    Toggle("Удалить таблицу, если она уже существует", isOn: $viewModel.dropIfExists)
                        .toggleStyle(.checkbox)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Схема")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $viewModel.existingSchema) {
                                ForEach(viewModel.schemas, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Таблица")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $viewModel.existingTable) {
                                Text("Выберите таблицу…").tag(String?.none)
                                ForEach(existingTables, id: \.id) { table in
                                    Text(table.name).tag(String?.some(table.name))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 260)
                        }

                        Spacer()
                    }

                    Text("Колонки сопоставляются по именам заголовков файла и колонок таблицы.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Пустые значения считать как NULL", isOn: $viewModel.emptyAsNull)
                        .toggleStyle(.checkbox)
                    Toggle("Удалять пробелы в начале и конце значений", isOn: $viewModel.trimWhitespace)
                        .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var existingTables: [DatabaseObject] {
        viewModel.existingTables.filter { $0.schema == viewModel.existingSchema }
    }

    // MARK: - Колонки

    private var columnsSection: some View {
        section(title: "Колонки новой таблицы", systemImage: "tablecells") {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Колонка").font(.caption).foregroundStyle(.secondary).frame(width: 220, alignment: .leading)
                    Text("Тип").font(.caption).foregroundStyle(.secondary).frame(width: 200, alignment: .leading)
                    Text("NULL").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    Spacer()
                }
                .padding(.bottom, 6)

                ForEach($viewModel.columns) { $column in
                    HStack(spacing: 10) {
                        TextField("имя", text: $column.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)

                        TypePicker(selection: $column.dataType)
                            .frame(width: 200)

                        Toggle("", isOn: $column.isNullable)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .frame(width: 60, alignment: .leading)

                        Spacer()

                        Text(inferredHint(for: column))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Button("Вернуть типы по данным") { viewModel.resetTypesToInferred() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }

    /// Подсказка, если тип отличается от выведенного по данным.
    private func inferredHint(for column: ColumnDefinition) -> String {
        guard let preview = viewModel.preview,
              let index = viewModel.columns.firstIndex(where: { $0.id == column.id }),
              index < preview.inferredTypes.count else { return "" }
        let inferred = preview.inferredTypes[index]
        return inferred == column.dataType ? "" : "из данных: \(inferred)"
    }

    // MARK: - Предпросмотр

    private var previewSection: some View {
        section(title: "Предпросмотр", systemImage: "eye") {
            if let preview = viewModel.preview {
                CSVPreviewTable(headers: preview.headers, rows: preview.sample(5), totalRows: preview.rowCount)
            }
        }
    }

    private func successBanner(_ report: CSVImportReport) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Импорт завершён")
                    .fontWeight(.medium)
                Text(report.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.12))
        )
    }

    // MARK: - Нижняя панель

    private var footer: some View {
        VStack(spacing: 8) {
            if viewModel.isImporting {
                ProgressView(value: viewModel.progress) {
                    Text("Загрузка: \(viewModel.loadedRows) из \(viewModel.preview?.rowCount ?? 0) строк")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let problem = viewModel.blockingProblem {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(problem.errorDescription ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                Button("Отмена", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                if let report = viewModel.report {
                    Button("Готово") { onFinish(report) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(viewModel.importButtonTitle) {
                        Task {
                            if await viewModel.runImport(), let report = viewModel.report {
                                onFinish(report)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canImport)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Вспомогательное

    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

// MARK: - Выбор типа

/// Выпадающий список типов PostgreSQL с сохранением нестандартного значения.
struct TypePicker: View {

    @Binding var selection: String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { type in
                Text(type).tag(type)
            }
        }
        .labelsHidden()
    }

    /// Предлагаемые типы плюс текущее значение, если оно не входит в список
    /// (например, тип, прочитанный из существующей таблицы).
    private var options: [String] {
        var result = CSVTypeInference.suggestedTypes
        if !selection.isBlank, !result.contains(selection) {
            result.insert(selection, at: 0)
        }
        return result
    }
}

// MARK: - Предпросмотр данных

/// Небольшая таблица с первыми строками файла.
struct CSVPreviewTable: View {

    let headers: [String]
    let rows: [[String]]
    let totalRows: Int

    private let columnWidth: CGFloat = 150

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(header)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: columnWidth, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                    }
                }
                .background(Color.primary.opacity(0.06))

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(Array(headers.indices), id: \.self) { column in
                            Text(column < row.count ? row[column] : "")
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: columnWidth, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                        }
                    }
                }

                if totalRows > rows.count {
                    Text("… и ещё \(totalRows - rows.count) строк")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
        .frame(maxHeight: 180)
    }
}
