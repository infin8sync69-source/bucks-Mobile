import Foundation
import Testing
@testable import BucksCore

/// The category catalogue and picker rules (Android Categories.kt) and the service a category maps to (Android serviceForCategory).
struct CategoriesTests {
    @Test func cleanCategoryTidiesAndChecksWhatTheOwnerTyped() {
        #expect(cleanCategory("  juice   bar ") == "Juice bar")
        #expect(cleanCategory("rangoli\tclasses\n") == "Rangoli classes")
        #expect(cleanCategory("ab") == "Ab")
        #expect(cleanCategory("Pan & Co. (new), 24+7-ok/x") == "Pan & Co. (new), 24+7-ok/x")
        #expect(cleanCategory("o'neil") == "O'neil")
        #expect(cleanCategory("ünique shop") == "Ünique shop")
        #expect(cleanCategory("a") == nil)
        #expect(cleanCategory("   ") == nil)
        #expect(cleanCategory("") == nil)
        #expect(cleanCategory(String(repeating: "a", count: 40)) == String(repeating: "a", count: 40).prefix(1).uppercased() + String(repeating: "a", count: 39))
        #expect(cleanCategory(String(repeating: "a", count: 41)) == nil)
        #expect(cleanCategory("Bad <tag>") == nil)
        #expect(cleanCategory("Cafe 😀") == nil)
        #expect(cleanCategory("a_b") == nil)
    }

    @Test func theCataloguesHaveNoDuplicatesAndEveryTypeIsAValidCategory() {
        for groups in [businessCategoryGroups, skillCategoryGroups] {
            let all = groups.flatMap(\.items)
            #expect(Set(all.map { $0.lowercased() }).count == all.count)
            #expect(Set(groups.map(\.name)).count == groups.count)
            for i in all { #expect(cleanCategory(i) == i) }
        }
        #expect(businessCategoryGroups.first?.name == "Food and drink")
        #expect(businessCategoryGroups.flatMap(\.items).contains("Property owner"))
        #expect(!businessCategoryGroups.flatMap(\.items).contains("Pharmacy"))
        #expect(skillCategoryGroups.first?.name == "IT and software")
        #expect(skillCategoryGroups.flatMap(\.items).contains("Plumber"))
    }

    @Test func serviceFollowsTheCategory() {
        for c in ["Restaurant", "bakery", "Catering", " Ice Cream ", "juice bar", "Street food", "FOOD TRUCK"] { #expect(serviceForCategory(c) == "FOOD") }
        for c in ["Grocery", "Dairy", "Kirana", "Organic store", "organic Store"] { #expect(serviceForCategory(c) == "GROCERY") }
        #expect(serviceForCategory("Vegetables") == "VEGETABLES"); #expect(serviceForCategory("Fruits") == "VEGETABLES")
        #expect(serviceForCategory("Fish") == "MEAT"); #expect(serviceForCategory("Eggs") == "MEAT")
        #expect(serviceForCategory("Property owner") == "PROPERTIES"); #expect(serviceForCategory("Builder") == "PROPERTIES")
        #expect(serviceForCategory("Electronics") == "SHOPPING"); #expect(serviceForCategory("Dental clinic") == "SHOPPING")
        #expect(serviceForCategory("Something nobody listed") == "SHOPPING"); #expect(serviceForCategory("") == "SHOPPING"); #expect(serviceForCategory(nil) == "SHOPPING")
    }

    @Test func pickerListsEverythingWhileTheSearchIsEmpty() {
        let m = CategoryPickerModel(kind: "BUSINESS", others: [], query: "")
        #expect(m.groups == businessCategoryGroups)
        #expect(m.own == nil); #expect(!m.offersOwn)
        let s = CategoryPickerModel(kind: "SKILL", others: [], query: "  ")
        #expect(s.groups == skillCategoryGroups)
    }

    @Test func othersAreAddedAfterTheBuiltInGroupsMinusWhatIsAlreadyBuiltIn() {
        let m = CategoryPickerModel(kind: "BUSINESS", others: ["Bakery", "Rangoli classes", "rangoli classes", "KIRANA"], query: "")
        #expect(m.groups.count == businessCategoryGroups.count + 1)
        #expect(m.groups.last == CategoryGroup("Added by others", ["Rangoli classes"]))
        let none = CategoryPickerModel(kind: "BUSINESS", others: ["bakery"], query: "")
        #expect(none.groups == businessCategoryGroups)
    }

    @Test func typingFiltersAndOffersTheOwnCategoryWhenItIsNotInTheList() {
        let m = CategoryPickerModel(kind: "BUSINESS", others: ["Rangoli classes"], query: "rangoli")
        #expect(m.groups == [CategoryGroup("Added by others", ["Rangoli classes"])])
        #expect(m.own == "Rangoli"); #expect(!m.exact); #expect(m.offersOwn)

        let exact = CategoryPickerModel(kind: "BUSINESS", others: [], query: "BAKERY")
        #expect(exact.groups.first == CategoryGroup("Food and drink", ["Bakery"]))
        #expect(exact.exact); #expect(!exact.offersOwn)

        let skill = CategoryPickerModel(kind: "SKILL", others: [], query: "plumb")
        #expect(skill.groups == [CategoryGroup("Home services", ["Plumber"])])
        #expect(skill.offersOwn)

        let short = CategoryPickerModel(kind: "BUSINESS", others: [], query: "q")
        #expect(short.own == nil); #expect(!short.offersOwn)
        let nothing = CategoryPickerModel(kind: "BUSINESS", others: [], query: "zzzzzz")
        #expect(nothing.groups.isEmpty); #expect(nothing.own == "Zzzzzz"); #expect(nothing.offersOwn)
        let bad = CategoryPickerModel(kind: "BUSINESS", others: [], query: "zz<>")
        #expect(bad.groups.isEmpty); #expect(bad.own == nil)
    }
}
