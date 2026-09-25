package com.bucks.app.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import org.json.JSONObject

/**
 * Everything the UI reads goes through this interface. The fake implementation below keeps
 * data in memory so the app runs standalone; replace it with a networked/P2P implementation
 * later without touching the screens.
 */
interface BucksRepository {
    val providers: StateFlow<List<Provider>>
    val drivers: StateFlow<List<Driver>>
    val posts: StateFlow<List<Post>>
    val chats: StateFlow<List<Chat>>
    val people: StateFlow<List<Person>>
    val communities: StateFlow<List<Community>>

    fun search(query: String): List<Provider>
    fun addProvider(p: Provider)
    fun removeProvider(id: String)
    fun voteProvider(id: String, up: Boolean, who: String, comment: String, voterId: String = "", verified: Boolean = false, txnId: String = "", signature: String = "")
    /** Recompute distances from the user's real position. */
    fun updateDistances(me: LatLng)
    fun voteDriver(id: String, up: Boolean)
    fun setDriverOnline(id: String, online: Boolean)
    /** Swap in the live driver list from the server; distances are measured from [me]. */
    fun replaceDrivers(list: List<Driver>, me: LatLng)

    fun addPost(p: Post)
    fun votePost(id: String, delta: Int, prev: Int)
    fun addPostComment(id: String, who: String, text: String)

    fun openChat(name: String, role: String): String
    fun sendMessage(chatId: String, text: String, mine: Boolean, attachment: Attachment? = null)
    fun markRead(chatId: String)
    fun follow(personId: String, follow: Boolean)
    fun join(communityId: String, join: Boolean)

    /** Multi-device sync: a JSON snapshot of everything that belongs to this user. */
    fun exportSnapshot(session: Session?): String
    fun importSnapshot(json: String): Session?
    fun deviceId(): String

    fun loadSession(): Session?
    fun savedSession(): Session?
    fun saveCredentials(email: String, password: String)
    fun checkCredentials(email: String, password: String): Boolean
    fun hasCredentials(email: String): Boolean
    fun saveSession(s: Session)
    fun clearSession()
    /** Removes everything this user stored on the device: profile, credentials and device id. */
    fun deleteAccount()
}

data class Session(val user: User, val pro: ProProfile?, val businesses: List<Business>)

class FakeBucksRepository(private val context: Context) : BucksRepository {
    override val providers = MutableStateFlow(Seed.providers)
    override val drivers = MutableStateFlow(Seed.drivers)
    override val posts = MutableStateFlow(Seed.posts)
    override val chats = MutableStateFlow(Seed.chats)
    override val people = MutableStateFlow(Seed.people)
    override val communities = MutableStateFlow(Seed.communities)

    override fun search(query: String): List<Provider> {
        val q = query.lowercase().trim(); if (q.isBlank()) return emptyList()
        val words = q.split(Regex("\\s+"))
        return providers.value.filter { p -> words.any { w -> p.tags.any { it.contains(w) } || p.name.lowercase().contains(w) || p.category.lowercase().contains(w) } }
    }
    override fun removeProvider(id: String) = providers.update { l -> l.filterNot { it.id == id } }
    override fun addProvider(p: Provider) = providers.update { l -> l.filterNot { it.id == p.id } + p }
    override fun voteProvider(id: String, up: Boolean, who: String, comment: String, voterId: String, verified: Boolean, txnId: String, signature: String) = providers.update { list ->
        list.map { if (it.id == id) it.copy(up = it.up + if (up) 1 else 0, down = it.down + if (up) 0 else 1, comments = listOf(Comment(who, comment, if (up) 1 else -1, voterId, verified, txnId, signature)) + it.comments) else it }
    }
    override fun updateDistances(me: LatLng) {
        providers.update { l -> l.map { it.copy(distanceKm = Math.round(Geo.distanceKm(me, it.pos) * 10) / 10.0) } }
        drivers.update { l -> l.map { it.copy(distanceKm = Math.round(Geo.distanceKm(me, it.pos) * 10) / 10.0) } }
    }
    override fun voteDriver(id: String, up: Boolean) = drivers.update { l -> l.map { if (it.id == id) it.copy(up = it.up + if (up) 1 else 0, down = it.down + if (up) 0 else 1) else it } }
    override fun setDriverOnline(id: String, online: Boolean) = drivers.update { l -> l.map { if (it.id == id) it.copy(online = online) else it } }
    override fun replaceDrivers(list: List<Driver>, me: LatLng) { drivers.value = list.map { it.copy(distanceKm = Math.round(Geo.distanceKm(me, it.pos) * 10) / 10.0) } }

