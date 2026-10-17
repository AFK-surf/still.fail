// The workspace's library (docs/vault.md 一个库), as the narrow web has it (web/src/mobile/Vault.tsx; one interaction set:
// bottom sheets): its row in the settings, its page (what it waits for first when locked, turning it on and the recovery
// words shown that once; then the requests waiting, whether it is locked, the profiles' accounts, each vault's secrets a
// section a kind, the devices holding its key), a secret's own page (its content shown, how agents may use it, when they
// did), adding and editing in bottom sheets, and an agent's request approved where it is asked (its card in the chat, the
// 奏 page, the page's 待批准). All of it is the core's (`vaults`, `vaultItems`, `vaultUses` topics, `vault.*` calls,
// client/core-ts/src/views/vault.ts): the system's prompt (fingerprint or screen lock) comes up from its calls through the
// host, never from here. What an item holds is shown only on its page, while it is up, never kept.
import { useState, useSyncExternalStore, type ReactNode } from "react";
import { Pressable, ScrollView, Text, TextInput, View, type StyleProp, type ViewStyle } from "react-native";
import * as Clipboard from "expo-clipboard";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { DecisionOption, ProfilesView, VaultItemRow, VaultItemsView, VaultRequest, VaultRow, VaultsView, VaultUse, VaultUsesView } from "../../../../web/src/core/shapes.ts";
import { app as theApp, SheetSpec, useApp, type AppState } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { errorText } from "../data/Calls";
import { ChatOf, rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { chatSubtle } from "../ui/ChatInk";
import { Button } from "../ui/Controls";
import { Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { IconIn, LargeTitle, ListCard, ListRow, NavBar, ProviderMark, ripple, SectionHeader, Seg } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { CODE_FONT, useC } from "../ui/Theme";
import { Spinner, WaitLine, WaitShape, Waiting } from "../ui/Waiting";
import { Switch } from "./Connects";
import { Body, Dot, Foot, Para, WideButton } from "./Security";
import { confirm } from "./Settings";
import { DecisionOptions, GoRow, PageNote } from "./SettingParts";
import { TopBack } from "./Stations";

// ── calls ──────────────────────────────────────────────────────────────

/** `vault.<name>` on the workspace `ws`, with what it takes. */
export function vaultCall(app: AppState, ws: string, name: string, params: Record<string, unknown> = {}): Promise<unknown> {
  return app.core.call(`vault.${name}`, { workspace: ws, ...params });
}

/**
 * What a vault call's failure says: nothing when the person turned the system's prompt down (`user_cancelled`), that
 * another device wrote first and the vault was read again (`vault_conflict`), else why.
 */
export function vaultSaid(e: CoreError): string | null {
  if (e.code === "user_cancelled") return null;
  if (e.code === "vault_conflict") return t("android-settings.vault.conflict");
  return errorText(e);
}

/** As [AppState.act], for a vault call: `没能<what>：<why>`; a write made elsewhere first said as such; the prompt turned down, nothing. */
export function vaultAct(app: AppState, what: string, done: string | null, run: () => Promise<unknown>) {
  run().then(
    () => { if (done != null) app.toast = done; },
    (e: unknown) => {
      if (!(e instanceof CoreError)) throw e;
      const why = vaultSaid(e);
      if (why == null) return;
      app.toast = e.code === "vault_conflict" ? why : t(e.code === "unconfirmed" ? "android-misc.act.unconfirmed" : "android-misc.act.failed", { what, error: why });
    },
  );
}

/** An item's plaintext as `vault.open` gives it (docs/vault.md 条目): held by its sheet only, while it is up. */
interface Plain { kind: string; name: string; fields: Record<string, string>; domains: string[]; notes: string }
const plainOf = (v: Partial<Plain> & { kind: string; name: string }): Plain => ({ kind: v.kind, name: v.name, fields: v.fields ?? {}, domains: v.domains ?? [], notes: v.notes ?? "" });

/** The kinds of item, in the editor's order, and the fields each holds (the secret ones masked where shown). */
const KINDS = ["token", "ssh_key", "login"];
const FIELDS: Record<string, string[]> = { token: ["value"], ssh_key: ["private_key", "public_key"], login: ["username", "password", "totp"] };
const OPEN_FIELDS = new Set(["public_key", "username"]);

const kindName = (kind: string | null | undefined) => (kind != null && KINDS.includes(kind) ? t(`android-settings.vault.kind.${kind}`) : "");
const kindIcon = (kind: string | null | undefined): IconPaths => (kind === "ssh_key" ? Icons.Server : kind === "login" ? Icons.User : Icons.Key);
const modeName = (mode: string) => (["proxy", "env", "ssh"].includes(mode) ? t(`android-settings.vault.mode.${mode}`) : mode);
function fieldName(field: string): string {
  switch (field) {
    case "value": return t("android-settings.vault.value");
    case "private_key": return t("android-settings.vault.privateKey");
    case "public_key": return t("android-settings.vault.publicKey");
    case "username": return t("android-settings.vault.username");
    case "password": return t("android-settings.vault.password");
    case "totp": return t("android-settings.vault.totp");
    default: return field;
  }
}

/** What agents may do with an item, in a line: `agent 可申请 · 代理 · api.github.com`, or that it is only its owner's. */
function agentLine(listed: boolean, modes: string[], hosts: string[], env: string | null = null): string {
  if (!listed) return t("android-settings.vault.selfOnly");
  return [t("android-settings.vault.agentCan"), ...modes.map(modeName), ...[hosts.join(", ") || null, env ? t("android-settings.vault.envLine", { name: env }) : null].filter((x): x is string => x != null)].join(" · ");
}

/** How a request would be given: by the proxy (限 which hosts), the station's ssh-agent, or the command's environment. */
function howLine(mode: string, hosts: string[]): string {
  const list = hosts.join(", ");
  return [modeName(mode), list !== "" && mode === "proxy" ? t("web-pages.vault.onlyTo", { hosts: list }) : null].filter((x) => x != null).join(" · ");
}

/** The kinds the library lists after the profiles' accounts, a section each, in this order (the editor's). */
const ITEM_SECTIONS = KINDS;

/**
 * The recovery words `vault.setup` gave, by workspace, until the person says they have written them down: in memory
 * only (a page left and come back to shows them again), never kept, and the core gives them only the once.
 */
const recoveryWords = (() => {
  let words: Record<string, string[]> = {};
  const listeners = new Set<() => void>();
  const changed = () => { for (const l of listeners) l(); };
  return {
    get: (ws: string) => words[ws],
    set: (ws: string, list: string[]) => { words = { ...words, [ws]: list }; changed(); },
    remove: (ws: string) => { const { [ws]: _, ...rest } = words; words = rest; changed(); },
    subscribe: (l: () => void) => { listeners.add(l); return () => { listeners.delete(l); }; },
  };
})();
const useRecoveryWords = (ws: string) => useSyncExternalStore(recoveryWords.subscribe, () => recoveryWords.get(ws));

// ── the settings' row ──────────────────────────────────────────────────

/** Settings' 密钥 (SettingsHome.kt, beside 安全), as the web's vaultStatus: how many requests wait (in red), else how many items, else off. */
export function VaultSettingsRow({ ws }: { ws: string }) {
  const topic = rememberTopic<VaultsView>(Topics.vaults(ws));
  const v = topic.value;
  if (v == null) return null;
  const waiting = v.requests.length;
  const value = waiting > 0 ? t("android-settings.vault.waiting", { n: waiting })
    : v.vaults.length > 0 ? t("android-settings.vault.items", { n: v.vaults.reduce((n, it) => n + it.items, 0) })
    : t("android-settings.vault.off");
  return <GoRow title={t("android-settings.vault.title")} value={value} bad={waiting > 0} onClick={() => theApp.push({ kind: "Vault" })} />;
}

// ── the page ───────────────────────────────────────────────────────────

export function VaultScreen({ current }: { current: WorkspaceEntry }) {
  const app = theApp;
  const C = useC();
  useApp((s) => s.doing);
  const ws = current.workspace.id;
  const topic = rememberTopic<VaultsView>(Topics.vaults(ws));
  const view = topic.value;
  const words = useRecoveryWords(ws);
  // Not locked (no security mode in the workspace): the library kept in the clear on its station, usable at once.
  const plain = view?.plain === true;
  const usable = view != null && words == null && (plain || (view.available && view.locked && view.canSign && view.setUp));
  const body = (): ReactNode => {
    if (words != null) return <Words words={words} />;
    if (view == null) return <Waiting shape={WaitShape.Cards} text={t("web-pages.settings.reading")} error={topic.error?.message} />;
    if (plain) return <Library ws={ws} view={view} />;
    // A web page's (no keys kept there): what is known of the names, nothing to open.
    if (!view.available) return (
      <>
        {view.vaults.map((v) => <VaultSection key={v.id} ws={ws} v={v} readOnly />)}
        <PageNote text={t("android-settings.vault.readOnly")} />
      </>
    );
    if (!view.locked) return <ToSecurity title={t("android-settings.vault.needsLock")} why={t("android-settings.vault.needsLockWhy")} />;
    if (!view.canSign) return <ToSecurity title={t("android-settings.vault.notSigner")} why={t("android-settings.vault.notSignerWhy")} />;
    if (!view.setUp) return <Off />;
    return <Library ws={ws} view={view} />;
  };
  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }}>
        <TopBack label={t("android-settings.title")} onBack={() => app.pop()} trailing={usable ? <RoundIcon icon={Icons.Plus} said={t("android-settings.vault.add")} tint={C.ink} onClick={() => addSheet(app, ws)} /> : null} />
        <LargeTitle small="" big={t("android-settings.vault.title")} />
        {body()}
        <View style={{ height: 30 }} />
      </ScrollView>
      {words != null ? (
        <Foot note={t("android-settings.vault.wordsOnce")}>
          <WideButton label={t("android-settings.vault.wordsDone")} primary modifier={{ alignSelf: "stretch" }} onClick={() => {
            recoveryWords.remove(ws);
            if (view != null && view.vaults.length === 0) createFirst(app, ws);
          }} />
        </Foot>
      ) : view != null && view.available && view.locked && view.canSign && !view.setUp ? (
        <Foot>
          <WideButton label={t("android-settings.vault.turnOn")} primary modifier={{ alignSelf: "stretch" }} busy={app.isDoing("vault.setup", { workspace: ws })} onClick={() => setUp(app, ws, view)} />
        </Foot>
      ) : null}
    </View>
  );
}

