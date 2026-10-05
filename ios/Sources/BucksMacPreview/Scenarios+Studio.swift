#if os(macOS)
import Foundation
import BucksCore
import BucksUI

/// `--scenario studio`: the Studio hub, a live shop's and a pending skill's dashboard, the product list, the forms.
@MainActor
func scenarioStudio(_ session: AppSession, _ router: Router) async {
    session.listings.refresh()
    await Scenarios.pause(2.0)
    for (name, route) in [("st01-hub", Route.myListings), ("st02-shop", .studio("S-shop")), ("st03-skill", .studio("S-skill")), ("st04-asset", .studio("S-asset")),
                          ("st05-items", .itemEdit(listing: "S-shop", item: nil)), ("st06-item-edit", .itemEdit(listing: "S-shop", item: "i1")), ("st07-item-new", .itemEdit(listing: "S-shop", item: "new")),
                          ("st08-edit-shop", .listingEdit(id: "S-shop", kind: "BUSINESS", service: nil)), ("st09-edit-skill", .listingEdit(id: "S-skill", kind: "SKILL", service: nil)),
                          ("st10-edit-asset", .listingEdit(id: "S-asset", kind: "ASSET", service: nil)), ("st11-create-driver", .listingEdit(id: nil, kind: "DRIVER", service: nil))] {
        router.popToRoot(); router.push(route)
        await Scenarios.pause(2.5)
        Scenarios.snap(name)
    }
}
#endif
