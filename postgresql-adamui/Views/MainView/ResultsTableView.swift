//
//  ResultsTableView.swift
//  postgresql-adamui
//
//  Таблица результатов SQL-запроса с динамическим набором колонок.
//

import SwiftUI

/// Отображает `QueryResult` в виде таблицы.
///
/// SwiftUI `Table` требует статически описанных колонок, поэтому таблица
/// построена вручную на `LazyVStack`: набор колонок определяется результатом.
struct ResultsTableView: View {

    let result: QueryResult

    private let columnWidth: CGFloat = 180

    var body: some View {
        if let error = result.error {
            ErrorBanner(message: error)
                .padding(12)
        } else if !result.hasRows {
            emptyState
        } else {
            table
        }
    }

    // MARK: - Таблица

    private var table: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(result.visibleRows.enumerated()), id: \.offset) { index, row in
                        rowView(row, index: index)
                    }

                    if result.isTruncated {
                        Text("Показаны первые \(AppConstants.Limits.visibleResultRows) строк из \(result.rowCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                } header: {
                    headerRow
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(result.columns.enumerated()), id: \.offset) { _, column in
                Text(column)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: columnWidth, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func rowView(_ row: [String?], index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(result.columns.indices), id: \.self) { column in
                cell(row.element(at: column))
                    .frame(width: columnWidth, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
    }

    private func cell(_ value: String?) -> some View {
        Group {
            if value == nil {
                Text("NULL")
                    .font(.system(.caption, design: .monospaced))
                    .italic()
                    .foregroundStyle(.tertiary)
            } else {
                Text(value.orDash.truncated(to: AppConstants.Limits.cellPreviewLength))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .help(value.orDash)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(result.commandTag ?? "Запрос выполнен")
                .font(.callout)
            if result.rowCount > 0 {
                Text("Затронуто: \(String.pluralized(result.rowCount, one: "строка", few: "строки", many: "строк"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ResultsTableView(
        result: QueryResult(
            query: "SELECT * FROM users",
            columns: ["id", "email", "created_at", "is_active", "notes"],
            rows: [
                ["1", "a@example.com", "2026-01-02 03:04:05", "true", nil],
                ["2", "b@example.com", "2026-02-03 04:05:06", "false", "Текст заметки"]
            ],
            executionTime: 0.024
        )
    )
    .frame(width: 800, height: 300)
}