/**
 * This device set up (its box key made, its certificate published): the first time the person's recovery words come
 * back, to be written down before going on; then (or at once, when one of their devices made the words before) their
 * personal vault, when they have none yet.
 */
function setUp(app: AppState, ws: string, view: VaultsView) {
  vaultAct(app, t("android-settings.vault.turnOn"), null, async () => {
    const said = (await vaultCall(app, ws, "setup")) as { words?: unknown } | null;
    const words = typeof said?.words === "string" ? said.words : null;
    if (words != null) recoveryWords.set(ws, words.trim().split(/\s+/));
    else if (view.vaults.length === 0) await vaultCall(app, ws, "create", { name: t("android-settings.vault.personal") });
  });
}

function createFirst(app: AppState, ws: string) {
  vaultAct(app, t("android-settings.vault.create"), null, () => vaultCall(app, ws, "create", { name: t("android-settings.vault.personal") }));
}

/** What has to come first (the workspace's security mode, this device confirmed in it), and the way to it. */
function ToSecurity({ title, why }: { title: string; why: string }) {
  return (
    <ListCard>
      <Body><Para main={title} sub={why} /></Body>
      <GoRow title={t("web-pages.security.title")} onClick={() => theApp.push({ kind: "Security" })} />
    </ListCard>
  );
}

function Off() {
  const C = useC();
  return (
    <ListCard>
      <Body>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
          <Dot on={false} />
          <T size={15} weight="600" color={C.ink}>{t("android-settings.vault.offTitle")}</T>
        </View>
        <Para main={t("android-settings.vault.offWhat")} />
        <Para main={t("android-settings.vault.offAgents")} sub={t("android-settings.vault.offUnlock")} />
      </Body>
    </ListCard>
  );
}

/** The 24 recovery words, numbered, three to a row, for the person to copy out (the page's foot goes on). */
function Words({ words }: { words: string[] }) {
  const C = useC();
  const rows: string[][] = [];
  for (let i = 0; i < words.length; i += 3) rows.push(words.slice(i, i + 3));
  return (
    <ListCard>
      <Body>
        <T size={15} weight="600" color={C.ink}>{t("android-settings.vault.wordsTitle")}</T>
        <T size={13} line={19} color={C.muted}>{t("android-settings.vault.wordsWhy")}</T>
        <View style={{ alignSelf: "stretch", paddingTop: 4, gap: 10 }}>
          {rows.map((three, row) => (
            <View key={row} style={{ flexDirection: "row" }}>
              {three.map((word, i) => (
                // The number and the word on one baseline: the same line height, from the top.
                <View key={i} style={{ flex: 1, flexDirection: "row", alignItems: "baseline" }}>
                  <T size={12} color={C.subtle} align="right" style={{ width: 22, fontFamily: CODE_FONT }}>{`${row * 3 + i + 1}`}</T>
                  <View style={{ width: 8 }} />
                  <T size={15} color={C.ink} style={{ fontFamily: CODE_FONT }}>{word}</T>
                </View>
              ))}
            </View>
          ))}
        </View>
      </Body>
    </ListCard>
  );
}

/**
 * The library (docs/vault.md 一个库), not locked or set up: the requests waiting on the viewer, whether it is locked (and
 * what is still in the clear from before), the profiles' accounts, each vault's secrets a section a kind, the devices
 * that hold the keys (locked).
 */
