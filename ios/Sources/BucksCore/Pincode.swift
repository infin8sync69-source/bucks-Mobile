import Foundation

/// City and state for a 6-digit Indian pincode (India Post's public directory), so a delivery address fills itself in (Pincode.kt).
/// Best effort: offline or an unknown pincode returns nil and the person types the two fields.
public enum Pincode {
    public static func lookup(_ pin: String) async -> (city: String, state: String)? {
        guard pin.range(of: "^[1-9][0-9]{5}$", options: .regularExpression) != nil, let url = URL(string: "https://api.postalpincode.in/pincode/\(pin)") else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let office = (arr.first?["PostOffice"] as? [[String: Any]])?.first,
              let city = office["District"] as? String, let state = office["State"] as? String, !city.isEmpty, !state.isEmpty else { return nil }
        return (city, state)
    }
}
