import CachiKit
import Foundation

extension Collection<ActionTestActivitySummary> {
    func flatten() -> [ActionTestActivitySummary] {
        var summaries = [ActionTestActivitySummary]()
        for summary in self {
            summaries += [summary] + summary.subactivities.flatten()
        }

        return summaries
    }
}
