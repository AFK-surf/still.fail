// What the app has done, through the core's calls by name (docs/client-core.md → Calls; client/core/src/ops.rs), as
// the web pages do (web/src/api.ts → stationApi). The app never makes a request itself: the core knows the request
// and brings the topics it touches up to date before it answers; nothing here keeps a cache.
package fail.still.android.data

import android.util.Base64
import fail.still.android.BuildConfig
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray


/** The admin API of one station, by what each call does. */
class StationApi(private val core: StillFailCore, val station: String) {
    private val ops = StationOperations { name, params -> core.call(name, JsonObject(params + ("station" to JsonPrimitive(station)))) }
    private suspend fun op(name: String, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {}): JsonElement =
        core.call(name, buildJsonObject { fill(); put("station", station) })

    private suspend fun chat(call: String, thread: Long, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {}) =
        core.call(call, buildJsonObject { put("station", station); put("thread", thread); fill() })

    /** Sends to the chat: the message shows at once from the view's outbox, and leaves it once the station has it. */
    suspend fun send(thread: Long, text: String, attachments: List<Attachment> = emptyList(), quotes: List<Quote> = emptyList()) {
        chat("chat.send", thread) {
            put("text", text)
            put("attachments", StillFailJson.encodeToJsonElement(ListSerializer(Attachment.serializer()), attachments))
            put("quotes", StillFailJson.encodeToJsonElement(ListSerializer(Quote.serializer()), quotes))
        }
    }

    /** A failed message from the outbox: send it again, or drop it. */
    suspend fun retry(thread: Long, id: String) { chat("chat.retry", thread) { put("id", id) } }
    suspend fun discard(thread: Long, id: String) { chat("chat.discard", thread) { put("id", id) } }

    /** Brings the page before the chat's first loaded message into the view. */
    suspend fun older(thread: Long) { chat("chat.older", thread) }

    /** Brings the page after the chat's last loaded message into the view (it shows a window short of its end), as many
     *  going at its start; they are read, not said: none comes in with a motion. */
    suspend fun newer(thread: Long) { chat("chat.newer", thread) }

    /** The chat's latest page in place of what it shows: the reader goes to its end. */
    suspend fun latest(thread: Long) { chat("chat.latest", thread) }

    /** Where the reader leaves the chat: the message at the top of what shows and how far below the list's top its top
     *  is (`offset`, px), or none at its end (it opens there next, while nothing is unread). */
    suspend fun place(thread: Long, seq: Long?, offset: Double? = null) { chat("chat.place", thread) { seq?.let { put("seq", it) }; offset?.let { put("offset", it) } } }

    /** Brings the page of an agent's execution history before what it shows into the view. */
    suspend fun historyOlder(key: String) { core.call("history.older", buildJsonObject { put("station", station); put("key", key) }) }

    // ── connects (web/src/api.ts → stationApi) ──

