import SwiftUI
import BucksCore

// The category picker of the listing form (port of ui/screens/manage/Categories.kt). The catalogues, `cleanCategory` and the filtering live in
// BucksCore (CategoryCatalog.swift) so they can be tested; this file is the field that opens the picker and the picker itself.

/// The closed field that opens the picker: shows the chosen category or a hint.
struct CategoryField: View {
    let value: String
    let hint: String
    let action: () -> Void
    var body: some View {
        let empty = value.trimmingCharacters(in: .whitespaces).isEmpty
        Button(action: action) {
            HStack(spacing: 8) {
                Text(empty ? hint : value).bucks(.bodyLarge).foregroundStyle(empty ? BucksColor.onSurfaceVariant : BucksColor.onSurface)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(BucksColor.onSurfaceVariant)
            }
            .padding(.horizontal, 14).frame(minHeight: 56).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surface))
            .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(empty ? hint : value).accessibilityHint("Choose")
    }
}

/// Searchable list of categories by field. Typing something that isn't in the list offers "Use “…” as my category", so nobody is stuck with
/// the wrong box; categories other owners already added (from the server) are listed too, so the catalogue grows by use.
struct CategoryPickerSheet: View {
    let kind: String
    let selected: String
    let onPick: (String) -> Void
    @Environment(AppSession.self) private var session
    @State private var q = ""
    @State private var others: [String] = []
    @State private var loadingOthers = true

    private var model: CategoryPickerModel { CategoryPickerModel(kind: kind, others: others, query: q) }

    var body: some View {
        let m = model
        VStack(alignment: .leading, spacing: 0) {
            Text(kind == "SKILL" ? "What do you do?" : "What kind of business?").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
            Muted("Pick the closest one, or type your own and add it.").padding(.top, 2)
            searchField(m).padding(.vertical, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let own = m.own, m.offersOwn { ownRow(own) }
                    ForEach(m.groups, id: \.name) { g in
                        Text(g.name).bucks(.labelLarge).foregroundStyle(BucksColor.primary).padding(.top, 14).padding(.bottom, 2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(g.items, id: \.self) { c in row(c) }
                    }
                    if m.groups.isEmpty && m.own == nil { Muted("Nothing matches. Type at least 2 letters to add your own.").padding(.top, 16) }
                    if loadingOthers && q.isEmpty { Muted("Checking what others added…").padding(.top, 14) }
                    Spacer().frame(height: 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, Gutter).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .task(id: kind) { await loadOthers() }
    }

    private func loadOthers() async {
        loadingOthers = true
        defer { loadingOthers = false }
        do { others = try await Backend.shared.categorySuggestions(kind: kind).map(\.category) }
        catch is CancellationError {}
        catch { session.toast("Couldn't load what others added. You can still pick from the list or type your own.") }
    }

    private func searchField(_ m: CategoryPickerModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(BucksColor.onSurfaceVariant)
            TextField("", text: $q, prompt: Text("Search or type your own").foregroundStyle(BucksColor.onSurfaceVariant))
                .font(.bucks(.bodyLarge)).foregroundStyle(BucksColor.onSurface)
                .submitLabel(.done).autocorrectionDisabled()
                .onChange(of: q) { _, v in if v.count > 40 { q = String(v.prefix(40)) } }
                .onSubmit { if let own = m.own, m.offersOwn { onPick(own) } }
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surface))
        .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
    }

    private func ownRow(_ own: String) -> some View {
        Button { onPick(own) } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(BucksColor.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Use “\(own)” as my category").bucks(.titleSmall).foregroundStyle(BucksColor.primary)
                    Muted("Your own category. Others can find and pick it too.")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8).frame(minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func row(_ c: String) -> some View {
        let on = c.caseInsensitiveCompare(selected) == .orderedSame
        return Button { onPick(c) } label: {
            HStack(spacing: 12) {
                Text(c).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                if on { Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(BucksColor.primary).accessibilityLabel("Selected") }
            }
            .padding(.vertical, 6).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
}
