# Categories for businesses and skills

- Creating or editing a business or skill opens one searchable picker: about 140 business types and 110 skills grouped by field (IT and digital, education, community and non-profit, health, home services, and more).
- Not in the list? Type it and tap "Use “…” as my category". It is saved as free text on the listing, is searchable like any other, and appears under "Added by others" for the next owner (`category_suggestions`).
- The separate "Service" step is gone. The service (Food, Grocery, Fresh, Meat, Shopping, Properties) is derived from the category (`service_for_category` on the server, `serviceForCategory` in `ui/Services.kt`); anything unknown is Shopping. A live listing keeps its service but its category can be renamed.
- Rules for a custom category: 2 to 40 characters of letters, digits and & / , ' . ( ) + -.
- Not done: tags beyond the one category, admin merge of duplicate custom categories, organisation as its own kind.
