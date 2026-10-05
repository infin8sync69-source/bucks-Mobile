import SwiftUI
import BucksCore

private let payExamples = ["Rs 15,000/month", "Rs 500/day", "Rs 800 per job", "Rs 120/hour"]

/// Post a job for a listing: title, what the work is, pay in plain words, and the kind of job.
struct NewJobScreen: View {
    let listingId: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var title = ""
    @State private var description = ""
    @State private var pay = ""
    @State private var type = "FULL_TIME"

    var body: some View {
        let jobs = session.jobs
        let listingTitle = jobs.listing.flatMap { $0.id == listingId ? $0.title : nil }
        let blankPay = pay.allSatisfy(\.isWhitespace)
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Post a job", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let listingTitle { Muted("For \(listingTitle). People nearby see it under Jobs and apply with their skill profile.").padding(.bottom, 14) }
                        BucksField($title, label: "Job title", placeholder: "Delivery rider, Billing staff, Tailor")
                        BucksField($description, label: "What the work is", placeholder: "Timings, area, what they need to bring (own bike, licence), who to ask for", singleLine: false, minLines: 4)
                        BucksField($pay, label: "Pay", placeholder: "Rs 15,000/month, Rs 500/day")
                        FlowChips(payExamples) { pay = $0 }
                        FieldLabel("Kind of job").padding(.top, 16)
                        FlowChips(JobsStore.types.map(\.label), selected: [JobsStore.typeLabel(type)]) { label in
                            if let t = JobsStore.types.first(where: { $0.label == label }) { type = t.key }
                        }
                        Muted(typeHint).padding(.top, 8)
                        if blankPay { Muted("Leave pay empty and the job shows \"Pay on request\". Jobs that say the pay get more applications.").padding(.top, 8) }
                        PrimaryButton(jobs.busy ? "Posting…" : "Post job", enabled: !jobs.busy && !title.allSatisfy(\.isWhitespace)) {
                            if title.allSatisfy(\.isWhitespace) { session.toast("Give the job a title.") }
                            else { jobs.postJob(listingId: listingId, title: title, description: description, pay: pay, type: type) { router.pop() } }
                        }.padding(.top, 24)
                        Muted("You can close the job any time. Applications reach you here in the app, not by phone.").padding(.top, 10)
                        Spacer().frame(height: 24)
                    }.padding(Gutter)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task(id: listingId) { if session.jobs.listing?.id != listingId { await session.jobs.loadListingJobs(listingId).value } }
        .onChange(of: title) { _, v in if v.count > 80 { title = String(v.prefix(80)) } }
        .onChange(of: description) { _, v in if v.count > 1000 { description = String(v.prefix(1000)) } }
        .onChange(of: pay) { _, v in if v.count > 60 { pay = String(v.prefix(60)) } }
    }

    private var typeHint: String {
        switch type {
        case "FULL_TIME": "Regular work, every day."
        case "PART_TIME": "A few hours or a few days a week."
        default: "One task or a short stint, paid once it's done."
        }
    }
}
