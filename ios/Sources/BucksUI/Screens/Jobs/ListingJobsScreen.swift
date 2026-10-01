import SwiftUI
import BucksCore

/// Jobs at one business. Everyone sees the open jobs; the owner and admins also see the closed ones, how many people applied,
/// and can post a new job.
struct ListingJobsScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let jobs = session.jobs
        let forThis = jobs.listing?.id == id
        let list = forThis ? jobs.jobs : []
        let open = list.filter(\.open), closed = list.filter { !$0.open }
        let manager = forThis && jobs.manager
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: (forThis ? jobs.listing.map { "Jobs at \($0.title)" } : nil) ?? "Jobs", onBack: { router.pop() }) {
                    JobsBarButton("arrow.clockwise", "Refresh") { jobs.loadListingJobs(id) }
                }
                JobsList {
                    if manager { PrimaryButton("Post a job") { router.push(.jobNew(id)) }.padding(.bottom, 6) }
                    if jobs.loadingJobs && !forThis {
                        JobsLoading(text: "Loading jobs…")
                    } else if list.isEmpty {
                        Muted(manager ? "No jobs yet. Post one and people nearby with the right skills can apply. You'll see every application here."
                              : "No open jobs here right now. Check back later, or look at jobs near you under Services.").padding(.top, 8)
                    } else {
                        if open.isEmpty {
                            Muted(manager ? "All your jobs are closed. Post a new one when you need people." : "No open jobs here right now. Check back later.").padding(.top, 8)
                        }
                        ForEach(open) { j in
                            JobCard(title: j.title, pay: j.pay, type: j.jobType, createdAt: j.createdAt, details: manager ? [JobsStore.applicationsLine(j.applications)] : [],
                                    badge: manager && j.newApplications > 0 ? "\(j.newApplications) new" : nil) { router.push(.job(j.id)) }
                        }
                        if manager && !closed.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                SectionTitle("Closed").padding(.top, 12)
                                Muted("Closed jobs take no new applications. Open one to see who applied or to reopen it.")
                            }
                            ForEach(closed) { j in
                                JobCard(title: j.title, pay: j.pay, type: j.jobType, createdAt: j.createdAt, details: [JobsStore.applicationsLine(j.applications)], closed: true) { router.push(.job(j.id)) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task(id: id) { await session.jobs.loadListingJobs(id).value }
    }
}
