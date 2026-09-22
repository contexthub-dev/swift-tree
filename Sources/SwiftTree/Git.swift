import Foundation

/// Runs `git -C cwd args…` and returns stdout, or throws `GitError`. Injected so tests can fake it.
typealias GitRunner = @Sendable (_ args: [String], _ cwd: URL) async throws -> Data

struct GitError: Error, CustomStringConvertible {
  let args: [String]
  let exitCode: Int32
  let stderr: String
  var description: String { "git \(args.joined(separator: " ")) exited \(exitCode): \(stderr)" }
}

enum Git {
  /// Runs off the cooperative pool: `waitUntilExit` blocks, and one blocked
  /// thread per repo would starve Swift concurrency's few threads.
  static let run: GitRunner = { args, cwd in
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(with: Result { try runBlocking(args, cwd) })
      }
    }
  }

  static func runBlocking(_ args: [String], _ cwd: URL) throws -> Data {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = ["git", "-C", cwd.path] + args
    process.standardInput = FileHandle.nullDevice
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    // ponytail: stderr is drained after stdout; a git that writes >64KB to
    // stderr before finishing stdout would block. Read both concurrently if that shows up.
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    let errors = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw GitError(
        args: args, exitCode: process.terminationStatus,
        stderr: String(decoding: errors, as: UTF8.self))
    }
    return output
  }
}
