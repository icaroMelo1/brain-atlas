import Foundation
import Network

// MARK: - BridgeEvent

struct BridgeEvent: Codable {
    let node: String
    let tool: String
    let ts: Int
}

// MARK: - SSE Client

/// Wraps an active NWConnection that is streaming SSE data.
private final class SSEClient: @unchecked Sendable {
    let id: UUID
    let connection: NWConnection

    init(connection: NWConnection) {
        self.id = UUID()
        self.connection = connection
    }

    func send(_ data: Data, completion: ((Error?) -> Void)? = nil) {
        connection.send(content: data, completion: .contentProcessed { error in
            completion?(error)
        })
    }

    func cancel() {
        connection.cancel()
    }
}

// MARK: - BridgeServer

actor BridgeServer {

    // MARK: Singleton

    static let shared = BridgeServer()

    // MARK: Private state

    private var listener: NWListener?
    private var clients: [UUID: SSEClient] = [:]
    private var keepAliveTimer: DispatchSourceTimer?
    private var isRunning = false

    /// Serial queue used for listener callbacks (bridged into actor via `Task`).
    private let listenerQueue = DispatchQueue(label: "com.brainatlas.bridge.listener")

    // MARK: Application Support helpers

    private var appSupportURL: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("BrainAtlas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var configURL: URL { appSupportURL.appendingPathComponent("config.json") }
    private var sessionsURL: URL { appSupportURL.appendingPathComponent("sessions.json") }

    // MARK: - Public API

    func start(port: Int = 8766) async {
        guard !isRunning else { return }

        let resolvedPort = resolvePort(defaultPort: port)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(resolvedPort)) else {
            print("[BridgeServer] Invalid port: \(resolvedPort)")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            let newListener = try NWListener(using: params, on: nwPort)
            self.listener = newListener

            newListener.stateUpdateHandler = { [weak self] state in
                Task { await self?.handleListenerState(state, port: resolvedPort) }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { await self?.handleNewConnection(connection) }
            }

            newListener.start(queue: listenerQueue)
            isRunning = true
            startKeepAlive()
            print("[BridgeServer] Listening on http://localhost:\(resolvedPort)")
        } catch {
            print("[BridgeServer] Failed to start listener: \(error)")
        }
    }

    func stop() async {
        isRunning = false
        keepAliveTimer?.cancel()
        keepAliveTimer = nil

        for client in clients.values {
            client.cancel()
        }
        clients.removeAll()

        listener?.cancel()
        listener = nil
        print("[BridgeServer] Stopped.")
    }

    func fanOut(event: BridgeEvent) async {
        guard let json = try? JSONEncoder().encode(event),
              let jsonString = String(data: json, encoding: .utf8) else { return }

        let ssePayload = "data: \(jsonString)\n\n"
        broadcast(ssePayload)
    }

    // MARK: - Internal helpers

    private func resolvePort(defaultPort: Int) -> Int {
        let saved = UserDefaults.standard.integer(forKey: "bridgePort")
        return saved > 0 ? saved : defaultPort
    }

    private func handleListenerState(_ state: NWListener.State, port: Int) {
        switch state {
        case .ready:
            print("[BridgeServer] Ready on port \(port).")
        case .failed(let error):
            print("[BridgeServer] Listener failed: \(error)")
        case .cancelled:
            print("[BridgeServer] Listener cancelled.")
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: listenerQueue)
        receiveRequest(from: connection)
    }

    // MARK: - HTTP request parsing

    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                print("[BridgeServer] Receive error: \(error)")
                return
            }
            guard let data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }
            Task { await self.processRawRequest(data: data, connection: connection) }
        }
    }

    private func processRawRequest(data: Data, connection: NWConnection) async {
        guard let raw = String(data: data, encoding: .utf8) else {
            sendResponse(to: connection, status: 400, body: #"{"error":"bad encoding"}"#)
            return
        }

        // Parse request line
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(to: connection, status: 400, body: #"{"error":"bad request"}"#)
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendResponse(to: connection, status: 400, body: #"{"error":"bad request line"}"#)
            return
        }

        let method = String(parts[0])
        let path   = String(parts[1])

        // Extract body (everything after the double CRLF)
        let bodyBytes: Data
        if let range = raw.range(of: "\r\n\r\n") {
            let bodyString = String(raw[range.upperBound...])
            bodyBytes = Data(bodyString.utf8)
        } else {
            bodyBytes = Data()
        }

        // Route
        switch (method, path) {
        case ("OPTIONS", _):
            handleOptions(connection: connection)

        case ("GET", "/stream"):
            await handleGetStream(connection: connection)

        case ("GET", "/config"):
            handleGetConfig(connection: connection)

        case ("POST", "/config"):
            handlePostConfig(body: bodyBytes, connection: connection)

        case ("GET", "/nodes"):
            handleGetNodes(connection: connection)

        case ("POST", "/event"):
            await handlePostEvent(body: bodyBytes, connection: connection)

        case ("GET", "/sessions"):
            handleGetSessions(connection: connection)

        case ("GET", "/health"):
            handleGetHealth(connection: connection)

        default:
            sendResponse(to: connection, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - Route handlers

    private func handleOptions(connection: NWConnection) {
        let headers = corsHeaders() + [
            "Content-Length: 0"
        ]
        sendRaw(to: connection, status: "200 OK", headers: headers, body: Data())
        connection.cancel()
    }

    private func handleGetStream(connection: NWConnection) async {
        let headers: [String] = [
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: *"
        ]
        let headerBlock = buildResponseHead(status: "200 OK", headers: headers)
        connection.send(content: headerBlock, completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            Task {
                guard let self else { return }
                await self.registerClient(connection: connection)
            }
        })
    }

    private func registerClient(connection: NWConnection) {
        let client = SSEClient(connection: connection)
        clients[client.id] = client

        // Watch for connection termination
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                Task { await self?.removeClient(id: client.id) }
            default:
                break
            }
        }
    }

    private func removeClient(id: UUID) {
        clients.removeValue(forKey: id)
    }

    private func handleGetConfig(connection: NWConnection) {
        let url = configURL
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           isValidJSON(data) {
            sendJSONData(to: connection, data: data)
        } else {
            sendJSON(to: connection, status: 200, body: #"{"setup":true}"#)
        }
        connection.cancel()
    }

    private func handlePostConfig(body: Data, connection: NWConnection) {
        guard !body.isEmpty,
              var dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            sendJSON(to: connection, status: 400, body: #"{"error":"invalid json"}"#)
            connection.cancel()
            return
        }

        // Expand ~ in sourceDir
        if let sourceDir = dict["sourceDir"] as? String {
            dict["sourceDir"] = NSString(string: sourceDir).expandingTildeInPath
        }

        guard let output = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) else {
            sendJSON(to: connection, status: 500, body: #"{"error":"serialization failed"}"#)
            connection.cancel()
            return
        }

        do {
            try output.write(to: configURL, options: .atomic)
            sendJSON(to: connection, status: 200, body: #"{"ok":true}"#)
        } catch {
            sendJSON(to: connection, status: 500, body: #"{"error":"\(error.localizedDescription)"}"#)
        }
        connection.cancel()
    }

    private func handleGetNodes(connection: NWConnection) {
        if let url = Bundle.module.url(forResource: "nodes", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            sendJSONData(to: connection, data: data)
        } else {
            sendJSON(to: connection, status: 200, body: #"{"nodes":[],"links":[],"satellites":{},"toolMap":[]}"#)
        }
        connection.cancel()
    }

    private func handlePostEvent(body: Data, connection: NWConnection) async {
        guard !body.isEmpty else {
            sendJSON(to: connection, status: 400, body: #"{"error":"empty body"}"#)
            connection.cancel()
            return
        }

        var dict: [String: Any]
        if let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            dict = parsed
        } else {
            sendJSON(to: connection, status: 400, body: #"{"error":"invalid json"}"#)
            connection.cancel()
            return
        }

        if dict["ts"] == nil {
            dict["ts"] = Int(Date().timeIntervalSince1970)
        }

        if let eventData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: eventData, encoding: .utf8) {
            let sse = "data: \(jsonString)\n\n"
            broadcast(sse)
        }

        sendJSON(to: connection, status: 200, body: #"{"ok":true}"#)
        connection.cancel()
    }

    private func handleGetSessions(connection: NWConnection) {
        let url = sessionsURL
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           isValidJSON(data) {
            sendJSONData(to: connection, data: data)
        } else {
            sendJSON(to: connection, status: 200, body: "[]")
        }
        connection.cancel()
    }

    private func handleGetHealth(connection: NWConnection) {
        let count = clients.count
        sendJSON(to: connection, status: 200, body: #"{"ok":true,"clients":\#(count)}"#)
        connection.cancel()
    }

    // MARK: - SSE fan-out

    private func broadcast(_ text: String) {
        let data = Data(text.utf8)

        for (id, client) in clients {
            client.send(data) { error in
                if error != nil {
                    Task { [weak self] in
                        await self?.removeClient(id: id)
                    }
                }
            }
        }
    }

    // MARK: - Keep-alive timer

    private func startKeepAlive() {
        let timer = DispatchSource.makeTimerSource(queue: listenerQueue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            Task { await self?.sendKeepAlive() }
        }
        timer.resume()
        keepAliveTimer = timer
    }

    private func sendKeepAlive() {
        broadcast(": keep-alive\n\n")
    }

    // MARK: - HTTP response helpers

    private func corsHeaders() -> [String] {
        [
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type"
        ]
    }

    private func buildResponseHead(status: String, headers: [String]) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        for h in headers { head += "\(h)\r\n" }
        head += "\r\n"
        return Data(head.utf8)
    }

    private func sendRaw(to connection: NWConnection, status: String, headers: [String], body: Data) {
        let head = buildResponseHead(status: status, headers: headers)
        var response = head
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in })
    }

    private func sendJSON(to connection: NWConnection, status: Int, body: String) {
        let bodyData = Data(body.utf8)
        sendJSONData(to: connection, statusCode: status, data: bodyData)
    }

    private func sendJSONData(to connection: NWConnection, statusCode: Int = 200, data: Data) {
        var headers = corsHeaders()
        headers += [
            "Content-Type: application/json",
            "Content-Length: \(data.count)"
        ]
        sendRaw(to: connection, status: "\(statusCode) \(httpStatusText(statusCode))", headers: headers, body: data)
    }

    private func sendResponse(to connection: NWConnection, status: Int, body: String) {
        sendJSON(to: connection, status: status, body: body)
        connection.cancel()
    }

    private func isValidJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return "Unknown"
        }
    }
}
