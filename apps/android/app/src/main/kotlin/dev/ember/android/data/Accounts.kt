// The `accounts` and `workspaces` topics: who is signed in, and which
// workspaces each account reaches (web/src/cloud/accounts.ts, web/src/cloud/api.ts).
package dev.ember.android.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable data class Account(val sub: String, val email: String, val name: String = "", val picture: String = "")

@Serializable data class WorkspaceSummary(val id: String, val name: String, val role: String = "", val stations: Int = 0, val members: Int = 0)

@Serializable data class AccountWorkspaces(
    val account: Account,
    val workspaces: List<WorkspaceSummary> = emptyList(),
    val invitations: List<JsonElement> = emptyList(),
    /** Set when this account could not be read. */
    val error: JsonElement? = null,
)

/** A workspace with the account it is reached through. */
data class WorkspaceEntry(val workspace: WorkspaceSummary, val account: Account)

fun List<AccountWorkspaces>.entries(): List<WorkspaceEntry> = flatMap { a -> a.workspaces.map { WorkspaceEntry(it, a.account) } }.distinctBy { it.workspace.id }

@Serializable data class Member(val email: String, val name: String = "")

@Serializable data class WorkspaceStation(val id: String, val name: String = "")

/** The `workspace` topic, as far as the app reads it: its members, to name people by their email, and its stations' names. */
@Serializable data class WorkspaceView(val id: String, val name: String = "", val members: List<Member> = emptyList(), val stations: List<WorkspaceStation> = emptyList())
