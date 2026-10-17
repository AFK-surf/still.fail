// What the desktop's settings do that the app does too (docs/mobile-parity.md), as the narrow web has it
// (web/src/mobile/WorkspacePage.tsx, sheets.tsx, Stations.tsx): the workspace itself (its name, its people, leaving or
// deleting it), where the account is signed in, and adding, renaming and removing stations. Asking is a sheet: whether
// to go on with what cannot be undone, a name, a command to copy.
import { useRef, useState, type ReactNode } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import * as Clipboard from "expo-clipboard";
// The system's photo picker, and the picture cut to its middle square at 96 px (the Android app's BitmapFactory and
// Bitmap.compress).
import * as ImagePicker from "expo-image-picker";
import { ImageManipulator, SaveFormat } from "expo-image-manipulator";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { JoinableStation, JoinableView, StationView } from "../../../../web/src/core/shapes.ts";
import { app as theApp, SheetSpec, useApp, type AppState } from "../AppState";
import { APP_NAME } from "../build";
import { manager, ROLE_HINT, ROLE_LABEL, type LoginSession, type Member, type SlackPerson, type WorkspaceEntry, type WorkspaceView } from "../data/Accounts";
import { Cloud, errorText, type Enrollment } from "../data/Calls";
import { rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { Button, DoingMark, Field, PickRow } from "../ui/Controls";
import { Icons } from "../ui/Icon";
import { StationIcons } from "../ui/IconSet";
import { Avatar, glyphColor, hasStationMark, IconIn, Illustration, LargeTitle, ListCard, ListRow, MARK_COLORS, markColor, NavButton, ripple, SectionHeader, Seg, StationMark } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { CODE_FONT, useC, withAlpha } from "../ui/Theme";
import { Spinner, WaitLine, WaitShape, Waiting } from "../ui/Waiting";
import { Action, useAction } from "./Action";
import { SecretField } from "./Connects";
import { TopBack } from "./Stations";

/** What is under way, followed: a page that asks `app.isDoing` is drawn again as it changes. */
const useDoing = () => useApp((s) => s.doing);

// ── asking ─────────────────────────────────────────────────────────────

/**
 * Asks before something that cannot be undone. With `what` (a verb phrase, as [AppState.act] takes) the sheet closes at
 * once, `then` runs (a page left, say) and `run` goes on by itself, the thing it is about marked under way, a failure
 * told by a toast; without it the sheet stays, with what went wrong, until it is done. Kotlin's named arguments in
 * their order; `run` last, alone after `action` when none is given.
 */
/** Kotlin's named arguments by name, for a caller that gives only some of them. */
export interface ConfirmNamed { danger?: boolean; what?: string | null; then?: (() => void) | null }
export interface AskNamed { secret?: boolean; hint?: string | null; what?: string | null; empty?: boolean }

export function confirm(app: AppState, title: string, text: string, action: string, run: () => Promise<void>): void;
export function confirm(app: AppState, title: string, text: string, action: string, danger: boolean, what: string | null | undefined, then: (() => void) | null | undefined, run: () => Promise<void>): void;
export function confirm(app: AppState, title: string, text: string, action: string, named: ConfirmNamed, run: () => Promise<void>): void;
export function confirm(app: AppState, title: string, text: string, action: string, danger: boolean | ConfirmNamed | (() => Promise<void>), what?: string | null | (() => Promise<void>), then?: (() => void) | null, run?: () => Promise<void>) {
  if (typeof danger === "object") return confirm(app, title, text, action, danger.danger ?? false, danger.what, danger.then, what as () => Promise<void>);
  const work = typeof danger === "function" ? danger : run!;
  const red = typeof danger === "function" ? false : danger;
  const after = then ?? (() => {});
  app.sheet = new SheetSpec(0.36, false, null, null, false, () => <ConfirmSheet app={app} title={title} text={text} action={action} danger={red} what={(what as string | null | undefined) ?? null} then={after} run={work} />);
}

function ConfirmSheet({ app, title, text, action, danger, what, then, run }: { app: AppState; title: string; text: string; action: string; danger: boolean; what: string | null; then: () => void; run: () => Promise<void> }) {
  const C = useC();
  const operation = useAction(() => new Action(app));
  const busy = operation.busy;
  const error = operation.error?.message;
  return (
    <>
      <SheetGrab />
      <SheetHead title={title} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 10 }}>
        <T size={14} color={C.muted}>{text}</T>
        {error != null && <T size={13} color={C.red}>{error}</T>}
        <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button label={action} primary busy={busy} danger={danger} onClick={() => {
            if (what != null) { app.sheet = null; then(); app.act(what, run); }
            else operation.run(async () => { await run(); app.sheet = null; });
          }} />
        </View>
      </ScrollView>
    </>
  );
}

/**
 * Asks for a line (a name); `run` gets it trimmed. With `what`, as [confirm]: closes at once and goes on by itself.
 * Kotlin's named arguments in their order; `run` last, alone after `action` when none is given.
 */
export function ask(app: AppState, title: string, value: string, placeholder: string, action: string, run: (line: string) => Promise<void>): void;
export function ask(app: AppState, title: string, value: string, placeholder: string, action: string, secret: boolean, hint: string | null | undefined, what: string | null | undefined, empty: boolean, run: (line: string) => Promise<void>): void;
export function ask(app: AppState, title: string, value: string, placeholder: string, action: string, named: AskNamed, run: (line: string) => Promise<void>): void;
export function ask(app: AppState, title: string, value: string, placeholder: string, action: string, secret: boolean | AskNamed | ((line: string) => Promise<void>), hint?: string | null | ((line: string) => Promise<void>), what?: string | null, empty?: boolean, run?: (line: string) => Promise<void>) {
  if (typeof secret === "object") return ask(app, title, value, placeholder, action, secret.secret ?? false, secret.hint, secret.what, secret.empty ?? false, hint as (line: string) => Promise<void>);
  const work = typeof secret === "function" ? secret : run!;
  const hidden = typeof secret === "function" ? false : secret;
  app.sheet = new SheetSpec(0.42, false, null, null, false, () => <AskSheet app={app} title={title} value={value} placeholder={placeholder} action={action} secret={hidden} hint={(hint as string | null | undefined) ?? null} what={what ?? null} empty={empty ?? false} run={work} />);
}

function AskSheet({ app, title, value, placeholder, action, secret, hint, what, empty, run }: { app: AppState; title: string; value: string; placeholder: string; action: string; secret: boolean; hint: string | null; what: string | null; empty: boolean; run: (line: string) => Promise<void> }) {
  const C = useC();
  const [text, setText] = useState(value);
  const operation = useAction(() => new Action(app));
  const busy = operation.busy;
  const error = operation.error?.message;
  return (
    <>
      <SheetGrab />
      <SheetHead title={title} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 10 }} keyboardShouldPersistTaps="handled">
        {secret ? <SecretField value={text} onChange={setText} placeholder={placeholder} /> : <Field value={text} onChange={setText} placeholder={placeholder} />}
        {hint != null && <T size={12} color={C.muted}>{hint}</T>}
        {error != null && <T size={13} color={C.red}>{error}</T>}
        <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button label={action} primary busy={busy} enabled={(empty || text.trim() !== "") && text.trim() !== value} onClick={() => {
            const line = text.trim();
            if (what != null) { app.sheet = null; app.act(what, () => run(line)); }
            else operation.run(async () => { await run(line); app.sheet = null; });
          }} />
        </View>
      </ScrollView>
    </>
  );
}

