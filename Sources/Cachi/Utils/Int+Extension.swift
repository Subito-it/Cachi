import Foundation

extension Int {
    func percentageString(total: Int, decimalDigits: Int) -> String {
        return String(format: "%.\(decimalDigits)f%%", Double(self * 100) / Double(total))
    }
}
