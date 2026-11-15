import SwiftUI
import BucksCore

private let feedbackStatus: [(key: String, label: String)] = [("OPEN", "Open"), ("PLANNED", "Planned"), ("IN_PROGRESS", "In progress"), ("DONE", "Done"), ("DECLINED", "Not planned")]
private let feedbackCategory: [(key: String, label: String)] = [("IDEA", "Idea"), ("BUG", "Bug"), ("OTHER", "Other")]
private func label(_ list: [(key: String, label: String)], _ key: String) -> String { list.first { $0.key == key }?.label ?? key }

/// Feedback board (ui/social/Feedback.kt): suggest ideas, report bugs, upvote what matters and see what the team is doing. Staff can
/// set a status and a public note on each post.
struct FeedbackBoardScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var sort = "TOP"
    @State private var filter = "ALL"
    @State private var rows: [FeedbackRow]?
    @State private var composing = false
    @State private var staffFor: FeedbackRow?
    @State private var tick = 0

    private let filters: [(key: String, label: String)] = [("ALL", "All"), ("PLANNED", "Planned"), ("IN_PROGRESS", "In progress"), ("DONE", "Done"), ("MINE", "Mine")]

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Feedback board", onBack: { router.pop() })
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Muted("Tell us what would make Bucks better. Vote for the ideas you want most. The team reads every post.")
                            .padding(.horizontal, Gutter).padding(.vertical, 4)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { ForEach(filters, id: \.key) { f in BucksChip(f.label, selected: filter == f.key) { filter = f.key } } }.padding(.horizontal, Gutter)
                        }.padding(.vertical, 8)
                        Picker("Sort", selection: $sort) { Text("Most votes").tag("TOP"); Text("Newest").tag("NEW") }
                            .pickerStyle(.segmented).padding(.horizontal, Gutter).padding(.bottom, 6)
                        if let rows {
                            if rows.isEmpty {
                                Muted(filter == "MINE" ? "No posts yet. Tap Suggest to share an idea." : "Nothing here yet. Be the first to suggest something.").padding(Gutter)
                            }
                            ForEach(rows) { r in
                                FeedbackCard(row: r, staff: session.services.isStaff, onVote: { vote(r) }, onStaff: { staffFor = r }, onDelete: { delete(r) },
                                             onReport: { session.reportTarget = ReportTarget(kind: "FEEDBACK", targetId: r.id, ownerId: nil, ownerName: r.authorName) })
                            }
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(40)
                        }
                    }.padding(.bottom, 96)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottomTrailing) {
            Button { composing = true } label: {
                Label("Suggest", systemImage: "lightbulb.fill").font(.bucks(.labelLarge)).foregroundStyle(BucksColor.onPrimary)
                    .padding(.horizontal, 18).frame(height: 52).background(Capsule().fill(BucksColor.primary))
            }.buttonStyle(.plain).padding(Gutter)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { session.services.checkStaff() }
        .task(id: "\(sort)|\(filter)|\(tick)") { await load() }
        .sheet(isPresented: $composing) {
            ComposeFeedbackSheet { composing = false; sort = "NEW"; filter = "ALL"; tick += 1 }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $staffFor) { r in
            StaffStatusSheet(row: r) { staffFor = nil; tick += 1 }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    private func load() async {
        rows = nil
        do {
            switch filter {
            case "MINE": rows = try await Backend.shared.feedbackList(sort: sort, mine: true)
            case "ALL": rows = try await Backend.shared.feedbackList(sort: sort)
            default: rows = try await Backend.shared.feedbackList(sort: sort, status: filter)
            }
        } catch is CancellationError {} catch { session.toast("Couldn't load the board. Check your connection."); rows = [] }
    }

    /// The count answers at once; the server's number replaces it, and a failure puts the old row back.
    private func vote(_ r: FeedbackRow) {
        guard let i = rows?.firstIndex(where: { $0.id == r.id }) else { return }
        let on = !r.voted
        rows?[i].voted = on; rows?[i].votes += on ? 1 : -1
        Task {
            do { let n = try await Backend.shared.feedbackVote(r.id, on: on); if let j = rows?.firstIndex(where: { $0.id == r.id }) { rows?[j].votes = n } }
            catch { if let j = rows?.firstIndex(where: { $0.id == r.id }) { rows?[j] = r }; session.toast("Couldn't save your vote.") }
        }
    }

    private func delete(_ r: FeedbackRow) {
        Task {
            do { try await Backend.shared.feedbackDelete(r.id); rows?.removeAll { $0.id == r.id } } catch { session.toast("Couldn't delete it.") }
        }
    }
}

private struct FeedbackCard: View {
    let row: FeedbackRow; let staff: Bool
    let onVote: () -> Void, onStaff: () -> Void, onDelete: () -> Void, onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The vote box: big target, clear state, count announced.
            Button(action: onVote) {
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up").font(.system(size: 16, weight: .bold))
                    Text("\(row.votes)").bucks(.titleMedium).contentTransition(.numericText(value: Double(row.votes)))
                }
                .foregroundStyle(row.voted ? BucksColor.onPrimaryContainer : BucksColor.onSurface)
                .frame(width: 56).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(row.voted ? BucksColor.primaryContainer : BucksColor.surfaceContainer))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.voted ? "\(row.votes) votes, including yours" : "\(row.votes) votes")
            .accessibilityHint(row.voted ? "Remove your vote" : "Vote for this")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    switch row.status {
                    case "DONE": PillGood(label(feedbackStatus, row.status))
                    case "PLANNED", "IN_PROGRESS": PillPurple(label(feedbackStatus, row.status))
                    default: PillGrey(label(feedbackStatus, row.status))
                    }
                    PillGrey(label(feedbackCategory, row.category))
                    Spacer(minLength: 0)
                    Menu {
                        if staff { Button("Set status", action: onStaff) }
                        if !row.isMine { Button("Report", systemImage: "flag", action: onReport) }
                        if row.isMine || staff { Button("Delete", role: .destructive, action: onDelete) }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("More options")
                }
                Text(row.title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 6)
                if !row.body.isEmpty { Text(row.body).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurfaceVariant).padding(.top, 4) }
                if !row.staffNote.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 14)).foregroundStyle(BucksColor.onPrimaryContainer)
                        Text("Bucks team: \(row.staffNote)").bucks(.bodySmall).foregroundStyle(BucksColor.onPrimaryContainer)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.primaryContainer)).padding(.top, 8)
                }
                Muted("\(row.isMine ? "You" : row.authorName) · \(feedAgo(row.createdAt))").padding(.top, 6)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).fill(BucksColor.surface))
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