    /** Changes a connect: any of `bind`, `mode`, `requireMention`, `enabled`, `slack`, `owner`. */
    suspend fun putConnect(id: String, body: JsonObject) { ops.connectPut(id = id) { this.input = body } }
    suspend fun deleteConnect(id: String) { ops.connectDelete(id = id) }
    suspend fun reconnect(id: String) { ops.connectReconnect(id = id) }
    /** A single-session connect's session: `session` null makes a new one (named `title`). */
    suspend fun bindSession(connect: String, session: String?, title: String) {
        ops.connectBindSession(connect = connect) { this.session = session; if (title.isNotBlank()) this.title = title }
    }
    /** Who the Slack tokens are (null with the errors when they do not work). */
    suspend fun verifySlack(connect: String?, install: String?, appToken: String, botToken: String): Pair<SlackIdentity?, List<String>> {
        val r = ops.slackVerify() { if (connect != null) this.connect = connect; if (install != null) this.install = install; this.appToken = appToken; this.botToken = botToken }.jsonObject
        val identity = r["identity"]?.takeIf { it !is JsonNull }?.let { decode(SlackIdentity.serializer(), it) }
        return identity to (r["errors"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList())
    }
    /** A Slack workspace's app configuration token (its refresh token); answers which workspace. */
    suspend fun addConfigToken(refreshToken: String): String =
        ops.slackAddConfigToken() { this.refreshToken = refreshToken }.jsonObject["teamId"]!!.jsonPrimitive.content
    /**
     * Makes a Slack app with still.fail's manifest in the workspace of `team`: its name and description, the rest as a new
     * app's. The station keeps it, waiting for its connect (the overview's `slackApps`); answers its app id.
     */
    suspend fun makeSlackApp(team: String, name: String, description: String): String =
        ops.slackMakeApp() { this.team = team
            this.settings = buildJsonObject {
                put("name", name); put("displayName", name); put("description", description); put("longDescription", ""); put("backgroundColor", "#F3E3D3")
                put("groups", buildJsonObject { SLACK_GROUPS.forEach { put(it, true) } })
            } }.jsonObject["appId"]!!.jsonPrimitive.content
    /** Drops an app made here from the waiting ones; it stays in Slack. */
    suspend fun dropSlackApp(appId: String) { ops.slackDropApp(appId = appId) }
    /** The people of the Slack workspaces this station's connects are in, once each by email, and what could not be read. */
    suspend fun slackPeople(): Pair<List<SlackPerson>, List<String>> {
        val r = ops.slackPeople().jsonObject
        val people = r["people"]?.takeIf { it !is JsonNull }?.let { decode(ListSerializer(SlackPerson.serializer()), it) } ?: emptyList()
        return people to (r["errors"]?.takeIf { it !is JsonNull }?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList())
    }
    /** Where to make a Slack app by hand from still.fail's manifest. */
    suspend fun createAppUrl(name: String): String =
        ops.slackCreateAppUrl(name = name).jsonObject["url"]!!.jsonPrimitive.content
    /** A new connect; answers its id. */
    suspend fun createConnect(body: JsonObject): String = ops.connectCreate() { this.input = body }.jsonObject["id"]!!.jsonPrimitive.content

    // ── profiles ──

    /** Changes a profile: any of `name`, `access`, `env`, `models`. */
    suspend fun putProfile(id: String, body: JsonObject) { ops.profilePut(id = id) { this.input = body } }
    suspend fun deleteProfile(id: String) { ops.profileDelete(id = id) }
    suspend fun refreshQuota(id: String) { ops.profileQuota(id = id) }
    suspend fun startLogin(profile: String) { ops.profileLogin(id = profile) }
    suspend fun cancelLogin(profile: String) { ops.profileCancelLogin(id = profile) }
    suspend fun loginCode(profile: String, code: String) { ops.profileLoginCode(id = profile) { this.code = code } }
    /** A subscription signed in before its profile exists: the station makes the profile when it succeeds. Answers the login's id. */
    suspend fun newLogin(runtime: String): String = ops.loginNew() { this.runtime = runtime }.jsonObject["id"]!!.jsonPrimitive.content
    suspend fun newLoginCode(id: String, code: String) { ops.loginCode(id = id) { this.code = code } }
    suspend fun dropLogin(id: String) { ops.loginDrop(id = id) }
    /** A keyed (or variables) profile, made only once its key is checked; answers its id. */
    suspend fun addProfile(runtime: String?, kind: String, key: String?): String = ops.profileAdd() { if (runtime != null) this.runtime = runtime
        this.access = buildJsonObject { put("kind", kind); if (key != null) put("key", key) } }.jsonObject["id"]!!.jsonPrimitive.content
    /** A profile on the machine's own login of `runtime` (one kept in a file); answers its id. */
    suspend fun useMachineLogin(runtime: String): String =
        ops.profileUseMachineLogin() { this.runtime = runtime }.jsonObject["id"]!!.jsonPrimitive.content

    /** Starts the session's runtime ahead of a message. */
    suspend fun warm(key: String) { ops.sessionWarm(key = key) }

    suspend fun stop(key: String) { ops.sessionStop(key = key) }

    /**
     * How it runs from its next turn on: a model, how hard it thinks, and who runs it (a profile kept to by hand, or
     * null: the station's pick).
     */
    suspend fun sessionSettings(key: String, model: String, effort: String?, profile: String?) {
        ops.sessionSettings(key = key) { this.model = model; this.effort = effort; this.profile = profile }
    }

    /** Releases an idle agent's process. */
    suspend fun evict(key: String) { ops.sessionEvict(key = key) }

    /** A new chat: its session and its thread, made before its first message so files can go into it. */
    suspend fun newChat(runtime: String, model: String, effort: String?): Pair<String, Long> =
        ops.sessionNew() { this.runtime = runtime; this.model = model
            if (effort != null) this.effort = effort }.jsonObject.let { it["key"]!!.jsonPrimitive.content to it["thread"]!!.jsonObject["id"]!!.jsonPrimitive.long }

    /** The chat of an agent that has none yet, bound to its session; answers the thread. */
    suspend fun chatFor(session: String): Long =
        ops.chatForSession() { this.session = session }.jsonObject["id"]!!.jsonPrimitive.long

    /** Checks a profile, which lists the models it can use. */
    suspend fun checkProfile(id: String) { ops.profileCheck(id = id) }

    /** "这是我" (bound) or "不是我" on a Slack user: the station takes them for the viewer, or no longer. */
    suspend fun slackIdentity(user: String, bound: Boolean) { ops.slackIdentity(user = user) { this.bound = bound } }

    /** Replaces a profile's enabled models. */
    suspend fun setModels(profile: String, models: List<String>) {
        ops.profilePut(id = profile) { this.input = buildJsonObject { putJsonArray("models") { models.forEach { add(JsonPrimitive(it)) } } } }
    }

    /** Puts a file on the station, in no chat yet; a message that sends it takes it into its chat. */
    suspend fun upload(name: String, bytes: ByteArray, width: Long?, height: Long?): Attachment {
        val encoded = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { Base64.encodeToString(bytes, Base64.NO_WRAP) }
        val saved = decode(Attachment.serializer(), core.call("station.upload", buildJsonObject {
            put("station", station); put("name", name); put("bytes", encoded)
        }))
        // An image's size travels with it, so every page can hold its place before it loads.
        return if (width != null && height != null) saved.copy(width = width, height = height) else saved
    }

    /** A file sent to the session. */
    suspend fun file(key: String, name: String): ByteArray {
        val answer = core.call("station.file", buildJsonObject { put("station", station); put("key", key); put("name", name) }).jsonObject
        return kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { Base64.decode(answer["bytes"]!!.jsonPrimitive.content, Base64.DEFAULT) }
    }

    /**
     * A file sent to the session, and its type as the station says (web/src/api.ts → file). `thumb`: an image as a chat
     * shows it (its thumbnail, where the station keeps one; an older station answers the image itself). `onProgress`:
     * the bytes so far and the whole size (null when the station does not say) as a whole file comes.
     */
    suspend fun file(key: String, name: String, thumb: Boolean, onProgress: ((Long, Long?) -> Unit)? = null): Pair<String, ByteArray> {
        val params = buildJsonObject {
            put("station", station); put("key", key); put("name", name)
            if (thumb) put("thumb", true)
            if (onProgress != null) put("progress", true)
        }
        val answer = (if (onProgress == null) core.call("station.file", params) else core.call("station.file", params) { got ->
            val o = got as? JsonObject
            val loaded = (o?.get("loaded") as? JsonPrimitive)?.content?.toLongOrNull()
            if (loaded != null) onProgress(loaded, (o["total"] as? JsonPrimitive)?.content?.toLongOrNull())
        }).jsonObject
        val type = (answer["type"] as? JsonPrimitive)?.content ?: ""
        return type to kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { Base64.decode(answer["bytes"]!!.jsonPrimitive.content, Base64.DEFAULT) }
    }

    /** What a visualization's widget kept (widget.state; null when nothing, or an older station that keeps nothing). */
    suspend fun widgetState(key: String, path: String): JsonElement? =
        ops.widgetState(key = key, path = path).jsonObject["state"]?.takeIf { it !is JsonNull }
    /** Keeps what a visualization's widget asks to keep (widget.setState), for the next time it is shown. */
    suspend fun setWidgetState(key: String, path: String, state: JsonElement) {
        ops.widgetSetState(key = key) { this.path = path; this.state = state }
    }

    // ── background jobs and web services (web/src/Jobs.tsx) ──

    // A job and its output are topics (Topics.job, Topics.jobLog): the core reads them again while shown.
    /** Stops a job from the app (its agent is told who did). */
    suspend fun stopJob(id: String) { ops.jobStop(id = id) }
    /** Clears a session's ended jobs (stopped, failed, ended by itself) off its pages, as the station keeps them. */
    suspend fun clearEndedJobs(session: String) { ops.jobClearEnded(session = session) }

    // ── decisions (client/core/src/decisions.rs) ──

    /** Answers a decision with one of its options: the viewer's message in its chat, the label quoting the post. */
    suspend fun answerDecision(thread: Long, seq: Long, option: String) {
        op("decision.answer") { put("thread", thread); put("seq", seq); put("option", option) }
    }
    /** Answers a card with the chat composer's text, attachments and quotes, also quoting the post that asked. */
    suspend fun replyDecision(thread: Long, seq: Long, text: String, attachments: List<Attachment> = emptyList(), quotes: List<Quote> = emptyList()) {
        op("decision.reply") {
            put("thread", thread); put("seq", seq); put("text", text)
            put("attachments", StillFailJson.encodeToJsonElement(ListSerializer(Attachment.serializer()), attachments))
            put("quotes", StillFailJson.encodeToJsonElement(ListSerializer(Quote.serializer()), quotes))
        }
    }
    /** Sets a decision aside on this device (待定): last on the decisions page, still pending; nothing is sent. */
    suspend fun deferDecision(thread: Long, seq: Long) { op("decision.defer") { put("thread", thread); put("seq", seq) } }
    /** Dismisses a decision for the viewer, on every device of theirs: off their list, still pending for others. */
    suspend fun keepChat(thread: Long) { ops.chatKeep(thread) }
    suspend fun dismissDecision(thread: Long, seq: Long) { ops.decisionDismiss(thread, seq) }

    // ── the archive (web/src/pages/Archive.tsx) ──

    /** A chat into the archive or back: its thread (with its session when it is that session's own), or an agent with no chat yet. */
    suspend fun setArchived(thread: Long?, session: String, archived: Boolean) {
        ops.chatArchive(session = session) { if (thread != null) this.thread = thread; this.archived = archived }
    }
    /** Keeps a chat at the top of the viewer's list, or lets it go (by its item's id, its session's key). */
    suspend fun setPinned(session: String, pinned: Boolean) { ops.chatPin(session = session) { this.pinned = pinned } }
    /** Deletes a session for good: its chat, its history and its workspace directory. */
    suspend fun deleteSession(key: String) { ops.sessionDelete(key = key) }

    // ── what a chat runs on, chosen (client/core/src/choose.rs; web/src/pick.ts) ──

    /**
     * A new chat, there at once, made with what is picked on this station (web/src/NewChat.tsx → useEnsureChat): the
     * core has its page, its row and what is sent to it under the key it answers (the station makes it behind it, told
     * that key as `clientKey`, so its row is known for this one's, never guessed).
     */
    suspend fun createNewChat(): String =
        core.call("newChat.create", buildJsonObject { put("station", station) }).jsonObject["key"]!!.jsonPrimitive.content
    /** Picks in a model control's panel (`of`: new, session:<key>, …; null: the default, the station's pick); `open`: from what it runs on now again. */
    suspend fun pickSet(of: String, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit) {
        core.call("pick.set", buildJsonObject { put("station", station); put("of", of); fill() })
    }
    /** What the panel picked becomes what it runs on (nothing changed: nothing done). */
    suspend fun pickSave(of: String) { core.call("pick.save", buildJsonObject { put("station", station); put("of", of) }) }

    // ── the machine's own sessions (web/src/MachineSessions.tsx) ──

    /** Sessions the machine's own Claude Code and Codex kept (in a terminal); a station from before them fails it. */
    suspend fun machineSessions(): List<MachineSession> =
        decode(ListSerializer(MachineSession.serializer()), ops.machineSessionsList().jsonObject["sessions"] ?: JsonArray(emptyList()))
    /** One of them to look at first: what was said in it (the latest `limit`), and how many there are in all. */
    suspend fun machineSession(runtime: String, id: String, limit: Int = 200): Pair<List<MachineSaid>, Long> {
        val r = ops.machineSessionsRead(runtime = runtime, id = id) { this.limit = limit.toLong() }.jsonObject
        val said = decode(ListSerializer(MachineSaid.serializer()), r["said"] ?: JsonArray(emptyList()))
        return said to (r["total"]?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong() ?: said.size.toLong())
    }
    /** A chat going on with one of them (the one already going on with it, if any); answers its key. */
    suspend fun continueMachineSession(runtime: String, id: String): String =
        ops.machineSessionsContinue() { this.runtime = runtime; this.id = id }.jsonObject["key"]!!.jsonPrimitive.content

    // ── the station's software, its memory, Slack apps (web/src/api.ts → stationApi) ──

    /** Updates the station or a runtime (`id`: station | claude | codex), or installs a runtime not there; the overview says how it goes. */
    suspend fun updateSoftware(id: String) { ops.softwareUpdate() { this.id = id } }
    /** Reads again what versions are out. */
    suspend fun checkSoftware() { ops.softwareCheck() }
    /** Puts the station on a channel (`stable` | `beta`); its versions are read again. */
    suspend fun setSoftwareChannel(channel: String) { ops.softwareChannel() { this.channel = channel } }
    /** Turns the station's updating by itself on or off; turned on, it reads what is out and updates at once. */
    suspend fun setSoftwareAuto(on: Boolean) { ops.softwareAuto { this.on = on } }
    /** The agents' memory on the station: the global one and the skills (projects' memories among them), as they are. */
    suspend fun memory(): JsonElement = ops.memoryGet()
    /**
     * Writes what changed of a connect's Slack app (any of name, displayName, description, longDescription,
     * backgroundColor, groups; `icon`: a data URL) into its manifest; answers whether Slack wants its new permissions
     * approved, and why the icon did not go up.
     */
    suspend fun putSlackApp(connect: String, input: JsonObject): JsonObject = ops.connectPutSlackApp(connect = connect) { this.input = input }.jsonObject
    /** A Slack app made with its settings as a whole (and its icon, a data URL); answers its app id and why the icon did not go up. */
    suspend fun makeSlackApp(team: String, settings: JsonObject, icon: String?): Pair<String, String?> {
        val r = ops.slackMakeApp() { this.team = team; this.settings = settings; if (icon != null) this.icon = icon }.jsonObject
        return r["appId"]!!.jsonPrimitive.content to r["iconError"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content
    }
    /** Forgets the viewer's configuration token of a Slack workspace. */
    suspend fun removeConfigToken(team: String) { ops.slackRemoveConfigToken(team = team) }
    /** Hands Slack's install code to the station that made the app; answers the workspace it went into. */
    suspend fun slackInstalled(code: String, state: String): String? =
        ops.slackInstalled() { this.code = code; this.state = state }.jsonObject["team"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content

    // ── a chat itself (web/src/api.ts → rename; chats made here, by their key) ──

    /** Sends to a chat by its key (one made here, made by its station or not): it waits in the chat until it can go. */
    suspend fun sendIn(session: String, text: String, attachments: List<Attachment> = emptyList(), quotes: List<Quote> = emptyList()) {
        op("chat.send") {
            put("session", session); put("text", text)
            put("attachments", StillFailJson.encodeToJsonElement(ListSerializer(Attachment.serializer()), attachments))
            put("quotes", StillFailJson.encodeToJsonElement(ListSerializer(Quote.serializer()), quotes))
        }
    }
    /** A failed message of such a chat, by its key: sent again, or dropped. */
    suspend fun retryIn(session: String, id: String) { op("chat.retry") { put("session", session); put("id", id) } }
    suspend fun discardIn(session: String, id: String) { op("chat.discard") { put("session", session); put("id", id) } }
    /** A chat named by hand; an empty name: named by its first message again. */
    suspend fun rename(thread: Long?, session: String, title: String) {
        ops.chatRename() { this.session = session; if (thread != null) this.thread = thread; this.title = title }
    }
}

/** A session the station's machine kept (its own Claude Code or Codex, in a terminal); `session`: the chat going on with it. */
@kotlinx.serialization.Serializable
data class MachineSession(
    val runtime: String,
    val id: String,
    val cwd: String,
    val title: String? = null,
    val first: String? = null,
    val model: String? = null,
    val updatedAt: Long,
    val session: String? = null,
    /** Its runtime, where it ran (the home directory as ~) and how long ago, in a line (the core's). */
    val meta: String? = null,
)

/** Something said in one of them: by the person, else by its agent; when, in ms. */
@kotlinx.serialization.Serializable
data class MachineSaid(val person: Boolean, val text: String, val at: Long? = null)

object Auth {
    // stillfail:// since the rename; the app still accepts ember:// coming back (MainActivity), and the cloud both.
    // The beta app's own scheme (app/build.gradle.kts), so the released app never takes its sign-in, nor it theirs.
    val REDIRECT = if (BuildConfig.BETA) "stillfail-beta://auth/callback" else "stillfail://auth/callback"

    /** The URL to open in a Custom Tab; still.fail cloud comes back to REDIRECT. The device signs in by the name the core gives it. */
    suspend fun begin(core: StillFailCore): String =
        core.call("auth.begin", buildJsonObject { put("redirect_uri", REDIRECT); put("return_to", "/") })
            .jsonObject["url"]!!.jsonPrimitive.content

    /** Finishes a sign-in with the callback's query string ("?code=…&state=…"). */
    suspend fun complete(core: StillFailCore, query: String) {
        core.call("auth.complete", buildJsonObject { put("query", query) })
    }

    suspend fun signOut(core: StillFailCore, account: String) {
        core.call("auth.signOut", buildJsonObject { put("account", account) })
    }
}

/** still.fail cloud's account API: what the app has done there, by name, done by the core as one of the signed-in accounts (web/src/cloud/api.ts). */
class Cloud(private val core: StillFailCore, private val account: String) {
    private val ops = CloudOperations { name, params -> core.call(name, JsonObject(params + ("account" to JsonPrimitive(account)))) }
    private suspend fun op(name: String, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {}): JsonElement =
        core.call(name, buildJsonObject { fill(); put("account", account) })

    /** `code`: an invite code, for an account not let in yet (still.fail is invite-only). Answers the new workspace's id. */
    suspend fun createWorkspace(name: String, code: String): String =
        ops.workspaceCreate() { this.name = name; if (code.isNotEmpty()) this.invite_code = code }.jsonObject["id"]!!.jsonPrimitive.content

    /** Answers the workspace joined. */
    suspend fun acceptInvitation(id: String): String = ops.invitationAccept() { this.id = id }.jsonObject["id"]!!.jsonPrimitive.content

    suspend fun declineInvitation(id: String) { ops.invitationDecline(id = id) }

    suspend fun renameWorkspace(workspace: String, name: String) { ops.workspaceRename(workspace = workspace) { this.name = name } }
    suspend fun deleteWorkspace(workspace: String) { ops.workspaceDelete(workspace = workspace) }
    /** Leaving a workspace is removing oneself. */
    suspend fun removeMember(workspace: String, member: String) { ops.workspaceRemoveMember(workspace = workspace, member = member) }
    suspend fun setRole(workspace: String, member: String, role: String) { ops.workspaceSetRole(workspace = workspace, member = member) { this.role = role } }
    /** Adds people by email: members at once, or from their first sign-in; no invitation to accept. */
    suspend fun addMembers(workspace: String, role: String, emails: List<String>): AddedMembers {
        val r = ops.workspaceAddMembers(workspace = workspace) { this.role = role; this.emails = emails }.jsonObject
        val list = { key: String -> r[key]?.takeIf { it !is JsonNull }?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList() }
        return AddedMembers(list("joined"), list("added"), list("already"))
    }
    /** An email added and not signed in yet, taken off. */
    suspend fun removeAdded(workspace: String, email: String) { ops.workspaceRemoveAdded(workspace = workspace, email = email) }
    suspend fun revokeInvitation(workspace: String, invitation: String) { ops.workspaceRevokeInvitation(workspace = workspace, invitation = invitation) }
    /** A one-time token for a machine to join as a station: the installer's command, and the command for a machine that has ember. */
    suspend fun enroll(workspace: String, name: String): Enrollment =
        ops.workspaceEnroll(workspace = workspace) { this.name = name }.jsonObject.let {
            Enrollment(it["install"]!!.jsonPrimitive.content, it["command"]!!.jsonPrimitive.content)
        }
    suspend fun renameStation(workspace: String, station: String, name: String) { ops.workspaceRenameStation(workspace = workspace, station = station) { this.name = name } }
    suspend fun removeStation(workspace: String, station: String) { ops.workspaceRemoveStation(workspace = workspace, station = station) }
    suspend fun revokeLoginSession(id: String) { ops.loginSessionRevoke(id = id) }
    /** What an invitation link leads to, for the account looking: the workspace, the role, who invited, whose email it is for. */
    suspend fun previewInvitation(token: String): InvitationPreview =
        decode(InvitationPreview.serializer(), ops.invitationPreview() { this.token = token })
    /** Accepts an invitation by its link's token; answers the workspace joined. */
    suspend fun acceptInvitationToken(token: String): String = ops.invitationAccept() { this.token = token }.jsonObject["id"]!!.jsonPrimitive.content
}

@kotlinx.serialization.Serializable
data class InvitationPreview(val workspace: String, val name: String, val role: String = "member", val inviter: String = "", val email: String? = null)

class Enrollment(val install: String, val command: String)

/** The permission groups a new Slack app is made with (web/src/pages/SlackApp.tsx → GROUPS), all on. */
private val SLACK_GROUPS = listOf("base", "public", "dm", "customize", "files", "reactions", "channels", "people", "extras", "canvases", "lists", "topics", "usergroups", "search", "connect", "more")

// still.fail cloud's invite-code errors in Chinese; the core passes their codes through.
private val INVITE_ERRORS = mapOf(
    "invite_code_required" to "新建 workspace 要有邀请码，被邀请加入别人的 workspace 不用",
    "invite_code_invalid" to "这个邀请码不对，检查一下有没有输错",
    "invite_code_used" to "这个邀请码已经被用过了",
    "invite_code_expired" to "这个邀请码已经过期了",
)

/** Whether creating a workspace failed for want of a (good) invite code. */
fun needsInviteCode(e: CoreException?): Boolean = e != null && e.code in INVITE_ERRORS

// Its limits: what an account may create, and how many a workspace holds (web/src/cloud/api.ts LIMIT_ERRORS).
private val LIMIT_ERRORS = mapOf(
    "too_many_workspaces" to "一个账号最多新建 5 个 workspace",
    "too_many_members" to "一个 workspace 最多邀请 5 个人",
)

fun errorText(e: CoreException): String = INVITE_ERRORS[e.code] ?: LIMIT_ERRORS[e.code] ?: e.message
