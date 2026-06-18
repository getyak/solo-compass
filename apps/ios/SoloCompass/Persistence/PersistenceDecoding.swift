// PersistenceDecoding.swift
//
// Beta-P0-B safety net for blob-backed @Model records. Schema iterations
// (we're on V1.6 already) mean older on-disk blobs may not match the
// current decoder shape. Historically these mismatches called
// `fatalError(...)` and crashed the app on launch. Now we log to Sentry,
// drop the offending row, and keep going.

import Foundation

/// Error type surfaced by Record `asValue`/`fromValue` throws paths.
/// Wraps the underlying decoder/encoder error with the record id so the
/// Sentry breadcrumb has enough context to triage which row went bad.
public struct PersistenceCodecError: Error, CustomStringConvertible {
    public let context: String
    public let recordId: String
    public let underlying: Error

    public init(context: String, recordId: String, underlying: Error) {
        self.context = context
        self.recordId = recordId
        self.underlying = underlying
    }

    public var description: String {
        "PersistenceCodecError[\(context) id=\(recordId)]: \(underlying)"
    }
}

/// Centralised helper so every Record file routes failures to the same
/// place. Keeps a lightweight summary in console for DEBUG and forwards
/// to Sentry so prod failures show up in the Beta dashboard.
public enum PersistenceLog {
    public static func recordDecodeFailure(_ error: PersistenceCodecError) {
        #if DEBUG
        print("[persistence] decode failed: \(error)")
        #endif
        // SentryService is @MainActor-isolated; hop to the main actor so
        // the helper can be invoked from any thread (SwiftData fetches
        // and JSON decode routinely run off-main).
        let snapshot = error
        Task { @MainActor in
            SentryService.capture(
                error: snapshot,
                context: [
                    "persistence_context": snapshot.context,
                    "record_id": snapshot.recordId
                ]
            )
        }
    }
}

/// Decode `T` from `blob` with a single-line call site. On failure
/// returns an empty-ish default produced by `fallback()` and logs to
/// Sentry. Used inside Record `asValue` getters so a malformed row
/// degrades gracefully instead of crashing the screen that reads it.
@inlinable
public func decodeOrLog<T: Decodable>(
    _ type: T.Type,
    from blob: Data,
    field: String,
    file: StaticString = #file,
    line: UInt = #line,
    fallback: () -> T
) -> T {
    if let value = try? JSONDecoder().decode(T.self, from: blob) {
        return value
    }
    PersistenceLog.recordDecodeFailure(
        PersistenceCodecError(
            context: "decode.\(field)",
            recordId: "\(file):\(line)",
            underlying: NSError(
                domain: "PersistenceCodec",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "decode field \(field) failed"]
            )
        )
    )
    return fallback()
}

/// Overload for `[String]` blobs — the common case in our records. The
/// caller doesn't have to spell out the fallback `[]` each time.
@inlinable
public func decodeOrLog(
    _ type: [String].Type,
    from blob: Data,
    field: String,
    file: StaticString = #file,
    line: UInt = #line
) -> [String] {
    decodeOrLog([String].self, from: blob, field: field, file: file, line: line, fallback: { [] })
}

/// Convenience wrapper used by Stores to skip corrupted rows without
/// crashing. Returns nil and side-effects a Sentry log when the throwing
/// closure fails.
@inlinable
public func tryDecodeLogging<T>(
    context: String,
    recordId: @autoclosure () -> String,
    _ work: () throws -> T
) -> T? {
    do {
        return try work()
    } catch let codecError as PersistenceCodecError {
        PersistenceLog.recordDecodeFailure(codecError)
        return nil
    } catch {
        PersistenceLog.recordDecodeFailure(
            PersistenceCodecError(
                context: context,
                recordId: recordId(),
                underlying: error
            )
        )
        return nil
    }
}