private struct ComposeFeedbackSheet: View {
    let onPosted: () -> Void
    @Environment(AppSession.self) private var session
    @State private var title = ""
    @State private var detail = ""
    @State private var category = "IDEA"
    @State private var busy = false

    private var bug: Bool { category == "BUG" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Share feedback").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                HStack(spacing: 8) { ForEach(feedbackCategory, id: \.key) { c in BucksChip(c.label, selected: category == c.key) { category = c.key } } }.padding(.vertical, 12)
                BucksField(Binding(get: { title }, set: { title = String($0.prefix(100)) }), label: bug ? "What went wrong?" : "Your idea in one line",
                           placeholder: bug ? "Photos don't load in chat" : "Let me pin a post to my profile")
                BucksField(Binding(get: { detail }, set: { detail = String($0.prefix(1000)) }), label: "More detail (optional)",
                           placeholder: bug ? "What you did, what you expected, what happened" : "Why it would help", singleLine: false, minLines: 3).padding(.top, 12)
                Muted("Everyone on the board can read this. Don't include phone numbers or anything private.").padding(.top, 4)
                PrimaryButton(busy ? "Posting…" : "Post", enabled: title.trimmingCharacters(in: .whitespaces).count >= 4 && !busy) { post() }.padding(.top, 16)
            }.padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively).bucksBackground()
    }

    private func post() {
        busy = true
        Task {
            do {
                _ = try await Backend.shared.feedbackPost(title: title.trimmingCharacters(in: .whitespaces), body: detail.trimmingCharacters(in: .whitespacesAndNewlines), category: category)
                session.toast("Thanks! Your post is on the board."); onPosted()
            } catch { session.toast(friendlyError(error)) }
            busy = false
        }
    }
}

private struct StaffStatusSheet: View {
    let row: FeedbackRow; let onSaved: () -> Void
    @Environment(AppSession.self) private var session
    @State private var status: String
    @State private var note: String

    init(row: FeedbackRow, onSaved: @escaping () -> Void) { self.row = row; self.onSaved = onSaved; _status = State(initialValue: row.status); _note = State(initialValue: row.staffNote) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Set status").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
            Text(row.title).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurfaceVariant).padding(.top, 4).padding(.bottom, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(feedbackStatus, id: \.key) { s in BucksChip(s.label, selected: status == s.key) { status = s.key } } }
            }
            BucksField(Binding(get: { note }, set: { note = String($0.prefix(500)) }), label: "Public note (optional)", placeholder: "Coming in the next update", singleLine: false, minLines: 2).padding(.top, 12)
            PrimaryButton("Save") {
                Task {
                    do { try await Backend.shared.feedbackSetStatus(row.id, status: status, note: note.trimmingCharacters(in: .whitespacesAndNewlines)); onSaved() }
                    catch { session.toast("Couldn't save.") }
                }
            }.padding(.top, 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28).bucksBackground()
    }
}
