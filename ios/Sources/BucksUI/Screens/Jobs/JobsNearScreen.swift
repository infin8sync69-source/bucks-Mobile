import SwiftUI
import BucksCore

/// Open jobs within 15 km of me, nearest first, with a filter by kind of job.
struct JobsNearScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var type = ""   // "" = every kind

    var body: some View {
        let jobs = session.jobs
        let list = jobs.near.filter { type.isEmpty || $0.jobType == type }
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Jobs near me", onBack: { router.pop() }) {
                    JobsBarButton("list.clipboard.fill", "My applications") { router.push(.myApplications) }
                    JobsBarButton("arrow.clockwise", "Refresh") { jobs.refreshNear() }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        BucksChip("All", selected: type.isEmpty) { type = "" }
                        ForEach(JobsStore.types, id: \.key) { t in BucksChip(t.label, selected: type == t.key) { type = type == t.key ? "" : t.key } }
                    }.padding(.horizontal, Gutter).padding(.vertical, 4)
                }
                JobsList {
                    if !session.locationGranted { Notice("Location is off, so this shows jobs around the city centre. Allow location in Settings to see jobs around you.") }
                    if jobs.loadingNear && jobs.near.isEmpty {
                        JobsLoading(text: "Finding jobs near you…")
                    } else if jobs.near.isEmpty {
                        Muted("No open jobs within 15 km right now. Businesses post here when they need people; check back in a day or two. Meanwhile, add a skill profile under Menu > Bucks Pro so they can find you.").padding(.top, 8)
                    } else if list.isEmpty {
                        Muted("No \(JobsStore.typeLabel(type).lowercased()) jobs nearby. Tap All to see every job.").padding(.top, 8)
                    } else {
                        ForEach(list) { j in
                            JobCard(title: j.title, pay: j.pay, type: j.jobType, createdAt: j.createdAt,
                                    details: [j.listingTitle, [j.area, JobsStore.distance(j.distanceM)].filter { !$0.allSatisfy(\.isWhitespace) }.joined(separator: ", ")]) { router.push(.job(j.id)) }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task(id: session.me?.id) { await session.jobs.refreshNear().value }
    }
}
