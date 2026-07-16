import Foundation

/// Creates any file format artifact from a specification string.
/// Powers the chat assistant's `create_artifact` tool.
enum ArtifactsCreator {

    // MARK: - Main Entry

    static func create(spec: ArtifactSpec) -> Artifact? {
        switch spec.kind {
        case .wav:
            guard let data = AudioGenerationService.generateWAV(from: spec.content) else { return nil }
            return save(data: data, name: spec.name, ext: "wav")

        case .midi:
            guard let data = AudioGenerationService.generateMIDI(from: spec.content, tempoBPM: UInt16(spec.tempoBPM ?? 120)) else { return nil }
            return save(data: data, name: spec.name, ext: "mid")

        case .text, .txt:
            guard let data = spec.content.data(using: .utf8) else { return nil }
            return save(data: data, name: spec.name, ext: "txt")

        case .csv:
            let csv = formatAsCSV(spec.content)
            guard let data = csv.data(using: .utf8) else { return nil }
            return save(data: data, name: spec.name, ext: "csv")

        case .json:
            guard let data = formatAsJSON(spec.content) else { return nil }
            return save(data: data, name: spec.name, ext: "json")

        case .html:
            let html = wrapAsHTML(spec.content)
            guard let data = html.data(using: .utf8) else { return nil }
            return save(data: data, name: spec.name, ext: "html")

        case .markdown, .md:
            guard let data = spec.content.data(using: .utf8) else { return nil }
            return save(data: data, name: spec.name, ext: "md")

        case .python:
            guard let data = spec.content.data(using: .utf8) else { return nil }
            return save(data: data, name: spec.name, ext: "py")

        case .javascript, .js:
            guard let data = spec.content.data(using: .utf8) else { return nil }
            return save(data: data, name: spec.name, ext: "js")

        case .swift:
            guard let data = spec.content.data(using: .utf8) else { return nil }
            return save(data: data, name: spec.name, ext: "swift")

        case .zip:
            // For zip, content should be a list of filenames separated by newlines.
            // Each entry becomes a real text file inside the archive.
            guard let data = createSimpleZip(files: spec.content) else { return nil }
            return save(data: data, name: spec.name, ext: "zip")

        case .appPrototype:
            // Generate a full app prototype as a zip containing HTML/JS/CSS
            guard let data = createAppPrototype(spec: spec) else { return nil }
            return save(data: data, name: spec.name, ext: "zip")
        }
    }

    // MARK: - ArtifactSpec

    struct ArtifactSpec {
        enum Kind {
            case wav, midi, text, txt, csv, json, html, markdown, md
            case python, javascript, js, swift, zip, appPrototype
        }
        let kind: Kind
        let name: String
        let content: String
        var tempoBPM: UInt16? = nil
    }

    // MARK: - Private Helpers

    private static func save(data: Data, name: String, ext: String) -> Artifact? {
        let cleanName = name.isEmpty ? "artifact" : name
        let fileName = "\(cleanName).\(ext)"
        let dir = FileStore.shared.artifactsDir
        let url = FileStore.shared.saveData(data, name: fileName, in: dir)
        let relPath = FileStore.shared.relativePath(url)
        let artifact = Artifact(name: fileName, relativePath: relPath, kind: ext, byteSize: Int64(data.count))
        ArtifactStore.shared.add(artifact)
        return artifact
    }

