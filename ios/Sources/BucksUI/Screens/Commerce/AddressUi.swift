import SwiftUI
import BucksCore

// Delivery addresses for shipped orders (AddressUi.kt): the card in the cart, the address book in a sheet, and the add / edit form.

/// The address a shipped order goes to: who, the number the courier calls, the lines, with a Change button.
struct AddressCard: View {
    let a: AddressRow?
    var onChange: () -> Void
    var body: some View {
        BucksCard(onTap: onChange) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill").foregroundStyle(BucksColor.primary)
                VStack(alignment: .leading, spacing: 0) {
                    if let a {
                        Text([a.name, a.label.isEmpty ? nil : a.label].compactMap { $0 }.joined(separator: " · ")).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted(a.oneLine)
                        Muted("Mobile \(a.phone)")
                    } else {
                        Text("Add a delivery address").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("Shops that ship need your name, number and full address.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(a == nil ? "Add" : "Change").bucks(.labelLarge).foregroundStyle(BucksColor.primary)
            }
        }
    }
}

/// The address book in a sheet: pick one for this order, edit or delete saved ones, or add a new one (pincode fills city and state).
/// Also the place to manage addresses on their own, so it works without a cart (`onPick` nil hides the radio buttons).
struct AddressSheet: View {
    let selectedId: String?
    var startNew = false
    var onPick: ((AddressRow) -> Void)?
    var onDismiss: () -> Void
    @Environment(AppSession.self) private var session
    @State private var editing: AddressRow?
    @State private var adding = false
    @State private var confirmDelete: AddressRow?

    private var commerce: CommerceStore { session.commerce }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if adding || editing != nil {
                    AddressForm(existing: editing, first: commerce.addresses.isEmpty, onCancel: { adding = false; editing = nil }) { saved in
                        commerce.saveAddress(saved) { r in
                            adding = false; editing = nil
                            if let onPick { onPick(r); onDismiss() }
                        }
                    }
                } else {
                    Text(onPick != nil ? "Deliver to" : "My addresses").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                    if !commerce.addressesLoaded { SkeletonLines(lines: 3).padding(.top, 16) }
                    else if commerce.addresses.isEmpty { Muted("No saved addresses yet.").padding(.top, 10) }
                    ForEach(commerce.addresses, id: \.self) { a in row(a) }
                    GhostButton("Add a new address") { adding = true }.padding(.top, 14)
                }
            }.padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { adding = startNew; commerce.loadAddresses() }
        .bucksConfirm(isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), title: "Delete this address?",
                      message: confirmDelete.map { "\($0.name), \($0.oneLine)" }, confirmTitle: "Delete", cancelTitle: "Keep", destructive: true) {
            if let id = confirmDelete?.id { commerce.deleteAddress(id) }
            confirmDelete = nil
        }
    }

    private func row(_ a: AddressRow) -> some View {
        let picked = a.id == selectedId
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    if let onPick { onPick(a); onDismiss() }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        if onPick != nil {
                            Image(systemName: picked ? "largecircle.fill.circle" : "circle").font(.system(size: 20)).foregroundStyle(picked ? BucksColor.primary : BucksColor.onSurfaceVariant).padding(.top, 2)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text([a.name, a.label.isEmpty ? nil : a.label, a.isDefault ? "Default" : nil].compactMap { $0 }.joined(separator: " · ")).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                            Muted(a.oneLine)
                            Muted("Mobile \(a.phone)")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(onPick == nil).accessibilityAddTraits(picked ? .isSelected : [])
                Button { editing = a } label: { Image(systemName: "pencil").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Edit address for \(a.name)")
                Button { confirmDelete = a } label: { Image(systemName: "trash").foregroundStyle(BucksColor.error).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Delete address for \(a.name)")
            }.padding(.top, 10)
            BucksDivider().padding(.top, 8)
        }
    }
}

