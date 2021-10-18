import Foundation

extension Collection where Element == URLQueryItem {
    var backUrl: String {
        guard let raw = first(where: { $0.name == "back_url" })?.value else { return "" }
        return String(hexadecimalRepresentation: raw) ?? ""
    }
}
