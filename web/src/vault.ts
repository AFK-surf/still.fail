// The vault (docs/vault.md) as both screens draw it: the core's topics (`vaults`, `vaultItems`) and calls
// (`vault.*`, client/core-ts/src/views/vault.ts), the words a row or a status says, an item's form, and how a call that
// failed is told. The wide screen's page is cloud/Vault.tsx, the phone's mobile/Vault.tsx, the approval card
// VaultApproval.tsx: they only draw.
import { useCallback, useState } from "react";
import { useCall, useTopic } from "./core/react.ts";
import type { VaultItemRow, VaultItemsView, VaultRequest, VaultsView, VaultUse, VaultUsesView } from "./core/shapes.ts";
import { useToast } from "@stillfail/ui/toast.tsx";
import { t } from "./i18n.ts";

export type { VaultItemRow, VaultItemsView, VaultRequest, VaultRow, VaultsView, VaultUse, VaultUsesView } from "./core/shapes.ts";

export type Kind = "token" | "ssh_key" | "login";
export type Mode = "proxy" | "env" | "ssh";
export const KINDS: Kind[] = ["token", "ssh_key", "login"];
/** How long a grant lasts, shortest first: one use, an hour, the chat until it is archived. */
export type Scope = "once" | "hour" | "chat";
export const SCOPES: Scope[] = ["once", "hour", "chat"];
/** The scope `lasts` names (the longest an item is granted for), any when it names none. */
export const scopeOf = (lasts: string | undefined | null): Scope => SCOPES.find((s) => s === lasts) ?? "chat";
/** The scopes up to `lasts`. */
export const scopesUpTo = (lasts: string | undefined | null): Scope[] => SCOPES.slice(0, SCOPES.indexOf(scopeOf(lasts)) + 1);
/** The longest an item is granted for, in a word: 仅一次, 1 小时, 直到对话归档. */
export const lastsName = (lasts: string | undefined | null): string => t(`web-pages.vault.lasts.${scopeOf(lasts)}`);
/** An item's longest grant as its editor offers it: its own, or its vault's (`default`, the library's setting). */
export type Lasts = Scope | "default";
export const LASTS: Lasts[] = ["default", ...SCOPES];
export const lastsChoice = (l: Lasts): string => (l === "default" ? t("web-pages.vault.lasts.default") : lastsName(l));
/** What an item's page says of its longest grant: its own, or 跟随默认 · the vault's. */
export const itemLasts = (own: string | undefined | null, vault: string | undefined | null): string =>
  own ? lastsName(own) : t("web-pages.vault.lasts.following", { lasts: lastsName(vault) });

/** What an item holds (its plaintext, docs/vault.md 条目): `vault.open` gives it, `vault.putItem` takes it. */
export interface Plain { kind: Kind; name: string; fields: Record<string, string>; domains: string[]; notes: string }
/** An item opened: its plaintext, and the version it is (the next write is the one after). */
export interface Opened { vault: string; id: string; version: number; plain: Plain }

export function useVaults(workspace: string): VaultsView | undefined {
  return useTopic<VaultsView>({ topic: "vaults", workspace }).value;
}

export function useVaultItems(workspace: string, vault: string): VaultItemsView | undefined {
  return useTopic<VaultItemsView>({ topic: "vaultItems", workspace, vault }).value;
}

/** An item's uses by agents, the latest first (the station's record of them). */
export function useVaultUses(workspace: string, vault: string, item: string): VaultUsesView | undefined {
  return useTopic<VaultUsesView>({ topic: "vaultUses", workspace, vault, item }).value;
}

/** An item's page (设置 › 密钥 › the item). */
export const itemPath = (workspace: string, vault: string, item: string) => `/w/${workspace}/settings/vault/${encodeURIComponent(vault)}/${encodeURIComponent(item)}`;

/** The kinds the library lists after the profiles, a section each, in this order. */
export const ITEM_SECTIONS: Kind[] = ["token", "ssh_key", "login"];

/** An item's second line in the library's list: when an agent last used it, else how agents may ask for it. */
export const listLine = (row: VaultItemRow): string => (row.lastUse ? usedLine(row.lastUse) : itemLine(row));
export const usedLine = (use: VaultUse): string => t("web-pages.vault.uses.last", { when: use.at.ago });

export const kindName = (kind: string | undefined): string => (KINDS.includes(kind as Kind) ? t(`web-pages.vault.kind.${kind}`) : "");
export const modeName = (mode: string): string => (["proxy", "env", "ssh"].includes(mode) ? t(`web-pages.vault.mode.${mode}`) : mode);

