import Foundation
import Logging
import MCP

actor StatusStdioTransport: Transport {
    private let stdio = StdioTransport()
    nonisolated var logger: Logger { stdio.logger }

    func connect() async throws {
        try await stdio.connect()
    }

    func disconnect() async {
        await stdio.disconnect()
    }

    func send(_ data: Data) async throws {
        try await stdio.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                let messages = await stdio.receive()
                do {
                    for try await message in messages {
                        continuation.yield(Self.compatibleMessage(message))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func compatibleMessage(_ data: Data) -> Data {
        // Swift MCP SDK 0.12.1 expects experimental capability values to be strings.
        // Codex sends objects. The status server does not use experimental capabilities.
        guard var message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              let experimental = capabilities["experimental"] as? [String: Any],
              !(experimental is [String: String])
        else {
            return data
        }

        capabilities.removeValue(forKey: "experimental")
        params["capabilities"] = capabilities
        message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? data
    }
}
