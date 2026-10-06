// Names of the choices the app offers: fixed words, not worked out from any data (what data says in words is the
// core's, client/core-ts/src/present.ts and format.ts). As web/src/format.ts.
package fail.still.android.data


val RUNTIME_LABEL = mapOf("claude" to "Claude Code", "codex" to "Codex")

/** How a connect's conversations become sessions, in words (web/src/format.ts → MODE). */
val MODE_LABEL get() = mapOf("multi-session" to t("android-misc.mode.multi"), "single-session" to t("android-misc.mode.single"))
val MODE_TEXT get() = mapOf(
    "multi-session" to t("android-misc.mode.multi.text"),
    "single-session" to t("android-misc.mode.single.text"),
)

/** How a profile reaches its model service, in a word (web/src/format.ts → ACCESS). */
val ACCESS_LABEL get() = mapOf("subscription" to t("android-misc.access.subscription"), "opencode-go" to "OpenCode Go", "anthropic-api" to "Anthropic API", "api-provider" to t("common.provider.title"), "env" to t("android-misc.access.env"))
/** The kinds that run on a key (web/src/format.ts → KEYED). */
val KEYED = setOf("opencode-go", "anthropic-api", "api-provider")
