import SwiftUI
import BucksCore

/// One job. Managers of the business see and decide on the applications; everyone else can apply with their skill profiles,
/// follow their application and withdraw it.
struct JobScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var applySheet = false
    @State private var confirm: JobConfirm?

    var body: some View {
        let jobs = session.jobs
        let job = jobs.job.flatMap { $0.id == id ? $0 : nil }
        let manager = job != nil && jobs.manager
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: job?.title ?? "Job", onBack: { router.pop() }) {
                    JobsBarButton("arrow.clockwise", "Refresh") { jobs.loadJob(id) }
                }
                if let job {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            JobDetails(job: job)
                            BusinessCard(job: job) { router.push(.listing(job.listingId)) }
                            if manager { ManagerSection(job: job, confirm: $confirm) }
                            else { ApplicantSection(job: job, confirm: $confirm, onApply: { applySheet = true }) }
                            Spacer().frame(height: 32)
                        }.padding(.horizontal, Gutter).padding(.vertical, 8)
                    }
                } else if jobs.jobMissing == id {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("This job isn't available").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("It was closed or removed by the business. Jobs you applied to stay under My applications.").padding(.top, 6)
                        SmallButton("Go back", tonal: true) { router.pop() }.padding(.top, 14)
                    }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    JobsLoading(text: "Loading the job…")
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task(id: id) { await session.jobs.loadJob(id).value }
        .jobConfirm($confirm)
        .sheet(isPresented: $applySheet) { if let job { ApplySheet(job: job) { applySheet = false } } }
    }
}

private struct JobDetails: View {
    let job: JobPageRow
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if job.open { JobTypePill(job.jobType) } else { PillGrey("Closed") }
                Muted("Posted \(JobsStore.timeSince(job.createdAt))")
            }.padding(.bottom, 6)
            Text(job.title).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface)
            Text(job.pay.allSatisfy(\.isWhitespace) ? "Pay on request" : job.pay).bucks(.titleMedium).foregroundStyle(BucksColor.primary).padding(.top, 4)
            if !job.description.allSatisfy(\.isWhitespace) {
                Text(job.description).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 12)
            } else {
                Muted("The business didn't add details. Message them or open their page to ask.").padding(.top, 12)
            }
        }
    }
}

private struct BusinessCard: View {
    let job: JobPageRow
    let onTap: () -> Void
    var body: some View {
        BucksCard(onTap: onTap) {
            HStack(spacing: 0) {
                Avatar(systemImage: "storefront.fill")
                VStack(alignment: .leading, spacing: 0) {
                    Text(job.listingTitle).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted(job.area.allSatisfy(\.isWhitespace) ? "Open the business page for reviews and directions" : job.area)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant).accessibilityLabel("Open business")
            }
        }.padding(.top, 16)
    }
}

// MARK: - the business side: applications and decisions

private struct ManagerSection: View {
    let job: JobPageRow
    @Binding var confirm: JobConfirm?
    @Environment(AppSession.self) private var session

    var body: some View {
        let jobs = session.jobs
        let apps = jobs.applications.filter { $0.jobId == job.id }
        let active = apps.filter { $0.status != "WITHDRAWN" }, withdrawn = apps.filter { $0.status == "WITHDRAWN" }
        let ordered = active.sorted { a, b in
            let ra = JobsStore.statusRank(a.status), rb = JobsStore.statusRank(b.status)
            return ra != rb ? ra < rb : a.createdAt < b.createdAt
        }
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(active.count == 0 ? "Applications" : active.count == 1 ? "1 application" : "\(active.count) applications").padding(.top, 24).padding(.bottom, 4)
            if jobs.loadingJob && apps.isEmpty {
                JobsLoading(text: "Loading applications…")
            } else if active.isEmpty {
                Muted(job.open ? "Nobody has applied yet. The job is visible to people within 15 km; give it a day or two." : "Nobody applied before the job was closed.").padding(.vertical, 8)
            }
            ForEach(ordered) { a in ApplicationCard(application: a, confirm: $confirm) }
            if !withdrawn.isEmpty { Muted("\(withdrawn.count) withdrew their application.").padding(.top, 8) }

            SectionTitle("This job").padding(.top, 24).padding(.bottom, 4)
            if job.open {
                Muted("Hiring someone doesn't close the job. Close it once you have the people you need; you can reopen it later.")
                BadButton(jobs.busy ? "Working…" : "Close this job") {
                    if !jobs.busy {
                        confirm = JobConfirm(title: "Close this job?", text: "It disappears from Jobs near me and nobody new can apply. People who already applied keep their status, and you can still shortlist or hire them.", button: "Close job", destructive: true) { jobs.closeJob(job.id) }
                    }
                }.padding(.top, 8)
            } else {
                Muted("This job is closed. Nobody new can apply, but you can still decide on the applications above.")
                SmallButton("Reopen job", tonal: true, enabled: !jobs.busy) { jobs.reopenJob(job.id) }.padding(.top, 10)
            }
        }
    }
}

