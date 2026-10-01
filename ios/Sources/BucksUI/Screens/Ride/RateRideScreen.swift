import SwiftUI
import BucksCore

/// After payment: recommend or not the driver with a line on why, or skip.
struct RateRideScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var vote: Int?
    @State private var comment = ""

    var body: some View {
        Group { if let r = session.dispatch.ride, let d = r.driver { content(r, d) } else { Color.clear } }
            .bucksBackground()
            .navigationBarBackButtonHidden(true)
            .bucksHideNavigationBar()
    }

    private func content(_ r: Ride, _ d: Driver) -> some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar()
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Avatar(initials: initials(d.name), size: 76)
                            Headline("How was \(d.name.components(separatedBy: " ")[0])?").multilineTextAlignment(.center).padding(.top, 12)
                            Muted("Paid ₹\(r.fare) by \(payWord(r.paidWith)).", align: .center)
                        }.frame(maxWidth: .infinity)
                        HStack(spacing: 10) {
                            VoteButton("Recommend", active: vote == 1, up: true) { vote = 1 }
                            VoteButton("Not recommended", active: vote == -1, up: false) { vote = -1 }
                        }.frame(maxWidth: .infinity).padding(.vertical, 22)
                        BucksField($comment, label: "One line on why", placeholder: "Safe riding, on time", singleLine: false, minLines: 2)
                        PrimaryButton("Post review") { finish(vote: vote, comment: comment, skip: false) }.padding(.top, 16)
                        Button("Skip for now") { finish(vote: nil, comment: "", skip: true) }
                            .buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary).padding(.top, 14)
                    }.padding(Gutter).padding(.top, 24)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func finish(vote: Int?, comment: String, skip: Bool) {
        if session.finishRide(vote: vote, comment: comment, skip: skip) { router.popToRoot() }
    }
}
