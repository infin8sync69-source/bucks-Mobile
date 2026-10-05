import SwiftUI
import BucksCore

private let interestOptions = ["Food", "Rides", "Home services", "Fitness", "Tech", "Design", "Jobs", "Kids", "Pets", "Shopping", "Events", "Health"]
private let genderOptions = ["Woman", "Man", "Non-binary", "Prefer not to say"]

/// Three-step profile setup. Editing an existing profile starts on step 1 with the values filled in.
struct CreateProfileScreen: View {
    var editing: Bool = false
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var step = 1
    @State private var name = ""
    @State private var bio = ""
    @State private var area = ""
    @State private var homeAt: LatLng?
    @State private var gender = ""
    @State private var interests: [String] = []
    @State private var loaded = false
    @State private var saving = false

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(onBack: backAction)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        progress
                        switch step {
                        case 1: stepName
                        case 2: stepPlace
                        default: stepAbout
                        }
                    }.padding(20)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .onAppear(perform: prefill)
        .onChange(of: session.hereLabel) { _, _ in adoptHere() }
        .onChange(of: session.hereKnown) { _, _ in adoptHere() }
    }

    /// Step back arrows move between steps; on step 1 only the edit screen (pushed on the main stack) has a way out.
    private var backAction: (() -> Void)? {
        if step > 1 { return { step -= 1 } }
        return editing ? { router.pop() } : nil
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { i in
                Capsule().fill(i <= step ? BucksColor.primary : BucksColor.surfaceContainerHigh).frame(height: 4)
            }
        }.padding(.bottom, 20)
    }

    private var stepName: some View {
        VStack(alignment: .leading, spacing: 0) {
            Headline(editing ? "Edit your profile" : "What should we call you?")
            Muted("This is what people and providers nearby see.").padding(.top, 8).padding(.bottom, 24)
            Avatar(initials: name.trimmingCharacters(in: .whitespaces).isEmpty ? "?" : initials(name), size: 84)
                .frame(maxWidth: .infinity).padding(.bottom, 20)
            BucksField($name, label: "Full name", placeholder: "e.g. Deepa Nair")
            PrimaryButton("Continue") {
                if name.trimmingCharacters(in: .whitespaces).isEmpty { session.toast("Add your name") } else { step = 2 }
            }
        }
    }

    private var stepPlace: some View {
        VStack(alignment: .leading, spacing: 0) {
            Headline("Where are you based?")
            Muted("Used for distance, ride pick-ups and who can recommend you. Only your area is shown, never your address.").padding(.top, 8).padding(.bottom, 24)
            LocationPicker(current: area, fix: session.hereKnown ? session.here : nil, fixLabel: session.hereLabel) { label, at in
                area = label; homeAt = at
            }
            FieldLabel("Gender (optional)").padding(.top, 20)
            ChipRow(genderOptions, selected: gender.isEmpty ? nil : gender) { gender = $0 }
            PrimaryButton("Continue") {
                if area.isEmpty { session.toast("Choose where you're based") } else { step = 3 }
            }.padding(.top, 24)
        }
    }

    private var stepAbout: some View {
        VStack(alignment: .leading, spacing: 0) {
            Headline("A little about you")
            Muted("Your reputation starts at zero and grows with reviews. Interests only shape what you see in Discover.").padding(.top, 8).padding(.bottom, 24)
            BucksField($bio, label: "One line about you (optional)", placeholder: "Product designer, biriyani enthusiast")
            FieldLabel("Interests")
            FlowChips(interestOptions, selected: Set(interests)) { i in
                if let at = interests.firstIndex(of: i) { interests.remove(at: at) } else { interests.append(i) }
            }
            PrimaryButton(editing ? "Save changes" : "Finish", enabled: !saving) { finish() }.padding(.top, 24)
        }
    }

    private func finish() {
        saving = true
        let home = homeAt ?? (!editing && session.hereKnown ? session.here : nil)
        let n = name.trimmingCharacters(in: .whitespaces), b = bio.trimmingCharacters(in: .whitespaces)
        Task {
            await session.createProfile(name: n, area: area, bio: b, gender: gender, interests: interests, home: home)
            saving = false
            if editing { router.pop() }
        }
    }

    private func prefill() {
        guard !loaded else { return }
        loaded = true
        if let u = session.user {
            name = u.name; bio = u.bio; area = u.area; gender = u.gender; interests = u.interests
        }
        if editing, let m = session.me {
            if name.isEmpty { name = m.name }
            if bio.isEmpty { bio = m.bio }
            if area.isEmpty { area = m.area }
        }
        adoptHere()
    }

    /// First time through, offer the phone's area until the person picks one.
    private func adoptHere() {
        guard !editing, area.isEmpty, homeAt == nil, session.hereKnown, let a = areaOf(session.hereLabel) else { return }
        area = a; homeAt = session.here
    }
}