/** A command to run elsewhere, with a button that copies it. */
export function CommandBox({ text }: { text: string }) {
  const C = useC();
  return (
    <Smooth radius={12} stroke={{ width: 1, color: C.line }} style={{ alignSelf: "stretch", flexDirection: "row", gap: 8, backgroundColor: C.surface2, paddingLeft: 12, paddingRight: 10, paddingTop: 10, paddingBottom: 10 }}>
      <T size={12} line={18} color={C.ink} style={{ fontFamily: CODE_FONT, flex: 1, minWidth: 0 }}>{text}</T>
      <Smooth radius={8} style={{ width: 32, height: 32, backgroundColor: C.chip }}>
        <Pressable
          onPress={() => { void Clipboard.setStringAsync(text); theApp.toast = t("common.copied"); }}
          android_ripple={ripple(C.ink)}
          style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
        >
          <IconIn icon={Icons.Copy} size={16} />
        </Pressable>
      </Smooth>
    </Smooth>
  );
}

// ── the workspace ──────────────────────────────────────────────────────

/**
 * The workspace itself, from settings (SettingsHome.kt), as the narrow web's WorkspacePage.tsx: its name as the title (a
 * tap renames it), its people in one list (those in it, those added who have not signed in, the invitations out), adding
 * them from the ＋ at the top, and leaving or deleting it at the bottom.
 */
export function WorkspaceScreen({ current }: { current: WorkspaceEntry }) {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  useDoing();
  const topic = rememberTopic<WorkspaceView>(Topics.workspace(current.workspace.id));
  const view = topic.value;
  const me = current.account;
  const cloud = new Cloud(app.core, me.sub);
  const body = (): ReactNode => {
    if (view == null) return <Waiting shape={WaitShape.Cards} text={t("android-settings.workspace.reading")} error={topic.error?.message} />;
    const name = view.name ?? "";
    const role = view.role ?? "member";
    const members = view.members ?? [];
    const added = view.added ?? [];
    const invitations = view.invitations ?? [];
    const stations = view.stations ?? [];
    const waiting = manager(view) ? added.length + invitations.length : 0;
    const renamed = { workspace: view.id };
    return (
      <>
        {/* Its name is the title, after its mark (when it has one), renamed by a tap on it (by its owner and admins). */}
        <Pressable disabled={!manager(view)} android_ripple={manager(view) ? ripple(C.ink) : undefined} onPress={() => {
          ask(app, t("android-settings.workspace.name"), name, t("android-settings.workspace.namePlaceholder"), t("common.save"), false, null, t("android-settings.workspace.renameWhat"), false, async (it) => {
            await cloud.renameWorkspace(view.id, it); app.toast = t("android-settings.renamed");
          });
        }}>
          <LargeTitle small="" big={name} lead={hasStationMark(view.emoji, view.icon) ? () => <StationMark emoji={view.emoji} icon={view.icon} size={30} tint={C.ink} /> : null} />
        </Pressable>
        <T size={13} color={C.muted} style={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 4 }}>
          {t(manager(view) ? "android-settings.workspace.aboutRename" : "android-settings.workspace.about", { role: ROLE_LABEL[role] ?? role, people: t("android-settings.members.count", { n: members.length }), stations: t("android-settings.workspace.stations", { n: stations.length }) })}
        </T>
        {/* Its mark, set by its owner and admins in the sheet a station's is (an icon, an emoji, a picture, or none). */}
        {manager(view) && (
          <>
            <View style={{ height: 10 }} />
            <ListCard>
              <ListRow onClick={() => {
                openMarkPick(app, name, view.emoji ?? null, view.icon ?? null, t("android-settings.workspace.iconWhat"), (emoji, icon) => cloud.setWorkspaceMark(view.id, emoji, icon));
              }}>
                <T size={15} color={C.ink} style={{ flex: 1, minWidth: 0 }}>{t("android-settings.workspace.icon")}</T>
                <DoingMark running={app.isDoing("workspace.rename", renamed)} failed={app.failedOf("workspace.rename", renamed)} />
                {hasStationMark(view.emoji, view.icon) ? <StationMark emoji={view.emoji} icon={view.icon} size={20} tint={C.ink} />
                  : <T size={14} color={C.muted}>{t("android-settings.workspace.iconNone")}</T>}
                <IconIn icon={Icons.ChevronRight} size={14} tint={C.subtle} />
              </ListRow>
            </ListCard>
          </>
        )}
        {/* Its people in one list: those in it, then those added who have not signed in yet, then the invitations out;
            which is which on each row's second line. */}
        <SectionHeader title={t("android-settings.members.title")} trailing={waiting > 0 ? t("android-settings.members.waiting", { n: members.length, waiting }) : t("android-settings.members.count", { n: members.length })} start={24} />
        <ListCard>
          {members.map((m) => <MemberRow key={`m/${m.sub ?? m.email}`} view={view} m={m} me={me.sub} cloud={cloud} />)}
          {manager(view) && added.map((a) => {
            const on = { workspace: view.id, email: a.email };
            const r = a.role ?? "member";
            return (
              <ListRow key={`a/${a.email}`}>
                <Avatar id={a.email} name={a.email} size={28} />
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} color={C.ink} numberOfLines={1}>{a.email}</T>
                  <T size={13} color={C.muted}>{t("android-settings.members.added", { role: ROLE_LABEL[r] ?? r })}</T>
                </View>
                <RowAction label={t("android-settings.members.remove")} color={C.accent} busy={app.isDoing("workspace.removeAdded", on)} failed={app.failedOf("workspace.removeAdded", on)} onClick={() => {
                  app.act(t("android-settings.members.removeWhat"), () => cloud.removeAdded(view.id, a.email), t("android-settings.members.removed"));
                }} />
              </ListRow>
            );
          })}
          {manager(view) && invitations.map((i) => {
            const on = { workspace: view.id, invitation: i.id };
            const r = i.role ?? "member";
            return (
              <ListRow key={`i/${i.id}`}>
                <Avatar id={i.email ?? i.id} name={i.email ?? "?"} size={28} />
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} color={C.ink}>{i.email ?? t("android-settings.members.anyone")}</T>
                  <T size={13} color={C.muted}>{t("android-settings.members.invitation", { role: ROLE_LABEL[r] ?? r, until: i.time?.["expires_at"]?.until ?? "" })}</T>
                </View>
                <RowAction label={t("android-settings.members.revoke")} color={C.accent} busy={app.isDoing("workspace.revokeInvitation", on)} failed={app.failedOf("workspace.revokeInvitation", on)} onClick={() => {
                  app.act(t("android-settings.members.revokeWhat"), () => cloud.revokeInvitation(view.id, i.id), t("android-settings.members.revoked"));
                }} />
              </ListRow>
            );
          })}
        </ListCard>
        <Relays view={view} cloud={cloud} />
        <View style={{ height: 18 }} />
        <ListCard>
          <ListRow onClick={() => {
            confirm(app, t("android-settings.workspace.leaveTitle", { name }), t("android-settings.workspace.leaveText"), t("android-settings.workspace.leave"), true,
              t("android-settings.workspace.leaveWhat"), () => app.home(), async () => {
                await cloud.removeMember(view.id, me.sub); app.toast = t("android-settings.workspace.left");
              });
          }}>
            <T size={15} color={C.red}>{t("android-settings.workspace.leaveRow")}</T>
          </ListRow>
          {role === "owner" && (
            <ListRow onClick={() => {
              confirm(app, t("android-settings.workspace.deleteTitle", { name }), t("android-settings.workspace.deleteText", { n: stations.length, app: APP_NAME }), t("android-settings.workspace.delete"), true,
                t("android-settings.workspace.deleteWhat"), () => app.home(), async () => {
                  await cloud.deleteWorkspace(view.id); app.toast = t("android-settings.workspace.deleted");
                });
            }}>
              <T size={15} color={C.red}>{t("android-settings.workspace.delete")}</T>
            </ListRow>
          )}
        </ListCard>
        <View style={{ height: 30 }} />
      </>
    );
  };
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.title")} onBack={() => app.pop()} trailing={view != null && manager(view) ? (
        <NavButton icon={Icons.UserPlus} onClick={() => { app.sheet = new SheetSpec(0.8, true, null, null, false, () => <AddSheet current={current} view={view} cloud={cloud} />); }} iconSize={20} />
      ) : null} />
      {body()}
    </ScrollView>
  );
}

