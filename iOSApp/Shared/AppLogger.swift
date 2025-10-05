import Foundation

final class AppLogger {
    static let shared = AppLogger()

    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let ioQueue = DispatchQueue(label: "app.logger.io.queue")
    private let fileURL: URL
    private var redactionBaseURLString: String?

    private init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("app.log")
        // Try to seed redaction base from stored settings
        redactionBaseURLString = UserDefaults.standard.string(forKey: "ActualBaseURL")
        rotateIfNeeded()
    }

    func log(_ message: String, level: Level = .info, context: String? = nil, metadata: [String: Any]? = nil) {
        let ts = ISO8601DateFormatter().string(from: Date())
        var record: [String: Any] = [
            "timestamp": ts,
            "level": level.rawValue,
            "message": message
        ]
        if let context { record["context"] = context }
        if let metadata { record["metadata"] = metadata }
        write(record)
    }

    func log(error: Error, context: String? = nil, metadata: [String: Any]? = nil) {
        var md = metadata ?? [:]
        md["errorType"] = String(describing: type(of: error))
        md["localizedDescription"] = redact(error.localizedDescription)
        let message = redact(String(describing: error))
        log(message, level: .error, context: context, metadata: md)
    }

    func readLogText() -> String {
        ioQueue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
    }

    func clear() {
        ioQueue.sync {
            try? FileManager.default.removeItem(at: fileURL)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    var logFileURL: URL { fileURL }

    func updateRedactionBaseURL(_ baseURLString: String?) {
        redactionBaseURLString = baseURLString
    }

    private func write(_ record: [String: Any]) {
        ioQueue.async {
            do {
                let data = try JSONSerialization.data(withJSONObject: record, options: [])
                if !FileManager.default.fileExists(atPath: self.fileURL.path) {
                    FileManager.default.createFile(atPath: self.fileURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: self.fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: "\n".data(using: .utf8)!)
            } catch {
                // Last resort: nothing to do if logging fails
            }
        }
    }

    private func rotateIfNeeded(maxBytes: Int = 512 * 1024) {
        ioQueue.async {
            let attrs = try? FileManager.default.attributesOfItem(atPath: self.fileURL.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            guard size > maxBytes else { return }
            let backupURL = self.fileURL.deletingPathExtension().appendingPathExtension("old.log")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: self.fileURL, to: backupURL)
            FileManager.default.createFile(atPath: self.fileURL.path, contents: nil)
        }
    }

    private func redact(_ text: String) -> String {
        guard let base = redactionBaseURLString, !base.isEmpty else { return text }
        return text.replacingOccurrences(of: base, with: "<redacted>")
    }
}


