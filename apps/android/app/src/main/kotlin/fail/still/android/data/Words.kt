// Names of the choices the app offers: fixed words, not worked out from any data (what data says in words is the
// core's, client/core/src/present.rs and format.rs). As web/src/format.ts.
package fail.still.android.data

val RUNTIME_LABEL = mapOf("claude" to "Claude Code", "codex" to "Codex")

/** How a connect's conversations become sessions, in words (web/src/format.ts → MODE). */
val MODE_LABEL = mapOf("multi-session" to "每个 thread 一个会话", "single-session" to "所有 thread 共用一个会话")
val MODE_TEXT = mapOf(
    "multi-session" to "在 thread 里 @ 它就开一个新会话，thread 里的后续消息都进这个会话。",
    "single-session" to "它看到的所有 thread 进同一个会话，适合一个长期值守的助手。",
)

/** How a profile reaches its model service, in a word (web/src/format.ts → ACCESS). */
val ACCESS_LABEL = mapOf("subscription" to "订阅账号", "opencode-go" to "OpenCode Go", "anthropic-api" to "Anthropic API", "env" to "自定义环境变量")
/** The kinds that run on a key (web/src/format.ts → KEYED). */
val KEYED = setOf("opencode-go", "anthropic-api")

/** A kind of profile to add: how it reaches its service, the runtime it runs (null: any), in words (web/src/pages/Accounts.tsx → CHOICES). */
class ProfileChoice(val kind: String, val runtime: String?, val title: String, val description: String)
val PROFILE_CHOICES = listOf(
    ProfileChoice("subscription", "claude", "Claude 订阅", "Claude Pro / Max，跑 Claude Code。在浏览器里登录一次。"),
    ProfileChoice("subscription", "codex", "ChatGPT 订阅", "ChatGPT Plus / Pro，跑 Codex。用设备码登录一次。"),
    ProfileChoice("opencode-go", null, "OpenCode Go", "一个 key，Claude Code 和 Codex 都能用。"),
    ProfileChoice("anthropic-api", null, "Anthropic API", "Anthropic 的 API key，跑 Claude Code。"),
    ProfileChoice("env", "claude", "自定义环境变量（Claude Code）", "自己设置接模型服务的环境变量。"),
    ProfileChoice("env", "codex", "自定义环境变量（Codex）", "自己设置接模型服务的环境变量。"),
)
