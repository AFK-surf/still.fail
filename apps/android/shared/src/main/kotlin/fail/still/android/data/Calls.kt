// What the app has done, through the core's calls by name (docs/client-core.md → Calls; client/core-ts/src/ops.ts), as
// the web pages do (web/src/api.ts → stationApi). The app never makes a request itself: the core knows the request
// and brings the topics it touches up to date before it answers; nothing here keeps a cache.
package fail.still.android.data

import fail.still.android.shared.BuildConfig
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
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray


/** The admin API of one station, by what each call does. */
/** The bytes of a file in one `station.upload.part` (web/src/api.ts UPLOAD_PART). */
private const val UPLOAD_PART = 4 * 1024 * 1024
/** How much of a part has come, as a part read with `progress` says while it comes. */
private fun partLoaded(heard: kotlinx.serialization.json.JsonElement): Long? =
    ((heard as? JsonObject)?.get("loaded") as? JsonPrimitive)?.content?.toDoubleOrNull()?.toLong()
/** How much of a part has gone, as a part sent with `progress` says while it goes. */
private fun partSent(heard: kotlinx.serialization.json.JsonElement): Long? =
    ((heard as? JsonObject)?.get("sent") as? JsonPrimitive)?.content?.toDoubleOrNull()?.toLong()

/** The bytes of a file in one `station.file.part`. */
private const val FILE_PART = 4 * 1024 * 1024
/** The most of a file of the drive one `drive.read` asks for (the station gives at most 8 MB). */
const val DRIVE_PART = 4 * 1024 * 1024

/** A part of a file of the drive (`drive.read`): its type, the whole file's size and when it last changed (null when the
 * station does not say), the bytes. */
class DriveRead(val type: String, val total: Long, val bytes: ByteArray, val mtime: Long? = null)

/** A part of a file written where it goes as it came (`stream`): its type, the whole file's size and when it last
 * changed (null when the station does not say), how many bytes came. */
class PartRead(val type: String, val total: Long, val mtime: Long?, val count: Long)

/**
 * The folders in one on the station (`drive.folders`), to pick one to lend: where, its parent (none at the top), the home,
 * the folders in it (`entries`; `folders`, their names alone, is all a station from before gives), the way there from the
 * home or the top (`crumbs`), and where folders usually are (`places`: the home, its own folders, the disks). Each says
 * whether the station may read it (macOS keeps some from a station it did not give full disk access).
 */
@kotlinx.serialization.Serializable
data class DriveFolders(
    val path: String, val parent: String? = null, val home: String = "", val folders: List<String> = emptyList(),
    val entries: List<PickFolder>? = null, val crumbs: List<DriveCrumb>? = null, val places: List<PickFolder> = emptyList(),
    /** The station may not list it (it answers so, with nothing in it; one from before refuses instead). */
    val unreadable: Boolean = false,
)

/** A folder to pick from: its name (a place's in the asker's words), where it is, whether the station may read it, whether it is a disk. */
@kotlinx.serialization.Serializable
data class PickFolder(val name: String, val path: String, val unreadable: Boolean = false, val disk: Boolean = false)