/**
 * The workspace's own relays, used besides still.fail's by its stations and its members' devices: owners and admins add
 * one from the last row (a sheet that says why one is refused) and take one out from its row.
 */
function Relays({ view, cloud }: { view: WorkspaceView; cloud: Cloud }) {
  const app = theApp;
  const C = useC();
  useDoing();
  const relays = view.relays ?? [];
  if (!manager(view) && relays.length === 0) return null;
  const busy = app.isDoing("workspace.setRelays", { workspace: view.id });
  return (
    <>
      <SectionHeader title={t("android-settings.relays.title")} start={24} />
      <ListCard>
        {relays.map((url) => (
          <ListRow key={url}>
            <T size={15} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{url.replace(/^https:\/\//, "").replace(/^http:\/\//, "")}</T>
            {manager(view) && <RowAction label={t("android-settings.members.remove")} color={C.accent} busy={busy} onClick={() => {
              app.act(t("android-settings.relays.removeWhat"), () => cloud.setRelays(view.id, relays.filter((r) => r !== url)), t("android-settings.relays.removed"));
            }} />}
          </ListRow>
        ))}
        {manager(view) && (
          <ListRow onClick={busy ? null : () => {
            ask(app, t("android-settings.relays.add"), "", "https://relay.example.com", t("android-settings.relays.addAction"), false, t("android-settings.relays.hint"), null, false, async (it) => {
              await cloud.setRelays(view.id, [...relays, it]); app.toast = t("android-settings.relays.added");
            });
          }}>
            <T size={15} color={C.accent}>{t(busy ? "common.saving" : "android-settings.relays.add")}</T>
          </ListRow>
        )}
      </ListCard>
      <T size={13} color={C.muted} style={{ paddingLeft: 20, paddingRight: 20, paddingTop: 6 }}>{t("android-settings.relays.lead", { app: APP_NAME })}</T>
    </>
  );
}

/** A person of the workspace; the owner changes their role, a manager moves them out (an owner only by an owner). */
function MemberRow({ view, m, me, cloud }: { view: WorkspaceView; m: Member; me: string; cloud: Cloud }) {
  const app = theApp;
  const C = useC();
  useDoing();
  const role = m.role ?? "member";
  const can = m.sub !== me && manager(view) && (role !== "owner" || view.role === "owner");
  // Its role being set or it being moved out (the sheet that asked may be gone): a spinner, or a red mark a moment.
  const calls = ["workspace.setRole", "workspace.removeMember"];
  const on = { workspace: view.id, member: m.sub ?? "" };
  return (
    <ListRow onClick={can ? () => { app.sheet = new SheetSpec(0.5, false, null, null, false, () => <MemberSheet view={view} m={m} cloud={cloud} />); } : null}>
      <Avatar id={m.email} name={m.name || m.email} size={28} picture={m.picture} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
          <T size={15} color={C.ink} numberOfLines={1} style={{ flexShrink: 1 }}>{m.name || m.email}</T>
          {m.sub === me && <You text={t("android-settings.members.you")} />}
        </View>
        <T size={13} color={C.muted} numberOfLines={1}>{m.email}</T>
      </View>
      <DoingMark running={app.isDoing(calls, on)} failed={app.failedOf(calls, on)} />
      <T size={13} color={C.muted}>{ROLE_LABEL[role] ?? role}</T>
    </ListRow>
  );
}

/** A word at a row's end that does something (移除, 撤回, 退出): a spinner in its place while it is under way; a red mark before it a moment after it failed. */
function RowAction({ label, color, busy, failed, onClick }: { label: string; color: string; busy: boolean; failed?: string | null; onClick: () => void }) {
  const C = useC();
  if (busy) return <Spinner />;
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
      <DoingMark running={false} failed={failed ?? null} />
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)}>
        <T size={14} color={color}>{label}</T>
      </Pressable>
    </View>
  );
}

function You({ text }: { text: string }) {
  const C = useC();
  return (
    <Smooth radius={6} style={{ backgroundColor: C.accentBg, paddingHorizontal: 6 }}>
      <T size={12} color={C.accentInk}>{text}</T>
    </Smooth>
  );
}

function MemberSheet({ view, m, cloud }: { view: WorkspaceView; m: Member; cloud: Cloud }) {
  const app = theApp;
  const C = useC();
  useDoing();
  const sub = m.sub ?? "";
  // A role set closes the sheet at once; the person's row shows it under way (MemberRow), a toast if it failed.
  const setting = app.isDoing("workspace.setRole", { workspace: view.id, member: sub });
  return (
    <>
      <SheetGrab />
      <SheetHead title={m.name || m.email} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        {view.role === "owner" && ["owner", "admin", "member"].map((r) => (
          <PickRow key={r} label={ROLE_LABEL[r] ?? r} sub={ROLE_HINT[r]} checked={(m.role ?? "member") === r} enabled={!setting} onClick={() => {
            app.sheet = null;
            if (r !== (m.role ?? "member")) app.act(t("android-settings.members.roleWhat"), () => cloud.setRole(view.id, sub, r), t("android-settings.members.roleSet"));
          }} />
        ))}
        <PickRow label={t("android-settings.members.moveOutRow")} color={C.red} onClick={() => {
          confirm(app, t("android-settings.members.moveOutTitle", { email: m.email, name: view.name ?? "" }), t("android-settings.members.moveOutText"), t("android-settings.members.moveOut"), true,
            t("android-settings.members.moveOutWhat"), null, async () => {
              await cloud.removeMember(view.id, sub); app.toast = t("android-settings.members.movedOut");
            });
        }} />
      </ScrollView>
    </>
  );
}

