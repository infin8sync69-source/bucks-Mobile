import Foundation

/// One person from the phone's own address book. Read on this phone and shown to its owner only; nothing here is uploaded.
/// (The reading itself, with the Contacts framework, is in BucksUI/Screens/Chat/PhoneContacts.swift.)
public struct PhoneContact: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var phones: [String]
    public var emails: [String]
    public var org: String
    public var title: String
    public var address: String
    public init(id: String, name: String, phones: [String] = [], emails: [String] = [], org: String = "", title: String = "", address: String = "") {
        self.id = id; self.name = name; self.phones = phones; self.emails = emails; self.org = org; self.title = title; self.address = address
    }
    public var initials: String {
        let s = name.split(separator: " ").prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
        return s.isEmpty ? "#" : s
    }
    /// Everything searchable about the contact, lower-cased.
    public var haystack: String { ([name, org, title, address] + phones + emails).joined(separator: "\n").lowercased() }
    public var digits: [String] { phones.map { $0.filter(\.isNumber) } }

    /// The search used by the Contacts screen and the phonebook picker: the text anywhere, or 3+ digits inside a number.
    public func matches(_ query: String) -> Bool {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        let d = t.filter(\.isNumber)
        return haystack.contains(t) || (d.count >= 3 && digits.contains { $0.contains(d) })
    }
}

public enum PhoneContacts {
    /// The number as a dialable +91 number when it looks like a 10-digit Indian mobile, else as typed.
    public static func dialable(_ p: String) -> String {
        let d = p.filter(\.isNumber)
        if d.count == 10 { return "+91" + d }
        if d.count == 12 && d.hasPrefix("91") { return "+" + d }
        if p.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return "+" + d }
        return d
    }
    /// The last 10 digits of a number, to tell whether two entries are the same phone.
    public static func tail10(_ p: String) -> String { String(p.filter(\.isNumber).suffix(10)) }

    /// How well a phonebook name matches a Bucks name: the number of name words they share.
    public static func nameScore(_ a: String, _ b: String) -> Int {
        let words = a.lowercased().split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init).filter { $0.count > 1 }
        let other = b.lowercased()
        return words.filter { other.contains($0) }.count
    }
    /// Splits "9845012345, 080 2222 3333" or one per line into a clean list.
    public static func splitList(_ text: String, max: Int = 5) -> [String] {
        var out: [String] = []
        for part in text.split(whereSeparator: { ",\n;".contains($0) }) {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !out.contains(t) { out.append(t) }
        }
        return Array(out.prefix(max))
    }
}
