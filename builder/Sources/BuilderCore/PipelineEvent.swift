import Foundation

public enum PipelineEvent: Equatable {
    case step(id: String, title: String)
    /// How far the current step is (0...1).
    case progress(Double)
    /// The built app, with the game inside it, in the workspace.
    case done(app: URL)
    case error(String)
    case log(String)
}

public let eventPrefix = "NFSU2-EVENT "

/// One output line of tools/builder_cli.py: `NFSU2-EVENT {json}` or plain log text.
public func parsePipelineLine(_ line: String) -> PipelineEvent {
    guard line.hasPrefix(eventPrefix),
          let data = String(line.dropFirst(eventPrefix.count)).data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return .log(line) }

    if let id = obj["step"] as? String, let title = obj["title"] as? String {
        return .step(id: id, title: title)
    }
    if let part = obj["progress"] as? Double { return .progress(part) }
    if let app = obj["done"] as? String {
        return .done(app: URL(fileURLWithPath: app))
    }
    if let msg = obj["error"] as? String { return .error(msg) }
    return .log(line)
}
