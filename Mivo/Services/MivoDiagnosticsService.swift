import Foundation
import MetricKit

final class MivoDiagnosticsService: NSObject, MXMetricManagerSubscriber {
    static let shared = MivoDiagnosticsService()
    private var enabled = false

    private override init() { super.init() }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value { MXMetricManager.shared.add(self) }
        else { MXMetricManager.shared.remove(self) }
    }

    func startForActiveUser(remoteAllowed: Bool = false) {
        setEnabled(remoteAllowed)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard enabled else { return }
        for payload in payloads {
            var flattened: [String: Double] = [:]
            if let object = try? JSONSerialization.jsonObject(with: payload.jsonRepresentation()),
               let dictionary = object as? [String: Any] {
                flattenNumbers(dictionary, path: "metric", into: &flattened)
            }
            var limited: [String: Double] = [:]
            for item in flattened.sorted(by: { $0.key < $1.key }) {
                if limited.count == 120 { break }
                limited[item.key] = item.value
            }
            Task { await ProductExpansionService.ingestDiagnostic(kind: "metrickit_daily", payload: ["metrics": limited]) }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard enabled else { return }
        for payload in payloads {
            let summary: [String: Any] = [
                "crashes": payload.crashDiagnostics?.count ?? 0,
                "hangs": payload.hangDiagnostics?.count ?? 0,
                "cpu_exceptions": payload.cpuExceptionDiagnostics?.count ?? 0,
                "disk_write_exceptions": payload.diskWriteExceptionDiagnostics?.count ?? 0,
                "launch_failures": payload.appLaunchDiagnostics?.count ?? 0
            ]
            Task { await ProductExpansionService.ingestDiagnostic(kind: "metrickit_diagnostic", payload: summary) }
        }
    }

    private func flattenNumbers(_ value: Any, path: String, into output: inout [String: Double]) {
        if output.count >= 120 { return }
        if let number = value as? NSNumber {
            output[path] = number.doubleValue
            return
        }
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let lowered = key.lowercased()
                if lowered.contains("stack") || lowered.contains("reason") || lowered.contains("identifier") { continue }
                flattenNumbers(child, path: "\(path).\(key)", into: &output)
            }
            return
        }
        if let array = value as? [Any] {
            for (index, child) in array.prefix(20).enumerated() {
                flattenNumbers(child, path: "\(path)[\(index)]", into: &output)
            }
        }
    }
}
