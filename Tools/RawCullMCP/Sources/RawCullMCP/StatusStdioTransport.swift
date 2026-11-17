import Foundation
import Logging
import MCP

actor StatusStdioTransport: Transport {
    private let stdio = StdioTransport()
    nonisolated var logger: Logger {
        stdio.logger
    }

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
        AsyncThrowingStream { continuation in
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
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return data }
        if let message = value as? [String: Any], let updated = compatibleInitialize(message) {
            return (try? JSONSerialization.data(withJSONObject: updated)) ?? data
        }
        guard var batch = value as? [Any] else { return data }
        var changed = false
        for index in batch.indices {
            guard let message = batch[index] as? [String: Any],
                  let updated = compatibleInitialize(message)
            else { continue }
            batch[index] = updated
            changed = true
        }
        guard changed else { return data }
        return (try? JSONSerialization.data(withJSONObject: batch)) ?? data
    }

    private static func compatibleInitialize(_ message: [String: Any]) -> [String: Any]? {
        // Swift MCP SDK 0.12.1 expects experimental capability values to be strings.
        // Codex sends objects. The status server does not use experimental capabilities.
        guard message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              let experimental = capabilities["experimental"] as? [String: Any],
              !(experimental is [String: String])
        else {
            return nil
        }

        capabilities.removeValue(forKey: "experimental")
        params["capabilities"] = capabilities
        var message = message
        message["params"] = params
        return message
    }
}
