import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        BrainWebView()
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WKWebView wrapper

struct BrainWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Permite fetch() de file:// e acesso cross-origin entre recursos locais
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Message handlers — expandidos em JSBridge.swift (Fase 5)
        config.userContentController.add(context.coordinator, name: "openMd")
        config.userContentController.add(context.coordinator, name: "bridgeEvent")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator

        loadHTML(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private func loadHTML(in webView: WKWebView) {
        // Durante o dev, carrega brain-atlas.html do bundle (Resources/)
        // Em produção, o arquivo é copiado para Resources/ no build phase
        if let url = Bundle.module.url(forResource: "brain-atlas", withExtension: "html") {
            let dir = url.deletingLastPathComponent()
            webView.loadFileURL(url, allowingReadAccessTo: dir)
            return
        }
        // Fallback: placeholder enquanto o bundle não está configurado
        let placeholder = """
        <html><body style="background:#0B0F19;color:#4cc3ff;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
          <div>
            <p style="font-size:14px;opacity:.6;text-align:center">brain-atlas.html não encontrado no bundle.<br>
            Adicione o arquivo em Sources/BrainAtlas/Resources/</p>
          </div>
        </body></html>
        """
        webView.loadHTMLString(placeholder, baseURL: nil)
    }
}

// MARK: - Coordinator (navigation + message handlers)

class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "openMd":
            // Expandido em MarkdownReaderView.swift (Fase 4)
            if let path = message.body as? String {
                NotificationCenter.default.post(name: .openMarkdownFile, object: path)
            }
        case "bridgeEvent":
            // Expandido em JSBridge.swift (Fase 5)
            break
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Injeta variável para o JS saber que está rodando dentro do app Swift
        webView.evaluateJavaScript("window.__BRAIN_ATLAS_NATIVE__ = true;")
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openMarkdownFile = Notification.Name("BrainAtlas.openMarkdownFile")
}
