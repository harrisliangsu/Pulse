import Foundation
import Testing
@testable import Pulse

/// The helper's stdout, and what happens when it closes.
///
/// **A `readabilityHandler` on a pipe whose far end has gone is a busy loop.**
/// `availableData` returns empty, the descriptor stays readable, and a handler
/// that merely returns is called again immediately — for ever. Shipped in
/// 1.2.0 it was 290% of a CPU for eleven hours after `codex app-server` had
/// already exited, with no child process left to point at (issue #25).
///
/// Driven against a plain `Pipe` rather than a real helper: the invariant is
/// about the file handle, not about Codex, and a test that needed `codex`
/// installed would not run anywhere.
@Suite("Codex app server")
struct CodexAppServerTests {
    /// The handler fires on a background queue, so give it a moment — but
    /// fail rather than hang if it never does.
    private static func waitForHandlerToClear(_ handle: FileHandle,
                                              within seconds: Double = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if handle.readabilityHandler == nil { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return handle.readabilityHandler == nil
    }

    @Test("A closed pipe takes its own handler off")
    func eofClearsTheHandler() async throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        let server = CodexAppServer()
        await server.startReading(reader)
        #expect(reader.readabilityHandler != nil)

        // What the helper exiting looks like from this side.
        try pipe.fileHandleForWriting.close()

        #expect(await Self.waitForHandlerToClear(reader),
                "the handler outlived the pipe — this is the busy loop")
    }

    /// Data still has to get through; a fix that stopped reading would be a
    /// provider that never answers.
    @Test("Data before the close is still read")
    func dataArrivesBeforeEOF() async throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        let server = CodexAppServer()
        await server.startReading(reader)

        try pipe.fileHandleForWriting.write(contentsOf: Data("{\"jsonrpc\":\"2.0\"}\n".utf8))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(reader.readabilityHandler != nil, "a handler that read one chunk then stopped")

        try pipe.fileHandleForWriting.close()
        #expect(await Self.waitForHandlerToClear(reader))
    }

    /// A restart installs a new reader while the old one may still be closing.
    /// Without the identity guard, the dead pipe's EOF tears down the helper
    /// that replaced it — which reads as Codex dying every time it restarts.
    @Test("An old pipe's close does not tear down the new one")
    func staleEOFLeavesTheCurrentReaderAlone() async throws {
        let server = CodexAppServer()
        let old = Pipe(), new = Pipe()

        await server.startReading(old.fileHandleForReading)
        await server.startReading(new.fileHandleForReading)

        // The old reader reaches EOF after it has been replaced.
        await server.readerClosed(old.fileHandleForReading)

        #expect(new.fileHandleForReading.readabilityHandler != nil,
                "the current reader was torn down by a stale one's EOF")
    }

    /// EOF must not leave a live helper with nothing able to kill it.
    ///
    /// EOF on stdout usually means the helper exited, but it can also mean one
    /// still running with its output closed. Forgetting the `Process` there
    /// orphans it: `shutDown` terminates a `process` that is by then nil, so
    /// quitting Pulse leaves it behind.
    @Test("A reader that closes does not orphan the helper")
    func eofTerminatesRatherThanForgets() async throws {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Closes its stdout immediately and then stays alive — exactly the
        // case where EOF is not the same thing as the process exiting.
        helper.arguments = ["-c", "exec 1>&-; sleep 30"]
        let pipe = Pipe()
        helper.standardOutput = pipe
        try helper.run()

        let server = CodexAppServer()
        await server.adopt(helper, reader: pipe.fileHandleForReading)
        await server.readerClosed(pipe.fileHandleForReading)

        // Give the signal a moment to land.
        let deadline = Date().addingTimeInterval(3)
        while helper.isRunning, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!helper.isRunning, "the helper outlived the reader that was dropped")
    }

    /// Shutting down has to take the handler off too. Terminating the child
    /// closes its end of the pipe, which is exactly the condition that spins.
    @Test("Shutting down takes the handler off")
    func shutDownStopsReading() async throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        let server = CodexAppServer()
        await server.startReading(reader)

        await server.shutDown()
        #expect(reader.readabilityHandler == nil)
    }
}
