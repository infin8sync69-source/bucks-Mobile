import SwiftUI
import BucksCore

/// Where the main stack can go. Ride routes are driven by the ride's status (see RootView); the rest are pushed by buttons.
public enum Route: Hashable {
    // Booking and the ride in progress
    case destination, chooseRide, confirmPickup, searching, driverFound, inRide, pay, rateRide
    // Driver and account
    case vehicles, vehicleEdit(String?), vehicleStats, paymentQr, editProfile, invites, account
    // Discover
    case search, listing(String)
    // Commerce
    case cart, order(String), myOrders, vendorOrders(String), deliveryTrack(String)
    // Studio (my listings)
    case myListings, studio(String), listingEdit(id: String?, kind: String, service: String?), listingDocs(String), staffReview, itemEdit(listing: String, item: String?)
    case members(String), recommendShow(String), recommendScan
    // Showcase documents a profile shows (the owner's manage screen), by listing id
    case showcaseDocs(String)
    // Jobs
    case listingJobs(String), job(String), jobNew(String), myApplications, jobsNear
    // Social
    case messages, chat(String), newGroup, sync, moments(String), momentNew, post(String), createPost, contacts, bucksId
    // Settings
    case settingsPrivacy, settingsNotifications, settingsAppearance, settingsBlocked, settingsCloseFriends
    // Maps
    case maps

    /// Routes that belong to a ride in progress (they are replaced together as the ride moves on).
    var isRide: Bool {
        switch self { case .destination, .chooseRide, .confirmPickup, .searching, .driverFound, .inRide, .pay, .rateRide: true; default: false }
    }
    /// The ride screen for a status (nil for a cancelled ride): where a rider goes as it moves along, and what Home's "Return" opens.
    public static func ride(for s: RideStatus) -> Route? {
        switch s {
        case .searching, .noDriver: .searching
        case .matched, .arrived: .driverFound
        case .inRide: .inRide
        case .completed: .pay
        case .paid: .rateRide
        case .cancelled: nil
        }
    }
}

/// The main navigation stack's path.
@MainActor @Observable
public final class Router {
    public var path: [Route] = []
    /// The bottom-bar destination showing at the root of the stack.
    public var tab: BottomTab = .home
    /// The "Bucks Pro" side menu.
    public var menuOpen = false
    /// Which part of Account opens: "profile", "activity" or "settings" (Android's account?tab=…).
    public var accountTab = "profile"
    public init() {}
    public func push(_ r: Route) { path.append(r) }
    public func pop() { if !path.isEmpty { path.removeLast() } }
    public func popToRoot() { path.removeAll() }
    /// Sign-in or sign-out: nothing of the previous person's navigation (tab, open screens, menu) may survive.
    public func reset() { path.removeAll(); tab = .home; menuOpen = false; accountTab = "profile" }
    /// A bottom-bar tap: back to the tab's root, whatever was open (Android pops to Home).
    public func select(_ t: BottomTab, accountTab: String? = nil) {
        path.removeAll(); tab = t
        if t == .account { self.accountTab = accountTab ?? "profile" }
    }
    /// Shows the ride screen for `r`, replacing the booking screens and any earlier ride screen.
    public func showRide(_ r: Route) { path = path.filter { !$0.isRide } + [r] }
}