/** The emails in what was typed or pasted: separated by commas, spaces, semicolons or lines; "Name <a@b.c>" too (web/src/cloud/adding.ts). */
function parseEmails(text: string): string[] {
  const found = text.match(/[^\s<>,;"'()]+@[^\s<>,;"'()]+\.[^\s<>,;"'()]+/g) ?? [];
  return [...new Set(found.map((e) => e.toLowerCase()))];
}

/**
 * Adding people by email, no invitation to accept: members at once when they have signed in to still.fail before, from their
 * first sign-in otherwise. Typed or pasted, or picked from the people of the Slack workspaces the online stations are in
 * (each station reads its own Slack).
 */
function AddSheet({ current, view, cloud }: { current: WorkspaceEntry; view: WorkspaceView; cloud: Cloud }) {
  const app = theApp;
  const C = useC();
  useDoing();
  const stations = rememberTopic<StationView[]>(Topics.stations(current.workspace.id));
  const online = (stations.value ?? []).filter((s) => s.online);
  const [text, setText] = useState("");
  const [role, setRole] = useState("member");
  const busy = app.isDoing("workspace.addMembers", { account: current.account.sub, workspace: view.id });
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [people, setPeople] = useState<SlackPerson[] | null>(null);
  const [problems, setProblems] = useState<string[]>([]);
  const [reading, setReading] = useState(false);
  const [picked, setPicked] = useState<ReadonlySet<string>>(new Set());
  const inside = new Set([...(view.members ?? []).map((m) => m.email.toLowerCase()), ...(view.added ?? []).map((a) => a.email.toLowerCase())]);
  const emails = [...new Set([...parseEmails(text), ...picked])].filter((e) => !inside.has(e));
  const roles = view.role === "owner" ? ["member", "admin", "owner"] : ["member", "admin"];
  const fromSlack = () => {
    setReading(true);
    void (async () => {
      const seen = new Map<string, SlackPerson>();
      const found: string[] = [];
      for (const s of online) {
        try {
          const [list, errors] = await app.api(s.station).slackPeople();
          for (const p of list) if (!seen.has(p.email)) seen.set(p.email, p);
          found.push(...errors);
        } catch (e) { if (e instanceof CoreError) found.push(e.message); else throw e; }
      }
      const all = [...seen.values()].sort((a, b) => Number(a.guest ?? false) - Number(b.guest ?? false) || ((a.name ?? "") < (b.name ?? "") ? -1 : (a.name ?? "") > (b.name ?? "") ? 1 : 0));
      setPeople(all); setProblems(found);
      // Once read, the workspace's own Slack people are picked; guests are left to choose.
      setPicked(new Set(all.filter((p) => !p.guest && !inside.has(p.email)).map((p) => p.email)));
      setReading(false);
    })();
  };
  const list = people;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-settings.add.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 10 }} keyboardShouldPersistTaps="handled">
        {done != null ? (
          <>
            <T size={14} color={C.ink}>{done}</T>
            <View style={{ flexDirection: "row", paddingBottom: 24, justifyContent: "flex-end" }}>
              <Button label={t("common.done")} primary onClick={() => { app.sheet = null; }} />
            </View>
          </>
        ) : (
          <>
            <T size={14} color={C.muted}>{t("android-settings.add.note", { name: view.name ?? "", app: APP_NAME })}</T>
            <T size={13} weight="600" color={C.ink}>{t("android-settings.add.emails")}</T>
            <Field value={text} onChange={setText} placeholder={t("android-settings.add.emailsPlaceholder")} lines={3} />
            {online.length > 0 && (list == null ? (
              <View style={{ flexDirection: "row" }}>
                <Button label={t("android-settings.add.fromSlack")} primary={false} busy={reading} onClick={fromSlack} />
              </View>
            ) : (
              <>
                <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
                  <T size={13} color={C.muted} style={{ flex: 1, minWidth: 0 }}>{t("android-settings.add.picked", { n: list.length, picked: [...picked].filter((e) => !inside.has(e)).length })}</T>
                  <Pressable onPress={() => setPicked(new Set(list.map((p) => p.email).filter((e) => !inside.has(e))))} android_ripple={ripple(C.ink)}>
                    <T size={14} color={C.accent}>{t("android-settings.all")}</T>
                  </Pressable>
                  <Pressable onPress={() => setPicked(new Set())} android_ripple={ripple(C.ink)}>
                    <T size={14} color={C.accent}>{t("android-settings.none")}</T>
                  </Pressable>
                </View>
                <View>
                  {list.map((p) => {
                    const there = inside.has(p.email);
                    return (
                      <PickRow
                        key={p.email}
                        label={p.name || p.email}
                        sub={[p.email, there ? t("android-settings.add.in") : p.guest ? t("android-settings.add.guest") : null].filter((x) => x != null).join(" · ")}
                        checked={there || picked.has(p.email)}
                        enabled={!there}
                        leading={() => <Avatar id={p.email} name={p.name || p.email} size={28} picture={p.image} />}
                        onClick={() => setPicked((was) => { const next = new Set(was); if (next.has(p.email)) next.delete(p.email); else next.add(p.email); return next; })}
                      />
                    );
                  })}
                </View>
                {problems.length > 0 && <T size={13} color={C.red}>{problems.join(t("android-settings.add.problemSep"))}</T>}
              </>
            ))}
            <T size={13} weight="600" color={C.ink}>{t("android-settings.add.role")}</T>
            <View>
              {roles.map((r) => <PickRow key={r} label={ROLE_LABEL[r] ?? r} sub={ROLE_HINT[r]} checked={role === r} onClick={() => setRole(r)} />)}
            </View>
            {error != null && <T size={13} color={C.red}>{error}</T>}
            <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
              <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
              <Button label={emails.length > 1 ? t("android-settings.add.many", { n: emails.length }) : t("android-settings.add.one")} primary busy={busy} enabled={emails.length > 0} onClick={() => {
                setError(null);
                void (async () => {
                  try {
                    const r = await cloud.addMembers(view.id, role, emails);
                    setDone(t("android-settings.add.done", {
                      list: [
                        r.joined.length > 0 ? t("android-settings.add.joined", { n: r.joined.length }) : "",
                        r.added.length > 0 ? t("android-settings.add.added", { n: r.added.length, app: APP_NAME }) : "",
                        r.already.length > 0 ? t("android-settings.add.already", { n: r.already.length }) : "",
                      ].filter((x) => x !== "").join(t("android-settings.add.sep")),
                    }));
                  } catch (e) { if (e instanceof CoreError) setError(errorText(e)); else throw e; }
                })();
              }} />
            </View>
          </>
        )}
      </ScrollView>
    </>
  );
}

// ── where the account is signed in ─────────────────────────────────────