/** How an agent gets it, in a line: 代理 · 限 api.github.com; ssh-agent; 环境变量. */
export function howLine(mode: string, hosts: readonly string[]): string {
  const name = modeName(mode);
  return mode === "proxy" && hosts.length ? `${name} · ${t("web-pages.vault.onlyTo", { hosts: hosts.join(", ") })}` : name;
}

/** An item's second line: whether agents may ask for it, and how (agent 可申请 · 代理 · api.github.com), or 只给自己看. */
export function itemLine(row: Pick<VaultItemRow, "listed" | "modes" | "hosts">): string {
  if (!row.listed) return t("web-pages.vault.private");
  return [t("web-pages.vault.agentMay"), ...row.modes.map(modeName), ...(row.modes.includes("proxy") ? row.hosts : [])].join(" · ");
}

/** What the settings say of the vault at their row's end: how many wait to be approved (red), else how many items, else
 * that it is off. */
export function vaultStatus(view: VaultsView | undefined): { text: string; bad: boolean } | undefined {
  if (!view) return undefined;
  if (view.requests.length > 0) return { text: t("web-pages.vault.waitingCount", { n: view.requests.length }), bad: true };
  if (view.vaults.length > 0) return { text: t("web-pages.vault.count", { n: view.vaults.reduce((n, v) => n + v.items, 0) }), bad: false };
  return { text: t("web-pages.vault.off"), bad: false };
}

/** The request a card names, while it waits on the viewer (the `vaults` topic's): none once decided, or not theirs. */
export function useVaultRequest(workspace: string, request: string | undefined): { view: VaultsView | undefined; request: VaultRequest | undefined } {
  const view = useVaults(workspace);
  return { view, request: request ? view?.requests.find((r) => r.id === request) : undefined };
}

const code = (e: unknown): string | undefined => {
  const c = (e as { code?: unknown } | null)?.code;
  return typeof c === "string" ? c : undefined;
};
const message = (e: unknown): string => (e instanceof Error ? e.message : String((e as { message?: unknown } | null)?.message ?? e));

/**
 * A vault call, said by toast as it ends: `done` when it went through; the person turning down the system's prompt
 * (`user_cancelled`) said nothing; another device having written first (`vault_conflict`, the vault read again), so;
 * anything else as `无法<what>：<why>`. Resolves with the answer, or undefined when it failed.
 */
export function useVaultCall(): <T = unknown>(name: string, params: Record<string, unknown>, what: string, done?: string) => Promise<T | undefined> {
  const call = useCall();
  const toast = useToast();
  return useCallback(<T>(name: string, params: Record<string, unknown>, what: string, done?: string) => call(name, params).then(
    (v) => { if (done) toast(done); return v as T; },
    (e: unknown) => {
      const c = code(e);
      if (c === "vault_conflict") toast(t("web-pages.vault.conflict"));
      else if (c !== "user_cancelled") toast(t("web-main.act.failed", { what, error: message(e) }));
      return undefined;
    },
  ), [call, toast]);
}

/** Copies a secret, and clears the clipboard 30 s later if it still holds it (where the page may read it back). */
export function copySecret(value: string, toast: (m: string) => void): void {
  void navigator.clipboard.writeText(value).then(() => {
    toast(t("web-pages.vault.copied"));
    setTimeout(() => {
      void navigator.clipboard.readText().then((now) => { if (now === value) void navigator.clipboard.writeText(""); }, () => {});
    }, 30_000);
  }, (e: unknown) => toast(t("web-main.act.failed", { what: t("common.copy"), error: message(e) })));
}

// ── an item's form ──

/** What the editor holds: the fields of every kind (one kind's are sent), and how agents may ask for it. */
export interface Form {
  kind: Kind;
  name: string;
  value: string;
  privateKey: string;
  publicKey: string;
  username: string;
  password: string;
  totp: string;
  agent: boolean;
  mode: Mode;
  hosts: string;
  env: string;
  /** The longest grant given for it: its own, or the library's (`default`). */
  lasts: Lasts;
}

export const blankForm = (): Form => ({ kind: "token", name: "", value: "", privateKey: "", publicKey: "", username: "", password: "", totp: "", agent: false, mode: "proxy", hosts: "", env: "", lasts: "default" });

