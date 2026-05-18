import SwiftUI
import WebKit
import AppKit

// MARK: - Category color palette

private let categoryColors: [String: NSColor] = [
    "agent": NSColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1), // #fbbf24
    "skill": NSColor(red: 0.753, green: 0.518, blue: 0.988, alpha: 1), // #c084fc
    "mcp":   NSColor(red: 0.984, green: 0.573, blue: 0.188, alpha: 1), // #fb923c
    "dsg":   NSColor(red: 0.298, green: 0.765, blue: 1.000, alpha: 1), // #4cc3ff
    "cast":  NSColor(red: 0.490, green: 0.831, blue: 0.643, alpha: 1), // #7dd4a4
]

private let defaultCategoryColor = NSColor(red: 0.298, green: 0.765, blue: 1.000, alpha: 1) // #4cc3ff

private func color(for category: String) -> NSColor {
    categoryColors[category.lowercased()] ?? defaultCategoryColor
}

private func hexString(from nsColor: NSColor) -> String {
    guard let c = nsColor.usingColorSpace(.deviceRGB) else { return "#4cc3ff" }
    return String(
        format: "#%02x%02x%02x",
        Int(c.redComponent * 255),
        Int(c.greenComponent * 255),
        Int(c.blueComponent * 255)
    )
}

// MARK: - MarkdownReaderView (SwiftUI)

struct MarkdownReaderView: View {
    let filePath: String
    let nodeName: String
    let category: String
    var onClose: (() -> Void)?

    @State private var markdownContent: String = ""
    @State private var loadError: String? = nil

    private var accentColor: Color {
        Color(color(for: category))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
                .background(Color(nsColor: color(for: category)).opacity(0.4))
            contentArea
        }
        .background(Color(red: 0.039, green: 0.055, blue: 0.094)) // #0a0e18
        .onAppear { loadFile() }
    }

    // MARK: Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(nodeName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accentColor)
                    .lineLimit(1)

                Text(filePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 0.502, green: 0.537, blue: 0.651)) // #808698
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let category = categoryColors[category.lowercased()] {
                Text(self.category.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: category))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: category).opacity(0.15))
                    .cornerRadius(4)
            }

            Button(action: { onClose?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.502, green: 0.537, blue: 0.651))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.043, green: 0.059, blue: 0.098)) // #0b0f19
    }

    // MARK: Content area

    @ViewBuilder
    private var contentArea: some View {
        if let error = loadError {
            errorView(message: error)
        } else {
            MarkdownWebView(
                markdownContent: markdownContent,
                accentHex: hexString(from: color(for: category))
            )
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(Color(red: 0.984, green: 0.573, blue: 0.188)) // #fb923c
            Text("Arquivo não encontrado")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.804, green: 0.839, blue: 0.957)) // #cdd6f4
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(red: 0.502, green: 0.537, blue: 0.651))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.039, green: 0.055, blue: 0.094))
    }

    // MARK: File loading

    private func loadFile() {
        let sourceDir: String
        if let saved = UserDefaults.standard.string(forKey: "sourceDir"), !saved.isEmpty {
            sourceDir = saved
        } else {
            // Fallback: use the directory of the running bundle
            sourceDir = Bundle.main.bundlePath
        }

        let base = URL(fileURLWithPath: sourceDir, isDirectory: true)
        let fileURL = base.appendingPathComponent(filePath)

        do {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            markdownContent = raw
            loadError = nil
        } catch {
            loadError = fileURL.path
        }
    }
}

// MARK: - MarkdownWebView (WKWebView renderer)

struct MarkdownWebView: NSViewRepresentable {
    let markdownContent: String
    let accentHex: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = buildHTML(markdown: markdownContent, accent: accentHex)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        // Open external links in the default browser instead of inside the WKWebView
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    // MARK: HTML builder

