// What the pages say of the vault (docs/vault.md), for every client alike: an item's kind, how agents may ask for it and
// get it, its longest grant, an opened item's fields, the library's state at the settings' row. The web's vault.ts
// worked these out; the core's views (views/vault.ts) put them on its topics, and the web's stories use them as the
// core does. Self-contained (its only import the words) so that the web may import it as it is.
import { t } from "./i18n.ts";

const KIND_WORDS = ["token", "ssh_key", "login", "file", "browser"];
const MODE_WORDS = ["proxy", "env", "ssh", "file", "browser"];
/// The ways an item goes only to the hosts it names (a proxy's, a sign-in's sites): they are said with it.
const HOSTED = ["proxy", "browser"];
const SCOPE_WORDS = ["once", "hour", "chat"];

/// A kind of item in a word (Token, SSH 密钥, 登录); "" for one not known.
export const kindText = (kind: unknown): string => (typeof kind === "string" && KIND_WORDS.includes(kind) ? t(`core-views.vault.kind.${kind}`) : "");
/// A way an agent is given it, in a word (代理, 环境变量, ssh-agent, 文件).
export const modeText = (mode: string): string => (MODE_WORDS.includes(mode) ? t(`core-views.vault.mode.${mode}`) : mode);
/// How an agent gets it, in a line: 代理 · 限 api.github.com; 浏览器 · 限 github.com; ssh-agent; 环境变量.
export function howText(mode: string, hosts: readonly string[]): string {
  const name = modeText(mode);
  return HOSTED.includes(mode) && hosts.length > 0 ? `${name} · ${t("core-views.vault.only_to", { hosts: hosts.join(", ") })}` : name;
}
/// The longest a grant of it lasts, in a word (仅一次, 1 小时, 直到对话归档): any but these, the chat.
export const lastsText = (lasts: unknown): string => t(`core-views.vault.lasts.${typeof lasts === "string" && SCOPE_WORDS.includes(lasts) ? lasts : "chat"}`);

/// An item's row's words: what kind it is; whether agents may ask for it and how (允许 agent 申请 · 代理 · api.github.com,
/// or 仅自己可见); its line in a list, what is worth knowing of it at a glance (lineText); how it is given, a line a
/// way; its longest grant (its own, or 跟随默认 · its vault's); its fields before it is opened.
export function itemWords(row: { kind?: unknown; listed: boolean; modes: string[]; hosts: string[]; env?: unknown; lasts: unknown; lastUse?: unknown }, vaultLasts: unknown): {
  kindText: string; agentText: string; lineText: string; howText: string; lastsText: string; shut: { key: string; label: string; value: string; secret: boolean; mono: boolean }[];
} {
  const agentText = row.listed ? [t("core-views.vault.agent_may"), ...row.modes.map(modeText), ...(row.modes.some((m) => HOSTED.includes(m)) ? row.hosts : [])].join(" · ") : t("core-views.vault.private");
  return {
    kindText: kindText(row.kind),
    agentText,
    lineText: lineText(row),
    howText: row.modes.map((m) => howText(m, row.hosts)).join("、"),
    lastsText: typeof row.lasts === "string" && row.lasts !== "" ? lastsText(row.lasts) : t("core-views.vault.lasts.following", { lasts: lastsText(vaultLasts) }),
    shut: shutFields(row.kind),
  };
}

/// An item's line in a list (全部密钥), what is worth knowing of it at a glance: how an agent gets it (代理 ·
/// api.github.com, 环境变量 GH_TOKEN, ssh-agent; the variable it is named by where it is given another way), or that it
/// is only the person's; when it was last used, and in which chat (昨天在「修 CI」用过).
function lineText(row: { listed: boolean; modes: string[]; hosts: string[]; env?: unknown; lastUse?: unknown }): string {
  const env = typeof row.env === "string" && row.env !== "" ? row.env : null;
  const ways = !row.listed ? [t("core-views.vault.private")]
    : [...row.modes.flatMap((m) => (HOSTED.includes(m) ? [modeText(m), ...row.hosts] : m === "env" && env ? [`${modeText(m)} ${env}`] : [modeText(m)])), ...(env && !row.modes.includes("env") ? [env] : [])];
  const use = row.lastUse as { at?: { ago?: unknown }; chatTitle?: unknown } | undefined;
  const when = String(use?.at?.ago ?? "");
  const used = use === undefined ? [] : [typeof use.chatTitle === "string" && use.chatTitle !== "" ? t("core-views.vault.usedIn", { when, chat: use.chatTitle }) : t("core-views.vault.used", { when })];
  return [...ways, ...used].join(" · ");
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
  if (kind === "file") {
    // its content as its text where it is text, else what it is and how big
    const content = typeof f.content === "string" ? fileText(f.content) : null;
    return [
      ...row("filename", "filename", false, false),
      ...(content === null ? [] : typeof content === "string" ? [{ key: "content", label: t("core-views.vault.field.content"), value: content, secret: true, mono: true }]
        : [{ key: "content", label: t("core-views.vault.field.content"), value: t("core-views.vault.binary", { size: bytesText(content.size) }), secret: false, mono: false }]),
    ];
  }
  if (kind === "ssh_key") return [...row("private_key", "private_key", true, true), ...row("public_key", "public_key", false, true)];
  if (kind === "browser") return row("cookies", "cookies", true, true);
  if (kind === "login") return [...row("username", "username", false, false), ...row("password", "password", true, true), ...row("totp", "totp", true, true)];
  return row("value", "value", true, true);
}