private struct ApplicationCard: View {
    let application: JobApplicationRow
    @Binding var confirm: JobConfirm?
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let jobs = session.jobs, a = application, name = jobs.nameOf(a.applicantId), busy = jobs.busy
        BucksCard {
            HStack(spacing: 0) {
                Avatar(initials: initials(name.isEmpty ? "?" : name), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted("Applied \(JobsStore.timeSince(a.createdAt))")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                ApplicationStatusPill(status: a.status)
            }
            if !a.note.allSatisfy(\.isWhitespace) { Text(a.note).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 10) }
            if !a.skillListingIds.isEmpty {
                FieldLabel("Skill profiles").padding(.top, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(a.skillListingIds, id: \.self) { sid in
                            if let l = jobs.skillProfiles[sid] {
                                BucksChip(l.title + (l.status != "LIVE" ? " · not live yet" : "")) { router.push(.listing(sid)) }
                            } else {
                                BucksChip("Skill profile not public yet") { session.toast("Their skill profile isn't live yet, so it can't be opened. Message them to ask about it.") }
                            }
                        }
                    }
                }
            } else {
                Muted("Applied without a skill profile.").padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if a.status == "APPLIED" || a.status == "REJECTED" { SmallButton("Shortlist", tonal: true, enabled: !busy) { jobs.setApplicationStatus(a.id, "SHORTLISTED") } }
                    if a.status != "HIRED" {
                        SmallButton("Hire", enabled: !busy) {
                            confirm = JobConfirm(title: "Hire \(name)?", text: "They'll see \"Hired\" on their application. Agree the start and pay with them in chat. The job stays open until you close it.", button: "Hire") { jobs.setApplicationStatus(a.id, "HIRED") }
                        }
                    }
                    SmallButton("Message", tonal: true, enabled: !busy) { jobs.message(a.id) { router.push(.chat($0)) } }
                    if a.status == "APPLIED" || a.status == "SHORTLISTED" {
                        SmallButton("Reject", tonal: true, enabled: !busy) {
                            confirm = JobConfirm(title: "Turn down \(name)?", text: "They'll see \"Not selected\". You can still shortlist them later if you change your mind.", button: "Turn down", destructive: true) { jobs.setApplicationStatus(a.id, "REJECTED") }
                        }
                    }
                }
            }.padding(.top, 12)
        }.padding(.top, 10)
    }
}

// MARK: - the applicant side