    private func buildHTML(markdown raw: String, accent: String) -> String {
        // Escape the markdown so it can be safely embedded in a JS string literal
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          /* ── Reset & base ── */
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

          :root {
            --bg:        #0a0e18;
            --bg-card:   rgba(255,255,255,0.04);
            --text:      #cdd6f4;
            --text-muted:#7f849c;
            --accent:    \(accent);
            --code-bg:   rgba(0,0,0,0.35);
            --border:    rgba(255,255,255,0.08);
            --mono:      'JetBrains Mono', 'Fira Code', 'Cascadia Code', ui-monospace, monospace;
            --sans:      -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
          }

          html, body {
            background: var(--bg);
            color: var(--text);
            font-family: var(--sans);
            font-size: 14px;
            line-height: 1.75;
            height: 100%;
          }

          body { padding: 28px 40px 60px; max-width: 820px; }

          /* ── Scrollbar ── */
          ::-webkit-scrollbar { width: 6px; }
          ::-webkit-scrollbar-track { background: transparent; }
          ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.12); border-radius: 3px; }
          ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.22); }

          /* ── Headings ── */
          h1, h2, h3, h4, h5, h6 {
            color: var(--accent);
            font-weight: 600;
            margin: 1.6em 0 0.5em;
            line-height: 1.3;
          }
          h1 { font-size: 1.75em; border-bottom: 1px solid var(--border); padding-bottom: 0.4em; }
          h2 { font-size: 1.35em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
          h3 { font-size: 1.1em; }
          h4, h5, h6 { font-size: 1em; color: color-mix(in srgb, var(--accent) 70%, var(--text) 30%); }

          /* ── Paragraphs & text ── */
          p { margin: 0.75em 0; }
          strong { color: #fff; font-weight: 600; }
          em { color: color-mix(in srgb, var(--text) 85%, var(--accent) 15%); }
          del { text-decoration: line-through; color: var(--text-muted); }

          /* ── Links ── */
          a { color: var(--accent); text-decoration: none; }
          a:hover { text-decoration: underline; opacity: 0.85; }

          /* ── Inline code ── */
          code {
            font-family: var(--mono);
            font-size: 0.875em;
            background: var(--code-bg);
            color: var(--text);
            padding: 0.15em 0.45em;
            border-radius: 4px;
            border: 1px solid var(--border);
          }

          /* ── Code blocks ── */
          pre {
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 1em 1.2em;
            overflow-x: auto;
            margin: 1em 0;
            position: relative;
          }
          pre code {
            background: transparent;
            border: none;
            padding: 0;
            font-size: 0.85em;
            color: var(--text);
            line-height: 1.6;
          }

          /* ── Blockquotes ── */
          blockquote {
            border-left: 3px solid var(--accent);
            margin: 1em 0;
            padding: 0.6em 1.2em;
            background: rgba(255,255,255,0.03);
            border-radius: 0 6px 6px 0;
            color: var(--text-muted);
          }
          blockquote p { margin: 0; }

          /* ── Lists ── */
          ul, ol { padding-left: 1.6em; margin: 0.6em 0; }
          li { margin: 0.2em 0; }
          li > ul, li > ol { margin: 0.1em 0; }

          /* ── Tables ── */
          table {
            width: 100%;
            border-collapse: collapse;
            margin: 1.2em 0;
            font-size: 0.9em;
          }
          th {
            background: rgba(255,255,255,0.06);
            color: var(--accent);
            font-weight: 600;
            text-align: left;
            padding: 8px 12px;
            border-bottom: 2px solid var(--border);
          }
          td {
            padding: 7px 12px;
            border-bottom: 1px solid var(--border);
            vertical-align: top;
          }
          tr:last-child td { border-bottom: none; }
          tr:hover td { background: rgba(255,255,255,0.025); }

          /* ── Horizontal rules ── */
          hr {
            border: none;
            border-top: 1px solid var(--border);
            margin: 2em 0;
          }

          /* ── Images ── */
          img {
            max-width: 100%;
            border-radius: 6px;
            margin: 0.5em 0;
          }

          /* ── Task lists ── */
          input[type="checkbox"] {
            accent-color: var(--accent);
            margin-right: 6px;
            vertical-align: middle;
          }
        </style>
        </head>
        <body>
        <div id="content">Carregando…</div>

        <!-- marked.js CDN-free inline-minimal parser (embedded) -->
        <script>
        // ── Minimal but complete Markdown renderer ──────────────────────────────
        // Handles: headings, bold, italic, code blocks, inline code, blockquotes,
        // ordered/unordered lists, task lists, tables, links, images, hr, strikethrough.
        (function() {
          function escapeHtml(s) {
            return s
              .replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;');
          }

          function parseInline(text) {
            // Images before links
            text = text.replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g, '<img alt="$1" src="$2">');
            // Links
            text = text.replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g, '<a href="$2">$1</a>');
            // Bold+italic
            text = text.replace(/\\*\\*\\*([^*]+)\\*\\*\\*/g, '<strong><em>$1</em></strong>');
            // Bold
            text = text.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
            text = text.replace(/__([^_]+)__/g, '<strong>$1</strong>');
            // Italic
            text = text.replace(/\\*([^*]+)\\*/g, '<em>$1</em>');
            text = text.replace(/_([^_]+)_/g, '<em>$1</em>');
            // Strikethrough
            text = text.replace(/~~([^~]+)~~/g, '<del>$1</del>');
            // Inline code
            text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
            return text;
          }

          function parseMarkdown(md) {
            const lines = md.split('\\n');
            let html = '';
            let i = 0;

            while (i < lines.length) {
              const line = lines[i];

              // Fenced code block
              if (/^```/.test(line)) {
                const lang = line.slice(3).trim();
                let code = '';
                i++;
                while (i < lines.length && !/^```/.test(lines[i])) {
                  code += escapeHtml(lines[i]) + '\\n';
                  i++;
                }
                html += `<pre><code class="language-${escapeHtml(lang)}">${code}</code></pre>\\n`;
                i++;
                continue;
              }

              // Headings
              const hMatch = line.match(/^(#{1,6})\\s+(.*)/);
              if (hMatch) {
                const level = hMatch[1].length;
                html += `<h${level}>${parseInline(hMatch[2])}</h${level}>\\n`;
                i++;
                continue;
              }

              // Horizontal rule
              if (/^(---+|===+|\\*\\*\\*+)\\s*$/.test(line)) {
                html += '<hr>\\n';
                i++;
                continue;
              }

              // Blockquote
              if (/^>\\s?/.test(line)) {
                let bqContent = '';
                while (i < lines.length && /^>\\s?/.test(lines[i])) {
                  bqContent += lines[i].replace(/^>\\s?/, '') + '\\n';
                  i++;
                }
                html += `<blockquote>${parseMarkdown(bqContent)}</blockquote>\\n`;
                continue;
              }

              // Table
              if (/\\|/.test(line) && i + 1 < lines.length && /^[|\\s:-]+$/.test(lines[i + 1])) {
                const headers = line.split('|').map(s => s.trim()).filter(Boolean);
                i += 2; // skip separator row
                let table = '<table><thead><tr>';
                headers.forEach(h => { table += `<th>${parseInline(h)}</th>`; });
                table += '</tr></thead><tbody>';
                while (i < lines.length && /\\|/.test(lines[i]) && lines[i].trim() !== '') {
                  const cells = lines[i].split('|').map(s => s.trim()).filter(Boolean);
                  table += '<tr>';
                  cells.forEach(c => { table += `<td>${parseInline(c)}</td>`; });
                  table += '</tr>';
                  i++;
                }
                table += '</tbody></table>';
                html += table + '\\n';
                continue;
              }

              // Unordered list
              if (/^[-*+]\\s/.test(line)) {
                html += '<ul>';
                while (i < lines.length && /^[-*+]\\s/.test(lines[i])) {
                  const itemText = lines[i].replace(/^[-*+]\\s/, '');
                  // Task list item
                  if (/^\\[[ xX]\\]/.test(itemText)) {
                    const checked = /^\\[[xX]\\]/.test(itemText);
                    const label = itemText.slice(4);
                    html += `<li><input type="checkbox" disabled ${checked ? 'checked' : ''}>${parseInline(label)}</li>`;
                  } else {
                    html += `<li>${parseInline(itemText)}</li>`;
                  }
                  i++;
                }
                html += '</ul>\\n';
                continue;
              }

              // Ordered list
              if (/^\\d+\\.\\s/.test(line)) {
                html += '<ol>';
                while (i < lines.length && /^\\d+\\.\\s/.test(lines[i])) {
                  const itemText = lines[i].replace(/^\\d+\\.\\s/, '');
                  html += `<li>${parseInline(itemText)}</li>`;
                  i++;
                }
                html += '</ol>\\n';
                continue;
              }

              // Empty line
              if (line.trim() === '') {
                i++;
                continue;
              }

              // Paragraph
              let para = '';
              while (i < lines.length && lines[i].trim() !== '' &&
                     !/^(#{1,6}\\s|>|```|[-*+]\\s|\\d+\\.\\s|\\|)/.test(lines[i]) &&
                     !/^(---+|===+|\\*\\*\\*+)\\s*$/.test(lines[i])) {
                para += (para ? ' ' : '') + lines[i];
                i++;
              }
              if (para) html += `<p>${parseInline(para)}</p>\\n`;
            }

            return html;
          }

          const raw = `\(escaped)`;
          document.getElementById('content').innerHTML = parseMarkdown(raw);
        })();
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - MarkdownReaderWindow (NSWindow manager)

final class MarkdownReaderWindow: NSObject {
    static let shared = MarkdownReaderWindow()
    private var window: NSWindow?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMarkdownFile(_:)),
            name: .openMarkdownFile,
            object: nil
        )
    }

    // MARK: Public API

    static func open(path: String, nodeName: String, category: String) {
        DispatchQueue.main.async {
            shared.openWindow(path: path, nodeName: nodeName, category: category)
        }
    }

    // MARK: Notification handler

    @objc private func handleOpenMarkdownFile(_ notification: Notification) {
        // Support both a plain String and a dict with path/nodeName/category
        if let dict = notification.object as? [String: String] {
            let path     = dict["path"]     ?? ""
            let nodeName = dict["nodeName"] ?? path
            let category = dict["category"] ?? "dsg"
            DispatchQueue.main.async { self.openWindow(path: path, nodeName: nodeName, category: category) }
        } else if let path = notification.object as? String {
            let nodeName = URL(fileURLWithPath: path)
                .deletingPathExtension()
                .lastPathComponent
            DispatchQueue.main.async { self.openWindow(path: path, nodeName: nodeName, category: "dsg") }
        }
    }

    // MARK: Window lifecycle

    private func openWindow(path: String, nodeName: String, category: String) {
        if let existing = window {
            // Reuse: swap content and bring to front
            existing.title = nodeName
            existing.contentView = NSHostingView(
                rootView: MarkdownReaderView(
                    filePath: path,
                    nodeName: nodeName,
                    category: category,
                    onClose: { [weak self] in self?.closeWindow() }
                )
            )
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = nodeName
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.minSize = NSSize(width: 600, height: 400)
        win.backgroundColor = NSColor(red: 0.039, green: 0.055, blue: 0.094, alpha: 1) // #0a0e18
        win.contentView = NSHostingView(
            rootView: MarkdownReaderView(
                filePath: path,
                nodeName: nodeName,
                category: category,
                onClose: { [weak self] in self?.closeWindow() }
            )
        )
        win.center()
        win.setFrameAutosaveName("BrainAtlasMarkdownReader")
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
    }

    private func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: NSWindowDelegate — clear reference when window is closed by the user

extension MarkdownReaderWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
