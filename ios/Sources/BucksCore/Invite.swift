import Foundation

/// Invite people to Bucks through any app (Messages, WhatsApp, Telegram…); port of ui/Invite.kt.
/// Bucks isn't on the App Store yet, so the link is the project's releases page; once it is, set `storeURL` and every invite uses it.
public enum Invite {
    public static let storeURL = ""
    private static let releases = "https://github.com/infin8sync69-source/bucks-Mobile/releases"

    public static var link: String { storeURL.isEmpty ? releases : storeURL }

    /// `message` followed by the download link, ready for the share sheet.
    public static func shareText(_ message: String) -> String {
        "\(message)\n\nGet Bucks for iPhone: \(link)" + (storeURL.isEmpty ? "\n(Bucks isn't on the App Store yet; open the link for the latest test build.)" : "")
    }

    /// What to invite one contact with (ContactsScreen's invite text).
    public static func contactText(firstName: String) -> String {
        "Hi \(firstName), I'm on Bucks: rides, food, shops, skills and homes near you, run by locals. Join here: \(link)"
            + (storeURL.isEmpty ? "\n(Bucks isn't on the App Store yet; open the link for the latest test build.)" : "")
    }

    /// What a customer sends to someone with a bike when no delivery agent is online near a shop.
    public static func deliveryAgent(near place: String) -> String {
        "Bucks needs delivery agents near \(place). If you have a bike, join Bucks, add it under My listings > Vehicles (Bucks checks its papers) and go online to deliver local orders and earn the delivery fee."
    }

    /// What a shop owner sends to someone they want as their own store rider.
    public static func storeRider(shop: String) -> String {
        "I'd like you to deliver for \(shop) on Bucks. Install Bucks and send me your Bucks ID (Account > Your Bucks ID) so I can invite you as our store rider. Then add your bike under My listings > Vehicles so Bucks can check it."
    }

    /// What to say for a locked service: who we need more of, in plain words.
    public static func forService(label: String, supplyNoun: String) -> String {
        "I want \(label) on Bucks near me, but it needs more \(supplyNoun) here first. If you're one (or know one), join Bucks and get recommended by locals so it opens for all of us."
    }
}