function Library({ ws, view }: { ws: string; view: VaultsView }) {
  const app = theApp;
  useApp((s) => s.doing);
  const plain = view.plain === true;
  const left = view.plainLeft ?? 0;
  return (
    <>
      {view.requests.length > 0 && (
        <>
          <SectionHeader title={`${t("android-settings.vault.waitingTitle")} · ${view.requests.length}`} start={24} />
          {view.requests.map((r) => <RequestCard key={r.id} ws={ws} view={view} r={r} />)}
        </>
      )}
      <LibraryState plain={plain} />
      {!plain && left > 0 && <PlainLeft ws={ws} n={left} />}
      <ProfileAccounts ws={ws} />
      {!plain && view.vaults.length === 0 && (
        <ListCard>
          <Body>
            <Para main={t("android-settings.vault.none")} />
            <WideButton label={t("android-settings.vault.create")} primary modifier={{ alignSelf: "stretch" }} busy={app.isDoing("vault.create", { workspace: ws })} onClick={() => createFirst(app, ws)} />
          </Body>
        </ListCard>
      )}
      {/* A vault this device has no key to: what is known of it, and how to get the key. */}
      {view.vaults.map((v) => (plain || v.keyed ? <LibraryVault key={v.id} ws={ws} v={v} plain={plain} /> : <VaultSection key={v.id} ws={ws} v={v} readOnly={false} />))}
      {!plain && view.vaults.length > 0 && <Devices ws={ws} view={view} />}
      {view.refused.map((r) => {
        const name = r.name || r.station;
        return <PageNote key={r.station} text={r.code === "vault_needs_lock" ? t("android-settings.vault.refusedLock", { name }) : t("android-settings.vault.refusedOld", { name })} />;
      })}
    </>
  );
}

/** A request waiting on the viewer: what it is for (item, reason, command, how it is given), its chat, the three answers. */
function RequestCard({ ws, view, r }: { ws: string; view: VaultsView; r: VaultRequest }) {
  const app = theApp;
  const C = useC();
  // The request's keeper is the station its vault is on (docs/vault.md: the agent asks there); its chat is the session's.
  const station = view.vaults.find((v) => v.id === r.vault)?.station || null;
  return (
    <>
      <ListCard>
        <Body>
          <T size={15} weight="600" color={C.ink}>{t("android-settings.vault.request.title", { name: r.itemName ?? t("android-settings.vault.request.someItem") })}</T>
          <T size={14} line={20} color={C.ink}>{r.reason}</T>
          {r.command != null && <T size={13} line={19} color={C.ink} style={{ fontFamily: CODE_FONT }}>{r.command}</T>}
          <T size={13} color={C.muted}>{howLine(r.mode, r.hosts)}</T>
          {station != null && (
            <Pressable onPress={() => app.push({ kind: "Chat", station: `${ws}/${station}`, of: ChatOf.Session(r.session) })} android_ripple={ripple(C.ink)} style={{ flexDirection: "row", alignItems: "center", gap: 2, alignSelf: "flex-start" }}>
              <T size={14} color={C.accent}>{t("android-settings.vault.request.openChat")}</T>
              <IconIn icon={Icons.ChevronRight} size={13} tint={C.accent} />
            </Pressable>
          )}
        </Body>
      </ListCard>
      <VaultOptions ws={ws} request={r.id} modifier={{ paddingHorizontal: 12, paddingBottom: 10 }} />
    </>
  );
}

/**
 * The three answers to an agent's request, in the decisions' options (Decisions.kt DecisionOptions): once (the one
 * recommended), this chat for an hour, refused. Approving asks the person through the system's prompt (the core's
 * call); the one under way turns where it was tapped.
 */
function VaultOptions({ ws, request, modifier, enabled = true }: { ws: string; request: string; modifier?: StyleProp<ViewStyle>; enabled?: boolean }) {
  const app = theApp;
  useApp((s) => s.doing);
  const once: DecisionOption = { label: t("android-settings.vault.approve.once"), detail: t("android-settings.vault.approve.onceDetail"), recommended: true };
  const hour: DecisionOption = { label: t("android-settings.vault.approve.hour"), detail: t("android-settings.vault.approve.hourDetail") };
  const deny: DecisionOption = { label: t("android-settings.vault.approve.deny"), detail: t("android-settings.vault.approve.denyDetail") };
  const on = { workspace: ws, request };
  const busy = app.isDoing("vault.approve", { ...on, scope: "once" }) ? once.label
    : app.isDoing("vault.approve", { ...on, scope: "hour" }) ? hour.label
    : app.isDoing("vault.deny", on) ? deny.label
    : null;
  return (
    <DecisionOptions options={[once, hour, deny]} modifier={modifier} enabled={enabled} busy={busy} onPick={(o: DecisionOption) => {
      if (o.label === deny.label) vaultAct(app, t("android-settings.vault.approve.denyWhat"), null, () => vaultCall(app, ws, "deny", { request }));
      else {
        const scope = o.label === once.label ? "once" : "hour";
        vaultAct(app, t("android-settings.vault.approve.what"), null, () => vaultCall(app, ws, "approve", { request, scope }));
      }
    }} />
  );
}

/**
 * An agent's request where its card is (a post's options card with `vault`: Decisions.kt, in a chat and on the 奏 page):
 * the three answers in place of the card's own, when it waits on the viewer here; shown but not to be tapped where they
 * cannot be (another's to decide, `mine` false: the card says whose; a web page's, said to be the app's); once decided
 * (no longer among the requests), nothing to tap, until its station takes the card back.
 */
export function VaultApproval({ workspace, request, mine, modifier }: { workspace: string; request: string; mine: boolean; modifier?: StyleProp<ViewStyle> }) {
  const app = theApp;
  const C = useC();
  useApp((s) => s.doing);
  const topic = rememberTopic<VaultsView>(Topics.vaults(workspace));
  const view = topic.value;
  const running = app.isDoing(["vault.approve", "vault.deny"], { workspace, request });
  const subtle = chatSubtle(C);
  return (
    <View style={modifier}>
      {view == null || !mine ? <VaultOptions ws={workspace} request={request} enabled={false} />
        : !view.available ? (
          <>
            <VaultOptions ws={workspace} request={request} enabled={false} />
            <T size={13} line={19} color={subtle} style={{ paddingTop: 6 }}>{t("android-settings.vault.approve.inApp")}</T>
          </>
        )
        : running || view.requests.some((r) => r.id === request) ? <VaultOptions ws={workspace} request={request} />
        : <T size={13} line={19} color={subtle}>{t("android-settings.vault.approve.decided")}</T>}
    </View>
  );
}

/**
 * A vault as far as it is known here, names only: a web page's (`readOnly`), or one this device has no key to (then how
 * to get it: the recovery words, when it has them).
 */
