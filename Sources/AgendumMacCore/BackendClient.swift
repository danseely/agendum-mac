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

public struct SyncStatus: Decodable, Equatable, Sendable {
    public let state: String
    public let lastSyncAt: String?
    public let lastError: String?
    public let changes: Int
    public let hasAttentionItems: Bool
}

public struct AgendumTask: Decodable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let source: String
    public let status: String
    public let project: String?
    public let ghRepo: String?
    public let ghUrl: String?
    public let ghNumber: Int?
    public let ghAuthor: String?
    public let ghAuthorName: String?
    public let tags: [String]
    public let seen: Bool
    public let lastChangedAt: String?
    public let updatedAt: String?
}

public struct WorkspaceSelection: Decodable, Equatable, Sendable {
    public let workspace: Workspace
    public let auth: AuthStatus
    public let sync: SyncStatus
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
    case requestTimedOut(TimeInterval)
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
        case .requestTimedOut(let timeout):
            return "Backend helper did not respond within \(timeout) seconds."
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
    public let requestTimeout: TimeInterval

    public init(
        helperURL: URL,
        pythonExecutableURL: URL = BackendClientConfiguration.defaultPythonExecutableURL(),
        workingDirectoryURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        requestTimeout: TimeInterval = 10
    ) {
        self.helperURL = helperURL
        self.pythonExecutableURL = pythonExecutableURL
        self.workingDirectoryURL = workingDirectoryURL
        self.environment = environment
        self.requestTimeout = requestTimeout
    }

    public static func development(
        repositoryRoot: URL? = nil
    ) -> BackendClientConfiguration {
        let repositoryRoot = repositoryRoot ?? discoverDevelopmentRepositoryRoot()
        return BackendClientConfiguration(
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

    public static func discoverDevelopmentRepositoryRoot(
        fileManager: FileManager = .default,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        executableURL: URL? = Bundle.main.executableURL
    ) -> URL {
        let candidates = [currentDirectoryURL, executableURL].compactMap { $0 }
        for candidate in candidates {
            if let root = firstAncestor(containing: "Backend/agendum_backend_helper.py", from: candidate, fileManager: fileManager) {
                return root
            }
        }
        return currentDirectoryURL
    }

    private static func firstAncestor(
        containing relativePath: String,
        from url: URL,
        fileManager: FileManager
    ) -> URL? {
        var candidate = url
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            candidate.deleteLastPathComponent()
        }

        var seen: Set<String> = []
        while seen.insert(candidate.path).inserted {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent(relativePath).path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
        return nil
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
    private var outputReader: BackendOutputReader?

    public init(configuration: BackendClientConfiguration = .development()) {
        self.configuration = configuration
    }

    deinit {
        if let input {
            try? input.close()
        }
        output?.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminate()
        }
    }

    public func currentWorkspace() async throws -> Workspace {
        let payload: WorkspaceResponsePayload = try await send(command: "workspace.current")
        return payload.workspace
    }

    public func listWorkspaces() async throws -> [Workspace] {
        let payload: WorkspaceListResponsePayload = try await send(command: "workspace.list")
        return payload.workspaces
    }

    public func selectWorkspace(namespace: String?) async throws -> WorkspaceSelection {
        try await send(command: "workspace.select", payload: WorkspaceSelectRequestPayload(namespace: namespace))
    }

    public func listTasks(
        source: String? = nil,
        status: String? = nil,
        project: String? = nil,
        includeSeen: Bool = true,
        limit: Int = 50
    ) async throws -> [AgendumTask] {
        let payload: TaskListResponsePayload = try await send(
            command: "task.list",
            payload: TaskListRequestPayload(
                source: source,
                status: status,
                project: project,
                includeSeen: includeSeen,
                limit: limit
            )
        )
        return payload.tasks
    }

    public func authStatus() async throws -> AuthStatus {
        let payload: AuthStatusResponsePayload = try await send(command: "auth.status")
        return payload.auth
    }

    func request<ResponsePayload: Decodable>(
        command: String,
        as responsePayload: ResponsePayload.Type = ResponsePayload.self
    ) async throws -> ResponsePayload {
        try await send(command: command)
    }

    public func close() {
        if let input {
            try? input.close()
        }
        output?.readabilityHandler = nil
        outputReader?.close()
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
        outputReader = nil
    }

    private func send<ResponsePayload: Decodable, RequestPayload: Encodable>(
        command: String,
        payload: RequestPayload
    ) async throws -> ResponsePayload {
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
            let probe: ResponseProbe
            do {
                probe = try decoder.decode(ResponseProbe.self, from: line)
            } catch {
                throw BackendClientError.invalidResponse("Backend helper response was not valid JSON.")
            }
            if probe.event != nil {
                continue
            }
            guard probe.id == requestID else {
                throw BackendClientError.unexpectedResponseID(expected: requestID, actual: probe.id)
            }

            let response: ResponseEnvelope<ResponsePayload>
            do {
                response = try decoder.decode(ResponseEnvelope<ResponsePayload>.self, from: line)
            } catch {
                throw BackendClientError.invalidResponse("Backend helper response did not match the expected schema.")
            }
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

    private func send<ResponsePayload: Decodable>(
        command: String
    ) async throws -> ResponsePayload {
        try await send(command: command, payload: EmptyPayload())
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

        let reader = BackendOutputReader()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                reader.close()
            } else {
                reader.append(data)
            }
        }

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        errorOutput = errorPipe.fileHandleForReading
        outputReader = reader
    }

    private func readLine() throws -> Data {
        guard let outputReader else {
            throw BackendClientError.invalidResponse("Backend helper output pipe is unavailable.")
        }

        do {
            return try outputReader.readLine(timeout: configuration.requestTimeout)
        } catch BackendClientError.requestTimedOut {
            close()
            throw BackendClientError.requestTimedOut(configuration.requestTimeout)
        } catch BackendClientError.helperTerminated {
            throw BackendClientError.helperTerminated(readStderr())
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

private final class BackendOutputReader: @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var closed = false

    func append(_ data: Data) {
        condition.lock()
        buffer.append(data)
        condition.signal()
        condition.unlock()
    }

    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }

    func readLine(timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)

        condition.lock()
        defer { condition.unlock() }

        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                return Data(line)
            }
            if closed {
                throw BackendClientError.helperTerminated("")
            }
            if !condition.wait(until: deadline) {
                throw BackendClientError.requestTimedOut(timeout)
            }
        }
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

private struct WorkspaceListResponsePayload: Decodable {
    let workspaces: [Workspace]
}

private struct WorkspaceSelectRequestPayload: Encodable, Sendable {
    let namespace: String?

    enum CodingKeys: String, CodingKey {
        case namespace
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let namespace {
            try container.encode(namespace, forKey: .namespace)
        } else {
            try container.encodeNil(forKey: .namespace)
        }
    }
}

private struct AuthStatusResponsePayload: Decodable {
    let auth: AuthStatus
}

private struct TaskListRequestPayload: Encodable, Sendable {
    let source: String?
    let status: String?
    let project: String?
    let includeSeen: Bool
    let limit: Int
}

private struct TaskListResponsePayload: Decodable {
    let tasks: [AgendumTask]
}