/** The account's devices: where it is signed in to still.fail; one not recognised can be signed out from here. */
export function Devices({ current }: { current: WorkspaceEntry }) {
  const app = theApp;
  const C = useC();
  useDoing();
  const topic = rememberTopic<LoginSession[]>(Topics.loginSessions(current.account.sub));
  const list = topic.value;
  if (list == null) return <WaitLine text={topic.error ? t("android-settings.devices.failed", { error: topic.error.message }) : t("common.reading")} error={topic.error != null} modifier={{ paddingHorizontal: 20, paddingVertical: 8 }} />;
  const cloud = new Cloud(app.core, current.account.sub);
  return (
    <ListCard>
      {list.map((s) => (
        <ListRow key={s.id}>
          <View style={{ flex: 1, minWidth: 0 }}>
            <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
              <T size={15} color={C.ink} numberOfLines={1} style={{ flexShrink: 1 }}>{s.name || t("android-settings.devices.unnamed")}</T>
              {s.current === true && <You text={t("android-settings.devices.here")} />}
            </View>
            <T size={13} color={C.muted}>{t("android-settings.devices.times", { ago: s.time?.["created_at"]?.ago ?? "", until: s.time?.["expires_at"]?.until ?? "" })}</T>
          </View>
          {s.current !== true && (app.isDoing("loginSession.revoke", { id: s.id }) ? <Spinner /> : (
            <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
              <DoingMark running={false} failed={app.failedOf("loginSession.revoke", { id: s.id })} />
              <Pressable onPress={() => app.act(t("android-settings.devices.signOutWhat"), () => cloud.revokeLoginSession(s.id), t("android-settings.devices.signedOut"))} android_ripple={ripple(C.ink)}>
                <T size={15} color={C.red}>{t("android-settings.devices.signOut")}</T>
              </Pressable>
            </View>
          ))}
        </ListRow>
      ))}
    </ListCard>
  );
}

// ── stations ───────────────────────────────────────────────────────────

/** Whether the viewer may add, rename and remove stations: the workspace's owner and admins. A hook (it reads the workspace). */
export function isManager(current: WorkspaceEntry): boolean {
  return managerOf(current) === true;
}

/** Whether the viewer is one of the workspace's owners or admins; null until the workspace is read (not, if it cannot be). A hook. */
export function managerOf(current: WorkspaceEntry): boolean | null {
  const topic = rememberTopic<WorkspaceView>(Topics.workspace(current.workspace.id));
  return topic.value ? manager(topic.value) : topic.error != null ? false : null;
}

/**
 * Adding a station: a name, then the command to run on that machine (which installs still.fail and joins it); the sheet
 * waits for it to join. To one who manages another workspace too, a choice first (as the narrow web's AddStationSheet):
 * a new machine that way, or a station of one of those added here as it is (docs/multi-workspace.md).
 */
export function openAddStation(app: AppState, current: WorkspaceEntry, known: string[], existingFirst = false) {
  app.sheet = new SheetSpec(0.72, true, null, null, false, () => <AddStationSheet app={app} current={current} known={known} existingFirst={existingFirst} />);
}

function AddStationSheet({ app, current, known, existingFirst }: { app: AppState; current: WorkspaceEntry; known: string[]; existingFirst: boolean }) {
  const C = useC();
  const joinable = rememberTopic<JoinableView>(Topics.joinable(current.workspace.id));
  const [existing, setExisting] = useState(existingFirst);
  // A new machine's command made: that is the way now, the choice gone.
  const [made, setMade] = useState(false);
  // The stations of other workspaces joined from this sheet: kept in the list where they were, said to have joined,
  // so the next is a tap away (the core's `joinable` has them no more).
  const [took, setTook] = useState<JoinableStation[]>([]);
  const order = useRef(new Map<string, number>()).current;
  for (const it of joinable.value?.items ?? []) if (!order.has(it.station)) order.set(it.station, order.size);
  const rows = [...(joinable.value?.items ?? []).filter((s) => !took.some((it) => it.station === s.station)), ...took]
    .sort((a, b) => (order.get(a.station) ?? 0) - (order.get(b.station) ?? 0));
  // A station of another workspace to add: offered only while there is one.
  const offered = joinable.value?.offered === true && rows.length > 0;
  const view = joinable.value;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-settings.station.add")} />
      {/* The choice stays at the top; only what is under it scrolls. */}
      {offered && !made && (
        <View accessibilityLabel={t("web-pages.settings.stations.kind")} style={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 10, alignSelf: "stretch" }}>
          <Seg options={[t("web-pages.settings.stations.kindNew"), t("web-pages.settings.stations.kindExisting")]} selected={existing ? 1 : 0} onSelect={(i: number) => setExisting(i === 1)} height={34} fill radius={17} />
        </View>
      )}
      {view != null && offered && existing && !made ? (
        <JoinStation current={current} rows={rows} loading={view.loading} took={took} onClose={() => { app.sheet = null; }} onJoined={(it) => setTook((was) => [...was, it])} />
      ) : (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 24, gap: 10 }} keyboardShouldPersistTaps="handled">
          <T size={14} color={C.muted}>{t("android-settings.station.addNote", { app: APP_NAME })}</T>
          <AddStationSteps current={current} known={known} onCancel={() => { app.sheet = null; }} onMade={() => setMade(true)} onJoined={() => { app.sheet = null; }} />
        </ScrollView>
      )}
    </>
  );
}

/** A station joined, in 添加 station: said in green (as the desktop's), and the sheet closed by Done. */
function Joined({ text, onDone }: { text: string; onDone: () => void }) {
  const C = useC();
  return (
    <>
      <Smooth radius={12} style={{ alignSelf: "stretch", flexDirection: "row", alignItems: "center", gap: 8, backgroundColor: withAlpha(C.green, 0.12), paddingHorizontal: 12, paddingVertical: 10 }}>
        <IconIn icon={Icons.Check} size={16} tint={C.green} />
        <T size={14} color={C.green} style={{ flexShrink: 1 }}>{text}</T>
      </Smooth>
      <View style={{ flexDirection: "row", justifyContent: "flex-end" }}>
        <Button label={t("common.done")} primary onClick={onDone} />
      </View>
    </>
  );
}

/**
 * A station of another workspace the viewer manages, picked from `rows` (the core's `joinable`, with those `took` here
 * already; the first open one at first) and added to this one as it is (`station.join`): what that shares of the
 * machine said under the list, why it was refused in red. `onJoined` with it once it has joined: it stays in its place,
 * said so, and the next one open is picked, so several are added one after another.
 */
