import Foundation
import WebKit

// MARK: - JSBridge

/// Gerencia a comunicação bidirecional Swift ↔ JS.
///
/// Swift → JS: conecta ao SSE stream do BridgeServer (localhost:8766/stream)
///             e injeta cada evento no WKWebView via window.__onBridgeEvent__.
///
/// JS → Swift (openMd):  abre o MarkdownReaderWindow para o nó clicado.
/// JS → Swift (bridgeEvent): reservado para relatórios futuros do JS.
final class JSBridge: NSObject {

    // MARK: - Singleton

    static let shared = JSBridge()

    // MARK: - Private state

    /// WKWebView atual. Atualizado pelo Coordinator após cada load.
    private weak var webView: WKWebView?

    /// Task de escuta do SSE stream. Cancelada ao trocar de webView.
    private var streamTask: Task<Void, Never>?

    /// URL do stream. Lida do UserDefaults para consistência com BridgeServer.
    private var streamURL: URL {
        let port = UserDefaults.standard.integer(forKey: "bridgePort")
        let resolvedPort = port > 0 ? port : 8766
        return URL(string: "http://localhost:\(resolvedPort)/stream")!
    }

    // MARK: - Init

    private override init() { super.init() }

    // MARK: - Registro do WebView

    /// Chamado pelo Coordinator quando um novo WKWebView está pronto.
    func register(webView: WKWebView) {
        self.webView = webView
        restartStream()
    }

    // MARK: - Swift → JS: injetar evento

    /// Serializa um BridgeEvent para JSON e chama window.__onBridgeEvent__ no WebView.
    func inject(event: BridgeEvent, into webView: WKWebView) {
        guard let data = try? JSONEncoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }

        let js = "if (typeof window.__onBridgeEvent__ === 'function') { window.__onBridgeEvent__(\(json)); }"

        DispatchQueue.main.async {
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    print("[JSBridge] evaluateJavaScript error: \(error)")
                }
            }
        }
    }

    // MARK: - SSE stream reader

    private func restartStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.listenToStream()
        }
    }

    /// Conecta ao BridgeServer via URLSession e processa o stream SSE.
    /// Reconecta automaticamente em caso de erro, com back-off simples.
    private func listenToStream() async {
        var backoff: UInt64 = 1_000_000_000 // 1 segundo inicial

        while !Task.isCancelled {
            do {
                try await openSSEConnection()
                backoff = 1_000_000_000 // reset ao reconectar com sucesso
            } catch is CancellationError {
                break
            } catch {
                print("[JSBridge] Stream error: \(error). Reconectando em \(backoff / 1_000_000_000)s...")
            }

            try? await Task.sleep(nanoseconds: backoff)
            backoff = min(backoff * 2, 30_000_000_000) // máximo 30s
        }
    }

    private func openSSEConnection() async throws {
        let request = URLRequest(url: streamURL, timeoutInterval: .infinity)
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        print("[JSBridge] SSE stream conectado em \(streamURL)")

        var buffer = ""

        for try await line in asyncBytes.lines {
            try Task.checkCancellation()

            // Linhas SSE: "data: {...}" ou ": keep-alive" ou vazia
            if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                buffer = payload
            } else if line.isEmpty && !buffer.isEmpty {
                // Evento completo — processa
                processSSEPayload(buffer)
                buffer = ""
            }
            // Ignora comentários (": keep-alive") e outras linhas
        }
    }

    private func processSSEPayload(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let event = try? JSONDecoder().decode(BridgeEvent.self, from: data) else {
            print("[JSBridge] Payload inválido ignorado: \(jsonString)")
            return
        }

        guard let webView else { return }
        inject(event: event, into: webView)
    }

    // MARK: - JS → Swift: processar mensagens

    /// Processa a mensagem "openMd" enviada pelo JS via window.webkit.messageHandlers.openMd.postMessage.
    ///
    /// Payload aceito:
    ///   - String: caminho absoluto do arquivo .md
    ///   - { path: String, nodeName: String, category: String }
    func handleOpenMd(message: WKScriptMessage) {
        DispatchQueue.main.async {
            if let dict = message.body as? [String: Any] {
                let path     = dict["path"]     as? String ?? ""
                let nodeName = dict["nodeName"] as? String ?? ""
                let category = dict["category"] as? String ?? ""
                MarkdownReaderWindow.open(path: path, nodeName: nodeName, category: category)

            } else if let path = message.body as? String {
                // Fallback: apenas o caminho, sem metadados
                let url    = URL(fileURLWithPath: path)
                let name   = url.deletingPathExtension().lastPathComponent
                MarkdownReaderWindow.open(path: path, nodeName: name, category: "")

            } else {
                print("[JSBridge] openMd: payload inesperado – \(message.body ?? "nil")")
            }
        }
    }

    /// Processa a mensagem "bridgeEvent" enviada pelo JS (uso futuro).
    func handleBridgeEvent(message: WKScriptMessage) {
        // Reservado para que o JS possa reportar eventos de volta ao Swift.
        // Exemplo de uso futuro: confirmar que triggerThought foi executado.
        print("[JSBridge] bridgeEvent recebido do JS: \(message.body ?? "nil")")
    }

    // MARK: - Script de inicialização

    /// Script injetado no WKWebView após cada página carregar.
    ///
    /// Define window.__BRAIN_ATLAS_NATIVE__ e window.__onBridgeEvent__,
    /// substituindo o EventSource como receptor de eventos quando rodando nativo.
    static let initScript: String = """
    (function() {
        'use strict';

        window.__BRAIN_ATLAS_NATIVE__ = true;

        window.__onBridgeEvent__ = function(data) {
            if (!data || !data.node) return;
            try {
                var engine = window.__cerebroEngineRef__;
                if (engine && typeof engine.nameToId !== 'undefined') {
                    var nodeId = engine.nameToId[data.node];
                    if (nodeId !== undefined && typeof engine.triggerThought === 'function') {
                        engine.triggerThought(nodeId, 3, true);
                    }
                }
            } catch (e) {
                console.warn('[JSBridge] __onBridgeEvent__ error:', e);
            }
        };

        console.log('[JSBridge] Native bridge pronto. EventSource continua como fallback.');
    })();
    """
}
