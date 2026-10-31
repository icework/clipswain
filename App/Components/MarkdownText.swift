import SwiftUI

/// Renders agent-written Markdown: headings, lists, quotes and fenced code as blocks, with
/// inline styling (bold, code, links) handled by `AttributedString`.
struct MarkdownText: View {
    let source: String
    var font: Font = .body

    enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, ordered: String?)
        case quote(String)
        case code(String)
        case rule
        case table(headers: [String], rows: [[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, 4)
        case .paragraph(let text):
            inline(text).font(font)
        case .bullet(let text, let ordered):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ordered.map { "\($0)." } ?? "•").font(font).foregroundStyle(.secondary)
                inline(text).font(font)
            }
        case .quote(let text):
            inline(text)
                .font(font)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(10)
            }
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        case .table(let headers, let rows):
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 6) {
                    Menu {
                        ForEach(headers.indices, id: \.self) { column in
                            Button(headers[column]) {
                                withAnimation { proxy.scrollTo(column, anchor: .leading) }
                            }
                        }
                    } label: {
                        Label(AppL10n.text("markdown.view_column", "View column"), systemImage: "tablecells")
                            .font(.caption)
                    }
                    ScrollView(.horizontal) {
                        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                ForEach(Array(headers.enumerated()), id: \.offset) { column, cell in
                                    inline(cell).font(.callout.bold())
                                        .frame(width: 190, alignment: .leading).padding(10).id(column)
                                }
                            }
                            .background(Color.secondary.opacity(0.12))
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                GridRow {
                                    ForEach(headers.indices, id: \.self) { column in
                                        inline(column < row.count ? row[column] : "").font(.callout)
                                            .frame(width: 190, alignment: .leading).padding(10)
                                    }
                                }.background(Color.secondary.opacity(index.isMultiple(of: 2) ? 0.04 : 0.08))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }

    static func blocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            index += 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(rawLine)
                continue
            }
            if line.contains("|"), index < lines.count {
                let headers = tableCells(line)
                let separator = tableCells(lines[index])
                if headers.count > 1, separator.count == headers.count,
                   separator.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) {
                    flush()
                    index += 1
                    var rows: [[String]] = []
                    while index < lines.count, lines[index].contains("|"),
                          !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                        rows.append(tableCells(lines[index]))
                        index += 1
                    }
                    blocks.append(.table(headers: headers, rows: rows))
                    continue
                }
            }
            if line.isEmpty {
                flush()
            } else if let level = headingLevel(line) {
                flush()
                blocks.append(.heading(level, String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" {
                flush()
                blocks.append(.rule)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush()
                var item = String(line.dropFirst(2))
                if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                if item.hasPrefix("[x] ") || item.hasPrefix("[X] ") { item = "☑ " + item.dropFirst(4) }
                blocks.append(.bullet(item, ordered: nil))
            } else if let (number, rest) = orderedItem(line) {
                flush()
                blocks.append(.bullet(rest, ordered: number))
            } else if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func tableCells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|"), !text.hasSuffix("\\|") { text.removeLast() }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for character in text {
            if escaped {
                if character != "|" { cell.append("\\") }
                cell.append(character)
                escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else { cell.append(character) }
        }
        if escaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func orderedItem(_ line: String) -> (String, String)? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count < 4 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (String(digits), String(rest.dropFirst(2)))
    }
}