function VaultSection({ ws, v, readOnly }: { ws: string; v: VaultRow; readOnly: boolean }) {
  const app = theApp;
  const C = useC();
  const topic = rememberTopic<VaultItemsView>(Topics.vaultItems(ws, v.id));
  const items = topic.value?.items ?? [];
  return (
    <>
      <SectionHeader title={v.name} start={24} />
      {!readOnly && !v.keyed && (
        <ListCard>
          <Body><Para main={t("android-settings.vault.noKey")} sub={t("android-settings.vault.noKeyHow")} /></Body>
          {v.recoverable && <GoRow title={t("android-settings.vault.recover")} onClick={() => recoverSheet(app, ws)} />}
        </ListCard>
      )}
      <ListCard>
        {items.length === 0 && (
          <Body>
            {topic.value == null ? <WaitLine text={topic.error?.message ?? t("web-pages.settings.reading")} error={topic.error != null} />
              : <T size={14} color={C.muted}>{t("android-settings.vault.empty")}</T>}
          </Body>
        )}
        {items.map((it) => <ItemRow key={it.id} item={it} />)}
      </ListCard>
    </>
  );
}

/** An item known by name: its kind's mark, its name (unknown while it is locked and not listed), what agents may do with it. */
function ItemRow({ item }: { item: VaultItemRow }) {
  const C = useC();
  return (
    <ListRow>
      <KindTile kind={item.kind ?? null} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} color={item.name == null ? C.muted : C.ink} numberOfLines={1} ellipsizeMode="tail">{item.name ?? t("android-settings.vault.lockedItem")}</T>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
          {item.listed && <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: C.green }} />}
          <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>{agentLine(item.listed, item.modes, item.hosts)}</T>
        </View>
      </View>
    </ListRow>
  );
}

// ── the library's parts (docs/vault.md 一个库) ─────────────────────────

/** A row's mark: an icon in the narrow column the library's rows keep for it. */
function RowMark({ children }: { children?: ReactNode }) {
  return <View style={{ width: 18, alignItems: "center", justifyContent: "center" }}>{children}</View>;
}

/** First in the library: whether it is locked (security mode on), and the way to lock it when not; a tap opens 安全. */
function LibraryState({ plain }: { plain: boolean }) {
  const C = useC();
  return (
    <ListCard>
      <ListRow onClick={() => theApp.push({ kind: "Security" })}>
        <RowMark><IconIn icon={Icons.ShieldCheck} size={18} tint={plain ? C.warn : C.subtle} /></RowMark>
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} color={plain ? C.warn : C.ink} numberOfLines={1} ellipsizeMode="tail">{t(plain ? "web-pages.vault.lib.plain" : "web-pages.vault.lib.sealed")}</T>
          <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{t(plain ? "web-pages.vault.lib.plainWhy" : "web-pages.vault.lib.sealedWhy")}</T>
        </View>
        {plain ? <T size={15} color={C.accent} numberOfLines={1}>{t("web-pages.vault.lib.turnOn")}</T> : <IconIn icon={Icons.ChevronRight} size={14} tint={C.subtle} />}
      </ListRow>
    </ListCard>
  );
}

/** Security mode on, the viewer's secrets saved before it still in plain text: encrypted into their vault (`vault.migrate`). */
function PlainLeft({ ws, n }: { ws: string; n: number }) {
  const app = theApp;
  const C = useC();
  useApp((s) => s.doing);
  return (
    <ListCard>
      <ListRow>
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} color={C.ink}>{t("android-settings.vault.migrate.title", { n })}</T>
          <T size={13} line={19} color={C.muted}>{t("android-settings.vault.migrate.body")}</T>
        </View>
        <Button label={t("android-settings.vault.migrate.action")} primary busy={app.isDoing("vault.migrate", { workspace: ws })} onClick={() => {
          vaultAct(app, t("android-settings.vault.migrate.what"), t("android-settings.vault.migrate.done"), () => vaultCall(app, ws, "migrate"));
        }} />
      </ListRow>
    </ListCard>
  );
}

/**
 * The profiles' accounts the library keeps (a subscription's sign-in, a model's key), a section a kind as the Profile
 * list groups them; each opens its profile as that list does (an account on several stations, its own page).
 */
function ProfileAccounts({ ws }: { ws: string }) {
  const app = theApp;
  const C = useC();
  const topic = rememberTopic<ProfilesView>(Topics.profiles(ws));
  const view = topic.value;
  if (view == null) return null;
  const groups = new Map<string, typeof view.items>();
  for (const it of view.items) groups.set(it.group, [...(groups.get(it.group) ?? []), it]);
  return (
    <>
      {[...groups.entries()].map(([group, g]) => (
        <View key={group}>
          <SectionHeader title={g[0]!.groupTitle} start={24} />
          <ListCard>
            {g.map((e) => {
              const p = e.profile;
              return (
                <ListRow key={e.key} onClick={() => app.push((e.members ?? []).filter((m) => m.role !== "user").length > 1 ? { kind: "ProfileAccount", key: e.key } : { kind: "Profile", address: e.station, profile: p.id })}>
                  <RowMark><ProviderMark runtime={p.runtime} kind={p.access.kind} size={18} mark={p.providerMark} /></RowMark>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{p.name}</T>
                    <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{["Profile", e.where].filter((x) => x !== "").join(" · ")}</T>
                  </View>
                  <IconIn icon={Icons.ChevronRight} size={14} tint={C.subtle} />
                </ListRow>
              );
            })}
          </ListCard>
        </View>
      ))}
    </>
  );
}

/**
 * A vault's secrets after the profiles' accounts, a section each kind: each one's name, and when an agent last used it
 * (else what agents may do with it); in a library not locked, that it is not encrypted, first. A tap opens its page.
 */
function LibraryVault({ ws, v, plain }: { ws: string; v: VaultRow; plain: boolean }) {
  const app = theApp;
  const C = useC();
  const topic = rememberTopic<VaultItemsView>(Topics.vaultItems(ws, v.id));
  const items = topic.value?.items;
  if (items == null) return null;
  const warn = C.warn;
  // Locked here: those whose names it does not know, a tap unlocking it; unlocked, locking it again.
  const hidden = items.filter((it) => it.name == null);
  return (
    <>
      {ITEM_SECTIONS.map((kind) => {
        const rows = items.filter((it) => it.name != null && it.kind === kind);
        if (rows.length === 0) return null;
        return (
          <View key={kind}>
            <SectionHeader title={kindName(kind)} start={24} />
            <ListCard>
              {rows.map((row) => (
                <ListRow key={row.id} onClick={() => app.push({ kind: "VaultItem", vault: v.id, item: row.id })}>
                  <RowMark><IconIn icon={kindIcon(row.kind)} size={18} tint={C.subtle} /></RowMark>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{row.name ?? ""}</T>
                    <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail">
                      {plain && <Text style={{ color: warn }}>{`${t("web-pages.vault.risk.row")} · `}</Text>}
                      {row.lastUse != null ? t("web-pages.vault.uses.last", { when: row.lastUse.at.ago }) : agentLine(row.listed, row.modes, row.hosts)}
                    </T>
                  </View>
                  <IconIn icon={Icons.ChevronRight} size={14} tint={C.subtle} />
                </ListRow>
              ))}
            </ListCard>
          </View>
        );
      })}
      {!plain && (hidden.length > 0 || v.open) && (
        <ListCard>
          {hidden.length > 0 && (
            <ListRow onClick={() => vaultAct(app, t("android-settings.vault.lockedNote"), null, () => vaultCall(app, ws, "open", { item: hidden[0]!.id }))}>
              <RowMark><IconIn icon={Icons.Key} size={18} tint={C.subtle} /></RowMark>
              <T size={15} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ flex: 1, minWidth: 0 }}>{t("android-settings.vault.lockedNote")}</T>
            </ListRow>
          )}
          {v.open && (
            <ListRow onClick={() => { vaultCall(app, ws, "lock").catch(() => undefined); }}>
              <RowMark />
              <T size={15} color={C.accent} style={{ flex: 1, minWidth: 0 }}>{t("android-settings.vault.lock")}</T>
            </ListRow>
          )}
        </ListCard>
      )}
    </>
  );
}

