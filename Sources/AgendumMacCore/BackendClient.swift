import Foundation

public struct Workspace: Decodable, Equatable, Sendable {
    public let id: String
    public let namespace: String?
    public let displayName: String
    public let configPath: String
    public let dbPath: String
    public let isCurrent: Bool
}

public struct AuthStatus: Decodable, Equatable, Sendable {
    public let ghFound: Bool
    public let ghPath: String?
    public let authenticated: Bool
    public let username: String?
    public let workspaceGhConfigDir: String
    public let repairInstructions: String?
}

public struct BackendErrorPayload: Decodable, Error, Equatable, Sendable {
    public let code: String
    public let message: String
    public let detail: String?
    public let recovery: String?
}

public enum BackendClientError: Error, Equatable, Sendable {
    case invalidResponse(String)
    case helperError(BackendErrorPayload)
    case helperTerminated(String)
    case unexpectedResponseID(expected: String, actual: String?)
    case unsupportedProtocolVersion(Int)
}

extension BackendClientError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidResponse(let message):
            return message
        case .helperError(let error):
            return error.recovery ?? error.detail ?? error.message
        case .helperTerminated(let stderr):
            return stderr.isEmpty ? "Backend helper terminated unexpectedly." : stderr
        case .unexpectedResponseID(let expected, let actual):
            return "Expected response id \(expected), received \(actual ?? "none")."
        case .unsupportedProtocolVersion(let version):
            return "Unsupported backend protocol version \(version)."
        }
    }
}

public struct BackendClientConfiguration: Sendable {
    public let helperURL: URL
    public let pythonExecutableURL: URL
    public let workingDirectoryURL: URL?
    public let environment: [String: String]

    public init(
        helperURL: URL,
        pythonExecutableURL: URL = BackendClientConfiguration.defaultPythonExecutableURL(),
        workingDirectoryURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.helperURL = helperURL
        self.pythonExecutableURL = pythonExecutableURL
        self.workingDirectoryURL = workingDirectoryURL
        self.environment = environment
    }

    public static func development(
        repositoryRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> BackendClientConfiguration {
        BackendClientConfiguration(
            helperURL: repositoryRoot.appendingPathComponent("Backend/agendum_backend_helper.py"),
            workingDirectoryURL: repositoryRoot
        )
    }

    public static func defaultPythonExecutableURL() -> URL {
        let fileManager = FileManager.default
        for path in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }
}

public actor AgendumBackendClient {
    private let configuration: BackendClientConfiguration
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var outputBuffer = Data()

    public init(configuration: BackendClientConfiguration = .development()) {
        self.configuration = configuration
    }

    deinit {
        if let input {
            try? input.close()
        }
        if let process, process.isRunning {
            process.terminate()
        }
    }

    public func currentWorkspace() throws -> Workspace {
        let payload: WorkspaceResponsePayload = try send(command: "workspace.current")
        return payload.workspace
    }

    public func authStatus() throws -> AuthStatus {
        let payload: AuthStatusResponsePayload = try send(command: "auth.status")
        return payload.auth
    }

    func request<ResponsePayload: Decodable>(
        command: String,
        as responsePayload: ResponsePayload.Type = ResponsePayload.self
    ) throws -> ResponsePayload {
        try send(command: command)
    }

    public func close() {
        if let input {
            try? input.close()
        }
        if let output {
            try? output.close()
        }
        if let errorOutput {
            try? errorOutput.close()
        }
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        input = nil
        output = nil
        errorOutput = nil
        outputBuffer.removeAll()
    }

    private func send<ResponsePayload: Decodable>(
        command: String,
        payload: EmptyPayload = EmptyPayload()
    ) throws -> ResponsePayload {
        try startIfNeeded()

        guard let input else {
            throw BackendClientError.invalidResponse("Backend helper input pipe is unavailable.")
        }

        let requestID = UUID().uuidString
        let request = RequestEnvelope(version: 1, id: requestID, command: command, payload: payload)
        var data = try encoder.encode(request)
        data.append(0x0A)
        input.write(data)

        while true {
            let line = try readLine()
            let probe = try decoder.decode(ResponseProbe.self, from: line)
            if probe.event != nil {
                continue
            }
            guard probe.id == requestID else {
                throw BackendClientError.unexpectedResponseID(expected: requestID, actual: probe.id)
            }

            let response = try decoder.decode(ResponseEnvelope<ResponsePayload>.self, from: line)
            guard response.version == 1 else {
                throw BackendClientError.unsupportedProtocolVersion(response.version)
            }
            guard response.ok else {
                throw BackendClientError.helperError(
                    response.error ?? BackendErrorPayload(
                        code: "unknown",
                        message: "Backend helper returned an unknown error.",
                        detail: nil,
                        recovery: nil
                    )
                )
            }
            guard let payload = response.payload else {
                throw BackendClientError.invalidResponse("Backend helper response did not include a payload.")
            }
            return payload
        }
    }

    private func startIfNeeded() throws {
        if let process, process.isRunning {
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = configuration.pythonExecutableURL
        process.arguments = [configuration.helperURL.path]
        process.currentDirectoryURL = configuration.workingDirectoryURL
        process.environment = configuration.environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        errorOutput = errorPipe.fileHandleForReading
        outputBuffer.removeAll()
    }

    private func readLine() throws -> Data {
        guard let output else {
            throw BackendClientError.invalidResponse("Backend helper output pipe is unavailable.")
        }

        while true {
            if let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
                let line = outputBuffer[..<newlineIndex]
                outputBuffer.removeSubrange(...newlineIndex)
                return Data(line)
            }

            let chunk = output.availableData
            if chunk.isEmpty {
                throw BackendClientError.helperTerminated(readStderr())
            }
            outputBuffer.append(chunk)
        }
    }

    private func readStderr() -> String {
        guard let errorOutput else {
            return ""
        }
        let data = errorOutput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct EmptyPayload: Encodable, Sendable {}

private struct RequestEnvelope<Payload: Encodable>: Encodable {
    let version: Int
    let id: String
    let command: String
    let payload: Payload
}

private struct ResponseProbe: Decodable {
    let id: String?
    let event: String?
}

private struct ResponseEnvelope<Payload: Decodable>: Decodable {
    let version: Int
    let id: String?
    let ok: Bool
    let payload: Payload?
    let error: BackendErrorPayload?
}

private struct WorkspaceResponsePayload: Decodable {
    let workspace: Workspace
}

private struct AuthStatusResponsePayload: Decodable {
    let auth: AuthStatus
}
