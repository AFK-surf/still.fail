// Names of the choices the app offers: fixed words, not worked out from any data (what data says in words is the
// core's, client/core/src/present.rs and format.rs). As web/src/format.ts.
package fail.still.android.data

import fail.still.android.ui.t

val RUNTIME_LABEL = mapOf("claude" to "Claude Code", "codex" to "Codex")

/** How a connect's conversations become sessions, in words (web/src/format.ts → MODE). */
val MODE_LABEL get() = mapOf("multi-session" to t("android-misc.mode.multi"), "single-session" to t("android-misc.mode.single"))
val MODE_TEXT get() = mapOf(
    "multi-session" to t("android-misc.mode.multi.text"),
    "single-session" to t("android-misc.mode.single.text"),
)

/** How a profile reaches its model service, in a word (web/src/format.ts → ACCESS). */
val ACCESS_LABEL get() = mapOf("subscription" to t("android-misc.access.subscription"), "opencode-go" to "OpenCode Go", "anthropic-api" to "Anthropic API", "env" to t("android-misc.access.env"))
/** The kinds that run on a key (web/src/format.ts → KEYED). */
val KEYED = setOf("opencode-go", "anthropic-api")

/** A kind of profile to add: how it reaches its service, the runtime it runs (null: any), in words (web/src/pages/Accounts.tsx → CHOICES). */
class ProfileChoice(val kind: String, val runtime: String?, val title: String, val description: String)
val PROFILE_CHOICES get() = listOf(
    ProfileChoice("subscription", "claude", t("android-misc.choice.claude"), t("android-misc.choice.claude.text")),
    ProfileChoice("subscription", "codex", t("android-misc.choice.chatgpt"), t("android-misc.choice.chatgpt.text")),
    ProfileChoice("opencode-go", null, "OpenCode Go", t("android-misc.choice.opencode.text")),
    ProfileChoice("anthropic-api", null, "Anthropic API", t("android-misc.choice.anthropic.text")),
    ProfileChoice("env", "claude", t("android-misc.choice.env", "runtime" to "Claude Code"), t("android-misc.choice.env.text")),
    ProfileChoice("env", "codex", t("android-misc.choice.env", "runtime" to "Codex"), t("android-misc.choice.env.text")),
)
