import Foundation

enum NetworkLogger {
    static func logHTTPError(method: String, url: URL, baseURLString: String?, status: Int, body: Data) {
        let full = url.absoluteString
        let base = (baseURLString.flatMap { URL(string: $0)?.absoluteString }) ?? ""
        let path = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : (URLComponents(url: url, resolvingAgainstBaseURL: false)?.url?.path ?? full)
        let bodyString = String(data: body, encoding: .utf8) ?? "<non-utf8>"
        AppLogger.shared.log(
            "HTTP Error",
            level: .error,
            context: "Network",
            metadata: [
                "method": method,
                "path": path,
                "status": status,
                "body": bodyString
            ]
        )
    }
}