    override fun addPost(p: Post) = posts.update { listOf(p) + it }
    override fun votePost(id: String, delta: Int, prev: Int) = posts.update { l ->
        l.map { p -> if (p.id != id) p else {
            var up = p.up; var down = p.down
            if (prev == 1) up--; if (prev == -1) down--
            if (delta == 1) up++; if (delta == -1) down++
            p.copy(up = up, down = down)
        } }
    }
    override fun addPostComment(id: String, who: String, text: String) = posts.update { l -> l.map { if (it.id == id) it.copy(comments = it.comments + (who to text)) else it } }

    override fun openChat(name: String, role: String): String {
        val existing = chats.value.firstOrNull { it.who == name }
        if (existing != null) return existing.id
        val c = Chat("c${System.currentTimeMillis()}", name, role, listOf(ChatMessage(false, "Hi, this is $name. How can I help?")), 0, true)
        chats.update { listOf(c) + it }; return c.id
    }
    override fun sendMessage(chatId: String, text: String, mine: Boolean, attachment: Attachment?) = chats.update { l -> l.map { if (it.id == chatId) it.copy(messages = it.messages + ChatMessage(mine, text, attachment), unread = if (mine) it.unread else it.unread + 1) else it } }
    override fun follow(personId: String, follow: Boolean) = people.update { l -> l.map { if (it.id == personId) it.copy(following = follow) else it } }
    override fun join(communityId: String, join: Boolean) = communities.update { l -> l.map { if (it.id == communityId) it.copy(joined = join, members = it.members + if (join) 1 else -1) else it } }

    override fun deviceId(): String {
        val saved = prefs.getString("device", null)
        if (saved != null) return saved
        val id = "dev-" + java.util.UUID.randomUUID().toString().take(8)
        prefs.edit().putString("device", id).apply(); return id
    }
    override fun exportSnapshot(session: Session?): String {
        val j = JSONObject()
        j.put("version", 1); j.put("device", deviceId()); j.put("exportedAt", System.currentTimeMillis())
        session?.let { j.put("session", JSONObject(sessionJson(it))) }
        j.put("following", JSONArray(people.value.filter { it.following }.map { it.id }))
        j.put("joined", JSONArray(communities.value.filter { it.joined }.map { it.id }))
        return j.toString(2)
    }
    override fun importSnapshot(json: String): Session? = runCatching {
        val j = JSONObject(json)
        j.optJSONArray("following")?.let { a -> val ids = List(a.length()) { a.getString(it) }.toSet(); people.update { l -> l.map { it.copy(following = it.id in ids) } } }
        j.optJSONArray("joined")?.let { a -> val ids = List(a.length()) { a.getString(it) }.toSet(); communities.update { l -> l.map { it.copy(joined = it.id in ids) } } }
        j.optJSONObject("session")?.let { parseSession(it.toString()) }?.also { saveSession(it) }
    }.getOrNull()
    override fun markRead(chatId: String) = chats.update { l -> l.map { if (it.id == chatId) it.copy(unread = 0) else it } }