    private static func formatAsCSV(_ content: String) -> String {
        // If content has commas or tabs, it's already CSV-like
        if content.contains(",") || content.contains("\t") {
            return content
        }
        // Try to convert line-by-line data to CSV
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private static func formatAsJSON(_ content: String) -> Data? {
        // If already valid JSON, return as-is
        if let data = content.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        // Try to wrap as a simple JSON object
        let obj: [String: Any] = ["content": content, "generatedAt": ISO8601DateFormatter().string(from: Date())]
        return try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
    }

    private static func wrapAsHTML(_ content: String) -> String {
        // If content already looks like HTML, return as-is
        if content.lowercased().contains("<html") || content.lowercased().contains("<!doctype") {
            return content
        }
        // Wrap markdown-like content in HTML
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>EZIN Artifact</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; line-height: 1.6; }
                pre { background: #f5f5f5; padding: 16px; border-radius: 8px; overflow-x: auto; }
                code { font-family: 'SF Mono', Menlo, monospace; font-size: 0.9em; }
                h1, h2, h3 { color: #333; }
            </style>
        </head>
        <body>
            <pre><code>\(content.htmlEscaped)</code></pre>
        </body>
        </html>
        """
    }

    private static func createSimpleZip(files: String) -> Data? {
        // One line per entry: each becomes a real file inside a fully valid archive
        // (real CRC-32 checksums, correct sizes/offsets) via the shared ZipWriter.
        let fileList = files.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var entries: [ZipWriter.Entry] = []
        for (index, line) in fileList.enumerated() {
            let cleanName = line.trimmingCharacters(in: .whitespaces)
            guard !cleanName.isEmpty else { continue }
            let body = "// File \(index + 1): \(cleanName)\n".data(using: .utf8) ?? Data()
            entries.append(ZipWriter.Entry(name: cleanName, data: body))
        }
        return ZipWriter.makeZip(entries: entries)
    }

    private static func createAppPrototype(spec: ArtifactSpec) -> Data? {
        // Generate a professional HTML/JS/CSS app prototype as a valid zip archive.
        let appName = spec.name.isEmpty ? "AppPrototype" : spec.name
        let safeName = appName.replacingOccurrences(of: " ", with: "_")

        // Parse features from content
        let features = spec.content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        // Generate professional HTML
        let html = generateAppHTML(name: appName, features: features)
        let css = generateAppCSS()
        let js = generateAppJS(features: features)

        let files: [(name: String, content: String)] = [
            ("\(safeName)/index.html", html),
            ("\(safeName)/style.css", css),
            ("\(safeName)/app.js", js),
            ("\(safeName)/README.md", "# \(appName)\n\nGenerated app prototype.\n\n## Features\n\(features.map { "- \($0)" }.joined(separator: "\n"))\n\n## Running\nOpen `index.html` in any modern browser.")
        ]

        let entries = files.compactMap { name, content -> ZipWriter.Entry? in
            guard let data = content.data(using: .utf8) else { return nil }
            return ZipWriter.Entry(name: name, data: data)
        }
        return ZipWriter.makeZip(entries: entries)
    }


    // MARK: - App Prototype Generators

    private static func generateAppHTML(name: String, features: [String]) -> String {
        let featureCards = features.map { f in
            let safeId = f.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
            return """
                <div class="card" id="card_\(safeId)">
                    <div class="card-icon">◆</div>
                    <div class="card-title">\(f)</div>
                    <div class="card-status">Ready</div>
                </div>
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(name)</title>
            <link rel="stylesheet" href="style.css">
        </head>
        <body>
            <div class="app-container">
                <header class="app-header">
                    <div class="logo">◈</div>
                    <h1>\(name)</h1>
                    <div class="header-actions">
                        <button class="btn btn-primary">New</button>
                        <button class="btn">Settings</button>
                    </div>
                </header>
                <nav class="app-nav">
                    <a href="#" class="nav-item active">Dashboard</a>
                    <a href="#" class="nav-item">Features</a>
                    <a href="#" class="nav-item">Analytics</a>
                    <a href="#" class="nav-item">Settings</a>
                </nav>
                <main class="app-main">
                    <div class="stats-row">
                        <div class="stat-card">
                            <div class="stat-value" id="stat-users">0</div>
                            <div class="stat-label">Users</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-value" id="stat-revenue">$0</div>
                            <div class="stat-label">Revenue</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-value" id="stat-growth">0%</div>
                            <div class="stat-label">Growth</div>
                        </div>
                    </div>
                    <h2 class="section-title">Features</h2>
                    <div class="cards-grid">
                        \(featureCards)
                    </div>
                </main>
            </div>
            <script src="app.js"></script>
        </body>
        </html>
        """
    }

    private static func generateAppCSS() -> String {
        return """
        :root {
            --primary: #6366f1;
            --primary-dark: #4f46e5;
            --bg: #0f172a;
            --surface: #1e293b;
            --surface-hover: #334155;
            --text: #f1f5f9;
            --text-muted: #94a3b8;
            --border: #334155;
            --success: #22c55e;
            --radius: 12px;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
        .app-container { max-width: 1200px; margin: 0 auto; min-height: 100vh; }
        .app-header { display: flex; align-items: center; gap: 16px; padding: 20px 32px; border-bottom: 1px solid var(--border); }
        .logo { font-size: 28px; color: var(--primary); }
        .app-header h1 { font-size: 20px; font-weight: 600; flex: 1; }
        .header-actions { display: flex; gap: 8px; }
        .btn { padding: 8px 16px; border-radius: 8px; border: 1px solid var(--border); background: var(--surface); color: var(--text); cursor: pointer; font-size: 14px; transition: all 0.2s; }
        .btn:hover { background: var(--surface-hover); }
        .btn-primary { background: var(--primary); border-color: var(--primary); }
        .btn-primary:hover { background: var(--primary-dark); }
        .app-nav { display: flex; gap: 4px; padding: 12px 32px; border-bottom: 1px solid var(--border); }
        .nav-item { padding: 8px 16px; border-radius: 8px; color: var(--text-muted); text-decoration: none; font-size: 14px; transition: all 0.2s; }
        .nav-item:hover, .nav-item.active { background: var(--surface); color: var(--text); }
        .app-main { padding: 32px; }
        .stats-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 32px; }
        .stat-card { background: var(--surface); border-radius: var(--radius); padding: 24px; border: 1px solid var(--border); }
        .stat-value { font-size: 32px; font-weight: 700; color: var(--primary); }
        .stat-label { font-size: 14px; color: var(--text-muted); margin-top: 4px; }
        .section-title { font-size: 18px; font-weight: 600; margin-bottom: 16px; }
        .cards-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; }
        .card { background: var(--surface); border-radius: var(--radius); padding: 24px; border: 1px solid var(--border); cursor: pointer; transition: all 0.2s; }
        .card:hover { border-color: var(--primary); transform: translateY(-2px); }
        .card-icon { font-size: 24px; color: var(--primary); margin-bottom: 12px; }
        .card-title { font-size: 16px; font-weight: 600; margin-bottom: 8px; }
        .card-status { font-size: 12px; color: var(--success); }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        .card { animation: fadeIn 0.4s ease-out; }
        """
    }

    private static func generateAppJS(features: [String]) -> String {
        return """
        // \(features.joined(separator: ", "))
        document.addEventListener('DOMContentLoaded', () => {
            // Animate stats
            const animateValue = (id, target, prefix = '', suffix = '') => {
                const el = document.getElementById(id);
                if (!el) return;
                let current = 0;
                const increment = target / 60;
                const timer = setInterval(() => {
                    current += increment;
                    if (current >= target) { current = target; clearInterval(timer); }
                    el.textContent = prefix + Math.floor(current).toLocaleString() + suffix;
                }, 16);
            };
            animateValue('stat-users', 1248);
            animateValue('stat-revenue', 48200, '$');
            animateValue('stat-growth', 23, '', '%');

            // Card interactions
            document.querySelectorAll('.card').forEach(card => {
                card.addEventListener('click', () => {
                    const status = card.querySelector('.card-status');
                    if (status) status.textContent = status.textContent === 'Active' ? 'Ready' : 'Active';
                });
            });
        });
        """
    }
}

// MARK: - String Extensions

private extension String {
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}


