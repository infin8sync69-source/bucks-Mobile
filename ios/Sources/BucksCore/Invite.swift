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

    /// What to say for a locked service: who we need more of, in plain words.
    public static func forService(label: String, supplyNoun: String) -> String {
        "I want \(label) on Bucks near me, but it needs more \(supplyNoun) here first. If you're one (or know one), join Bucks and get recommended by locals so it opens for all of us."
    }
}
