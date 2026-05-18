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

        // Guarda referência no Coordinator para que o JSBridge possa alcançar a view.
        context.coordinator.webView = webView

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

    /// Referência fraca ao WKWebView gerenciado por este coordinator.
    /// Definida em makeNSView após a criação da view.
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "openMd":
            JSBridge.shared.handleOpenMd(message: message)

        case "bridgeEvent":
            JSBridge.shared.handleBridgeEvent(message: message)

        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Registra o WebView no JSBridge para que eventos SSE sejam retransmitidos via JS.
        JSBridge.shared.register(webView: webView)

        // Injeta o script de inicialização que define window.__BRAIN_ATLAS_NATIVE__
        // e window.__onBridgeEvent__, substituindo o EventSource quando rodando nativo.
        webView.evaluateJavaScript(JSBridge.initScript) { _, error in
            if let error {
                print("[ContentView] Erro ao injetar initScript: \(error)")
            }
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openMarkdownFile = Notification.Name("BrainAtlas.openMarkdownFile")
}
