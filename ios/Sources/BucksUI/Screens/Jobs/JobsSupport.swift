import SwiftUI
import BucksCore

/* Bits shared by the jobs screens (Android's JobsCommon.kt). */

/// Application status as a coloured pill.
struct ApplicationStatusPill: View {
    let status: String
    var body: some View {
        let label = JobsStore.statusLabel(status)
        switch status {
        case "HIRED": PillGood(label)
        case "SHORTLISTED": PillWarn(label)
        case "REJECTED": PillBad(label)
        case "WITHDRAWN": PillGrey(label)
        default: PillPurple(label)
        }
    }
}

func JobTypePill(_ type: String) -> Pill { PillGrey(JobsStore.typeLabel(type)) }

/// Centred spinner with a line under it, for a screen that is still loading.
struct JobsLoading: View {
    var text = "Loading…"
    var body: some View {
        VStack(spacing: 0) { BucksLoader(); Muted(text, align: .center).padding(.top, 12) }
            .frame(maxWidth: .infinity).padding(Gutter).padding(.top, 40)
    }
}

/// A refresh / shortcut button in a top bar, 44 pt like the bar's own buttons.
struct JobsBarButton: View {
    let systemImage: String, label: String, action: () -> Void
    init(_ systemImage: String, _ label: String, action: @escaping () -> Void) { self.systemImage = systemImage; self.label = label; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 20)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// One job in a list: title, pay, type pill and a line of details (business, distance, posted time, counts).
struct JobCard: View {
    let title: String, pay: String, type: String, createdAt: String
    var details: [String] = []
    var closed = false
    var badge: String?
    let onTap: () -> Void

    var body: some View {
        BucksCard(onTap: onTap) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                    Text(pay.isEmpty || pay.allSatisfy(\.isWhitespace) ? "Pay on request" : pay).bucks(.bodyMedium).foregroundStyle(BucksColor.primary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if closed { PillGrey("Closed") } else { JobTypePill(type) }
            }
            HStack(spacing: 8) {
                Muted((details + ["Posted \(JobsStore.timeSince(createdAt))"]).filter { !$0.allSatisfy(\.isWhitespace) }.joined(separator: " · "), maxLines: 2)
                if let badge { PillPurple(badge) }
            }.padding(.top, 8)
        }
    }
}

/// Shows an alert for a question asked before an action that can't be taken back.
struct JobConfirm: Identifiable {
    let id = UUID()
    let title: String, text: String, button: String
    var destructive = false
    let run: () -> Void
}

extension View {
    func jobConfirm(_ item: Binding<JobConfirm?>) -> some View {
        alert(item.wrappedValue?.title ?? "", isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })) {
            if let c = item.wrappedValue {
                Button("Cancel", role: .cancel) {}
                Button(c.button, role: c.destructive ? .destructive : nil, action: c.run)
            }
        } message: { if let c = item.wrappedValue { Text(c.text) } }
    }
}

/// Scrolling screen body used by the list screens: 20 pt sides, 8 pt top and bottom, 10 pt between rows.
struct JobsList<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 10) { content; Spacer().frame(height: 24) }.padding(.horizontal, Gutter).padding(.vertical, 8) }
    }
}
