import Foundation

struct ProcessError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Runs external commands (git, gh, dropdb, code, claude, osascript) as
/// argv arrays -- no shell, so no injection risk. Reads stdout/stderr
/// incrementally via readabilityHandler rather than waiting for exit and
/// then reading, since a process that writes more than the pipe buffer
/// (~64KB) while nobody is draining it would otherwise hang forever.
enum ProcessRunner {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        var settled = false
        var timeoutItem: DispatchWorkItem?
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], cwd: URL? = nil, timeout: TimeInterval? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let cwd { process.currentDirectoryURL = cwd }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let state = State()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                state.lock.lock(); state.outData.append(chunk); state.lock.unlock()
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                state.lock.lock(); state.errData.append(chunk); state.lock.unlock()
            }

            @Sendable func finish(_ result: Result<String, Error>) {
                state.lock.lock()
                let already = state.settled
                state.settled = true
                let item = state.timeoutItem
                state.lock.unlock()
                guard !already else { return }
                item?.cancel()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(with: result)
            }

            process.terminationHandler = { proc in
                // The process has already exited by the time this fires, so
                // draining whatever's left can't block.
                let leftoverOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let leftoverErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                state.lock.lock()
                state.outData.append(leftoverOut)
                state.errData.append(leftoverErr)
                let stdout = String(data: state.outData, encoding: .utf8) ?? ""
                let stderr = String(data: state.errData, encoding: .utf8) ?? ""
                state.lock.unlock()

                if proc.terminationStatus == 0 {
                    finish(.success(stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    let argsStr = arguments.joined(separator: " ")
                    let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = (executable as NSString).lastPathComponent
                    finish(.failure(ProcessError(message: "\(name) \(argsStr) failed: \(detail.isEmpty ? stdout : detail)")))
                }
            }

            do {
                try process.run()
            } catch {
                finish(.failure(ProcessError(message: "Failed to launch \(executable): \(error.localizedDescription)")))
                return
            }

            if let timeout {
                let item = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                    let name = (executable as NSString).lastPathComponent
                    finish(.failure(ProcessError(message: "\(name) timed out after \(Int(timeout))s")))
                }
                state.lock.lock(); state.timeoutItem = item; state.lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
            }
        }
    }
}
