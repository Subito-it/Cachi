import Foundation
import CachiKit

extension Collection where Element == ActionTestActivitySummary {
    func flatten() -> [ActionTestActivitySummary] {
        var summaries = [ActionTestActivitySummary]()
        for summary in self {
            summaries += [summary] + summary.subactivities.flatten()
        }

        return summaries
    }
}
