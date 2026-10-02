// Names of the choices forms offer: fixed words, not worked out from any data (what data says in words is the core's,
// client/core/src/present.rs and format.rs). Read as they are shown (getters), in the language then.
import type { AccessKind, ConnectMode, RuntimeKind } from "./api.ts";
import { t } from "./i18n.ts";

export const MODE: Record<ConnectMode, { label: string; description: string }> = {
  "multi-session": { get label() { return t("web-main.mode.multi.label"); }, get description() { return t("web-main.mode.multi.description"); } },
  "single-session": { get label() { return t("web-main.mode.single.label"); }, get description() { return t("web-main.mode.single.description"); } },
};

export const RUNTIME_LABEL: Record<RuntimeKind, string> = { claude: "Claude Code", codex: "Codex" };

export const ACCESS: Record<AccessKind, { label: string; description: string }> = {
  "subscription": { get label() { return t("web-main.access.subscription.label"); }, get description() { return t("web-main.access.subscription.description"); } },
  "opencode-go": { label: "OpenCode Go", get description() { return t("web-main.access.opencodeGo.description"); } },
  "anthropic-api": { label: "Anthropic API", get description() { return t("web-main.access.anthropicApi.description"); } },
  "api-provider": { get label() { return t("common.provider.title"); }, get description() { return t("common.provider.lead"); } },
  "env": { get label() { return t("web-main.access.env.label"); }, get description() { return t("web-main.access.env.description"); } },
};

export const KEYED = new Set<AccessKind>(["opencode-go", "anthropic-api", "api-provider"]);