function JoinStation({ current, rows, loading, took, onClose, onJoined }: { current: WorkspaceEntry; rows: JoinableStation[]; loading: boolean; took: JoinableStation[]; onClose: () => void; onJoined: (s: JoinableStation) => void }) {
  const app = theApp;
  const C = useC();
  useDoing();
  const ws = current.workspace.id;
  const [picked, setPicked] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const joined = (s: JoinableStation) => took.some((it) => it.station === s.station);
  // One whose home's security mode keeps it out is shown, not picked.
  const open = rows.filter((it) => it.needsLock !== true && !joined(it));
  const chosen = open.find((it) => it.station === picked) ?? open[0];
  const busy = chosen != null && app.isDoing("station.join", { workspace: ws, station: chosen.station });
  // The words 20 in from the sheet's edges; the picking rows edge to edge, their own room making it 20 for theirs.
  const side = { paddingHorizontal: 20 };
  return (
    <View style={{ flex: 1, alignSelf: "stretch" }}>
      {/* The stations scroll; the actions stay under them. */}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ gap: 10 }}>
        <T size={14} color={C.muted} style={side}>{t("web-pages.settings.stations.existingLead")}</T>
        {rows.length === 0 && loading ? <WaitLine text={t("common.reading")} modifier={side} />
          : rows.length === 0 ? <T size={14} color={C.muted} style={side}>{t("web-pages.settings.stations.existingNone")}</T>
          : (
            <View>
              {rows.map((s) => {
                // Its mark before its name, as a station's own sheet has it: every name starts in one line.
                const mark = hasStationMark(s.emoji, s.icon) ? () => <StationMark emoji={s.emoji} icon={s.icon} size={15} tint={C.ink} /> : null;
                return joined(s)
                  ? <PickRow key={s.station} label={s.name} sub={t("web-pages.settings.stations.joinedRow")} done mark={mark} onClick={() => {}} />
                  : <PickRow key={s.station} label={s.name} sub={s.line} checked={s.station === chosen?.station} enabled={!busy && s.needsLock !== true} mark={mark} onClick={() => { setPicked(s.station); setError(null); }} />;
              })}
            </View>
          )}
        <T size={12} color={C.muted} style={side}>{t("web-pages.settings.stations.softIsolation")}</T>
        {error != null && <T size={13} color={C.red} style={side}>{error}</T>}
      </ScrollView>
      <View style={[side, { flexDirection: "row", paddingTop: 10, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }]}>
        <Button label={t(took.length === 0 ? "common.cancel" : "common.done")} primary={false} onClick={onClose} />
        <Button label={t("web-pages.settings.stations.joinAction")} primary busy={busy} enabled={chosen != null} onClick={() => {
          const s = chosen;
          if (s == null) return;
          setError(null);
          void (async () => {
            try { onJoined({ ...s, name: (await app.api(s.station).joinWorkspace(ws)) ?? s.name }); }
            catch (e) { if (e instanceof CoreError) setError(errorText(e)); else throw e; }
          })();
        }} />
      </View>
    </View>
  );
}

/**
 * A station's name, then the one command that installs still.fail on that machine and joins it (one with still.fail already
 * too), copied from here, and the wait for it; `onMade` once the command is there, `onJoined` once it has joined.
 * `onCancel`: a way out beside the first step.
 * `label`: what the name's line is called.
 */
function AddStationSteps({ current, known, label = t("android-settings.station.name"), placeholder = t("android-settings.station.namePlaceholder"), onCancel = null, onMade = () => {}, onJoined }: { current: WorkspaceEntry; known: string[]; label?: string; placeholder?: string; onCancel?: (() => void) | null; onMade?: () => void; onJoined: () => void }) {
  const app = theApp;
  const C = useC();
  useDoing();
  const stations = rememberTopic<StationView[]>(Topics.stations(current.workspace.id));
  const [name, setName] = useState("");
  const [made, setMade] = useState<Enrollment | null>(null);
  const busy = app.isDoing("workspace.enroll", { account: current.account.sub, workspace: current.workspace.id });
  const [error, setError] = useState<string | null>(null);
  const joined = made ? stations.value?.find((s) => !known.includes(s.id)) : undefined;
  const enrollment = made;
  return (
    <View style={{ alignSelf: "stretch", gap: 10 }}>
      {enrollment == null ? (
        <>
          <T size={13} weight="600" color={C.ink}>{label}</T>
          <Field value={name} onChange={setName} placeholder={placeholder} />
          {error != null && <T size={13} color={C.red}>{error}</T>}
          <View style={{ flexDirection: "row", paddingTop: 6, gap: 8, justifyContent: "flex-end" }}>
            {onCancel != null && <Button label={t("common.cancel")} primary={false} onClick={onCancel} />}
            <Button label={t("android-settings.station.make")} primary busy={busy} enabled={name.trim() !== ""} onClick={() => {
              setError(null);
              void (async () => {
                try { setMade(await new Cloud(app.core, current.account.sub).enroll(current.workspace.id, name.trim())); onMade(); }
                catch (e) { if (e instanceof CoreError) setError(errorText(e)); else throw e; }
              })();
            }} />
          </View>
        </>
      ) : joined != null ? (
        <Joined text={t("android-settings.station.joined", { name: joined.name })} onDone={onJoined} />
      ) : (
        <>
          <T size={14} color={C.ink}>{t("android-settings.station.run")}</T>
          <CommandBox text={enrollment.install} />
          <T size={13} color={C.muted}>{t("android-settings.station.runNote", { app: APP_NAME })}</T>
          <WaitLine text={t("android-settings.station.waiting")} />
        </>
      )}
    </View>
  );
}

/**
 * A workspace with no station: its first one added in the page (as the desktop's Onboarding, web/src/cloud/workspace.tsx,
 * and the narrow web's FirstStation, web/src/mobile/Stations.tsx): what a station is, its name, then the command to copy
 * and the wait. The workspace's pages take over once it has joined. Only its owner and admins add one; anyone else is
 * told to wait for them.
 */
export function FirstStation({ current }: { current: WorkspaceEntry }) {
  const C = useC();
  const topic = rememberTopic<WorkspaceView>(Topics.workspace(current.workspace.id));
  const view = topic.value;
  return (
    <View style={{ alignSelf: "stretch", padding: 30, alignItems: "center", gap: 10 }}>
      <Illustration light="illus_no_station" dark="illus_no_station_dark" width={240} />
      <T size={17} weight="600" color={C.ink} align="center">{t("android-settings.station.first")}</T>
      <T size={14} color={C.muted} align="center">{t("android-settings.station.firstNote")}</T>
      <View style={{ alignSelf: "stretch", paddingTop: 8, gap: 12 }}>
        {view == null ? (
          // Not read yet, or could not be: in red then, no longer turning.
          <WaitLine text={topic.error?.message ?? t("android-settings.workspace.reading")} error={topic.error != null} />
        ) : !manager(view) ? (
          <Smooth radius={12} style={{ alignSelf: "stretch", backgroundColor: withAlpha(C.warn, 0.12), paddingHorizontal: 12, paddingVertical: 10 }}>
            <T size={13} line={19.5} color={C.ink}>{t("android-settings.station.wait")}</T>
          </Smooth>
        ) : (
          <>
            <AddStationSteps current={current} known={[]} label={t("android-settings.station.firstName")} placeholder={t("android-settings.station.firstPlaceholder")} onJoined={() => {}} />
            <FirstExisting current={current} />
          </>
        )}
      </View>
    </View>
  );
}

