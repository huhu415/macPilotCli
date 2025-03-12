// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import JSONSchemaBuilder
import MCPServer

print("Hello, world!")

let transport = Transport.stdio()
func proxy(_ transport: Transport) -> Transport {
    var sendToDataSequence: AsyncStream<Data>.Continuation?
    let dataSequence = AsyncStream<Data>.init { continuation in
        sendToDataSequence = continuation
    }

    Task {
        for await data in transport.dataSequence {
            // mcpLogger.info("Reading data from transport: \(String(data: data, encoding: .utf8)!, privacy: .public)")
            sendToDataSequence?.yield(data)
        }
    }

    return Transport(
        writeHandler: { data in
            // mcpLogger.info("Writing data to transport: \(String(data: data, encoding: .utf8)!, privacy: .public)")
            try await transport.writeHandler(data)
        },
        dataSequence: dataSequence
    )
}

let server = try await MCPServer(
    info: Implementation(name: "macPilot", version: "1.0.0"),
    capabilities: ServerCapabilityHandlers(tools: tools),
    transport: proxy(transport)
)

try await server.waitForDisconnection()
