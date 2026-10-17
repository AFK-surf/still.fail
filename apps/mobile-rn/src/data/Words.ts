// Names of the choices the app offers (data/Words.kt): fixed words, not worked out from any data (what data says in
// words is the core's, client/core-ts/src/present.ts and format.ts). As web/src/format.ts. The ones in words are read
// in the language now each time (getters), as the Kotlin's `get()`.
import { t } from "../i18n";

export const RUNTIME_LABEL: Record<string, string> = { claude: "Claude Code", codex: "Codex", dsh: "DeepSeek Harness" };

/** How a connect's conversations become sessions, in words (web/src/format.ts → MODE). */
export const MODE_LABEL: Record<string, string> = {
  get "multi-session"() { return t("android-misc.mode.multi"); },
  get "single-session"() { return t("android-misc.mode.single"); },
};
export const MODE_TEXT: Record<string, string> = {
  get "multi-session"() { return t("android-misc.mode.multi.text"); },
  get "single-session"() { return t("android-misc.mode.single.text"); },
};

/** How a profile reaches its model service, in a word (web/src/format.ts → ACCESS). */
export const ACCESS_LABEL: Record<string, string> = {
  get subscription() { return t("android-misc.access.subscription"); },
  "opencode-go": "OpenCode Go",
  "anthropic-api": "Anthropic API",
  get "api-provider"() { return t("common.provider.title"); },
  get env() { return t("android-misc.access.env"); },
};
/** The kinds that run on a key (web/src/format.ts → KEYED). */
export const KEYED: ReadonlySet<string> = new Set(["opencode-go", "anthropic-api", "api-provider"]);