/** A station the viewer manages in another workspace, added here as it is instead (docs/multi-workspace.md). */
function FirstExisting({ current }: { current: WorkspaceEntry }) {
  const C = useC();
  const joinable = rememberTopic<JoinableView>(Topics.joinable(current.workspace.id));
  const v = joinable.value;
  if (!(v != null && v.offered && v.items.length > 0)) return null;
  return (
    <Pressable onPress={() => openAddStation(theApp, current, [], true)} android_ripple={ripple(C.ink)}>
      <T size={14} color={C.accent}>{t("web-pages.settings.stations.firstExisting")}</T>
    </Pressable>
  );
}

/**
 * A station's or a workspace's mark (`name` its, `emoji` and `icon` the ones it has now), picked in a sheet (the web's:
 * web/src/cloud/MarkPick.tsx, the phone web's sheet): one of still.fail's icons (in a colour, or the words') or an emoji
 * (any, pasted or typed), a picture put up, or none; set at once by `save`, `what` naming it should it fail. What is sent
 * is web/src/stationPick.ts's: a glyph keeps its emoji beside it for older clients, an emoji or a picture takes the other away.
 */
function openMarkPick(app: AppState, name: string, emoji: string | null, icon: string | null, what: string, save: (emoji: string, icon: string) => Promise<void>) {
  const set = (e: string, i: string) => {
    if (e !== (emoji ?? "") || i !== (icon ?? "")) app.act(what, () => save(e, i), t("android-settings.station.emojiSet"));
  };
  const pick = (e: string, i: string) => { app.sheet = null; set(e, i); };
  app.sheet = new SheetSpec(0.78, false, null, null, false, () => <MarkPickSheet app={app} name={name} emoji={emoji} icon={icon} set={set} pick={pick} />);
}

function MarkPickSheet({ app, name, emoji, icon, set, pick }: { app: AppState; name: string; emoji: string | null; icon: string | null; set: (e: string, i: string) => void; pick: (e: string, i: string) => void }) {
  const C = useC();
  const glyph = StationIcons.of(icon);
  const picture = icon != null && icon.startsWith("data:image/") ? icon : null;
  const [emojis, setEmojis] = useState(glyph == null && picture == null && emoji != null);
  const [typed, setTyped] = useState("");
  const [color, setColor] = useState<string | null>(glyphColor(icon));
  const [query, setQuery] = useState("");
  const tint = markColor(color);
  const upload = () => {
    void (async () => {
      const url = await stationPictureOf().catch(() => null);
      // Nothing picked: nothing said.
      if (url === undefined) return;
      if (url == null) app.toast = t("android-settings.station.imageFailed"); else pick("", url);
    })();
  };
  // Six to a row, wide enough for a thumb; the one it has on the accent's wash.
  const kept = emojis ? (glyph == null && picture == null && emoji != null ? emoji.replaceAll("️", "") : null) : (glyph?.name ?? null);
  // The icons found by every word typed (in their names, English or Chinese); all of them for none.
  const terms = query.toLowerCase().split(/\s+/).filter((w) => w !== "");
  const offered: string[] = !emojis ? StationIcons.all.filter((g) => terms.every((w) => g.words.includes(w))).map((g) => g.name)
    : kept != null && !STATION_EMOJI.some((e) => e.replaceAll("️", "") === kept) ? [emoji!, ...STATION_EMOJI.slice(0, -1)] : STATION_EMOJI;
  const rows: string[][] = [];
  for (let i = 0; i < offered.length; i += 6) rows.push(offered.slice(i, i + 6));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-settings.station.emojiTitle", { name })} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }} keyboardShouldPersistTaps="handled">
        <View style={{ paddingLeft: 18, paddingRight: 18, paddingBottom: 10, gap: 10 }}>
          <Seg options={[t("android-settings.station.glyphs"), "Emoji"]} selected={emojis ? 1 : 0} onSelect={(i: number) => setEmojis(i === 1)} height={34} fill radius={17} />
          {emojis
            ? <Field value={typed} onChange={(v: string) => { setTyped(v); const one = firstEmoji(v); if (one != null) pick(one, ""); }} placeholder={t("android-settings.station.emojiPaste")} />
            : <Field value={query} onChange={setQuery} placeholder={t("android-settings.station.glyphSearch")} />}
        </View>
        {/* The icons' colour: the words' own first, then MARK_COLORS; the one picked ringed. It colours the grid, and the
            icon it has, at once. */}
        {!emojis && (
          <View style={{ flexDirection: "row", paddingLeft: 18, paddingRight: 18, paddingBottom: 10, justifyContent: "space-between" }}>
            {([null, ...MARK_COLORS] as (string | null)[]).map((c) => (
              <ColorDot key={c ?? "default"} color={c} on={c === color} onClick={() => {
                setColor(c);
                if (glyph != null) set(glyph.emoji, `glyph:${glyph.name}` + (c != null ? `:${c}` : ""));
              }} />
            ))}
          </View>
        )}
        {offered.length === 0 && <T size={15} color={C.muted} align="center" style={{ paddingVertical: 24 }}>{t("android-settings.station.glyphNone")}</T>}
        <View style={{ paddingLeft: 14, paddingRight: 14, paddingBottom: 10, gap: 4 }}>
          {rows.map((row, r) => (
            <View key={r} style={{ flexDirection: "row", gap: 4 }}>
              {row.map((key) => {
                const on = (emojis ? key.replaceAll("️", "") : key) === kept;
                const g = emojis ? null : StationIcons.all.find((it) => it.name === key)!;
                return (
                  <Smooth key={key} radius={14} style={{ flex: 1, aspectRatio: 1, backgroundColor: on ? C.accentBg : "transparent" }}>
                    <Pressable
                      accessibilityLabel={key}
                      onPress={() => { if (g == null) pick(key, ""); else pick(g.emoji, `glyph:${g.name}` + (color != null ? `:${color}` : "")); }}
                      android_ripple={ripple(C.ink)}
                      style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
                    >
                      {g == null ? <T size={26} line={30}>{key}</T> : <IconIn icon={g.icon} size={24} tint={tint ?? (on ? C.accent : C.ink)} />}
                    </Pressable>
                  </Smooth>
                );
              })}
              {Array.from({ length: 6 - row.length }, (_, i) => <View key={`room${i}`} style={{ flex: 1 }} />)}
            </View>
          ))}
        </View>
        <PickRow
          label={t(picture != null ? "android-settings.station.imageAnother" : "android-settings.station.image")}
          leading={() => (picture != null ? <StationMark emoji={null} icon={picture} size={20} tint={C.ink} /> : <IconIn icon={Icons.ImageUpload} size={20} tint={C.ink} />)}
          onClick={upload}
        />
        {hasStationMark(emoji, icon) && <PickRow label={t("android-settings.station.emojiClear")} leading={() => <IconIn icon={Icons.Close} size={20} tint={C.ink} />} onClick={() => pick("", "")} />}
      </ScrollView>
    </>
  );
}

