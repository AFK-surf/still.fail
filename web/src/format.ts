// Names of the choices forms offer: fixed words, not worked out from any data (what data says in words is the core's,
// client/core-ts/src/present.ts and format.ts). Read as they are shown (getters), in the language then.
import type { AccessKind, ConnectMode, RuntimeKind } from "./api.ts";
import { t } from "./i18n.ts";

export const MODE: Record<ConnectMode, { label: string; description: string }> = {
  "multi-session": { get label() { return t("web-main.mode.multi.label"); }, get description() { return t("web-main.mode.multi.description"); } },
  "single-session": { get label() { return t("web-main.mode.single.label"); }, get description() { return t("web-main.mode.single.description"); } },
};

/** A Feishu connect's: a group (or chat) is a conversation, not a thread (docs/feishu.md). */
const FEISHU_MODE: Record<ConnectMode, { label: string; description: string }> = {
  "multi-session": { get label() { return t("web-main.mode.feishu.multi.label"); }, get description() { return t("web-main.mode.feishu.multi.description"); } },
  "single-session": { get label() { return t("web-main.mode.feishu.single.label"); }, get description() { return t("web-main.mode.feishu.single.description"); } },
};

/** An X connect's: a post and the replies under it are a conversation (docs/x.md). */
const X_MODE: Record<ConnectMode, { label: string; description: string }> = {
  "multi-session": { get label() { return t("web-main.mode.x.multi.label"); }, get description() { return t("web-main.mode.x.multi.description"); } },
  "single-session": { get label() { return t("web-main.mode.x.single.label"); }, get description() { return t("web-main.mode.x.single.description"); } },
};

/** The modes as a connect of `kind` has them. */
export const modeOf = (kind: string | null | undefined) => (kind === "feishu" ? FEISHU_MODE : kind === "x" ? X_MODE : MODE);

/** A key of words that differ for a Feishu or X connect (its `.feishu` or `.x` twin) as `kind` has it. */
export const kindKey = (key: string, kind: string | null | undefined) => (kind === "feishu" || kind === "x" ? `${key}.${kind}` : key);

export const RUNTIME_LABEL: Record<RuntimeKind, string> = { claude: "Claude Code", codex: "Codex", dsh: "DeepSeek Harness", grok: "Grok Build", cursor: "Cursor", devin: "Devin", hermes: "Hermes Agent" };

export const ACCESS: Record<AccessKind, { label: string; description: string }> = {
  "subscription": { get label() { return t("web-main.access.subscription.label"); }, get description() { return t("web-main.access.subscription.description"); } },
  "opencode-go": { label: "OpenCode Go", get description() { return t("web-main.access.opencodeGo.description"); } },
  "anthropic-api": { label: "Anthropic API", get description() { return t("web-main.access.anthropicApi.description"); } },
  "api-provider": { get label() { return t("common.provider.title"); }, get description() { return t("common.provider.lead"); } },
  "env": { get label() { return t("web-main.access.env.label"); }, get description() { return t("web-main.access.env.description"); } },
};

export const KEYED = new Set<AccessKind>(["opencode-go", "anthropic-api", "api-provider"]);
