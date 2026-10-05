import SwiftUI
import BucksCore

private let activeStatuses: Set<String> = ["APPLIED", "SHORTLISTED", "HIRED"]

/// Every job I applied to, newest first, with the business and where the application stands.
struct MyApplicationsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let jobs = session.jobs
        let list = jobs.myApplications
        let active = list.filter { activeStatuses.contains($0.status) }, past = list.filter { !activeStatuses.contains($0.status) }
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "My applications", onBack: { router.pop() }) {
                    JobsBarButton("briefcase.fill", "Jobs near me") { router.push(.jobsNear) }
                    JobsBarButton("arrow.clockwise", "Refresh") { jobs.refreshMyApplications() }
                }
                JobsList {
                    if jobs.loadingMine && list.isEmpty {
                        JobsLoading(text: "Loading your applications…")
                    } else if list.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Muted("You haven't applied to any job yet. Open Jobs under Services to see what businesses near you are hiring, then apply with your skill profile.").padding(.top, 8)
                            PrimaryButton("See jobs near me") { router.push(.jobsNear) }.padding(.top, 16)
                        }
                    } else {
                        if active.isEmpty { Muted("Nothing in progress. Your past applications are below.").padding(.top, 8) }
                        ForEach(active) { a in row(a) }
                        if !past.isEmpty {
                            SectionTitle("Past").padding(.top, 12)
                            ForEach(past) { a in row(a) }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { await session.jobs.refreshMyApplications().value }
    }

    private func row(_ a: MyApplicationRow) -> some View {
        BucksCard(onTap: { router.push(.job(a.jobId)) }) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.jobTitle).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                    Text([a.listingTitle, a.area].filter { !$0.allSatisfy(\.isWhitespace) }.joined(separator: " · ")).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ApplicationStatusPill(status: a.status)
            }
            Muted([a.pay, "Applied \(JobsStore.timeSince(a.createdAt))", a.jobOpen ? "" : "Job closed"].filter { !$0.allSatisfy(\.isWhitespace) }.joined(separator: " · "), maxLines: 2).padding(.top, 8)
        }
    }
}