/// A kind's fields while it is not opened (its page's): what each is called over dots, as many as a stand-in of it.
export function shutFields(kind: unknown): { key: string; label: string; value: string; secret: boolean; mono: boolean }[] {
  const dots = (n: number) => "•".repeat(Math.min(Math.max(n, 8), 20));
  if (kind === "file") return ["filename", "content"].map((key) => ({ key, label: t(`core-views.vault.field.${key}`), value: dots(key === "content" ? 20 : 10), secret: true, mono: key === "content" }));
  if (kind === "browser") return shownFields({ kind, fields: { cookies: dots(20) } });
  const fields: Record<string, string> = kind === "ssh_key" ? { private_key: dots(20) } : kind === "login" ? { username: dots(10), password: dots(12) } : { value: dots(20) };
  return shownFields({ kind: kind === "ssh_key" || kind === "login" ? kind : "token", fields });
}

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// A file's content (its bytes in base64) as text, where it is UTF-8 throughout; else how many bytes it is; null where
/// it is not base64.
export function fileText(content: string): string | { size: number } | null {
  const bytes = fileBytes(content);
  if (bytes === null) return null;
  return utf8Throughout(bytes) ? new TextDecoder().decode(bytes) : { size: bytes.length };
}

/// Whether `b` is UTF-8 from start to end (by hand: not every engine the core runs in decodes with `fatal`), without
/// the control characters text has none of (a NUL, a byte of a binary format).
function utf8Throughout(b: Uint8Array): boolean {
  for (let i = 0; i < b.length; ) {
    const c = b[i]!;
    const n = c < 0x80 ? 0 : c >= 0xc2 && c < 0xe0 ? 1 : c >= 0xe0 && c < 0xf0 ? 2 : c >= 0xf0 && c < 0xf5 ? 3 : -1;
    if (n < 0 || (c < 0x20 && c !== 9 && c !== 10 && c !== 13)) return false;
    for (let k = 1; k <= n; k++) if (i + k >= b.length || (b[i + k]! & 0xc0) !== 0x80) return false;
    i += n + 1;
  }
  return true;
}

/// A file's content's bytes (base64, padded); null where it is not that.
export function fileBytes(content: string): Uint8Array | null {
  const s = content.replace(/=+$/, "");
  if (content.length % 4 !== 0 || content.length - s.length > 2) return null;
  const out = new Uint8Array(Math.floor((s.length * 3) / 4));
  let bits = 0, n = 0, o = 0;
  for (let i = 0; i < s.length; i++) {
    const v = B64.indexOf(s[i]!);
    if (v < 0) return null;
    bits = (bits << 6) | v;
    n += 6;
    if (n >= 8) {
      n -= 8;
      out[o++] = (bits >> n) & 255;
    }
  }
  return out;
}

/// Bytes in words: "820 B", "12 KB".
const bytesText = (n: number): string => (n < 1024 ? `${n} B` : `${Math.round(n / 1024)} KB`);

/// What the settings say of the vault at their row's end: how many wait to be approved (bad), else how many items, else
/// that it is off.
export function statusWords(vaults: readonly { items?: unknown }[], requests: readonly unknown[]): { statusText: string; statusBad: boolean } {
  if (requests.length > 0) return { statusText: t("core-views.vault.waiting", { n: requests.length }), statusBad: true };
  if (vaults.length > 0) return { statusText: t("core-views.vault.count", { n: vaults.reduce((n, v) => n + (typeof v.items === "number" ? v.items : 0), 0) }), statusBad: false };
  return { statusText: t("core-views.vault.off"), statusBad: false };
}