/** A step of the way to a folder: its name, where it is. */
@kotlinx.serialization.Serializable
data class DriveCrumb(val name: String, val path: String)

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

    /** Reads whole an execution history's step or thought shown in brief, as it is opened (its transcript entries). */
    suspend fun historyDetail(key: String, entries: List<Long>) {
        if (entries.isEmpty()) return
        core.call("history.detail", buildJsonObject { put("station", station); put("key", key); put("from", entries.min()); put("to", entries.max()) })
    }

    // ── connects (web/src/api.ts → stationApi) ──

    /** Changes a connect: any of `bind`, `mode`, `requireMention`, `enabled`, `slack`, `owner`. */
    suspend fun putConnect(id: String, body: JsonObject) { ops.connectPut(id = id) { this.input = body } }
    suspend fun deleteConnect(id: String) { ops.connectDelete(id = id) }
    suspend fun reconnect(id: String) { ops.connectReconnect(id = id) }
    /** A Feishu connect's App Secret replaced: its station verifies it first (failing, it says why), then reconnects. */
    suspend fun putFeishuSecret(id: String, appSecret: String) { ops.feishuPutSecret(id = id, appSecret = appSecret) }
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
    /** Shared with the workspace's other stations (`allow` null: every one), or no longer. */
    suspend fun shareProfile(id: String, on: Boolean, allow: List<String>?) { ops.profileShare(id = id) { this.on = on; if (allow != null) this.allow = allow } }
    /** A shared profile moved to another station (its subscription signed in there from then on). */
    suspend fun moveProfile(id: String, to: String) { ops.profileMove(id = id, to = to) }
    /** A skill shared with the workspace's other stations, or no longer. */
    suspend fun shareSkill(name: String, on: Boolean) { ops.skillShare(name = name) { this.on = on } }
    suspend fun resetQuota(id: String) { ops.profileResetQuota(id = id) }
    suspend fun refreshQuota(id: String) { ops.profileQuota(id = id) }
    suspend fun startLogin(profile: String) { ops.profileLogin(id = profile) }
    suspend fun cancelLogin(profile: String) { ops.profileCancelLogin(id = profile) }
    suspend fun loginCode(profile: String, code: String) { ops.profileLoginCode(id = profile) { this.code = code } }
    /** A subscription (or, `access` opencode-go, an OpenCode Console account) signed in before its profile exists: the
     *  station makes the profile when it succeeds. Answers the login's id. */
    suspend fun newLogin(runtime: String, access: String? = null): String = ops.loginNew() { this.runtime = runtime; if (access != null) this.access = access }.jsonObject["id"]!!.jsonPrimitive.content
    suspend fun newLoginCode(id: String, code: String) { ops.loginCode(id = id) { this.code = code } }
    suspend fun dropLogin(id: String) { ops.loginDrop(id = id) }
    /** A keyed (or variables) profile, made only once its key is checked; answers its id. */
    suspend fun addProfile(runtime: String?, kind: String, key: String?, provider: String? = null, endpoint: String? = null): String = ops.profileAdd() { if (runtime != null) this.runtime = runtime
        this.access = buildJsonObject { put("kind", kind); if (key != null) put("key", key); if (provider != null) put("provider", provider); if (endpoint != null) put("endpoint", endpoint) } }.jsonObject["id"]!!.jsonPrimitive.content
    /** A profile on the machine's own login of `runtime` (one kept in a file); answers its id. */
    /** Ends a login an agent started here (docs/remote-login.md): its command stopped, its card a line saying so. */
    suspend fun cancelMachineLogin(id: String) { ops.machineLoginCancel(id) }
    /** What a login's page gave (a code), sent to its command (`paste`). */
    suspend fun answerMachineLogin(id: String, text: String) { ops.machineLoginAnswer(id, text) }

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

    /** One model named by hand, added to those enabled (a provider that does not list its models). */
    suspend fun addModel(profile: String, model: String) { ops.profileAddModel(id = profile, model = model) }

    /**
     * Puts a file on the station, in no chat yet; a message that sends it takes it into its chat. It goes a part at a
     * time (`station.upload.part`, web/src/api.ts the same), read from `open` as it goes, so a big one is never all in
     * memory; `onProgress` hears how much of it the station has after each part.
     */
    suspend fun upload(name: String, size: Long, open: () -> java.io.InputStream, width: Long?, height: Long?, onProgress: (Long) -> Unit = {}): Attachment {
        val id = java.util.UUID.randomUUID().toString().replace("-", "")
        val saved = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            var input = open()
            var at = 0L
            try {
                var have = 0L
                var done: Attachment? = null
                // Said at once (nothing yet), then as each part goes.
                onProgress(0)
                while (done == null) {
                    // The station goes on from what it has: elsewhere than where the file was read to, read again from there.
                    if (at != have) { input.close(); input = open(); var left = have; while (left > 0) { val n = input.skip(left); if (n <= 0) throw java.io.IOException("short file"); left -= n }; at = have }
                    val part = ByteArray(minOf(UPLOAD_PART.toLong(), size - have).toInt())
                    var got = 0
                    while (got < part.size) { val n = input.read(part, got, part.size - got); if (n < 0) throw java.io.IOException("short file"); got += n }
                    at += got
                    val from = have
                    val told = core.call("station.upload.part", buildJsonObject {
                        put("station", station); put("id", id); put("name", name); put("size", size); put("offset", have); put("progress", true)
                    }, part) { heard -> partSent(heard)?.let { onProgress(from + it) } }.jsonObject
                    val file = told["file"]?.takeIf { it !is JsonNull }
                    if (file != null) { done = decode(Attachment.serializer(), file); onProgress(size); break }
                    val next = told["have"]?.jsonPrimitive?.long ?: (have + got)
                    // Nothing more: a part the station could not take.
                    if (next == have) throw CoreException("upload", t("android-chat.file.uploadFailed"), null)
                    have = next
                    onProgress(have)
                }
                done!!
            } finally { input.close() }
        }
        // An image's size travels with it, so every page can hold its place before it loads.
        return if (width != null && height != null) saved.copy(width = width, height = height) else saved
    }

    /**
     * A file of the station's drive put among its uploads, as one sent up would be (a folder: zipped there, `zip`), for a
     * message to send (`drive.stage`): the phone's Station 文件 switched to a file (StationFiles.kt).
     */
    suspend fun driveStage(root: String, path: String, zip: Boolean): Attachment =
        decode(Attachment.serializer(), ops.driveStage(root, path) { if (zip) this.zip = true })

    /**
     * A big file sent to the session, onto the disk at `into` a part at a time (`station.file.part`), never all in
     * memory; `onProgress` hears the bytes so far and the whole size (`size`, as its message says, until the station
     * says), at once and then as each part comes. What is already in `into` is gone on from. Throws `unsupported` from a
     * station from before parts.
     */
    suspend fun fileToDisk(key: String, name: String, into: java.io.File, size: Long, onProgress: (Long, Long) -> Unit = { _, _ -> }) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            java.io.FileOutputStream(into, true).use { out ->
                var at = into.length()
                var total = Long.MAX_VALUE
                onProgress(at, size)
                while (at < total) {
                    val from = at
                    val of = if (total == Long.MAX_VALUE) size else total
                    val got = partTo("station.file.part", buildJsonObject {
                        put("station", station); put("key", key); put("name", name); put("offset", at); put("length", FILE_PART)
                    }, out) { onProgress(from + it, of) }
                    total = if (got.total >= 0) got.total else total
                    if (got.count == 0L) break
                    at += got.count
                    onProgress(at, total)
                }
            }
        }
    }

    /** The first `length` bytes of a file sent to the session (`station.file.part`); throws `unsupported` from a station from before parts. */
    suspend fun fileHead(key: String, name: String, length: Int): ByteArray {
        val (_, bytes) = core.callBytes("station.file.part", buildJsonObject {
            put("station", station); put("key", key); put("name", name); put("offset", 0); put("length", length)
        })
        return bytes ?: ByteArray(0)
    }

    /** A video's poster as the station makes it (a small JPEG of its first frame); null when it has none. */
    suspend fun poster(key: String, name: String): ByteArray? {
        val (got, bytes) = core.callBytes("station.poster", buildJsonObject { put("station", station); put("key", key); put("name", name) })
        return if (got is JsonNull) null else bytes
    }

    /** A file sent to the session. */
    suspend fun file(key: String, name: String): ByteArray {
        return core.callBytes("station.file", buildJsonObject { put("station", station); put("key", key); put("name", name) }).second ?: ByteArray(0)
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
        val (answer, bytes) = if (onProgress == null) core.callBytes("station.file", params) else core.streamBytes("station.file", params) { got, _ ->
            val o = got as? JsonObject
            val loaded = (o?.get("loaded") as? JsonPrimitive)?.content?.toLongOrNull()
            if (loaded != null) onProgress(loaded, (o["total"] as? JsonPrimitive)?.content?.toLongOrNull())
        }
        val type = ((answer as? JsonObject)?.get("type") as? JsonPrimitive)?.content ?: ""
        return type to (bytes ?: ByteArray(0))
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

    // ── decisions (client/core-ts/src/decisions.ts) ──

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
    /** A failure notice (its entry) sent to the still.fail team as a bug report: its number (FB-n), and whether it was sent before. */
    suspend fun reportNotice(thread: Long, seq: Long): Pair<Long?, Boolean> {
        val r = ops.chatReport(thread, seq) as? JsonObject
        return (r?.get("number") as? JsonPrimitive)?.longOrNull to ((r?.get("duplicate") as? JsonPrimitive)?.booleanOrNull == true)
    }

    // ── the archive (web/src/pages/Archive.tsx) ──

    /** A chat into the archive or back: its thread (with its session when it is that session's own), or an agent with no chat yet. */
    suspend fun setArchived(thread: Long?, session: String, archived: Boolean) {
        ops.chatArchive(session = session) { if (thread != null) this.thread = thread; this.archived = archived }
    }
    /** Keeps a chat at the top of the viewer's list, or lets it go (by its item's id, its session's key). */
    suspend fun setPinned(session: String, pinned: Boolean) { ops.chatPin(session = session) { this.pinned = pinned } }
    /** Shares a chat with the viewer's other workspaces ticked (none: no longer), their agents sending in it too when `write`. */
    suspend fun share(thread: Long?, session: String, to: List<String>, write: Boolean) {
        op("chat.xshare") {
            put("session", session)
            if (thread != null) put("thread", thread)
            putJsonArray("to") { to.forEach { add(JsonPrimitive(it)) } }
            put("write", write)
        }
    }
    /**
     * The chats of other workspaces a text written here refers to by its marks that are not shared with this station's
     * workspace yet (sending it would leave this workspace's agents unable to read them): docs/chat-share.md.
     */
    suspend fun outsideRefs(text: String): List<OutsideRef> =
        decode(OutsideRefs.serializer(), op("chat.outsideRefs") { put("text", text) }).chats
    /** What a public snapshot of the chat would hold now (nothing kept): its messages, what was hidden in them, its attachments. */
    suspend fun publishPreview(thread: Long): PublishPreview = decode(PublishPreview.serializer(), op("chat.publishPreview") { put("thread", thread) })
    /** Keeps a public snapshot of the chat up to `upto` (the preview's last message), with the attachments ticked: its link. */
    suspend fun publish(thread: Long, upto: Long, files: List<String>): ChatPublished =
        decode(ChatPublished.serializer(), op("chat.publish") { put("thread", thread); put("upto", upto); putJsonArray("files") { files.forEach { add(JsonPrimitive(it)) } } })
    /** Revokes one of the chat's public snapshots: its link opens nothing any more. */
    suspend fun unpublish(thread: Long, id: String) { op("chat.unpublish") { put("thread", thread); put("id", id) } }
    /** Shares this station's chat `id` with one workspace more (`workspace`), telling its station `prefer` first. */
    suspend fun shareInto(id: String, workspace: String, prefer: String?) {
        op("chat.xshareAdd") { put("id", id); put("workspace", workspace); prefer?.let { put("prefer", it) } }
    }
    /**
     * This station (by its address in its home workspace) added to `workspace` as it is (docs/multi-workspace.md):
     * answers what it is called there, null when the station does not say. A refusal comes in words.
     */
    suspend fun joinWorkspace(workspace: String): String? =
        ((op("station.join") { put("workspace", workspace) } as? JsonObject)?.get("joined") as? JsonObject)?.get("name")
            ?.let { it as? JsonPrimitive }?.takeIf { it.isString }?.content
    /** Deletes a session for good: its chat, its history and its workspace directory. */
    suspend fun deleteSession(key: String) { ops.sessionDelete(key = key) }

    // ── what a chat runs on, chosen (client/core-ts/src/choose.ts; web/src/pick.ts) ──

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
    /** The panel's picked model is another station's (its `borrow`): that station is asked to share its account with this one. */
    suspend fun pickBorrow(of: String) { core.call("pick.borrow", buildJsonObject { put("station", station); put("of", of) }) }

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

    /** Updates the station or a runtime (`id`: station | claude | codex | dsh | grok | cursor), or installs a runtime not there; the overview says how it goes. */
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

    // ── the station's drive (docs/drive.md) ──

    /** The folders the station lends its members, the whole list (the workspace's owners and admins). */
    suspend fun driveSetRoots(roots: List<String>) { ops.driveSetRoots(roots) }

    // ── what macOS lets a Mac station's still.fail Helper do (docs/remote-screens.md "Grants") ──

    /**
     * The helper's window for `grant` (a StationGrant's id) put up on the Mac. Answers whether the next step is the
     * Mac's screen from here: the window is up and that screen can be seen and driven.
     */
    suspend fun requestGrant(grant: String): Boolean {
        val r = ops.permissionsRequest(grant) as? JsonObject ?: return false
        return (r["window"] as? JsonPrimitive)?.content == "up" && (r["screen"] as? JsonPrimitive)?.content == "true"
    }
    /** The folders in `path` on the station (its home when null), to pick one to lend (owners and admins). */
    suspend fun driveFolders(path: String?): DriveFolders = decode(DriveFolders.serializer(), ops.driveFolders { if (path != null) this.path = path })
    suspend fun driveMkdir(root: String, path: String) { ops.driveMkdir(root, path) }
    suspend fun driveRename(root: String, from: String, to: String) { ops.driveRename(root, from, to) }
    /** To the machine's trash where the station has one (`permanent`: for good; `no_trash` where none takes it). */
    suspend fun driveRemove(root: String, path: String, permanent: Boolean = false) { ops.driveRemove(root, path) { if (permanent) this.permanent = true } }
    /** A folder zipped on the station to download: where the zip is (a root of its own and its path there), its name and size. */
    suspend fun driveZip(root: String, path: String): DriveZip = decode(DriveZip.serializer(), ops.driveZip(root, path))
    /** A folder read again, answering once it is (its page's refresh). */
    suspend fun driveRefresh(root: String, path: String) { core.call("drive.refresh", buildJsonObject { put("station", station); put("root", root); put("path", path) }) }
    /** Where a file was left on this device (a text's offset, a video's time in ms), of how much when known. */
    suspend fun drivePlace(root: String, path: String, at: Double, of: Double?) {
        core.call("drive.place", buildJsonObject { put("station", station); put("root", root); put("path", path); put("at", at); if (of != null) put("of", of) })
    }

    /**
     * A part read with `stream` (`station.file.part`, `drive.read`): its bytes written onto `out` as they come, beside the
     * core's values, never base64 in its answer (on a phone, a 4 MB part made base64, sent in JSON and read back took
     * longer than it took to come, and nothing came meanwhile: a bar that stood still between parts); `heard`: its bytes
     * so far. A total the station does not say is -1.
     */
    private suspend fun partTo(call: String, params: JsonObject, out: java.io.OutputStream, heard: ((Long) -> Unit)? = null): PartRead {
        var count = 0L
        var failed: java.io.IOException? = null
        val got = core.stream(call, buildJsonObject { params.forEach { (k, v) -> put(k, v) }; put("stream", true) }) { _, bytes ->
            if (bytes != null && failed == null) {
                try { out.write(bytes) } catch (e: java.io.IOException) { failed = e; return@stream }
                count += bytes.size
                heard?.invoke(count)
            }
        }.jsonObject
        failed?.let { throw it }
        val total = got["total"]?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong() ?: -1
        val mtime = (got["mtime"] as? JsonPrimitive)?.content?.toDoubleOrNull()?.toLong()
        return PartRead((got["type"] as? JsonPrimitive)?.content ?: "", total, mtime, count)
    }

    /** A part of a file of the drive (at most DRIVE_PART) written onto `out` as it comes, as [partTo] does. */
    suspend fun driveReadTo(root: String, path: String, offset: Long, length: Int, out: java.io.OutputStream, heard: ((Long) -> Unit)? = null): PartRead =
        partTo("drive.read", buildJsonObject {
            put("station", station); put("root", root); put("path", path); put("offset", offset); put("length", length.coerceAtMost(DRIVE_PART))
        }, out, heard).let { if (it.total >= 0) it else PartRead(it.type, offset + it.count, it.mtime, it.count) }

    /** A part of a file of the drive (at most DRIVE_PART), with the file's whole size as the station has it now; `heard`: its bytes so far, as they come. */
    suspend fun driveRead(root: String, path: String, offset: Long, length: Int, heard: ((Long) -> Unit)? = null): DriveRead {
        val params = buildJsonObject {
            put("station", station); put("root", root); put("path", path); put("offset", offset); put("length", length.coerceAtMost(DRIVE_PART))
            if (heard != null) put("progress", true)
        }
        val (answer, beside) = if (heard == null) core.callBytes("drive.read", params) else core.streamBytes("drive.read", params) { p, _ -> partLoaded(p)?.let(heard) }
        val got = answer.jsonObject
        val bytes = beside ?: ByteArray(0)
        val total = got["total"]?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong() ?: (offset + bytes.size)
        val mtime = (got["mtime"] as? JsonPrimitive)?.content?.toDoubleOrNull()?.toLong()
        return DriveRead((got["type"] as? JsonPrimitive)?.content ?: "", total, bytes, mtime)
    }

    /**
     * The first `limit` bytes of a file of the drive (the whole of it when shorter), a part at a time; `onProgress` hears
     * bytes so far and its size (`size`, as its folder said, until the station says), as each part comes.
     */
    suspend fun driveBytes(root: String, path: String, limit: Long = Long.MAX_VALUE, size: Long = Long.MAX_VALUE, onProgress: (Long, Long) -> Unit = { _, _ -> }): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        var at = 0L
        var total = Long.MAX_VALUE
        while (at < minOf(total, limit)) {
            val from = at
            val of = minOf(if (total == Long.MAX_VALUE) size else total, limit)
            val got = driveReadTo(root, path, at, minOf(DRIVE_PART.toLong(), minOf(total, limit) - at).toInt(), out, if (of == Long.MAX_VALUE) null else { n -> onProgress(from + n, of) })
            total = got.total
            if (got.count == 0L) break
            at += got.count
            onProgress(at, total)
        }
        return out.toByteArray()
    }

    /**
     * A file of the drive onto the phone's disk at `into`, a part at a time, never all in memory; what is in `into`
     * already is gone on from. `onProgress` as driveBytes's.
     */
    suspend fun driveToDisk(root: String, path: String, into: java.io.File, size: Long = Long.MAX_VALUE, onProgress: (Long, Long) -> Unit = { _, _ -> }) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { java.io.FileOutputStream(into, true) }.use { out ->
            var at = into.length()
            var total = Long.MAX_VALUE
            while (at < total) {
                val from = at
                val of = if (total == Long.MAX_VALUE) size else total
                val got = driveReadTo(root, path, at, DRIVE_PART, out, if (of == Long.MAX_VALUE) null else { n -> onProgress(from + n, of) })
                total = got.total
                if (got.count == 0L) break
                at += got.count
                onProgress(at, total)
            }
        }
    }

    /**
     * Puts a file into a folder of the drive (`path`: where it goes, under `root`), a part at a time (`drive.upload.part`,
     * as [upload] does for a chat), read from `open` as it goes; `onProgress` hears how much of it the station has. A
     * station that has a file of that name already refuses the first part with `exists`, unless `replace`. Once whole, the
     * core has read its folder again.
     */
    suspend fun driveUpload(root: String, path: String, size: Long, open: () -> java.io.InputStream, replace: Boolean = false, onProgress: (Long) -> Unit = {}) {
        val id = java.util.UUID.randomUUID().toString().replace("-", "")
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            var input = open()
            var at = 0L
            try {
                var have = 0L
                var done = false
                // Small first, doubling while parts go through (as DriveSource's reads): a name taken is told after a quarter
                // of a megabyte sent, not four.
                var planned = 256 * 1024
                while (!done) {
                    // The station goes on from what it has: elsewhere than where the file was read to, read again from there.
                    if (at != have) { input.close(); input = open(); var left = have; while (left > 0) { val n = input.skip(left); if (n <= 0) throw java.io.IOException("short file"); left -= n }; at = have }
                    val part = ByteArray(minOf(planned.toLong(), size - have).toInt())
                    var got = 0
                    while (got < part.size) { val n = input.read(part, got, part.size - got); if (n < 0) throw java.io.IOException("short file"); got += n }
                    at += got
                    val told = core.call("drive.upload.part", buildJsonObject {
                        put("station", station); put("root", root); put("path", path); put("id", id); put("offset", have); put("total", size)
                        if (replace) put("replace", true)
                    }, part).jsonObject
                    val entry = told["entry"]?.takeIf { it !is JsonNull }
                    val next = told["have"]?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong() ?: (have + got)
                    when {
                        // Whole and in its place.
                        entry != null -> done = true
                        // All of it there with no entry said (an empty file): the folder is read again all the same.
                        next >= size -> done = true
                        // Nothing more taken: a part the station could not take.
                        next == have -> throw CoreException("upload", t("android-chat.file.uploadFailed"), null)
                    }
                    planned = if (next == have + got) (planned * 2).coerceAtMost(UPLOAD_PART) else 256 * 1024
                    have = next
                    onProgress(if (done) size else have)
                }
            } finally { input.close() }
        }
    }

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

    /** Deletes the account in still.fail cloud, then forgets it here as signing out does; refused (`sole_owner`, said) while
     *  it is a workspace's only owner beside other members. */
    suspend fun deleteAccount(core: StillFailCore, account: String) {
        core.call("auth.deleteAccount", buildJsonObject { put("account", account) })
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
    /** Its icon and emoji together, as a station's (setStationMark); "" takes either away. */
    suspend fun setWorkspaceMark(workspace: String, emoji: String, icon: String) { ops.workspaceRename(workspace = workspace) { this.emoji = emoji; this.icon = icon } }
    /** The workspace's own relays, the whole list (cloud directory.ts setRelays). */
    suspend fun setRelays(workspace: String, relays: List<String>) { ops.workspaceSetRelays(workspace = workspace) { this.relays = relays } }
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
    /** "" takes it away. */
    /** Its icon and emoji together (web/src/stationPick.ts); "" takes either away. */
    suspend fun setStationMark(workspace: String, station: String, emoji: String, icon: String) { ops.workspaceRenameStation(workspace = workspace, station = station) { this.emoji = emoji; this.icon = icon } }
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

// still.fail cloud's invite-code errors in words; the core passes their codes through.
private val INVITE_ERRORS get() = mapOf(
    "invite_code_required" to t("android-misc.invite.codeRequired"),
    "invite_code_invalid" to t("android-misc.invite.codeInvalid"),
    "invite_code_used" to t("android-misc.invite.codeUsed"),
    "invite_code_expired" to t("android-misc.invite.codeExpired"),
)

/** Whether creating a workspace failed for want of a (good) invite code. */
fun needsInviteCode(e: CoreException?): Boolean = e != null && e.code in INVITE_ERRORS

// Its limits: what an account may create, and how many a workspace holds (web/src/cloud/api.ts LIMIT_ERRORS).
private val LIMIT_ERRORS get() = mapOf(
    "too_many_workspaces" to t("android-misc.limit.workspaces"),
    "too_many_members" to t("android-misc.limit.members"),
)

fun errorText(e: CoreException): String = INVITE_ERRORS[e.code] ?: LIMIT_ERRORS[e.code] ?: e.message

/** A chat of another workspace a text refers to (`chat.outsideRefs`): `may`, whether the viewer may share it (its starter, or an owner or admin there). */
@kotlinx.serialization.Serializable
data class OutsideRef(val station: String, val id: String, val title: String, val workspace: String, val workspaceName: String, val may: Boolean)

@kotlinx.serialization.Serializable
private class OutsideRefs(val chats: List<OutsideRef> = emptyList())

/** A folder zipped on the station (`drive.zip`): read as any file of the drive is, by its root and path. */
@kotlinx.serialization.Serializable
data class DriveZip(val root: String, val path: String, val name: String, val size: Long)