/** The form for an item opened (with its row: how agents may ask for it). */
export function formOf(opened: Opened, row: VaultItemRow | undefined): Form {
  const f = opened.plain.fields;
  const kind = KINDS.includes(opened.plain.kind) ? opened.plain.kind : "token";
  const mode = (row?.modes[0] as Mode | undefined) ?? (kind === "ssh_key" ? "ssh" : "proxy");
  return {
    ...blankForm(), kind, name: opened.plain.name, value: f.value ?? "", privateKey: f.private_key ?? "", publicKey: f.public_key ?? "",
    username: f.username ?? "", password: f.password ?? "", totp: f.totp ?? "",
    agent: row?.listed ?? false, mode, hosts: (row?.hosts ?? []).join(", "), env: row?.env ?? "", lasts: SCOPES.find((s) => s === row?.lasts) ?? "default",
  };
}

/** The modes a kind is given by: a token or a login through the proxy or an env variable, an SSH key by ssh-agent. */
export const modesOf = (kind: Kind): Mode[] => (kind === "ssh_key" ? ["ssh"] : ["proxy", "env"]);

const hostsOf = (s: string) => s.split(/[,\s，、]+/).map((h) => h.trim().toLowerCase()).filter((h) => h !== "");

/** Why the form cannot be saved yet (a word for the field), or null. */
export function formProblem(f: Form): "name" | "value" | "hosts" | null {
  if (!f.name.trim()) return "name";
  if (f.kind === "token" && !f.value.trim()) return "value";
  if (f.kind === "ssh_key" && !f.privateKey.trim()) return "value";
  if (f.kind === "login" && !f.username.trim() && !f.password) return "value";
  const mode = modesOf(f.kind).includes(f.mode) ? f.mode : modesOf(f.kind)[0]!;
  if (f.agent && mode === "proxy" && hostsOf(f.hosts).length === 0) return "hosts";
  return null;
}

/** `vault.putItem`'s `plain` and `listing` (the listing only when agents may ask for it). */
export function putOf(f: Form, notes = ""): { plain: Plain; listing?: { name: string; kind: Kind; modes: Mode[]; hosts: string[]; env?: string; lasts?: Scope } } {
  const fields: Record<string, string> =
    f.kind === "token" ? { value: f.value.trim() }
    : f.kind === "ssh_key" ? { private_key: f.privateKey.trim() + "\n", ...(f.publicKey.trim() ? { public_key: f.publicKey.trim() } : {}) }
    : { username: f.username.trim(), password: f.password, ...(f.totp.trim() ? { totp: f.totp.trim().replace(/\s+/g, "") } : {}) };
  const name = f.name.trim();
  const plain: Plain = { kind: f.kind, name, fields, domains: [], notes };
  if (!f.agent) return { plain };
  const mode = modesOf(f.kind).includes(f.mode) ? f.mode : modesOf(f.kind)[0]!;
  const env = f.kind === "ssh_key" ? "" : f.env.trim();
  return { plain, listing: { name, kind: f.kind, modes: [mode], hosts: hostsOf(f.hosts), ...(env ? { env } : {}), ...(f.lasts !== "default" ? { lasts: f.lasts } : {}) } };
}

/** An item's fields as its detail shows them, in order: what each is called, its value, whether it is masked. */
export function fieldsOf(plain: Plain): { key: string; label: string; value: string; secret: boolean; mono: boolean }[] {
  const f = plain.fields;
  const row = (key: string, label: string, secret: boolean, mono: boolean) => (f[key] ? [{ key, label, value: f[key]!, secret, mono }] : []);
  if (plain.kind === "ssh_key") return [...row("private_key", t("web-pages.vault.editor.privateKey"), true, true), ...row("public_key", t("web-pages.vault.editor.publicKey"), false, true)];
  if (plain.kind === "login") return [...row("username", t("web-pages.vault.editor.username"), false, false), ...row("password", t("web-pages.vault.editor.password"), true, true), ...row("totp", t("web-pages.vault.editor.totp"), true, true)];
  return row("value", t("web-pages.vault.editor.value"), true, true);
}

/** A form kept while the editor is open: its value, a change to some fields, and it all again from `first`. */
export function useForm(first: () => Form): [Form, (patch: Partial<Form>) => void] {
  const [form, setForm] = useState(first);
  const change = useCallback((patch: Partial<Form>) => setForm((f) => {
    const next = { ...f, ...patch };
    // A kind given only one way is given that way.
    if (patch.kind && !modesOf(next.kind).includes(next.mode)) next.mode = modesOf(next.kind)[0]!;
    return next;
  }), []);
  return [form, change];
}

/** Masked: as many dots as it is long (a few at least, a line's worth at most). */
export const masked = (value: string) => "•".repeat(Math.min(Math.max(value.length, 8), 20));
