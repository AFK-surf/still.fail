// The `accounts` and `workspaces` topics: who is signed in, and which
// workspaces each account reaches (web/src/cloud/accounts.ts, web/src/cloud/api.ts).
package fail.still.android.data

import fail.still.android.ui.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable data class Account(val sub: String, val email: String, val name: String = "", val picture: String = "")

@Serializable data class WorkspaceSummary(val id: String, val name: String, val role: String = "", val stations: Int = 0, val members: Int = 0)

@Serializable data class AccountWorkspaces(
    val account: Account,
    val workspaces: List<WorkspaceSummary> = emptyList(),
    /** Invitations waiting for this account's email. */
    val invitations: List<PendingInvitation> = emptyList(),
    /** The account's `/v1/me` has answered; until then (or after a failure) an empty list says nothing. */
    val loaded: Boolean = false,
    /** still.fail cloud lets this account use the beta apps (its `/v1/me` says `user.beta`). */
    val beta: Boolean = false,
    /** In the beta app, an account still.fail cloud has not let into the beta: what to say (the core's), with a way out. */
    val blocked: String? = null,
    /** Set when this account could not be read. */
    val error: JsonElement? = null,
)

@Serializable data class PendingInvitation(val id: String, val workspace: String = "", val name: String = "", val role: String = "member", val inviter: String = "")

val ROLE_LABEL get() = mapOf("owner" to "Owner", "admin" to t("android-misc.role.admin"), "member" to t("android-misc.role.member"))

/** A workspace with the account it is reached through. */
data class WorkspaceEntry(val workspace: WorkspaceSummary, val account: Account)

fun List<AccountWorkspaces>.entries(): List<WorkspaceEntry> = flatMap { a -> a.workspaces.map { WorkspaceEntry(it, a.account) } }.distinctBy { it.workspace.id }

val ROLE_HINT get() = mapOf("owner" to t("android-misc.role.owner.hint"), "admin" to t("android-misc.role.admin.hint"), "member" to t("android-misc.role.member.hint"))

@Serializable data class Member(val email: String, val name: String = "", val sub: String = "", val picture: String? = null, val role: String = "member")

@Serializable data class WorkspaceStation(val id: String, val name: String = "")

/** An invitation not accepted yet; `time` has its expiry in words (the core's). */
@Serializable data class Invitation(val id: String, val role: String = "member", val email: String? = null, val time: Map<String, Stamp>? = null)

/** An email added to a workspace whose account has not signed in yet: a member from its first sign-in on (cloud/src/types.ts → AddedView). */
@Serializable data class Added(val email: String, val role: String = "member", @SerialName("added_by") val addedBy: String = "")

/**
 * The `workspace` topic: the viewer's role in it, its members (to name people by their email, and to manage them), its
 * stations' names, the emails added but not signed in yet, the invitations not accepted yet, and its own relays (used
 * besides still.fail's; none from a cloud from before them).
 */
@Serializable data class WorkspaceView(
    val id: String, val name: String = "", val role: String = "member", val members: List<Member> = emptyList(),
    val stations: List<WorkspaceStation> = emptyList(), val invitations: List<Invitation> = emptyList(),
    val added: List<Added> = emptyList(), val relays: List<String> = emptyList(),
) {
    val manager get() = role == "owner" || role == "admin"
}

/** Where an account is signed in to still.fail (the `loginSessions` topic); `time` has when, in words. */
@Serializable data class LoginSession(val id: String, val name: String = "", val current: Boolean = false, val time: Map<String, Stamp>? = null)

/** What adding people by email came to: who joined at once, who joins at their first sign-in, who was in already. */
class AddedMembers(val joined: List<String>, val added: List<String>, val already: List<String>)

/** A person of a Slack workspace a station's connects are in, by their email there (GET /slack/people). */
@Serializable data class SlackPerson(val email: String, val name: String = "", val image: String? = null, val guest: Boolean = false, val team: String? = null)