/// Add or edit one address. Checks what the server checks (10-digit mobile, 6-digit pincode) and says what is wrong next to the field.
private struct AddressForm: View {
    let existing: AddressRow?
    let first: Bool
    var onCancel: () -> Void
    var onSave: (AddressRow) -> Void
    @State private var label = ""
    @State private var name = ""
    @State private var phone = ""
    @State private var pin = ""
    @State private var line1 = ""
    @State private var line2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var isDefault = false
    @State private var tried = false
    @State private var looking = false
    @State private var loaded = false

    private var phoneOk: Bool { phone.range(of: "^[6-9][0-9]{9}$", options: .regularExpression) != nil }
    private var pinOk: Bool { pin.range(of: "^[1-9][0-9]{5}$", options: .regularExpression) != nil }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && phoneOk && pinOk && line1.trimmingCharacters(in: .whitespaces).count >= 3
            && !city.trimmingCharacters(in: .whitespaces).isEmpty && !state.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existing == nil ? "New address" : "Edit address").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
            FieldLabel("Save as").padding(.top, 12)
            HStack(spacing: 8) { ForEach(["Home", "Work", "Other"], id: \.self) { l in BucksChip(l, selected: label == l) { label = label == l ? "" : l } } }
            Spacer().frame(height: 12)
            BucksField(Binding(get: { name }, set: { name = String($0.prefix(80)) }), label: "Full name", placeholder: "Who receives it")
            if tried && name.trimmingCharacters(in: .whitespaces).isEmpty { hint("Enter the name of the person receiving it.") }
            BucksField(Binding(get: { phone }, set: { phone = String($0.filter(\.isNumber).prefix(10)) }), label: "Mobile number", placeholder: "10 digits, the courier may call it", keyboard: .phone)
            if tried && !phoneOk { hint("Enter a 10-digit mobile number starting with 6, 7, 8 or 9.") }
            BucksField(Binding(get: { pin }, set: { pin = String($0.filter(\.isNumber).prefix(6)) }), label: "Pincode", placeholder: "6 digits", keyboard: .number)
            if looking { hint("Looking up the city…") } else if tried && !pinOk { hint("Enter a 6-digit pincode.") }
            BucksField(Binding(get: { line1 }, set: { line1 = String($0.prefix(150)) }), label: "House or flat number and street", placeholder: "e.g. 12, 4th Cross, MG Road")
            if tried && line1.trimmingCharacters(in: .whitespaces).count < 3 { hint("Enter the house or flat number and street.") }
            BucksField(Binding(get: { line2 }, set: { line2 = String($0.prefix(150)) }), label: "Area or landmark (optional)", placeholder: "e.g. near the park")
            HStack(spacing: 10) {
                BucksField(Binding(get: { city }, set: { city = String($0.prefix(60)) }), label: "City")
                BucksField(Binding(get: { state }, set: { state = String($0.prefix(60)) }), label: "State")
            }
            Toggle("Make this my default address", isOn: $isDefault).font(.bucks(.bodyLarge)).tint(BucksColor.primary).frame(minHeight: 48)
            HStack(spacing: 10) {
                GhostButton("Cancel", action: onCancel)
                PrimaryButton("Save address") {
                    tried = true
                    guard valid else { return }
                    onSave(AddressRow(id: existing?.id, label: label, name: name.trimmingCharacters(in: .whitespaces), phone: phone, line1: line1.trimmingCharacters(in: .whitespaces),
                                      line2: line2.trimmingCharacters(in: .whitespaces), city: city.trimmingCharacters(in: .whitespaces), state: state.trimmingCharacters(in: .whitespaces),
                                      pincode: pin, isDefault: isDefault))
                }
            }.padding(.top, 12)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing { label = e.label; name = e.name; phone = e.phone; pin = e.pincode; line1 = e.line1; line2 = e.line2; city = e.city; state = e.state; isDefault = e.isDefault }
            else { isDefault = first }
        }
        // A full pincode fills the city and state (the person can still change them).
        .task(id: pin) {
            guard pin.count == 6, existing?.pincode != pin else { return }
            looking = true
            if let r = await Pincode.lookup(pin), !Task.isCancelled { city = r.city; state = r.state }
            looking = false
        }
    }

    private func hint(_ s: String) -> some View { Muted(s).padding(.bottom, 8) }
}
