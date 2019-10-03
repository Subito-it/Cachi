import Foundation

private let syncQueue = DispatchQueue(label: "cachi.browser.benchmark")
private var benchmark = [String: TimeInterval]()

func benchmarkStart() -> String {
    let uuid = UUID().uuidString
    syncQueue.sync { benchmark[uuid] = CFAbsoluteTimeGetCurrent() }
    return uuid
}

func benchmarkStop(_ uuid: String) -> TimeInterval {
    let start: TimeInterval = syncQueue.sync {
        guard let start = benchmark[uuid] else { fatalError("Benchmark id not found") }
        benchmark[uuid] = nil
        return start
    }
    return (CFAbsoluteTimeGetCurrent() - start) * 1000
}