/** One of the colours offered for a glyph (the words' own: none), ringed when it is the one picked. */
function ColorDot({ color, on, onClick }: { color: string | null; on: boolean; onClick: () => void }) {
  const C = useC();
  const of = markColor(color) ?? C.ink;
  return (
    <Pressable
      accessibilityLabel={color ?? "default"}
      onPress={onClick}
      android_ripple={ripple(C.ink)}
      style={{ width: 32, height: 32, borderRadius: 16, overflow: "hidden", alignItems: "center", justifyContent: "center", borderWidth: on ? 2 : 0, borderColor: of }}
    >
      <View style={{ width: 18, height: 18, borderRadius: 9, backgroundColor: of }} />
    </Pressable>
  );
}

/** The emoji offered (any other can be pasted or typed): web/src/stationPick.ts's EMOJI. */
const STATION_EMOJI = [
  "🖥️", "💻", "🍎", "🐧", "🪟", "☁️", "🏠", "🏢", "🚀", "⚡", "🔥", "🧪", "🛠️", "🐳", "🦀", "🐙", "🌲", "🌊", "🌙", "☀️", "🍊", "🍋", "🍇", "🐱",
  "🐶", "🦊", "🐼", "🐸", "🦉", "🐝", "🦄", "🐢", "🌵", "🌸", "🍄", "🌈", "❄️", "⭐", "🪐", "🌍", "🍉", "🍒", "🥑", "🍕", "☕", "🎧", "🎮", "🤖",
];

/** The first character as a person sees one (Java's BreakIterator): the system's segmenter, else what joins a sequence. */
function firstGrapheme(text: string): string {
  type Seg = new (lang?: string, o?: { granularity: string }) => { segment(s: string): Iterable<{ segment: string }> };
  const Segmenter = (Intl as unknown as { Segmenter?: Seg }).Segmenter;
  if (Segmenter) {
    for (const s of new Segmenter(undefined, { granularity: "grapheme" }).segment(text)) return s.segment;
    return "";
  }
  const cps = Array.from(text);
  const cp = (i: number) => cps[i]?.codePointAt(0) ?? -1;
  let n = 1;
  // A flag is two regional indicators.
  if (cp(0) >= 0x1f1e6 && cp(0) <= 0x1f1ff && cp(1) >= 0x1f1e6 && cp(1) <= 0x1f1ff) n = 2;
  for (;;) {
    const c = cp(n);
    // Variation selectors, skin tones, the keycap, tags: part of the one before.
    if (c === 0xfe0f || c === 0xfe0e || (c >= 0x1f3fb && c <= 0x1f3ff) || c === 0x20e3 || (c >= 0xe0020 && c <= 0xe007f)) { n++; continue; }
    // A zero-width joiner joins the next one to it (a family, a profession).
    if (c === 0x200d && n + 1 < cps.length) { n += 2; continue; }
    break;
  }
  return cps.slice(0, n).join("");
}

/** The first emoji of what was typed or pasted, as a person sees one (a flag, a family are one); null for none. */
function firstEmoji(text: string): string | null {
  const tx = text.trim();
  if (tx === "") return null;
  const one = firstGrapheme(tx) || tx.slice(0, 1);
  const cp = one.codePointAt(0)!;
  // Pictographs and symbols (U+2190 on, past CJK's own) and flags' regional indicators; not letters, digits or CJK.
  const emoji = (cp >= 0x1f000 && cp <= 0x1faff) || (cp >= 0x2190 && cp <= 0x2bff) || (cp >= 0x1f1e6 && cp <= 0x1f1ff) || cp === 0x00a9 || cp === 0x00ae || cp === 0x3030 || cp === 0x303d;
  return emoji ? one : null;
}

/**
 * A picked picture as a station's icon (web/src/stationPick.ts pictureOf): its middle square at 96 px, as a data URL small
 * enough to go with the workspace (WebP, else PNG, else JPEG); null when it can't be read or made small enough;
 * undefined when nothing was picked (the system's photo picker, images only).
 */
async function stationPictureOf(): Promise<string | null | undefined> {
  const picked = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ["images"], allowsEditing: false, quality: 1 });
  const asset = picked.canceled ? null : picked.assets[0];
  if (asset == null) return undefined;
  const side = Math.min(asset.width, asset.height);
  const sx = Math.floor((asset.width - side) / 2), sy = Math.floor((asset.height - side) / 2);
  const image = await ImageManipulator.manipulate(asset.uri).crop({ originX: sx, originY: sy, width: side, height: side }).resize({ width: 96, height: 96 }).renderAsync();
  // The first that can be made, as the Android app takes it; then whether it is small enough.
  const tries: [SaveFormat, number, string][] = [[SaveFormat.WEBP, 0.86, "webp"], [SaveFormat.PNG, 1, "png"], [SaveFormat.JPEG, 0.85, "jpeg"], [SaveFormat.JPEG, 0.6, "jpeg"]];
  for (const [format, compress, type] of tries) {
    try {
      const out = await image.saveAsync({ format, compress, base64: true });
      if (out.base64 == null) continue;
      const url = `data:image/${type};base64,${out.base64}`;
      return url.length <= 46_000 ? url : null;
    } catch { /* this format cannot be made here: the next */ }
  }
  return null;
}

/** A station's own actions: its name, its icon, and removing it from the workspace. */
export function openStationMenu(app: AppState, current: WorkspaceEntry, s: StationView) {
  const cloud = new Cloud(app.core, current.account.sub);
  app.sheet = new SheetSpec(0.34, false, null, null, false, () => <StationMenuSheet app={app} current={current} s={s} cloud={cloud} />);
}

function StationMenuSheet({ app, current, s, cloud }: { app: AppState; current: WorkspaceEntry; s: StationView; cloud: Cloud }) {
  const C = useC();
  const ws = current.workspace.id;
  return (
    <>
      <SheetGrab />
      <SheetHead title={s.name} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <PickRow label={t("android-settings.station.rename")} onClick={() => {
          ask(app, t("android-settings.station.renameTitle"), s.name, t("android-settings.station.renamePlaceholder"), t("common.save"), false, null, t("android-settings.station.renameWhat"), false, async (it) => {
            await cloud.renameStation(ws, s.id, it); app.toast = t("android-settings.renamed");
          });
        }} />
        <PickRow label={t("android-settings.station.emoji")} mark={hasStationMark(s.emoji, s.icon) ? () => <StationMark emoji={s.emoji} icon={s.icon} size={15} tint={C.ink} /> : null} onClick={() => {
          openMarkPick(app, s.name, s.emoji ?? null, s.icon ?? null, t("android-settings.station.emojiWhat"), (emoji, icon) => cloud.setStationMark(ws, s.id, emoji, icon));
        }} />
        <PickRow label={t("android-settings.station.removeRow")} color={C.red} onClick={() => {
          confirm(app, t("android-settings.station.removeTitle", { name: s.name }), t("android-settings.station.removeText", { app: APP_NAME }), t("android-settings.station.remove"), true,
            t("android-settings.station.removeWhat"), () => app.pop(), async () => {
              await cloud.removeStation(ws, s.id); app.toast = t("android-settings.station.removed");
            });
        }} />
      </ScrollView>
    </>
  );
}
