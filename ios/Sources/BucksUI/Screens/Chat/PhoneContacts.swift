import Foundation
import BucksCore
#if os(iOS)
import Contacts
#endif

/// Reading the phone's address book (data/PhoneContacts.kt). Needs `NSContactsUsageDescription` in Info.plist. Contacts are read on this phone only;
/// nothing is uploaded. Off iOS (the Mac preview harness) there is no address book.
extension PhoneContacts {
    enum Access { case granted, denied, notAsked }

    static var access: Access {
        #if os(iOS)
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        default: return .granted   // authorized, and limited (iOS 18)
        }
        #else
        return .denied
        #endif
    }

    /// Shows the system permission prompt (the first time only); whether contacts can be read afterwards.
    static func requestAccess() async -> Bool {
        #if os(iOS)
        return (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        #else
        return false
        #endif
    }

    /// Reads the address book: name, numbers, emails, organisation, job title and address. Sorted by name; people with no number and no email are left out.
    static func load() async -> [PhoneContact] {
        #if os(iOS)
        await Task.detached(priority: .userInitiated) { () -> [PhoneContact] in
            let keys: [CNKeyDescriptor] = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey,
                                           CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey].map { $0 as CNKeyDescriptor }
            var out: [PhoneContact] = []
            let req = CNContactFetchRequest(keysToFetch: keys)
            try? CNContactStore().enumerateContacts(with: req) { c, _ in
                var phones: [String] = []; var seen = Set<String>()
                for n in c.phoneNumbers {
                    let v = n.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if v.isEmpty { continue }
                    let tail = PhoneContacts.tail10(v)
                    if seen.insert(tail.isEmpty ? v : tail).inserted { phones.append(v) }
                }
                var emails: [String] = []
                for e in c.emailAddresses { let v = (e.value as String).trimmingCharacters(in: .whitespacesAndNewlines); if !v.isEmpty, !emails.contains(v) { emails.append(v) } }
                guard !phones.isEmpty || !emails.isEmpty else { return }
                let address = c.postalAddresses.first.map { CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress).replacingOccurrences(of: "\n", with: " ") } ?? ""
                var name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                if name.isEmpty { name = c.nickname }
                if name.isEmpty { name = c.organizationName }
                if name.isEmpty { name = phones.first ?? emails.first ?? "Unknown" }
                out.append(PhoneContact(id: c.identifier, name: name, phones: phones, emails: emails, org: c.organizationName, title: c.jobTitle, address: address.trimmingCharacters(in: .whitespaces)))
            }
            return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }.value
        #else
        return []
        #endif
    }
}