/**
 * 添加 in the library: a subscription or a model's key (a profile, added on the Profile list), or a secret of a kind (its
 * editor, the kind fixed). Not locked: that such a secret is kept in the clear, under the list.
 */
function addSheet(app: AppState, ws: string) {
  app.sheet = new SheetSpec(0.55, true, null, null, false, () => <AddSheet app={app} ws={ws} />);
}

function AddSheet({ app, ws }: { app: AppState; ws: string }) {
  const C = useC();
  const topic = rememberTopic<VaultsView>(Topics.vaults(ws));
  const view = topic.value;
  const mine = view?.vaults.find((v) => v.mine);
  const plain = view?.plain === true;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.vault.addKind.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <ListCard>
          <AddRow icon={Icons.Quota} kind="profile" onClick={() => { app.sheet = null; app.push({ kind: "Profiles" }); }} />
          {mine != null && ITEM_SECTIONS.map((k) => <AddRow key={k} icon={kindIcon(k)} kind={k} onClick={() => editorSheet(app, ws, mine.id, null, k, plain)} />)}
        </ListCard>
        {plain && mine != null && <T size={13} line={19} color={C.warn} style={{ paddingHorizontal: 24 }}>{t("web-pages.vault.risk.editor")}</T>}
      </ScrollView>
    </>
  );
}

function AddRow({ icon, kind, onClick }: { icon: IconPaths; kind: string; onClick: () => void }) {
  const C = useC();
  return (
    <ListRow onClick={onClick}>
      <RowMark><IconIn icon={icon} size={18} tint={C.subtle} /></RowMark>
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} color={C.ink}>{t(`web-pages.vault.addKind.${kind}`)}</T>
        <T size={13} color={C.muted}>{t(`web-pages.vault.addKind.${kind}Detail`)}</T>
      </View>
    </ListRow>
  );
}

function KindTile({ kind }: { kind: string | null }) {
  const C = useC();
  return (
    <Smooth radius={10} style={{ width: 32, height: 32, backgroundColor: C.bg, alignItems: "center", justifyContent: "center" }}>
      <IconIn icon={kindIcon(kind)} size={16} tint={kind == null ? C.subtle : C.ink} />
    </Smooth>
  );
}