    // --- session persistence (SharedPreferences + JSON, no extra libraries) ---
    private val prefs get() = context.getSharedPreferences("bucks", Context.MODE_PRIVATE)
    override fun loadSession(): Session? = if (prefs.getBoolean("signedOut", false)) null else savedSession()
    /** The last profile saved on this device, even after signing out; used to restore it when the same phone or email signs in again. */
    override fun savedSession(): Session? = prefs.getString("session", null)?.let { parseSession(it) }
    private fun parseSession(raw: String): Session? {
        return runCatching {
            val j = JSONObject(raw); val u = j.getJSONObject("user")
            val user = User(u.getString("name"), u.getString("area"), u.optString("bio"), u.getString("phone"), u.optInt("up"), u.optInt("down"), u.optString("email"), u.optString("gender"), u.optJSONArray("interests")?.let { a -> List(a.length()) { a.getString(it) } } ?: emptyList(), u.optString("id"), u.optJSONArray("verified")?.let { a -> List(a.length()) { i -> VerificationLevel.entries.firstOrNull { it.name == a.getString(i) } }.filterNotNull().toSet() } ?: emptySet())
            fun vehicle(o: JSONObject) = Vehicle(VehicleKind.valueOf(o.getString("kind")), o.getString("model"), o.getString("plate"), o.optString("mode").let { m -> ListingMode.entries.firstOrNull { it.name == m } ?: ListingMode.TAXI }, o.optBoolean("verified", true), o.optInt("docs"))
            fun business(b: JSONObject): Business {
                val items = b.optJSONArray("items")?.let { a -> List(a.length()) { i -> a.getJSONObject(i).let { Item(it.getString("n"), it.getInt("p"), it.optString("t"), it.optString("d"), it.optString("g")) } } } ?: emptyList()
                return Business(b.getString("name"), b.getString("category"), Scope.valueOf(b.getString("scope")), items, b.optBoolean("online", true), b.optString("area"), b.optInt("followers"))
            }
            // Older sessions stored a single "vehicle", a plain "skills" name list and a single "biz"; both shapes are read.
            val pro = j.optJSONObject("pro")?.let { p ->
                val vehicles = p.optJSONArray("vehicles")?.let { a -> List(a.length()) { vehicle(a.getJSONObject(it)) } } ?: listOfNotNull(p.optJSONObject("vehicle")?.let { vehicle(it) })
                val skills = p.optJSONArray("skillList")?.let { a -> List(a.length()) { i -> a.getJSONObject(i).let { SkillListing(it.getString("name"), SkillLevel.valueOf(it.optString("level", "AMATEUR")), it.optInt("portfolio"), it.optBoolean("online", true)) } } }
                    ?: p.optJSONArray("skills")?.let { a -> List(a.length()) { SkillListing(a.getString(it)) } } ?: emptyList()
                ProProfile(vehicles, skills, p.optString("rate"), p.optString("active").ifBlank { null }, p.optString("upi"))
            }
            val businesses = j.optJSONArray("businesses")?.let { a -> List(a.length()) { business(a.getJSONObject(it)) } } ?: listOfNotNull(j.optJSONObject("biz")?.let { business(it) })
            Session(user, pro, businesses)
        }.getOrNull()
    }
    override fun saveSession(s: Session) { prefs.edit().putString("session", sessionJson(s)).putBoolean("signedOut", false).apply() }
    private fun sessionJson(s: Session): String {
        val j = JSONObject()
        j.put("user", JSONObject().apply { put("name", s.user.name); put("area", s.user.area); put("bio", s.user.bio); put("phone", s.user.phone); put("up", s.user.up); put("down", s.user.down); put("email", s.user.email); put("gender", s.user.gender); put("interests", JSONArray(s.user.interests)); put("id", s.user.id); put("verified", JSONArray(s.user.verified.map { it.name })) })
        s.pro?.let { p -> j.put("pro", JSONObject().apply {
            put("vehicles", JSONArray().apply { p.vehicles.forEach { v -> put(JSONObject().apply { put("kind", v.kind.name); put("model", v.model); put("plate", v.plate); put("mode", v.mode.name); put("verified", v.verified); put("docs", v.docs) }) } })
            put("skillList", JSONArray().apply { p.skillListings.forEach { k -> put(JSONObject().apply { put("name", k.name); put("level", k.level.name); put("portfolio", k.portfolio); put("online", k.online) }) } })
            put("rate", p.rate); put("upi", p.upiId); p.activeVehicle?.let { put("active", it) }
        }) }
        j.put("businesses", JSONArray().apply { s.businesses.forEach { b -> put(JSONObject().apply {
            put("name", b.name); put("category", b.category); put("scope", b.scope.name); put("online", b.online); put("area", b.area); put("followers", b.followers)
            put("items", JSONArray().apply { b.items.forEach { put(JSONObject().apply { put("n", it.name); put("p", it.price); put("t", it.tag); put("d", it.detail); put("g", it.group) }) } })
        }) } })
        return j.toString()
    }
    // Signing out keeps the profile on the device (it is the user's own data); it just stops auto sign-in until the same person verifies again.
    override fun clearSession() { prefs.edit().putBoolean("signedOut", true).apply() }
    override fun deleteAccount() { prefs.edit().clear().apply(); runCatching { Identity.deleteKey() } }
    // Prototype-grade credential store: hashed password per email. Replace with Firebase/your auth service.
    private fun hash(s: String) = java.security.MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
    override fun saveCredentials(email: String, password: String) { val j = JSONObject(prefs.getString("creds", "{}") ?: "{}"); j.put(email.lowercase(), hash(password)); prefs.edit().putString("creds", j.toString()).apply() }
    override fun checkCredentials(email: String, password: String): Boolean = JSONObject(prefs.getString("creds", "{}") ?: "{}").optString(email.lowercase()) == hash(password)
    override fun hasCredentials(email: String): Boolean = JSONObject(prefs.getString("creds", "{}") ?: "{}").has(email.lowercase())
}
