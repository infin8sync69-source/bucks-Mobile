package com.bucks.app.data

import android.content.Context
import android.provider.ContactsContract
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** One person from the phone's own address book. Read on this phone and shown to its owner only; nothing here is uploaded. */
data class PhoneContact(val id: Long, val name: String, val phones: List<String>, val emails: List<String>, val org: String, val title: String, val address: String) {
    val initials: String get() = name.split(" ").filter { it.isNotBlank() }.take(2).joinToString("") { it.first().uppercase() }.ifBlank { "#" }
    /** Everything searchable about the contact, lower-cased once. */
    val haystack: String = (listOf(name, org, title, address) + phones + emails).joinToString("\n").lowercase()
    val digits: List<String> = phones.map { p -> p.filter { it.isDigit() } }
}

object PhoneContacts {
    /** Reads the address book: name, numbers, emails, organisation, job title and address. Needs READ_CONTACTS. Sorted by name. */
    suspend fun load(ctx: Context): List<PhoneContact> = withContext(Dispatchers.IO) {
        val D = ContactsContract.Data.CONTENT_URI
        val mimes = arrayOf(ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE, ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE,
            ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE, ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE)
        class Acc(val name: String) { val phones = LinkedHashMap<String, String>(); val emails = LinkedHashSet<String>(); var org = ""; var title = ""; var address = "" }
        val by = LinkedHashMap<Long, Acc>()
        runCatching {
            ctx.contentResolver.query(D, arrayOf(ContactsContract.Data.CONTACT_ID, ContactsContract.Data.DISPLAY_NAME, ContactsContract.Data.MIMETYPE, ContactsContract.Data.DATA1, ContactsContract.Data.DATA4),
                "${ContactsContract.Data.MIMETYPE} IN (?,?,?,?)", mimes, "${ContactsContract.Data.DISPLAY_NAME} COLLATE NOCASE ASC")?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0); val a = by.getOrPut(id) { Acc(c.getString(1)?.trim().orEmpty()) }; val v = c.getString(3)?.trim().orEmpty()
                    if (v.isBlank()) continue
                    when (c.getString(2)) {
                        ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE -> a.phones.putIfAbsent(v.filter { it.isDigit() }.takeLast(10).ifBlank { v }, v)
                        ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE -> a.emails.add(v)
                        ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE -> { if (a.org.isBlank()) a.org = v; if (a.title.isBlank()) a.title = c.getString(4)?.trim().orEmpty() }
                        ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE -> if (a.address.isBlank()) a.address = v.replace('\n', ' ')
                    }
                }
            }
        }
        by.map { (id, a) -> PhoneContact(id, a.name.ifBlank { a.phones.values.firstOrNull() ?: a.emails.firstOrNull() ?: "Unknown" }, a.phones.values.toList(), a.emails.toList(), a.org, a.title, a.address) }
            .filter { it.phones.isNotEmpty() || it.emails.isNotEmpty() }
            .sortedBy { it.name.lowercase() }
    }

    /** The number as a dialable +91 number when it looks like a 10-digit Indian mobile, else as typed. */
    fun dialable(p: String): String { val d = p.filter { it.isDigit() }; return when { d.length == 10 -> "+91$d"; d.length == 12 && d.startsWith("91") -> "+$d"; p.trim().startsWith("+") -> "+$d"; else -> d } }
}