private struct ApplicantSection: View {
    let job: JobPageRow
    @Binding var confirm: JobConfirm?
    let onApply: () -> Void
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let jobs = session.jobs
        let mine = jobs.myApplication.flatMap { $0.jobId == job.id ? $0 : nil }
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Your application").padding(.top, 24).padding(.bottom, 4)
            if jobs.loadingJob && mine == nil {
                JobsLoading(text: "Checking…")
            } else if let mine {
                application(mine, busy: jobs.busy)
            } else if job.open {
                Muted("Apply with your skill profile and a short note. The business sees your name and profile, not your phone number, until you chat.")
                PrimaryButton("Apply for this job", enabled: !jobs.busy, action: onApply).padding(.top, 12)
            } else {
                Muted("This job is closed and takes no new applications. Look for others under Jobs near me.")
            }
            // Questions before applying, or agreeing the start and pay after: the business's shared inbox, where every owner and admin sees it.
            if !(jobs.loadingJob && mine == nil) {
                SmallButton("Message the business", tonal: true, enabled: !jobs.messaging) { jobs.messageBusiness(job.listingId) { router.push(.chat($0)) } }.padding(.top, 12)
            }
        }
    }

    private func application(_ mine: JobApplicationRow, busy: Bool) -> some View {
        BucksCard(tint: mine.status == "HIRED") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Applied \(JobsStore.timeSince(mine.createdAt))").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    if !mine.note.allSatisfy(\.isWhitespace) { Muted(mine.note, maxLines: 3).padding(.top, 4) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                ApplicationStatusPill(status: mine.status)
            }
            Muted(statusLine(mine.status)).padding(.top, 10)
            if ["APPLIED", "SHORTLISTED", "HIRED"].contains(mine.status) {
                BadButton(busy ? "Working…" : "Withdraw application") {
                    if !busy {
                        confirm = JobConfirm(title: "Withdraw your application?", text: "The business will see you withdrew. You won't be able to apply again to this job.", button: "Withdraw", destructive: true) { session.jobs.withdraw(mine.id) }
                    }
                }.padding(.top, 8)
            }
        }
    }

    private func statusLine(_ s: String) -> String {
        switch s {
        case "APPLIED": "Waiting for the business to look at it. They'll message you here if they want to talk."
        case "SHORTLISTED": "You're on the shortlist. Keep an eye on your messages."
        case "HIRED": "Congratulations, you're hired. Agree the start day and pay with the business in chat."
        case "REJECTED": "Not selected this time. Other jobs nearby are under Jobs near me."
        default: "You withdrew this application. You can't apply again to the same job."
        }
    }
}

/// Pick one or more of my skill profiles and add a note.
private struct ApplySheet: View {
    let job: JobPageRow
    let onDismiss: () -> Void
    @Environment(AppSession.self) private var session
    @State private var selected: Set<String> = []
    @State private var note = ""

    var body: some View {
        let jobs = session.jobs
        let skills = jobs.mySkills
        let noteBlank = note.allSatisfy(\.isWhitespace)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Apply: \(job.title)").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("\(job.listingTitle) · \(job.pay.allSatisfy(\.isWhitespace) ? "Pay on request" : job.pay)").padding(.top, 2).padding(.bottom, 14)
                FieldLabel("Apply with")
                if skills.isEmpty {
                    Notice("You don't have a skill profile yet. Add one under Menu > Bucks Pro > Create > Skill profile (for example Delivery driver, Tailor, Electrician) so businesses can see your experience and reviews. You can still apply now with a note.")
                } else {
                    FlowChips(skills.map(\.title), selected: Set(skills.filter { selected.contains($0.id) }.map(\.title))) { title in
                        if let s = skills.first(where: { $0.title == title }) { if selected.contains(s.id) { selected.remove(s.id) } else { selected.insert(s.id) } }
                    }
                }
                BucksField($note, label: "Note to the business", placeholder: "When you can start, experience, what you'd like to know", singleLine: false, minLines: 3).padding(.top, 14)
                PrimaryButton(jobs.busy ? "Sending…" : "Send application", enabled: !jobs.busy && (!selected.isEmpty || !noteBlank)) {
                    jobs.apply(job.id, skillIds: skills.map(\.id).filter { selected.contains($0) }, note: note); onDismiss()
                }
                if selected.isEmpty && noteBlank { Muted("Pick a skill profile or write a line about yourself.").padding(.top, 8) }
            }.padding(Gutter).padding(.bottom, 24)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .task { await jobs.loadMySkills().value }
        .onChange(of: skills.count, initial: true) { _, _ in if selected.isEmpty, skills.count == 1, let f = skills.first { selected = [f.id] } }
        .onChange(of: note) { _, v in if v.count > 500 { note = String(v.prefix(500)) } }
    }
}
