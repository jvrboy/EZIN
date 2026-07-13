import SwiftUI

/// Lightweight Markdown renderer for chat messages: headings, sub-headings, bullet
/// and numbered lists, block quotes, horizontal rules, and inline **bold**/*italic*/`code`.
/// Renders cleanly on iOS 15+ (uses AttributedString for inline styling) so professional
/// structured output shows as real formatting instead of raw asterisks.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [MDBlock] {
        markdown.components(separatedBy: "\n").map { MDBlock(line: $0) }
    }
}

private struct MDBlock: Identifiable {
    let id = UUID()
    let line: String

    @ViewBuilder var view: some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Spacer().frame(height: 2)
        } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            Divider().overlay(Color.white.opacity(0.15))
        } else if trimmed.hasPrefix("### ") {
            styled(trimmed.dropFirst(4)).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95)).padding(.top, 2)
        } else if trimmed.hasPrefix("## ") {
            styled(trimmed.dropFirst(3)).font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white).padding(.top, 3)
        } else if trimmed.hasPrefix("# ") {
            styled(trimmed.dropFirst(2)).font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white).padding(.top, 3)
        } else if trimmed.hasPrefix("> ") {
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 3)
                styled(trimmed.dropFirst(2)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                styled(trimmed.dropFirst(2)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.92))
            }.padding(.leading, 4)
        } else if let m = numberedPrefix(trimmed) {
            HStack(alignment: .top, spacing: 8) {
                Text(m.marker).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                styled(m.rest).font(.system(size: 14)).foregroundStyle(.white.opacity(0.92))
            }.padding(.leading, 4)
        } else {
            styled(Substring(trimmed)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.92))
        }
    }

    /// Parse a "1. text" numbered-list prefix.
    private func numberedPrefix(_ s: String) -> (marker: String, rest: Substring)? {
        guard let dot = s.firstIndex(of: ".") else { return nil }
        let num = s[s.startIndex..<dot]
        guard !num.isEmpty, num.allSatisfy(\.isNumber),
              s.index(after: dot) < s.endIndex, s[s.index(after: dot)] == " " else { return nil }
        return ("\(num).", s[s.index(dot, offsetBy: 2)...])
    }

    /// Inline markdown (**bold**, *italic*, `code`) -> styled Text.
    private func styled(_ s: Substring) -> Text {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attr = try? AttributedString(markdown: String(s), options: options) {
            return Text(attr)
        }
        return Text(String(s))
    }
}
