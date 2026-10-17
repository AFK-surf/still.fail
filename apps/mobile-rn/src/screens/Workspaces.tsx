// Workspaces, as still.fail cloud's pages have them (web/src/cloud/CloudApp.tsx,
// workspace.tsx): straight into one; for an account with none, its invitations
// or a new workspace of its own (with an invite code when still.fail cloud asks for
// one); the switcher with the invitations waiting, every account's workspaces
// and a new one.
import { useEffect, useState } from "react";
import { KeyboardAvoidingView, Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { WorkspaceMark, WorkspaceMarksView } from "../../../../web/src/core/shapes.ts";
import { usePrefs } from "../../../../web/src/prefs.ts";
import { app, SheetSpec, useApp, type AppState } from "../AppState";
import { APP_NAME } from "../build";
import { Auth, Cloud, errorText, needsInviteCode, type InvitationPreview } from "../data/Calls";
import { ROLE_LABEL, type Account, type AccountWorkspaces, type PendingInvitation, type WorkspaceSummary } from "../data/Accounts";
import { rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { Button, Field, PickRow } from "../ui/Controls";
import { Illustration } from "../ui/Drawing";
import { Icons } from "../ui/Icon";
import { hasStationMark, IconIn, ripple, StationMark } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { WaitLine } from "../ui/Waiting";
import { Action, useAction } from "./Action";
import { MarkCounts, signIn } from "./SettingParts";

const roleLabel = (role: string | undefined) => ROLE_LABEL[role ?? "member"] ?? role ?? "member";

/** A write behind a button: whether it runs, and how the last try ended. */
class Write extends Action {
  #arg: string | null = null;
  #done = false;
  /** What the running (or last) try was given. */
  get arg() { return this.#arg; }
  set arg(v: string | null) { this.#arg = v; this.changed(); }
  get done() { return this.#done; }
  set done(v: boolean) { this.#done = v; this.changed(); }
}

/** Runs `write` for a button: busy while it runs, its error kept until the next try. */
function run(w: Write, arg: string | null, write: () => Promise<void>) {
  w.arg = arg; w.done = false;
  w.run(async () => { await write(); w.done = true; });
}

/** The workspace an invitation's acceptance joined becomes the one in view. */
async function join(account: Account, invite: PendingInvitation) {
  app.pickWorkspace(await new Cloud(app.core, account.sub).acceptInvitation(invite.id));
  app.home();
}

/**
 * Signed in, with no workspace yet: the invitations waiting, or, with none, said so; a workspace of the first account's
 * own is made only when asked for (with the invite code still.fail cloud wants, once it asks for one).
 */
export function Landing({ accounts, workspaces }: { accounts: Account[]; workspaces: AccountWorkspaces[] }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  useApp((st) => st.doing);
  const first = accounts[0]!;
  const create = useAction(() => new Write(app));
  const accept = useAction(() => new Write(app));
  const pending = workspaces.flatMap((a) => (a.invitations ?? []).map((it) => [a.account, it] as const));
  const make = (code: string) => run(create, code, async () => {
    app.pickWorkspace(await new Cloud(app.core, first.sub).createWorkspace(t("android-misc.workspace.defaultName", { name: first.name || first.email.split("@")[0]! }), code));
  });
  // Once asked for a code, the form stays while a code is tried, rather than flicking to "creating…".
  const [asked, setAsked] = useState(false);
  if (needsInviteCode(create.error) && !asked) setAsked(true);
  const asking = (asked || needsInviteCode(create.error)) && !create.done;
  return (
    <KeyboardAvoidingView behavior="height" style={{ flex: 1, backgroundColor: C.bg, paddingTop: insets.top, paddingBottom: insets.bottom }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 24, paddingVertical: 40, alignItems: "center", gap: 12 }} keyboardShouldPersistTaps="handled">
        <Illustration light="illus_sign_in" dark="illus_sign_in_dark" width={260} />
        {pending.length > 0 ? (
          <>
            <Title text={t("android-misc.invite.received")} />
            {pending.map(([account, invite]) => (
              <Smooth key={invite.id} radius={16} style={{ alignSelf: "stretch", flexDirection: "row", alignItems: "center", gap: 12, backgroundColor: C.surface, paddingHorizontal: 16, paddingVertical: 12 }}>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} weight="600" color={C.ink}>{invite.name ?? ""}</T>
                  <T size={13} color={C.muted}>{t("android-misc.invite.invitedAs", { inviter: (invite.inviter ?? "") || t("android-misc.invite.someone"), email: account.email, role: roleLabel(invite.role) })}</T>
                </View>
                <Button label={t("android-misc.invite.join")} primary busy={accept.busy && accept.arg === invite.id} onClick={() => run(accept, invite.id, () => join(account, invite))} />
              </Smooth>
            ))}
            {accept.error != null && <ErrorLine text={accept.error.message} />}
            {asking ? <InviteCodeForm create={create} make={make} />
              : <Button label={t("android-misc.invite.declineCreate")} primary={false} busy={create.busy} onClick={() => make("")} />}
          </>
        ) : asking ? (
          <>
            <Title text={t("android-misc.invite.onlyInvited", { app: APP_NAME })} />
            <Lead text={t("android-misc.invite.codeLead", { app: APP_NAME, email: first.email })} />
            <InviteCodeForm create={create} make={make} />
            <Button label={t("android-misc.account.switch")} primary={false} busy={app.isDoing("auth.begin")} onClick={() => { void signIn(app); }} />
          </>
        ) : (
          <>
            <Title text={t("android-misc.workspace.none")} />
            <Lead text={t("android-misc.workspace.none.lead", { app: APP_NAME, email: first.email })} />
            <Button label={t("android-misc.workspace.createOne")} primary busy={create.busy} onClick={() => make("")} />
            {create.error != null && <ErrorLine text={errorText(create.error)} />}
            <Button label={t("android-misc.invite.byLink")} primary={false} onClick={() => openInviteLink(app)} />
            <Button label={t("android-misc.account.switch")} primary={false} busy={app.isDoing("auth.begin")} onClick={() => { void signIn(app); }} />
          </>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

/** An account the beta app cannot be used with (the core's `blocked`): it signs out, or another signs in. */
export function Blocked({ entry }: { entry: AccountWorkspaces }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  useApp((st) => st.doing);
  const out = useAction(() => new Write(app));
  return (
    <ScrollView style={{ flex: 1, backgroundColor: C.bg }} contentContainerStyle={{ paddingTop: insets.top + 40, paddingBottom: insets.bottom + 40, paddingHorizontal: 24, alignItems: "center", gap: 12 }}>
      <Illustration light="illus_sign_in" dark="illus_sign_in_dark" width={260} />
      <Title text={entry.blocked ?? ""} />
      <Lead text={entry.account.email} />
      <Button label={t("android-misc.account.signOut")} primary busy={out.busy} onClick={() => run(out, entry.account.sub, async () => { await Auth.signOut(app.core, entry.account.sub); })} />
      {out.error != null && <ErrorLine text={out.error.message} />}
      <Button label={t("android-misc.account.switch")} primary={false} busy={app.isDoing("auth.begin")} onClick={() => { void signIn(app); }} />
    </ScrollView>
  );
}

function Title({ text }: { text: string }) {
  const C = useC();
  return <T size={22} weight="700" color={C.ink} align="center">{text}</T>;
}

function Lead({ text }: { text: string }) {
  const C = useC();
  return <T size={14} color={C.muted} align="center">{text}</T>;
}

/** Workspaces.kt's Error: what went wrong, in red. */
function ErrorLine({ text }: { text: string }) {
  const C = useC();
  return <T size={13} color={C.red}>{text}</T>;
}

/** Asks for the invite code a new workspace needs; what the last try said stands under it. */
function InviteCodeForm({ create, make }: { create: Write; make: (code: string) => void }) {
  const [code, setCode] = useState(create.arg ?? "");
  const error = create.error;
  return (
    <View style={{ alignSelf: "stretch", gap: 8 }}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
        <Field value={code} onChange={setCode} placeholder="XXXX-XXXX-XXXX" mono modifier={{ flex: 1 }} />
        <Button label={t("android-misc.workspace.create")} primary busy={create.busy} enabled={code.trim() !== ""} onClick={() => make(code.trim())} />
      </View>
      {/* Nothing was wrong with a code nobody had typed yet. */}
      {error != null && !!create.arg && <ErrorLine text={errorText(error)} />}
    </View>
  );
}

// ── the switcher ───────────────────────────────────────────────────────

export function openWorkspaces(appState: AppState) {
  appState.sheet = new SheetSpec(0.7, true, null, null, false, () => <WorkspacesSheet appState={appState} />);
}

/**
 * The workspace sheet, opened from its name on Home (web/src/mobile/Workspaces.tsx): the invitations waiting, the one in
 * use (checked) and the others to switch to (with more than one account signed in, whose each is under its name; what it
 * holds at the row's end), a new one, and joining by an invitation's link. The workspace's settings are in 设置
 * (SettingsHome.kt).
 */
function WorkspacesSheet({ appState }: { appState: AppState }) {
  const C = useC();
  useApp((st) => st.doing);
  const all = rememberTopic<AccountWorkspaces[]>(Topics.workspaces);
  const byAccount = all.value ?? [];
  const respond = useAction(() => new Write(appState));
  // The workspace in view, followed as the prefs have it.
  const workspace = usePrefs((p) => p.workspace) ?? undefined;
  const pending = byAccount.flatMap((a) => (a.invitations ?? []).map((it) => [a.account, it] as const));
  const currentOf = byAccount.find((a) => (a.workspaces ?? []).some((w) => w.id === workspace));
  const current = (currentOf?.workspaces ?? []).find((w) => w.id === workspace);
  const others = byAccount.flatMap((a) => (a.workspaces ?? []).filter((w) => w.id !== workspace).map((w) => [a.account, w] as const));
  // Each its mark before its name, its letter where it has none, once any has one.
  const anyMarked = byAccount.some((a) => (a.workspaces ?? []).some((w) => hasStationMark(w.emoji, w.icon)));
  // What each of the others has waiting, as the core counts it.
  const marks = rememberTopic<WorkspaceMarksView>(Topics.workspaceMarks(workspace ?? ""));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.workspace.sheet.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        {current != null && currentOf != null && (
          <>
            <Label text={t("android-misc.workspace.current")} />
            <Smooth radius={16} style={{ marginLeft: 12, marginRight: 12, marginTop: 4, marginBottom: 16, backgroundColor: C.bg }}>
              <PickRow label={current.name} sub={currentOf.account.email} checked leading={anyMarked ? () => <WorkspaceIcon w={current} /> : null} onClick={() => { appState.sheet = null; }} />
            </Smooth>
          </>
        )}
        {pending.length > 0 && (
          <>
            <Label text={t("android-misc.invite.label")} />
            {pending.map(([account, invite]) => (
              <View key={invite.id} style={{ flexDirection: "row", paddingHorizontal: 20, paddingVertical: 8, alignItems: "center", gap: 8 }}>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} color={C.ink}>{t("android-misc.invite.invitedYou", { inviter: (invite.inviter ?? "") || t("android-misc.invite.someone"), name: invite.name ?? "" })}</T>
                  <T size={12} color={C.muted}>{account.email}</T>
                </View>
                <Button label={t("android-misc.invite.join")} primary busy={respond.busy && respond.arg === `+${invite.id}`} onClick={() => {
                  run(respond, `+${invite.id}`, async () => { await join(account, invite); appState.toast = t("android-misc.invite.joined", { name: invite.name ?? "" }); });
                }} />
                <Button label={t("android-misc.invite.ignore")} primary={false} busy={respond.busy && respond.arg === `-${invite.id}`} onClick={() => {
                  run(respond, `-${invite.id}`, async () => { await new Cloud(appState.core, account.sub).declineInvitation(invite.id); appState.toast = t("android-misc.invite.ignored"); });
                }} />
              </View>
            ))}
            {respond.error != null && <View style={{ paddingHorizontal: 20 }}><ErrorLine text={respond.error.message} /></View>}
          </>
        )}
        {others.length > 0 && <Label text={t("android-misc.workspace.others")} />}
        {others.map(([account, w]) => (
          <WorkspaceRow key={w.id} w={w} email={account.email} mark={marks.value?.workspaces?.[w.id] ?? null} lead={anyMarked} onClick={() => { appState.pickWorkspace(w.id); appState.home(); }} />
        ))}
      </ScrollView>
      <View style={{ paddingTop: 8, paddingBottom: 16 }}>
        <PickRow label={t("android-misc.workspace.addAccount")} sub={t("android-misc.workspace.addAccount.sub")} busy={app.isDoing("auth.begin")} leading={() => <IconIn icon={Icons.LogIn} size={20} />} onClick={() => { void signIn(appState); }} />
        <PickRow label={t("android-misc.workspace.new")} leading={() => <IconIn icon={Icons.Plus} size={20} />} onClick={() => openNewWorkspace(appState)} />
      </View>
    </>
  );
}

/** Workspace identity (its icon, when it has one, and name) and its waiting work; membership counts belong in settings. */
function WorkspaceRow({ w, email, mark, lead, onClick }: { w: WorkspaceSummary; email: string; mark: WorkspaceMark | null; lead: boolean; onClick: () => void }) {
  const C = useC();
  return (
    <View style={{ paddingHorizontal: 12 }}>
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={{ flexDirection: "row", paddingHorizontal: 8, paddingVertical: 12, alignItems: "center", gap: 12 }}>
        {lead && <WorkspaceIcon w={w} />}
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{w.name}</T>
          <T size={12} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{email}</T>
        </View>
        {mark != null && <MarkCounts mark={mark} />}
      </Pressable>
    </View>
  );
}

/** A workspace's mark in the sheet's rows, drawn as a station's is; its first letter, muted, where it has none. */
function WorkspaceIcon({ w }: { w: WorkspaceSummary }) {
  const C = useC();
  return (
    <View style={{ width: 24, height: 24, alignItems: "center", justifyContent: "center" }}>
      {hasStationMark(w.emoji, w.icon) ? <StationMark emoji={w.emoji} icon={w.icon} size={22} tint={C.ink} />
        : <T size={15} weight="600" color={C.muted}>{Array.from(w.name.trim()).slice(0, 1).join("").toUpperCase()}</T>}
    </View>
  );
}

function Label({ text }: { text: string }) {
  const C = useC();
  return <T size={13} color={C.muted} style={{ paddingLeft: 20, paddingRight: 20, paddingTop: 6, paddingBottom: 2 }}>{text}</T>;
}

// ── a new workspace ────────────────────────────────────────────────────

function openNewWorkspace(appState: AppState) {
  appState.sheet = new SheetSpec(0.8, false, null, null, false, () => <NewWorkspaceSheet appState={appState} />);
}

function NewWorkspaceSheet({ appState }: { appState: AppState }) {
  const C = useC();
  const accounts = rememberTopic<Account[]>(Topics.accounts);
  const list = accounts.value ?? [];
  const [name, setName] = useState("");
  const [owner, setOwner] = useState<string | null>(null);
  // Sent every time: still.fail cloud looks at it only for an account not let in yet, and then asks for it when it is missing or wrong.
  const [code, setCode] = useState("");
  const create = useAction(() => new Write(appState));
  const [asked, setAsked] = useState(false);
  if (needsInviteCode(create.error) && !asked) setAsked(true);
  const sub = (owner != null && list.some((a) => a.sub === owner) ? owner : null) ?? list[0]?.sub ?? null;
  const go = () => {
    if (name.trim() !== "" && sub != null) run(create, null, async () => {
      const id = await new Cloud(appState.core, sub).createWorkspace(name.trim(), code.trim());
      appState.pickWorkspace(id);
      appState.home();
    });
  };
  const error = create.error;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.workspace.new")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 10 }} keyboardShouldPersistTaps="handled">
        <T size={14} color={C.muted}>{t("android-misc.workspace.new.text")}</T>
        <Label0 text={t("android-misc.workspace.name")} />
        <Field value={name} onChange={setName} placeholder={t("android-misc.workspace.name.placeholder")} />
        {list.length > 1 && (
          <>
            <Label0 text={t("android-misc.workspace.account")} />
            {list.map((a) => <PickRow key={a.sub} label={a.email} checked={a.sub === sub} onClick={() => setOwner(a.sub)} />)}
          </>
        )}
        {(asked || needsInviteCode(error)) && (
          <>
            <Label0 text={t("android-misc.invite.code")} />
            <Field value={code} onChange={setCode} placeholder="XXXX-XXXX-XXXX" mono />
            {error != null && needsInviteCode(error) && code.trim() !== "" ? <ErrorLine text={errorText(error)} />
              : <T size={12} color={C.muted}>{t("android-misc.invite.codeNeeded", { app: APP_NAME })}</T>}
          </>
        )}
        {error != null && !needsInviteCode(error) && <ErrorLine text={error.message} />}
        <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { appState.sheet = null; }} />
          <Button label={t("android-misc.workspace.createButton")} primary busy={create.busy} enabled={name.trim() !== ""} onClick={go} />
        </View>
      </ScrollView>
    </>
  );
}

function Label0({ text }: { text: string }) {
  const C = useC();
  return <T size={13} weight="600" color={C.ink}>{text}</T>;
}

/** Whether invitations wait for any signed-in account: the switcher says so with a dot. */
export function invitationsWaiting(_app: AppState): boolean {
  const all = rememberTopic<AccountWorkspaces[]>(Topics.workspaces);
  return (all.value ?? []).some((a) => (a.invitations ?? []).length > 0);
}

// ── an invitation's link ───────────────────────────────────────────────

/** The token of an invitation's link (`<cloud>/invite#<token>`), or what was pasted when it is a token by itself. */
export function invitationToken(text: string): string | null {
  const tx = text.trim();
  if (tx === "") return null;
  const at = tx.indexOf("/invite#");
  const hash = at < 0 ? "" : tx.slice(at + "/invite#".length);
  return (hash !== "" ? hash : tx.includes("/") || tx.includes(" ") ? "" : tx).trim() || null;
}

/** Joining by an invitation's link: pasted here, then what it leads to is shown before it is accepted (as the web's /invite). */
export function openInviteLink(appState: AppState) {
  appState.sheet = new SheetSpec(0.5, false, null, null, false, () => <InviteLinkSheet appState={appState} given={null} />);
}

/** An invitation's link opened in the app: what it leads to, before it is accepted. */
export function openInvite(appState: AppState, token: string) {
  appState.sheet = new SheetSpec(0.5, false, null, null, false, () => <InviteLinkSheet appState={appState} given={token} />);
}

function InviteLinkSheet({ appState, given }: { appState: AppState; given: string | null }) {
  const C = useC();
  useApp((st) => st.doing);
  const accounts = rememberTopic<Account[]>(Topics.accounts);
  const list = accounts.value ?? [];
  const [text, setText] = useState("");
  const [token, setToken] = useState<string | null>(given);
  const [chosen, setChosen] = useState<string | null>(null);
  const sub = (chosen != null && list.some((a) => a.sub === chosen) ? chosen : null) ?? list[0]?.sub ?? null;
  // Read once per account: what the link leads to depends on who looks.
  const [preview, setPreview] = useState<InvitationPreview | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const accept = useAction(() => new Write(appState));
  useEffect(() => {
    setPreview(null); setFailed(null);
    const tk = token;
    if (tk == null || sub == null) return;
    let gone = false;
    new Cloud(appState.core, sub).previewInvitation(tk).then(
      (p) => { if (!gone) setPreview(p); },
      (e: unknown) => { if (!gone) setFailed((e as Error).message); },
    );
    return () => { gone = true; };
  }, [token, sub]);
  // Signed out: nothing reads the invitation yet (as the web's /invite: sign in first, then decide).
  if (accounts.value != null && list.length === 0) {
    return (
      <>
        <SheetGrab />
        <SheetHead title={t("android-misc.signIn.title", { app: APP_NAME })} />
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 10 }}>
          <T size={14} color={C.muted}>{t("android-misc.signIn.invited", { app: APP_NAME })}</T>
          <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
            <Button label={t("common.cancel")} primary={false} onClick={() => { appState.sheet = null; }} />
            <Button label={t("android-misc.signIn.google")} primary busy={app.isDoing("auth.begin")} onClick={() => { void signIn(appState); }} />
          </View>
        </ScrollView>
      </>
    );
  }
  const p = preview;
  const link = token;
  return (
    <>
      <SheetGrab />
      <SheetHead title={token == null ? t("android-misc.invite.byLink") : p != null ? t("android-misc.invite.joinNamed", { name: p.name }) : failed != null ? t("android-misc.invite.unusable") : t("android-misc.invite.loading")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 10 }} keyboardShouldPersistTaps="handled">
        {link == null ? (
          <>
            <T size={14} color={C.muted}>{t("android-misc.invite.pasteLink", { app: APP_NAME })}</T>
            <Field value={text} onChange={setText} placeholder="https://app.still.fail/invite#…" lines={2} />
            <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
              <Button label={t("common.cancel")} primary={false} onClick={() => { appState.sheet = null; }} />
              <Button label={t("android-misc.invite.view")} primary enabled={invitationToken(text) != null} onClick={() => setToken(invitationToken(text))} />
            </View>
          </>
        ) : failed != null ? (
          <>
            <T size={14} color={C.muted}>{failed}</T>
            <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
              {given == null && <Button label={t("android-misc.invite.otherLink")} primary={false} onClick={() => setToken(null)} />}
              <Button label={t("common.close")} primary onClick={() => { appState.sheet = null; }} />
            </View>
          </>
        ) : p == null ? <WaitLine text={t("common.reading")} /> : (
          <>
            <T size={14} color={C.muted}>{t(p.email != null ? "android-misc.invite.invitedYouAsOnly" : "android-misc.invite.invitedYouAs", { inviter: (p.inviter ?? "") || t("android-misc.invite.someone"), role: roleLabel(p.role), email: p.email ?? "" })}</T>
            {list.length > 1 && (
              <>
                <Label0 text={t("android-misc.invite.whichAccount")} />
                <View>{list.map((a) => <PickRow key={a.sub} label={a.email} checked={a.sub === sub} onClick={() => setChosen(a.sub)} />)}</View>
              </>
            )}
            {accept.error != null && <ErrorLine text={accept.error.message} />}
            <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
              <Button label={t("common.cancel")} primary={false} onClick={() => { appState.sheet = null; }} />
              <Button label={t("android-misc.invite.joinAs", { email: list.find((a) => a.sub === sub)?.email ?? "" })} primary busy={accept.busy} enabled={sub != null} onClick={() => {
                run(accept, null, async () => {
                  const id = await new Cloud(appState.core, sub!).acceptInvitationToken(link);
                  appState.pickWorkspace(id); appState.home(); appState.toast = t("android-misc.invite.joined", { name: p.name });
                });
              }} />
            </View>
          </>
        )}
      </ScrollView>
    </>
  );
}
