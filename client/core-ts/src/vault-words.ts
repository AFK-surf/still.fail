// What the pages say of the vault (docs/vault.md), for every client alike: an item's kind, how agents may ask for it and
// get it, its longest grant, an opened item's fields, the library's state at the settings' row. The web's vault.ts
// worked these out; the core's views (views/vault.ts) put them on its topics, and the web's stories use them as the
// core does. Self-contained (its only import the words) so that the web may import it as it is.
import { t } from "./i18n.ts";

const KIND_WORDS = ["token", "ssh_key", "login"];
const MODE_WORDS = ["proxy", "env", "ssh"];
const SCOPE_WORDS = ["once", "hour", "chat"];

/// A kind of item in a word (Token, SSH 密钥, 登录); "" for one not known.
export const kindText = (kind: unknown): string => (typeof kind === "string" && KIND_WORDS.includes(kind) ? t(`core-views.vault.kind.${kind}`) : "");
/// A way an agent is given it, in a word (代理, 环境变量, ssh-agent).
export const modeText = (mode: string): string => (MODE_WORDS.includes(mode) ? t(`core-views.vault.mode.${mode}`) : mode);
/// How an agent gets it, in a line: 代理 · 限 api.github.com; ssh-agent; 环境变量.
export function howText(mode: string, hosts: readonly string[]): string {
  const name = modeText(mode);
  return mode === "proxy" && hosts.length > 0 ? `${name} · ${t("core-views.vault.only_to", { hosts: hosts.join(", ") })}` : name;
}
/// The longest a grant of it lasts, in a word (仅一次, 1 小时, 直到对话归档): any but these, the chat.
export const lastsText = (lasts: unknown): string => t(`core-views.vault.lasts.${typeof lasts === "string" && SCOPE_WORDS.includes(lasts) ? lasts : "chat"}`);

/// An item's row's words: what kind it is; whether agents may ask for it and how (允许 agent 申请 · 代理 · api.github.com,
/// or 仅自己可见); its second line in a list (when it was last used, else that); how it is given, a line a way; its
/// longest grant (its own, or 跟随默认 · its vault's); its fields before it is opened.
export function itemWords(row: { kind?: unknown; listed: boolean; modes: string[]; hosts: string[]; lasts: unknown; lastUse?: unknown }, vaultLasts: unknown): {
  kindText: string; agentText: string; lineText: string; howText: string; lastsText: string; shut: { key: string; label: string; value: string; secret: boolean; mono: boolean }[];
} {
  const agentText = row.listed ? [t("core-views.vault.agent_may"), ...row.modes.map(modeText), ...(row.modes.includes("proxy") ? row.hosts : [])].join(" · ") : t("core-views.vault.private");
  return {
    kindText: kindText(row.kind),
    agentText,
    lineText: row.lastUse !== undefined ? t("core-views.vault.used", { when: String((row.lastUse as { at?: { ago?: unknown } } | undefined)?.at?.ago ?? "") }) : agentText,
    howText: row.modes.map((m) => howText(m, row.hosts)).join("、"),
    lastsText: typeof row.lasts === "string" && row.lasts !== "" ? lastsText(row.lasts) : t("core-views.vault.lasts.following", { lasts: lastsText(vaultLasts) }),
    shut: shutFields(row.kind),
  };
}

/// An opened item's fields as its page shows them, in order: what each is called, its value, whether it is masked,
/// whether in a fixed width.
export function shownFields(plain: unknown): { key: string; label: string; value: string; secret: boolean; mono: boolean }[] {
  const p = (plain ?? {}) as { kind?: unknown; fields?: Record<string, unknown> };
  const f = p.fields ?? {};
  const row = (key: string, label: string, secret: boolean, mono: boolean) => {
    const value = f[key];
    return typeof value === "string" && value !== "" ? [{ key, label: t(`core-views.vault.field.${label}`), value, secret, mono }] : [];
  };
  const kind = p.kind;
  if (kind === "ssh_key") return [...row("private_key", "private_key", true, true), ...row("public_key", "public_key", false, true)];
  if (kind === "login") return [...row("username", "username", false, false), ...row("password", "password", true, true), ...row("totp", "totp", true, true)];
  return row("value", "value", true, true);
}

/// A kind's fields while it is not opened (its page's): what each is called over dots, as many as a stand-in of it.
export function shutFields(kind: unknown): { key: string; label: string; value: string; secret: boolean; mono: boolean }[] {
  const dots = (n: number) => "•".repeat(Math.min(Math.max(n, 8), 20));
  const fields: Record<string, string> = kind === "ssh_key" ? { private_key: dots(20) } : kind === "login" ? { username: dots(10), password: dots(12) } : { value: dots(20) };
  return shownFields({ kind: kind === "ssh_key" || kind === "login" ? kind : "token", fields });
}

/// What the settings say of the vault at their row's end: how many wait to be approved (bad), else how many items, else
/// that it is off.
export function statusWords(vaults: readonly { items?: unknown }[], requests: readonly unknown[]): { statusText: string; statusBad: boolean } {
  if (requests.length > 0) return { statusText: t("core-views.vault.waiting", { n: requests.length }), statusBad: true };
  if (vaults.length > 0) return { statusText: t("core-views.vault.count", { n: vaults.reduce((n, v) => n + (typeof v.items === "number" ? v.items : 0), 0) }), statusBad: false };
  return { statusText: t("core-views.vault.off"), statusBad: false };
}
