import SwiftUI

/// Lightweight Markdown renderer that produces clean, professional SwiftUI output:
/// headings, bold/italic/inline-code, bullet & numbered lists, code blocks, tables,
/// block quotes and horizontal rules. Fixes the old "raw ** everywhere" look.
struct MarkdownView: View {
    let text: String
    var textColor: Color = .white.opacity(0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block model

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullets([String])
        case numbered([String])
        case code(String)
        case table(header: [String], rows: [[String]])
        case quote(String)
        case rule
    }

    private var blocks: [Block] {
        var out: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        func isTableRow(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("|") && t.dropFirst().contains("|")
        }
        func splitRow(_ s: String) -> [String] {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.isEmpty { i += 1; continue }

            // Code fence
            if line.hasPrefix("```") {
                var code: [String] = []; i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1
                out.append(.code(code.joined(separator: "\n")))
                continue
            }
            // Horizontal rule
            if line == "---" || line == "***" || line == "___" { out.append(.rule); i += 1; continue }
            // Heading
            if line.hasPrefix("#") {
                let hashes = line.prefix(while: { $0 == "#" }).count
                let content = String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                out.append(.heading(level: min(hashes, 4), text: content)); i += 1; continue
            }
            // Table
            if isTableRow(line) {
                var rows: [[String]] = []
                while i < lines.count, isTableRow(lines[i]) { rows.append(splitRow(lines[i])); i += 1 }
                if rows.count >= 2 {
                    let header = rows[0]
                    // Row 1 is the |---| separator — drop it.
                    let body = Array(rows.dropFirst(2))
                    out.append(.table(header: header, rows: body))
                } else if let only = rows.first {
                    out.append(.paragraph(only.joined(separator: " ")))
                }
                continue
            }
            // Block quote
            if line.hasPrefix(">") {
                out.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); i += 1; continue
            }
            // Bullet list
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") {
                        items.append(String(l.dropFirst(2))); i += 1
                    } else { break }
                }
                out.append(.bullets(items)); continue
            }
            // Numbered list
            if let r = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if let rr = l.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        items.append(String(l[rr.upperBound...])); i += 1
                    } else { break }
                }
                _ = r
                out.append(.numbered(items)); continue
            }
            // Paragraph (merge consecutive plain lines)
            var para = [line]; i += 1
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("- ") || l.hasPrefix("* ")
                    || l.hasPrefix(">") || l.hasPrefix("```") || isTableRow(l)
                    || l.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil { break }
                para.append(l); i += 1
            }
            out.append(.paragraph(para.joined(separator: " ")))
        }
        return out
    }

    // MARK: - Rendering

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let t):
            inline(t)
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(textColor)
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph(let t):
            inline(t).font(.system(size: 14)).foregroundStyle(textColor)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(Glass.accent2)
                        inline(it).font(.system(size: 14)).foregroundStyle(textColor)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, it in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).").foregroundStyle(Glass.accent2).font(.system(size: 14, weight: .semibold))
                        inline(it).font(.system(size: 14)).foregroundStyle(textColor)
                    }
                }
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
        case .table(let header, let rows):
            tableView(header: header, rows: rows)
        case .quote(let t):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Glass.accent).frame(width: 3)
                inline(t).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
            }
        case .rule:
            Divider().overlay(Color.white.opacity(0.15)).padding(.vertical, 2)
        }
    }

    private func tableView(header: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, h in
                        inline(h).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(minWidth: 70, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                }
                .background(Color.white.opacity(0.10))
                ForEach(Array(rows.enumerated()), id: \.offset) { ridx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                                .frame(minWidth: 70, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                        }
                    }
                    .background(ridx % 2 == 0 ? Color.clear : Color.white.opacity(0.04))
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return 20; case 2: return 17; case 3: return 15; default: return 14 }
    }

    /// Inline formatting via AttributedString markdown (bold/italic/code/links).
    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(s)
    }
}