/** A round icon button, named for screen readers. */
function RoundIcon({ icon, said, tint, size = 34, onClick }: { icon: IconPaths; said: string; tint?: string; size?: number; onClick: () => void }) {
  const C = useC();
  return (
    <Pressable accessibilityLabel={said} onPress={onClick} android_ripple={ripple(C.ink)} style={{ width: size, height: size, borderRadius: size / 2, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
      <IconIn icon={icon} size={18} tint={tint ?? C.muted} />
    </Pressable>
  );
}

/** A secondary action in words alone (no ground, no frame). */
function TextAction({ label, color, onClick }: { label: string; color?: string; onClick: () => void }) {
  const C = useC();
  return (
    <Smooth radius={8} style={{ alignSelf: "flex-start" }}>
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={{ paddingHorizontal: 6, paddingVertical: 6 }}>
        <T size={14} color={color ?? C.accent}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/** The devices that hold each vault's key; its owner gives it to the ones set up since (`vault.addDevice`). */
function Devices({ ws, view }: { ws: string; view: VaultsView }) {
  const app = theApp;
  const C = useC();
  useApp((s) => s.doing);
  return (
    <>
      <SectionHeader title={t("android-settings.vault.devices")} start={24} />
      <ListCard>
        {view.vaults.map((v) => {
          const giving = app.isDoing("vault.addDevice", { workspace: ws, vault: v.id });
          const give = v.mine && v.keyed && v.missing > 0;
          const hold = t("android-settings.vault.devicesHold", { n: v.devices });
          return (
            <ListRow key={v.id} onClick={give && !giving ? () => vaultAct(app, t("android-settings.vault.giveKey"), t("android-settings.vault.gaveKey"), () => vaultCall(app, ws, "addDevice", { vault: v.id })) : null}>
              <View style={{ flex: 1, minWidth: 0 }}>
                <T size={15} color={C.ink}>{view.vaults.length > 1 ? `${v.name} · ${hold}` : hold}</T>
                {v.missing > 0 && <T size={13} color={C.warn}>{t("android-settings.vault.missing", { n: v.missing })}</T>}
              </View>
              {giving ? <Spinner /> : give ? <T size={14} color={C.accent}>{t("android-settings.vault.giveKey")}</T> : null}
            </ListRow>
          );
        })}
      </ListCard>
    </>
  );
}

// ── an item ────────────────────────────────────────────────────────────

/** What `vault.open` gives of an item (the system's prompt first when its vault is locked here), or null when it did not. */
async function openPlain(app: AppState, ws: string, item: string): Promise<Plain | null> {
  try {
    const said = (await vaultCall(app, ws, "open", { item })) as { plain: Partial<Plain> & { kind: string; name: string } };
    return plainOf(said.plain);
  } catch (e) {
    if (!(e instanceof CoreError)) throw e;
    const why = vaultSaid(e);
    if (why != null) app.toast = t("android-misc.act.failed", { what: t("android-settings.vault.openWhat"), error: why });
    return null;
  }
}

/**
 * A secret's page (as the narrow web's VaultItemScreen): its kind and where it is kept; in a library not locked, that it
 * is not encrypted and the way to lock it; its content masked until shown (`vault.open`), each field shown and copied;
 * how agents may use it; when they did, each use leading to its chat. 编辑 opens it first, then its editor.
 */
export function VaultItemScreen({ current, vault, item }: { current: WorkspaceEntry; vault: string; item: string }) {
  const app = theApp;
  const C = useC();
  const ws = current.workspace.id;
  const vaults = rememberTopic<VaultsView>(Topics.vaults(ws));
  const items = rememberTopic<VaultItemsView>(Topics.vaultItems(ws, vault));
  const uses = rememberTopic<VaultUsesView>(Topics.vaultUses(ws, vault, item));
  // What it holds, once shown: on this page only, while it is up.
  const [opened, setOpened] = useState<Plain | null>(null);
  const [opening, setOpening] = useState(false);
  const v = vaults.value?.vaults.find((it) => it.id === vault);
  const row = items.value?.items.find((it) => it.id === item);
  const plain = vaults.value?.plain === true;
  const open = (then: (p: Plain) => void = () => {}) => {
    if (opening) return;
    setOpening(true);
    void (async () => {
      const got = await openPlain(app, ws, item);
      if (got != null) { setOpened(got); then(got); }
      setOpening(false);
    })();
  };
  const back = t("android-settings.vault.title");
  if (v == null || row == null) {
    return (
      <View style={{ flex: 1 }}>
        <NavBar back={back} onBack={() => app.pop()} title={back} />
        <Waiting shape={WaitShape.Cards} count={2} error={vaults.error?.message ?? items.error?.message} />
      </View>
    );
  }
  const shown = opened;
  const list = uses.value?.uses;
  return (
    <View style={{ flex: 1 }}>
      <NavBar
        back={back}
        onBack={() => app.pop()}
        title={row.name ?? ""}
        sub={() => <T size={11} color={C.muted} numberOfLines={1}>{[kindName(row.kind), t("web-pages.vault.storedOn", { station: v.stationName })].filter((x) => x !== "").join(" · ")}</T>}
        trailing={() => <RoundIcon icon={Icons.Edit} said={t("common.edit")} tint={C.ink} onClick={() => {
          if (opened != null) editorSheet(app, ws, vault, { item: row, plain: opened }, null, plain);
          else open((it) => editorSheet(app, ws, vault, { item: row, plain: it }, null, plain));
        }} />}
      />
      <ScrollView style={{ flex: 1 }}>
        {plain && (
          <ListCard>
            <Body>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                <Dot on={false} warn />
                <T size={15} weight="600" color={C.ink}>{t("web-pages.vault.risk.title")}</T>
              </View>
              <T size={14} line={21} color={C.subtle}>{t("web-pages.vault.risk.body", { station: v.stationName })}</T>
              <Link label={t("web-pages.vault.lib.turnOn")} onClick={() => app.push({ kind: "Security" })} />
            </Body>
          </ListCard>
        )}
        <SectionHeader title={t("web-pages.vault.content")} start={24} />
        <ListCard>
          {shown == null ? (
            <ListRow>
              {/* Masked, as long whatever its length (which would say something of it). */}
              <T size={14} color={C.ink} numberOfLines={1} ellipsizeMode="clip" style={{ fontFamily: CODE_FONT, flex: 1, minWidth: 0 }}>••••••••••••••••••••</T>
              {opening ? <Spinner inline /> : <Link label={t("web-pages.vault.show")} onClick={() => open()} />}
            </ListRow>
          ) : (FIELDS[shown.kind] ?? Object.keys(shown.fields)).map((f) => {
            const value = shown.fields[f];
            return value ? <FieldRow key={f} label={fieldName(f)} value={value} secret={!OPEN_FIELDS.has(f)} /> : null;
          })}
        </ListCard>
        <SectionHeader title={t("web-pages.vault.forAgents")} start={24} />
        <ListCard>
          <Body>
            {!row.listed ? <T size={15} color={C.muted}>{t("web-pages.vault.notForAgents")}</T> : (
              <>
                <Fact label={t("web-pages.vault.how")} value={row.modes.map((m) => howLine(m, row.hosts)).join("、")} />
                {row.env ? <Fact label={t("android-settings.vault.env")} value={row.env} mono /> : null}
              </>
            )}
          </Body>
        </ListCard>
        <SectionHeader title={t("web-pages.vault.uses.title")} start={24} />
        <ListCard>
          {list == null ? <ListRow><T size={15} color={C.muted}>{uses.error?.message ?? t("web-pages.settings.reading")}</T></ListRow>
            : list.length === 0 ? <ListRow><T size={15} color={C.muted}>{t("web-pages.vault.uses.none")}</T></ListRow>
            : list.map((u, i) => <UseRow key={`${u.session}/${u.at.at}/${i}`} ws={ws} u={u} />)}
        </ListCard>
        <View style={{ height: 30 }} />
      </ScrollView>
    </View>
  );
}

/** A fact of an item: its name in a narrow column, then what it is. */
function Fact({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  const C = useC();
  return (
    <View style={{ flexDirection: "row", gap: 16 }}>
      <T size={14} line={21} color={C.muted} style={{ minWidth: 52 }}>{label}</T>
      <T size={mono ? 14 : 15} line={21} color={C.ink} style={[{ flex: 1, minWidth: 0 }, mono && { fontFamily: CODE_FONT }]}>{value}</T>
    </View>
  );
}

/** An agent's use of an item: its chat (turned down, said so), the command or how it was given, when; a tap opens the chat. */
function UseRow({ ws, u }: { ws: string; u: VaultUse }) {
  const app = theApp;
  const C = useC();
  const warn = C.warn;
  const s = u.station;
  return (
    <ListRow onClick={s != null ? () => app.push({ kind: "Chat", station: `${ws}/${s}`, of: ChatOf.Session(u.session) }) : null}>
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail">
          {u.chatTitle ?? u.session}
          {u.denied === true && <Text style={{ color: warn }}>{` · ${t("web-pages.vault.uses.denied")}`}</Text>}
        </T>
        <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ fontFamily: CODE_FONT }}>{u.command ?? howLine(u.mode, u.hosts)}</T>
      </View>
      <T size={13} color={C.muted} numberOfLines={1}>{u.at.ago}</T>
    </ListRow>
  );
}

/** A link in words in a card's body: no ground, flush with the text around it. */
function Link({ label, onClick }: { label: string; onClick: () => void }) {
  const C = useC();
  return <T size={15} color={C.accent} onPress={onClick} suppressHighlighting>{label}</T>;
}

/** A field of an opened item: its name over its value (dots until shown, when secret), shown and copied from beside it. */
function FieldRow({ label, value, secret }: { label: string; value: string; secret: boolean }) {
  const app = theApp;
  const C = useC();
  const [shown, setShown] = useState(!secret);
  return (
    <View style={{ alignSelf: "stretch", flexDirection: "row", paddingLeft: 16, paddingRight: 8, paddingTop: 10, paddingBottom: 10, alignItems: "center", gap: 2 }}>
      <View style={{ flex: 1, minWidth: 0, gap: 2 }}>
        <T size={12} color={C.muted}>{label}</T>
        {/* Masked, as long whatever its length (which would say something of it). */}
        <T size={14} line={20} color={C.ink} numberOfLines={shown ? undefined : 1} ellipsizeMode="tail" style={{ fontFamily: CODE_FONT }}>{shown ? value : "••••••••••••"}</T>
      </View>
      {secret && <RoundIcon icon={Icons.Eye} said={shown ? t("android-settings.vault.hide") : t("android-settings.vault.reveal")} tint={shown ? C.accent : C.muted} onClick={() => setShown(!shown)} />}
      <RoundIcon icon={Icons.Copy} said={t("common.copy")} onClick={() => copy(app, value, secret)} />
    </View>
  );
}

/**
 * Copied to the clipboard: a secret marked sensitive (the system's preview of it masked, Android 13 on) and cleared 30
 * seconds later, unless something else was copied meanwhile (when the clipboard cannot be read then, the app not in
 * front, it is cleared all the same: a secret left there is worse).
 */
function copy(app: AppState, text: string, secret: boolean) {
  // NATIVE: ClipDescription.EXTRA_IS_SENSITIVE on the clip (Android 13's masked preview); expo-clipboard sets plain text only.
  void Clipboard.setStringAsync(text);
  app.toast = secret ? t("android-settings.vault.copied") : t("common.copied");
  if (!secret) return;
  setTimeout(() => {
    void (async () => {
      const now = await Clipboard.getStringAsync().catch(() => null);
      // NATIVE: ClipboardManager.clearPrimaryClip; an empty text stands in for it.
      if (now == null || now === "" || now === text) await Clipboard.setStringAsync("").catch(() => undefined);
    })();
  }, 30_000);
}

// ── the editor ─────────────────────────────────────────────────────────

/** An item being changed: as its vault's list has it (its listing), and what it holds as opened. */
interface Editing { item: VaultItemRow; plain: Plain }

/** `kind`: a new one of that kind (chosen in 添加), no kind to switch; `plain`: the library not locked, said at its top. */
function editorSheet(app: AppState, ws: string, vault: string, editing: Editing | null, kind: string | null = null, plain = false) {
  app.sheet = new SheetSpec(0.92, false, null, null, false, () => <Editor app={app} ws={ws} vault={vault} editing={editing} fixed={kind} plainLibrary={plain} />);
}

/**
 * An item written (`vault.putItem`): its kind, name and fields, and whether agents may ask for it (then how it is given,
 * where to, under which variable). The sheet stays while it is saved (the system's prompt may come up for a locked
 * vault): turned down, nothing is lost; refused, why stands under it. 删除这一条 for one that is there.
 */
function Editor({ app, ws, vault, editing, fixed, plainLibrary }: { app: AppState; ws: string; vault: string; editing: Editing | null; fixed: string | null; plainLibrary: boolean }) {
  const C = useC();
  const was = editing?.plain ?? null;
  const [kind, setKind] = useState(Math.max(0, KINDS.indexOf(was?.kind ?? fixed ?? "")));
  const [name, setName] = useState(was?.name ?? "");
  const [fields, setFields] = useState<Record<string, string>>({ ...(was?.fields ?? {}) });
  const [agent, setAgent] = useState(editing?.item.listed ?? false);
  const [mode, setMode] = useState(editing?.item.modes.find((m) => m === "proxy" || m === "env") ?? "proxy");
  const [hosts, setHosts] = useState(editing?.item.hosts.join(", ") ?? "");
  const [env, setEnv] = useState(editing?.item.env ?? "");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const k = KINDS[kind]!;
  const field = (f: string) => fields[f] ?? "";
  const put = (f: string) => (value: string) => setFields((was2) => ({ ...was2, [f]: value }));
  const hostList = hosts.split(/[, \n]/).map((h) => h.trim()).filter((h) => h !== "");
  const modes = k === "ssh_key" ? ["ssh"] : [mode];
  const filled = k === "token" ? field("value").trim() !== "" : k === "ssh_key" ? field("private_key").trim() !== "" : field("username").trim() !== "" || field("password").trim() !== "";
  const noHosts = agent && mode === "proxy" && k !== "ssh_key" && hostList.length === 0;
  const ready = name.trim() !== "" && filled && !noHosts;

  const save = () => {
    if (saving || !ready) return;
    setSaving(true);
    setError(null);
    const kept: Record<string, string> = {};
    // A private key as pasted (its last line break is part of it); the rest without the spaces around them.
    for (const f of FIELDS[k]!) {
      const v = fields[f];
      if (v == null) continue;
      const value = f === "private_key" ? v : v.trim();
      if (value.trim() !== "") kept[f] = value;
    }
    const plain = { kind: k, name: name.trim(), fields: kept, domains: [...(was?.domains ?? [])], notes: was?.notes ?? "" };
    const listing = !agent ? null : {
      name: name.trim(),
      kind: k,
      modes,
      hosts: modes.length === 1 && modes[0] === "proxy" ? hostList : [],
      ...(env.trim() !== "" && k !== "ssh_key" ? { env: env.trim() } : {}),
    };
    void (async () => {
      try {
        await vaultCall(app, ws, "putItem", { vault, ...(editing != null ? { id: editing.item.id } : {}), plain, ...(listing != null ? { listing } : {}) });
        app.sheet = null;
      } catch (e) {
        if (!(e instanceof CoreError)) throw e;
        const why = vaultSaid(e);
        // Written elsewhere first: the vault was read again; what is here was written over that, so it goes.
        if (e.code === "vault_conflict") { app.sheet = null; app.toast = why; } else setError(why);
      } finally {
        setSaving(false);
      }
    })();
  };

  const optional = (f: string) => t("android-settings.vault.optional", { name: fieldName(f) });
  return (
    <>
      <SheetGrab />
      <SheetHead
        title={was == null ? t("android-settings.vault.newTitle") : t("android-settings.vault.editTitle", { name: was.name })}
        trailing={() => <Button label={t("common.save")} primary busy={saving} enabled={ready} onClick={save} />}
      />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, gap: 12 }} keyboardShouldPersistTaps="handled">
        {plainLibrary && <T size={13} line={19} color={C.warn}>{t("web-pages.vault.risk.editor")}</T>}
        {was == null && fixed == null && <Seg options={KINDS.map(kindName)} selected={kind} onSelect={setKind} height={34} fill />}
        <Labeled label={t("android-settings.vault.name")}><VaultField value={name} onChange={setName} placeholder={t("android-settings.vault.namePlaceholder")} /></Labeled>
        {k === "token" ? (
          <Labeled label={fieldName("value")}><VaultField value={field("value")} onChange={put("value")} placeholder="ghp_…" mono secret /></Labeled>
        ) : k === "ssh_key" ? (
          <>
            <Labeled label={fieldName("private_key")}><VaultField value={field("private_key")} onChange={put("private_key")} placeholder="-----BEGIN OPENSSH PRIVATE KEY-----" mono lines={4} /></Labeled>
            <Labeled label={optional("public_key")}><VaultField value={field("public_key")} onChange={put("public_key")} placeholder="ssh-ed25519 AAAA…" mono lines={2} /></Labeled>
          </>
        ) : (
          <>
            <Labeled label={fieldName("username")}><VaultField value={field("username")} onChange={put("username")} placeholder="name@example.com" /></Labeled>
            <Labeled label={fieldName("password")}><VaultField value={field("password")} onChange={put("password")} placeholder="" mono secret /></Labeled>
            <Labeled label={optional("totp")}><VaultField value={field("totp")} onChange={put("totp")} placeholder="JBSWY3DPEHPK3PXP" mono secret /></Labeled>
          </>
        )}
        <Smooth radius={16} style={{ alignSelf: "stretch", backgroundColor: C.surface, paddingHorizontal: 16, paddingVertical: 14, gap: 12 }}>
          <Pressable onPress={() => setAgent(!agent)} android_ripple={ripple(C.ink)} style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink}>{t("android-settings.vault.agent")}</T>
              <T size={13} color={C.muted}>{t("android-settings.vault.agentNote")}</T>
            </View>
            <Switch on={agent} />
          </Pressable>
          {agent && (k === "ssh_key" ? (
            <Labeled label={t("android-settings.vault.how")}>
              <T size={15} color={C.ink}>{modeName("ssh")}</T>
              <T size={12} line={18} color={C.muted}>{t("android-settings.vault.sshNote")}</T>
            </Labeled>
          ) : (
            <>
              <Labeled label={t("android-settings.vault.how")}>
                <Seg options={[modeName("proxy"), modeName("env")]} selected={mode === "env" ? 1 : 0} onSelect={(i: number) => setMode(i === 1 ? "env" : "proxy")} height={34} fill />
                <T size={12} line={18} color={C.muted} style={{ paddingTop: 4 }}>{t("android-settings.vault.howNote")}</T>
              </Labeled>
              {mode === "proxy" && (
                <Labeled label={t("android-settings.vault.hosts")}>
                  <VaultField value={hosts} onChange={setHosts} placeholder="api.github.com, uploads.github.com" />
                  {noHosts && hosts !== "" && <T size={12} color={C.red}>{t("android-settings.vault.hostsNeeded")}</T>}
                </Labeled>
              )}
              <Labeled label={t("android-settings.vault.env")}><VaultField value={env} onChange={(it) => setEnv(it.trim())} placeholder={t("android-settings.vault.envPlaceholder")} mono /></Labeled>
            </>
          ))}
        </Smooth>
        {error != null && <T size={13} color={C.red}>{error}</T>}
        {editing != null && (
          <TextAction label={t("android-settings.vault.delete")} color={C.red} onClick={() => {
            confirm(app, t("android-settings.vault.deleteTitle", { name: editing.plain.name }), t("android-settings.vault.deleteText"), t("common.delete"), true, t("android-settings.vault.deleteWhat"), null, async () => {
              await vaultCall(app, ws, "deleteItem", { vault, item: editing.item.id });
            });
          }} />
        )}
      </ScrollView>
    </>
  );
}

/** A field's name over it. */
function Labeled({ label, children }: { label: string; children?: ReactNode }) {
  const C = useC();
  return (
    <View style={{ alignSelf: "stretch", gap: 6 }}>
      <T size={13} color={C.muted}>{label}</T>
      {children}
    </View>
  );
}

/**
 * A line (or `lines`) to type a secret's parts in, as the settings' fields are (Workspaces.kt Field) but of any length;
 * `secret`: dots until the eye beside it is tapped, and no suggestions kept by the keyboard.
 */
function VaultField({ value, onChange, placeholder, mono = false, secret = false, lines = 1 }: { value: string; onChange: (v: string) => void; placeholder: string; mono?: boolean; secret?: boolean; lines?: number }) {
  const C = useC();
  const [shown, setShown] = useState(false);
  const size = mono ? 14 : 15;
  return (
    <Smooth radius={12} stroke={{ width: 1, color: C.line }} style={{ alignSelf: "stretch", flexDirection: "row", alignItems: "center", gap: 8, backgroundColor: C.surface, paddingLeft: 12, paddingRight: secret ? 8 : 12, paddingTop: 10, paddingBottom: 10 }}>
      <TextInput
        value={value}
        onChangeText={onChange}
        placeholder={placeholder}
        placeholderTextColor={C.subtle}
        multiline={lines > 1}
        numberOfLines={lines > 1 ? lines : undefined}
        secureTextEntry={secret && !shown}
        autoCapitalize="none"
        autoCorrect={!secret && !mono}
        keyboardType={secret ? (shown ? "visible-password" : "default") : mono ? "ascii-capable" : "default"}
        cursorColor={C.accent}
        textAlignVertical={lines > 1 ? "top" : "center"}
        style={{ flex: 1, minWidth: 0, color: C.ink, fontSize: size, lineHeight: 20, fontFamily: mono ? CODE_FONT : undefined, padding: 0, includeFontPadding: false, minHeight: lines * 20, maxHeight: lines === 1 ? 20 : 200 }}
      />
      {secret && (
        <Pressable accessibilityLabel={shown ? t("android-settings.vault.hide") : t("android-settings.vault.reveal")} onPress={() => setShown(!shown)} android_ripple={ripple(C.ink)} style={{ width: 20, height: 20, borderRadius: 10, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
          <IconIn icon={Icons.Eye} size={18} tint={shown ? C.accent : C.subtle} />
        </Pressable>
      )}
    </Smooth>
  );
}

// ── recovering ─────────────────────────────────────────────────────────

/** This device keyed into the person's vaults again by their 24 recovery words (`vault.recover`). */
function recoverSheet(app: AppState, ws: string) {
  app.sheet = new SheetSpec(0.62, false, null, null, false, () => <RecoverSheet app={app} ws={ws} />);
}

function RecoverSheet({ app, ws }: { app: AppState; ws: string }) {
  const C = useC();
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const n = text.trim().split(/\s+/).filter((w) => w !== "").length;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-settings.vault.recover")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 10 }} keyboardShouldPersistTaps="handled">
        <T size={14} color={C.muted}>{t("android-settings.vault.recoverLead")}</T>
        <VaultField value={text} onChange={(it) => { setText(it); setError(null); }} placeholder="orbit canvas lemon …" mono lines={5} />
        <T size={12} color={n === 24 ? C.green : C.subtle}>{t("android-settings.vault.recoverCount", { n })}</T>
        {error != null && <T size={13} color={C.red}>{error}</T>}
        <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button label={t("android-settings.vault.recoverAction")} primary busy={busy} enabled={n === 24} onClick={() => {
            setBusy(true);
            void (async () => {
              try {
                const said = (await vaultCall(app, ws, "recover", { words: text.trim() })) as { recovered?: unknown } | null;
                const got = typeof said?.recovered === "number" ? Math.trunc(said.recovered) : 0;
                app.sheet = null;
                app.toast = got > 0 ? t("android-settings.vault.recovered", { n: got }) : t("android-settings.vault.recoveredNone");
              } catch (e) {
                if (!(e instanceof CoreError)) throw e;
                setError(vaultSaid(e));
              } finally {
                setBusy(false);
              }
            })();
          }} />
        </View>
      </ScrollView>
    </>
  );
}
