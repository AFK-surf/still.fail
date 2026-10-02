import type { MachineLogin } from "../core/shapes.ts";
import { profilesPage, useStation, useLink } from "../station.tsx";
import { Edit, External, LogIn, Plus, Refresh, Trash } from "../icons.tsx";
import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { useAction, useApi, useOverview, type AccessKind, type LoginJob, type Overview, type ProfileInput, type Profile, type RuntimeKind } from "../api.ts";
import { KEYED } from "../format.ts";
import { useDoing, useDoingFailed } from "../doing.ts";
import { useAct } from "../toast.tsx";
import { useToast } from "../toast.tsx";
import { QuotaBars } from "../components.tsx";
import * as modelCss from "../ModelTriple.css.ts";
import { MachineLoginCard } from "../ProfileCard.tsx";
import { About, Button, Choices, Confirm, ConnectAvatar, CopyCommand, Dialog, Empty, Field, ICON, IconButton, Loading, Menu, BackLink, ModelLogo, Pill, ProviderLogo, RuntimeTags, Section, SwitchRow, Time, Tip } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as baseCss from "../styles/base.css.ts";
import * as css from "./Accounts.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as waitingCss from "../styles/waiting.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as chatCss from "../styles/chat.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { tx } from "../cloud/words.tsx";
/**
 * What can be added, by whose account it is; `runtime` only where the account is for one (a subscription, variables).
 * Its words are getters, read in the language at the time.
 */
export const CHOICES = {
  "claude-sub": { kind: "subscription", runtime: "claude", get title() { return t("web-pages.profiles.choice.claudeSub"); }, get description() { return t("web-pages.profiles.choice.claudeSubLead"); } },
  "chatgpt-sub": { kind: "subscription", runtime: "codex", get title() { return t("web-pages.profiles.choice.chatgptSub"); }, get description() { return t("web-pages.profiles.choice.chatgptSubLead"); } },
  "opencode-go": { kind: "opencode-go", runtime: null, title: "OpenCode Go", get description() { return t("web-pages.profiles.choice.opencodeGoLead"); } },
  "anthropic-api": { kind: "anthropic-api", runtime: null, title: "Anthropic API", get description() { return t("web-pages.profiles.choice.anthropicApiLead"); } },
  "env-claude": { kind: "env", runtime: "claude", get title() { return t("web-pages.profiles.choice.envClaude"); }, get description() { return t("web-pages.profiles.choice.envLead"); } },
  "env-codex": { kind: "env", runtime: "codex", get title() { return t("web-pages.profiles.choice.envCodex"); }, get description() { return t("web-pages.profiles.choice.envLead"); } },
} as const satisfies Record<string, { kind: AccessKind; runtime: RuntimeKind | null; title: string; description: string }>;
export type Choice = keyof typeof CHOICES;

/** What a profile is, in a line, where the first one is asked for (an element: its words are read as it is drawn). */
export const PROFILE_LEAD = <ProfileLead />;

function ProfileLead() {
  return <>{tx("web-pages.profiles.lead", { subscription: <span className={baseCss.phrase}>{t("web-pages.profiles.leadSubscription")}</span> })}</>;
}

/**
 * Where a first profile is asked for: the accounts this machine's own Claude Code and Codex are signed in with (the
 * station reads them: src/machine-logins.ts). One kept in a file is used as it is — a profile on the machine's login,
 * which follows it; one kept only in the keychain cannot be, and is offered as a sign-in with the same account.
 */
export function MachineLoginOffers({ logins, onAdd }: { logins: MachineLogin[] | undefined; onAdd(choice: Choice): void }) {
  const api = useApi();
  const link = useLink();
  const navigate = useNavigate();
  const toast = useToast();
  const use = useAction((runtime: MachineLogin["runtime"]) => api.useMachineLogin(runtime), ({ id }) => {
    toast(t("web-pages.profiles.machineAdded"));
    navigate(link(`/settings/accounts/${id}`));
  });
  const offers = (logins ?? []).filter((l) => l.offered);
  if (!offers.length) return null;
  return (
    <div className={css.machineLogins}>
      <p className={css.machineLoginsHead}>{t("web-pages.profiles.machineSignedIn")}</p>
      {offers.map((l) => (
        // A refused account is said so, with nothing to do with it here.
        <MachineLoginCard key={l.runtime} login={l} action={l.quota?.state === "blocked" ? null : l.usable
          ? <Tip label={t("web-pages.profiles.useMachineTip")}><Button busy={use.busy && use.args?.[0] === l.runtime} disabled={use.busy} onClick={() => void use.run(l.runtime)}>{t("web-pages.profiles.useThis")}</Button></Tip>
          : <Tip label={t("web-pages.profiles.keychainTip", { name: NAME })}><Button onClick={() => onAdd(l.runtime === "claude" ? "claude-sub" : "chatgpt-sub")}>{t("web-pages.profiles.signIn")}</Button></Tip>} />
      ))}
      {use.error && <p className={controlsCss.fieldError} role="alert">{use.error.message}</p>}
    </div>
  );
}

/**
 * A new profile: a subscription is signed in first and the station makes the profile once that succeeds (named by the
 * account); a key is checked first and the profile made only if it works. Nothing is left behind by one that did not.
 * `initial`: the kind chosen when it opens.
 */
export function AddAccountDialog({ open, onClose, initial = "claude-sub" }: { open: boolean; onClose(): void; initial?: Choice }) {
  const api = useApi();
  const link = useLink();
  const station = useStation();
  const overview = useOverview(station.address);
  const navigate = useNavigate();
  const toast = useToast();
  // What to add, by whose account it is: a subscription (which one), a key, or variables set by hand for one runtime.
  const [choice, setChoice] = useState<Choice>(initial);
  const { kind, runtime } = CHOICES[choice];
  const [key, setKey] = useState("");
  const [login, setLogin] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const pending = login ? overview.value?.logins.find((l) => l.id === login) : undefined;
  const provider = runtime === "claude" ? "Claude" : "ChatGPT";
  const close = () => {
    if (login && !pending?.created) void api.dropLogin(login).catch(() => {});
    setLogin(null); setKey(""); setCode(""); setChoice("claude-sub");
    onClose();
  };
  const go = (id: string, message: string) => { toast(message); setLogin(null); setKey(""); setCode(""); onClose(); navigate(link(`/settings/accounts/${id}`)); };
  // The sign-in made its profile: on to it.
  useEffect(() => { if (pending?.created) go(pending.created, t("web-pages.profiles.signedInAdded")); }, [pending?.created]); // eslint-disable-line react-hooks/exhaustive-deps
  const start = useAction(() => api.newLogin(runtime!), ({ id }) => setLogin(id));
  const send = useAction(() => api.newLoginCode(login!, code), () => setCode(""));
  const add = useAction(() => api.addProfile({ ...(runtime ? { runtime } : {}), access: { kind, ...(KEYED.has(kind) ? { key } : {}) } }), ({ id }) => go(id, t("web-pages.profiles.verifiedAdded")));
  const job = pending?.job ?? null;
  const signing = login !== null;
  return (
    <Dialog open={open} onClose={close} title={station.name ? t("web-pages.profiles.addTo", { name: station.name }) : t("web-pages.settings.profiles.add")}
      footer={<>
        <Button variant="ghost" onClick={close}>{t("common.cancel")}</Button>
        {!signing && (kind === "subscription"
          ? <Button variant="primary" icon={LogIn} busy={start.busy} onClick={() => void start.run()}>{t("web-pages.profiles.signInTo", { provider })}</Button>
          : <Button variant="primary" disabled={KEYED.has(kind) && !key.trim()} busy={add.busy} onClick={() => void add.run()}>{KEYED.has(kind) ? t("web-pages.profiles.verifyAdd") : t("web-pages.settings.members.addOne")}</Button>)}
      </>}>
      {signing ? (
        pending?.error || job?.state === "failed" || job?.state === "cancelled"
          ? <div className={pagesCss.card}><p className={controlsCss.fieldError}>{pending?.error ?? job?.error ?? t("web-pages.profiles.signInUnfinished")}</p><Button onClick={() => { void api.dropLogin(login!).catch(() => {}); setLogin(null); }}>{t("web-pages.profiles.restart")}</Button></div>
          : <LoginSteps job={job} provider={provider} code={code} setCode={setCode} send={() => void send.run()} sending={send.busy} sendError={send.error?.message ?? null} />
      ) : (
        <>
          <Field label={t("web-pages.profiles.account")}>
            <Choices label={t("web-pages.profiles.account")} value={choice} onChange={(v) => setChoice(v as Choice)}
              options={(Object.keys(CHOICES) as Choice[]).map((c) => ({
                value: c, title: CHOICES[c].title, description: CHOICES[c].description,
                icon: <span className={pagesCss.mark} style={{ width: 28, height: 28 }}><ProviderLogo runtime={CHOICES[c].runtime ?? "claude"} kind={CHOICES[c].kind} size={16} /></span>,
              }))} />
          </Field>
          {KEYED.has(kind) && (
            <Field label={kind === "opencode-go" ? "OpenCode Go key" : "API key"} htmlFor="account-key" hint={t("web-pages.profiles.keyHint")}>
              <input id="account-key" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} type="password" autoComplete="off" value={key} onChange={(e) => setKey(e.target.value.trim())} />
            </Field>
          )}
          {kind === "subscription" && <p className={shellCss.muted}>{t("web-pages.profiles.subscriptionNote", { name: NAME })}</p>}
          {(start.error ?? add.error) && <p className={controlsCss.fieldError} role="alert">{(start.error ?? add.error)!.message}</p>}
        </>
      )}
    </Dialog>
  );
}

export function AccountPage() {
  const { id } = useParams();
  const overview = useOverview(useStation().address);
  const profile = overview.value?.profiles.find((p) => p.id === id);
  if (!overview.value) return overview.error ? <Empty><p>{overview.error.message}</p></Empty> : <Loading label={t("web-pages.profiles.loading")} />;
  if (!profile) return <Empty><p>{t("web-pages.profiles.notFound", { id: id ?? "" })}</p></Empty>;
  return <AccountView key={profile.id} profile={profile} overview={overview.value} />;
}

function AccountView({ profile, overview }: { profile: Profile; overview: Overview }) {
  const api = useApi();
  const station = useStation();
  const link = useLink();
  const navigate = useNavigate();
  const toast = useToast();
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(profile.name);
  const save = useAction((input: ProfileInput) => api.putProfile(profile.id, input));
  const remove = useAction(() => api.deleteProfile(profile.id), () => { toast(profile.machine ? t("web-pages.profiles.disabled") : t("web-pages.profiles.deleted")); navigate(profilesPage(station)); });
  // One on the machine's login is stopped rather than deleted: the login stays the machine's, to be used again.
  const removal = profile.machine
    ? { item: t("web-pages.profiles.disable"), title: t("web-pages.profiles.disableConfirm", { name: profile.name }), action: t("web-pages.profiles.disable"), description: t("web-pages.profiles.disableBody", { name: NAME, runtime: MACHINE_RUNTIME[profile.runtime] }) }
    : { item: t("web-pages.profiles.delete"), title: t("web-pages.archive.deleteConfirm", { title: profile.name }), action: t("web-pages.profiles.delete"), description: t("web-pages.profiles.deleteBody", { name: NAME }) };
  const check = useAction(() => api.checkProfile(profile.id));
  const saveThen = (input: ProfileInput, done: () => void) => void save.run(input).then((ok) => { if (ok) done(); });
  // Its new name shows while it is saved.
  const renamingTo = save.busy ? save.args?.[0].name : undefined;
  const rename = () => {
    setEditingName(false);
    if (name.trim() && name.trim() !== profile.name) saveThen({ name: name.trim() }, () => toast(t("web-pages.settings.workspace.renamed")));
  };
  // Its last check, as the station has it (a check done here, or after a sign-in, comes back with the overview).
  const latest = profile.check;
  const users = profile.usedBy.map((id) => overview.connects.find((c) => c.id === id)).filter((c) => c !== undefined);
  const [deleting, setDeleting] = useState(false);

  const signIn = profile.access.kind === "subscription";
  const signingIn = profile.login && ["starting", "needs_code", "needs_approval", "verifying"].includes(profile.login.state);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <BackLink to={profilesPage(station)} label="Profile" />
      {/* Who the account is and whether it works now: its provider, name, runtimes, and its last check. */}
      <header className={pagesCss.identity}>
        <span className={`${pagesCss.mark} ${waitingCss.runtimeMark}`} style={{ width: 48, height: 48 }}><ProviderLogo runtime={profile.runtime} kind={profile.access.kind} size={26} /></span>
        <div className={pagesCss.identityText}>
          {editingName ? (
            <input className={`${controlsCss.input} ${css.identityNameInput}`} value={name} autoFocus aria-label={t("web-pages.profiles.name")} onChange={(e) => setName(e.target.value)} onBlur={rename}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) rename(); if (e.key === "Escape") { setName(profile.name); setEditingName(false); } }} />
          ) : (
            <h1 className={pagesCss.identityName}>{renamingTo ?? profile.name}
              {renamingTo && <span className={`${waitingCss.spinner} ${controlsCss.iconSpinner}`} role="status" aria-label={t("web-pages.settings.stations.renaming")} />}<RuntimeTags runtimes={profile.runtimes} />{!profile.machine && <IconButton label={t("web-pages.settings.stations.rename")} icon={Edit} onClick={() => setEditingName(true)} />}</h1>
          )}
          <p className={`${pagesCss.identitySub} ${css.profileState}`}>
            {profile.checkTone !== "green" && <Pill tone={profile.checkTone}>{profile.checkText}</Pill>}
            {/* Keep check details without repeating the healthy status. */}
            <span>{latest ? latest.detail.replace(/^可用[，,]\s*/, "") : t("web-pages.profiles.neverChecked")}</span>
            {latest && <span className={shellCss.muted}>{tx("web-pages.profiles.checkedAt", { time: <Time stamp={latest.time?.checkedAt} /> })}</span>}
            <IconButton label={check.busy ? t("web-pages.version.checking") : t("web-pages.profiles.recheck")} icon={Refresh} busy={check.busy} onClick={() => void check.run()} />
          </p>
          {check.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.profiles.checkFailed", { error: check.error.message })}</p>}
        </div>
        <Menu items={[{ label: profile.usedBy.length ? t("web-pages.profiles.inUse", { item: removal.item }) : removal.item, icon: Trash, danger: true, disabled: profile.usedBy.length > 0, onSelect: () => setDeleting(true) }]} />
      </header>
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
      {/* A subscription that needs signing in, or is signing in: that comes first. */}
      {signIn && !profile.machine && (latest?.state === "login" || signingIn) && <section className={pagesCss.section}><SignIn profile={profile} needed /></section>}

      <QuotaSection profile={profile} />

      {profile.fast !== undefined && profile.fast !== null && <FastSection profile={profile} />}

      <ModelPool profile={profile} found={latest?.models ?? null} onSave={(models) => save.run({ models })} />

      {/* A station older than the setting says nothing of it. */}
      {profile.runtimes.includes("claude") && profile.backgroundOnMessage !== undefined && (
        <Section title={t("web-pages.profiles.run")}>
          <SwitchRow title={t("web-pages.profiles.background")} checked={profile.backgroundOnMessage} disabled={save.busy}
            description={profile.backgroundOnMessage
              ? t("web-pages.profiles.backgroundOn")
              : t("web-pages.profiles.backgroundOff")}
            onChange={(on) => saveThen({ backgroundOnMessage: on }, () => toast(on ? t("web-pages.profiles.turnedOn") : t("web-pages.profiles.turnedOff")))} />
        </Section>
      )}

      <Section title={t("web-pages.profiles.usedBy")}>
        {users.length === 0 ? <p className={shellCss.muted}>{t("web-pages.profiles.usedByNone")}</p> : (
          <ul className={pagesCss.list}>
            {users.map((c) => (
              <li key={c.id}><Link className={pagesCss.listRow} to={link(`/connects/${c.id}`)}><ConnectAvatar connect={c} size={24} /><span className={pagesCss.listRowTitle}>{c.name}</span><span className={shellCss.muted}>{c.modelName ?? (profile.model ? profile.names[profile.model] ?? profile.model : t("web-pages.profiles.defaultModel"))}</span></Link></li>
            ))}
          </ul>
        )}
      </Section>

      {profile.machine ? <MachineAccount profile={profile} /> : <AccountSection profile={profile} signedIn={latest?.state !== "login" && !signingIn}
        onSave={(input, done) => saveThen(input, () => { toast(t("web-pages.profiles.savedChecking")); done(); })} busy={save.busy} />}

      {profile.access.kind === "env" && <EnvSection profile={profile} onSave={(input) => saveThen(input, () => toast(t("web-pages.profiles.saved")))} busy={save.busy} />}
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.busy} onConfirm={() => void remove.run()}
        title={removal.title} action={removal.action} description={removal.description} error={remove.error?.message} />
    </div>
  );
}

const MACHINE_RUNTIME: Record<RuntimeKind, string> = { claude: "Claude Code", codex: "Codex" };

/** A profile on the machine's own login: whose it is, and that it is changed on the machine. */
function MachineAccount({ profile }: { profile: Profile }) {
  const station = useStation();
  const runtime = MACHINE_RUNTIME[profile.runtime];
  return (
    <Section title={t("web-pages.profiles.account")}>
      <p>{station.name ? t("web-pages.profiles.machineLoginOn", { station: station.name, runtime }) : t("web-pages.profiles.machineLoginHere", { runtime })}<About>{t("web-pages.profiles.machineLoginAbout", { runtime })}</About></p>
    </Section>
  );
}

/**
 * The account itself: its key (shown masked, replaced here — its provider stays, since a profile is that account), or
 * for a subscription, signing in again (as another account, or after it expired).
 */
function AccountSection({ profile, signedIn, onSave, busy }: { profile: Profile; signedIn: boolean; onSave(input: ProfileInput, done: () => void): void; busy: boolean }) {
  const [replacing, setReplacing] = useState(false);
  const [key, setKey] = useState("");
  const keyed = KEYED.has(profile.access.kind);
  if (!keyed && profile.access.kind !== "subscription") return null;
  return (
    <Section title={t("web-pages.profiles.account")}>
      {keyed ? (
        <div className={pagesCss.card}>
          {!replacing ? (
            <div className={pagesCss.cardRow}>
              <div className={pagesCss.cardRowText}>
                <strong>{profile.access.kind === "opencode-go" ? "OpenCode Go key" : "API key"}</strong>
                <span className={`${shellCss.muted} ${shellCss.mono}`}>{profile.access.key || t("web-pages.profiles.notSaved")}</span>
              </div>
              <Button onClick={() => setReplacing(true)}>{t("web-pages.profiles.replace")}</Button>
            </div>
          ) : (
            <Field label={profile.access.kind === "opencode-go" ? t("web-pages.profiles.newOpencodeKey") : t("web-pages.profiles.newApiKey")} htmlFor="access-key" hint={t("web-pages.profiles.recheckHint")}>
              <div className={additionsCss.inputRow}>
                <input id="access-key" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} type="password" autoComplete="off" autoFocus value={key} onChange={(e) => setKey(e.target.value.trim())} placeholder={t("web-pages.profiles.pasteKey")} />
                <Button variant="ghost" onClick={() => { setReplacing(false); setKey(""); }}>{t("common.cancel")}</Button>
                <Button variant="primary" disabled={!key} busy={busy} onClick={() => onSave({ access: { kind: profile.access.kind, key } }, () => { setKey(""); setReplacing(false); })}>{t("common.save")}</Button>
              </div>
            </Field>
          )}
        </div>
      ) : signedIn && <SignIn profile={profile} needed={false} />}
    </Section>
  );
}

interface EnvRow { row: number; key: string; value: string; masked: string | null; original: string | null }
let nextRow = 1;

/** The variables a custom profile runs with: what reaches its runtime's model service, set by hand. */
function EnvSection({ profile, onSave, busy }: { profile: Profile; onSave(input: ProfileInput): void; busy: boolean }) {
  const [rows, setRows] = useState<EnvRow[]>(() => profile.env.map((e) => ({ row: nextRow++, key: e.key, value: e.secret ? "" : e.value, masked: e.secret ? e.value : null, original: e.key })));
  const patch = (): Record<string, string | null> => {
    const out: Record<string, string | null> = {};
    const kept = new Set(rows.map((r) => r.key.trim()));
    for (const e of profile.env) if (!kept.has(e.key)) out[e.key] = null;
    for (const r of rows) {
      const key = r.key.trim();
      if (!key) continue;
      if (r.original && r.original !== key) out[r.original] = null;
      if (r.masked !== null && r.value === "" && r.original === key) continue;
      out[key] = r.value;
    }
    return out;
  };
  const update = (row: number, p: Partial<EnvRow>) => setRows(rows.map((r) => (r.row === row ? { ...r, ...p } : r)));
  return (
    <Section title={t("web-pages.profiles.env")} description={t("web-pages.profiles.envLead", { route: "{route}" })}>
      <div className={pagesCss.card}>
        <div className={css.envTable}>
          {rows.map((r) => {
            const secret = r.masked !== null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(r.key);
            return (
              <div key={r.row} className={css.envRow}>
                <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} aria-label={t("web-pages.profiles.envName")} value={r.key} onChange={(e) => update(r.row, { key: e.target.value })} placeholder="NAME" />
                <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} aria-label={t("web-pages.profiles.envValueOf", { name: r.key || t("web-pages.profiles.envVariable") })} type={secret ? "password" : "text"} autoComplete="off" value={r.value}
                  onChange={(e) => update(r.row, { value: e.target.value })} placeholder={r.masked !== null ? t("web-pages.profiles.envSaved", { masked: r.masked }) : t("web-pages.profiles.envValue")} />
                <Button variant="ghost" onClick={() => setRows(rows.filter((x) => x.row !== r.row))}>{t("common.delete")}</Button>
              </div>
            );
          })}
          <div><Button variant="ghost" icon={Plus} onClick={() => setRows([...rows, { row: nextRow++, key: "", value: "", masked: null, original: null }])}>{t("web-pages.profiles.envAdd")}</Button></div>
        </div>
        <div className={pagesCss.cardActions}>
          <Button variant="primary" busy={busy} onClick={() => onSave({ env: patch() })}>{t("common.save")}</Button>
        </div>
      </div>
    </Section>
  );
}

/**
 * Signing a subscription account in without a terminal: ember runs the
 * runtime's login on its own machine and this panel relays the browser steps.
 */
function SignIn({ profile, needed }: { profile: Profile; needed: boolean }) {
  const api = useApi();
  const toast = useToast();
  const [code, setCode] = useState("");
  const [manual, setManual] = useState(false);
  const job = profile.login;
  const start = useAction(() => api.startLogin(profile.id));
  const cancel = useAction(() => api.cancelLogin(profile.id));
  const send = useAction(() => api.loginCode(profile.id, code), () => setCode(""));
  const active = job && ["starting", "needs_code", "needs_approval", "verifying"].includes(job.state);
  const provider = profile.runtime === "claude" ? "Claude" : "ChatGPT";
  // Announce a sign-in finishing while the page is open, not one that finished earlier.
  const previous = useRef(job?.state);
  useEffect(() => {
    if (job?.state === "done" && previous.current && previous.current !== "done") toast(t("web-pages.profiles.signedIn"));
    previous.current = job?.state;
  }, [job?.state, toast]);

  if (!active) {
    return (
      <div className={pagesCss.card}>
        <div className={pagesCss.cardRow}>
          <div className={pagesCss.cardRowText}>
            <strong>{needed ? t("web-pages.profiles.notSignedIn", { provider }) : t("web-pages.profiles.subscriptionSignIn", { provider })}</strong>
            <span className={shellCss.muted}>
              {job?.state === "failed" ? t("web-pages.profiles.lastFailed", { error: job.error ?? "" }) : job?.state === "done" ? t("web-pages.profiles.signedInSwitch") : t("web-pages.profiles.signInNote", { name: NAME })}
            </span>
          </div>
          <Button variant={needed ? "primary" : "secondary"} icon={LogIn} busy={start.busy} onClick={() => void start.run()}>
            {job?.state === "done" || !needed ? t("web-pages.signIn.again") : t("web-pages.profiles.signIn")}
          </Button>
        </div>
        {start.error && <p className={controlsCss.fieldError} role="alert">{start.error.message}</p>}
        <button type="button" className={controlsCss.textToggle} onClick={() => setManual(!manual)}>{manual ? t("web-pages.profiles.collapse") : t("web-pages.profiles.manual")}</button>
        {manual && <CopyCommand text={profile.loginCommand} />}
      </div>
    );
  }

  return (
    <div className={`${pagesCss.card} ${css.signIn}`} aria-live="polite">
      <div className={pagesCss.cardRow}>
        <div className={pagesCss.cardRowText}><strong>{t("web-pages.profiles.signingIn", { provider })}</strong><span className={shellCss.muted}>{t("web-pages.profiles.signingInNote")}</span></div>
        <Button variant="ghost" busy={cancel.busy} onClick={() => void cancel.run()}>{t("common.cancel")}</Button>
      </div>
      {cancel.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.profiles.cancelFailed", { error: cancel.error.message })}</p>}
      <LoginSteps job={job} provider={provider} code={code} setCode={setCode} send={() => void send.run()} sending={send.busy} sendError={send.error?.message ?? null} />
    </div>
  );
}

/**
 * Codex's device sign-in: the code comes first and is copied as the login page opens, so it is pasted there with no
 * trip back; the rest finishes by itself.
 */
function DeviceCode({ url, code }: { url: string; code: string }) {
  const [copied, setCopied] = useState(false);
  const toast = useToast();
  const go = () => {
    // Not copied: the page opens all the same, the code to type in by hand.
    void navigator.clipboard.writeText(code).then(() => setCopied(true), () => toast(t("web-pages.profiles.copyFailed"))).finally(() => window.open(url, "_blank", "noopener"));
  };
  return (
    <div className={css.deviceCode}>
      <span className={`${css.deviceCodeValue} ${shellCss.mono}`}>{code}</span>
      <Button variant="primary" icon={External} onClick={go}>{copied ? t("web-pages.profiles.copiedReopen") : t("web-pages.profiles.copyOpen")}</Button>
      <p className={shellCss.muted}>{t("web-pages.profiles.deviceCodeNote", { name: NAME })}</p>
    </div>
  );
}

/** What the person does in the browser for a sign-in under way: the link and the code to paste (Claude), or the link
 * and the one-time code to enter (Codex). */
function LoginSteps({ job, provider, code, setCode, send, sending, sendError }: {
  job: LoginJob | null; provider: string; code: string; setCode(code: string): void; send(): void; sending: boolean; sendError: string | null;
}) {
  if (!job || job.state === "starting") return <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />{t("web-pages.profiles.generatingLink", { provider })}</p>;
  return (
    <>
      {job.state === "needs_code" && job.url && (
        <ol className={controlsCss.steps}>
          <li>
            <span>{t("web-pages.profiles.step1", { name: NAME })}</span>
            <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href={job.url} target="_blank" rel="noopener"><External {...ICON} />{t("web-pages.profiles.openAuth")}</a>
          </li>
          <li>
            <span>{t("web-pages.profiles.step2")}</span>
            <div className={additionsCss.inputRow}>
              <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} autoComplete="off" value={code} onChange={(e) => setCode(e.target.value)} placeholder={t("web-pages.profiles.pasteCode")} aria-label={t("web-pages.profiles.code")}
                onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && code.trim() && !sending) send(); }} />
              <Button variant="primary" disabled={!code.trim()} busy={sending} onClick={() => send()}>{t("web-pages.profiles.finish")}</Button>
            </div>
            {sendError && <p className={controlsCss.fieldError} role="alert">{sendError}</p>}
          </li>
        </ol>
      )}
      {job.state === "needs_approval" && job.url && job.userCode && <DeviceCode url={job.url} code={job.userCode} />}
      {job.state === "verifying" && <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />{t("web-pages.profiles.finishing")}</p>}
      {job.state === "done" && <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />{t("web-pages.profiles.adding")}</p>}
    </>
  );
}

function FastSection({ profile }: { profile: Profile }) {
  const api = useApi();
  const station = useStation();
  const act = useAct();
  const params = { station: station.address, id: profile.id };
  const busy = useDoing("profile.put", params);
  const error = useDoingFailed("profile.put", params);
  return <Section title={t("web-pages.profiles.run")}><SwitchRow title={t("web-pages.profiles.fast")} checked={!!profile.fast} disabled={busy}
    description={t("web-pages.profiles.fastLead")}
    onChange={(fast) => act(api.putProfile(profile.id, { fast }), t("web-pages.profiles.fastSave"), fast ? t("web-pages.profiles.fastOn") : t("web-pages.profiles.fastOff"))} />
    {busy && <p className={shellCss.muted}>{t("web-pages.profiles.saving")}</p>}
    {error && <p className={controlsCss.fieldError}>{error}</p>}
  </Section>;
}

function QuotaSection({ profile }: { profile: Profile }) {
  const api = useApi();
  // A refresh comes back with the overview.
  const refresh = useAction(() => api.refreshQuota(profile.id));
  const quota = profile.quota;
  const station = useStation();
  const toast = useToast();
  const [resetting, setResetting] = useState(false);
  const params = { station: station.address, id: profile.id };
  const busy = useDoing("profile.resetQuota", params);
  const failed = useDoingFailed("profile.resetQuota", params);
  const reset = useAction(async () => { await api.resetQuota(profile.id); setResetting(false); toast(t("web-pages.profiles.quotaReset")); });
  return (
    <Section title={<>{t("web-pages.profiles.quota")}{quota?.time?.checkedAt && <About>{t("web-pages.profiles.quotaAbout", { ago: quota.time.checkedAt.ago })}</About>}</>}
      actions={<Button variant="ghost" icon={Refresh} busy={refresh.busy} onClick={() => void refresh.run()}>{t("web-pages.profiles.refresh")}</Button>}>
      {(quota?.windows.length || !quota?.creditsText) ? <QuotaBars quota={quota} /> : null}
      {quota?.creditsText && <p>{tx("web-pages.profiles.credits", { credits: <span className={shellCss.muted}>{quota.creditsText}</span> })}</p>}
      {quota?.resetCount != null && <p>{tx("web-pages.profiles.resets", { resets: <span className={shellCss.muted}>{quota.resetText}</span> })}{" "}
        <Button variant="ghost" disabled={!quota.resetCount || busy} busy={busy} onClick={() => setResetting(true)}>{t("web-pages.profiles.reset")}</Button>
      </p>}
      {failed && <p className={controlsCss.fieldError}>{failed}</p>}
      <Confirm open={resetting} onClose={() => setResetting(false)} title={t("web-pages.profiles.resetConfirm")} action={t("web-pages.profiles.resetAction")}
        description={t("web-pages.profiles.resetBody", { name: profile.name, n: quota?.resetCount ?? 0 })} busy={busy}
        onConfirm={() => void reset.run()} error={reset.error?.message} />
      {refresh.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.profiles.refreshFailed", { error: refresh.error.message })}</p>}
    </Section>
  );
}

/**
 * Which of the profile's models may be used: none until picked here. Chats
 * and connects offer only enabled models, and the account pool sends a chat
 * only to a profile that has its model enabled.
 */
function ModelPool({ profile, found, onSave }: { profile: Profile; found: string[] | null; onSave(models: string[]): Promise<unknown> }) {
  const enabled = new Set(profile.models);
  const busy = profile.modelsSaving != null;
  const [filter, setFilter] = useState("");

  const all = [...new Set([...(found ?? []), ...profile.models])].sort();
  const name = (m: string) => profile.names[m] ?? m;
  const shown = all.filter((m) => [m, name(m)].some((s) => s.toLowerCase().includes(filter.trim().toLowerCase())));
  const commit = (next: Set<string>) => { void onSave([...next].sort()); };
  const toggle = (m: string) => {
    const next = new Set(enabled);
    if (next.has(m)) next.delete(m); else next.add(m);
    commit(next);
  };
  // With none enabled yet (a profile just added), the whole list is out to choose from.
  const [picked, setChoosing] = useState<boolean | null>(null);
  const choosing = picked ?? enabled.size === 0;
  // By series, newest first (the core's); one a newer check found that the core has not placed yet goes with 其他.
  const placed = new Set(profile.series.flatMap((s) => s.models));
  const loose = all.filter((m) => !placed.has(m));
  const series = [...profile.series.filter((s) => s.name !== "其他"),
    ...((profile.series.find((s) => s.name === "其他")?.models.length ?? 0) + loose.length ? [{ name: "其他", models: [...(profile.series.find((s) => s.name === "其他")?.models ?? []), ...loose] }] : [])];
  const ordered = series.flatMap((s) => s.models);
  const on = [...enabled].sort((a, b) => ordered.indexOf(a) - ordered.indexOf(b));
  return (
    <Section title={<>{t("web-pages.profiles.models")}<About>{all.length ? t("web-pages.profiles.modelsAbout") : t("web-pages.profiles.modelsAboutNone")}</About></>}
      actions={all.length > 0 && <Button variant="ghost" onClick={() => setChoosing(!choosing)}>{choosing ? t("web-pages.profiles.collapse") : t("web-pages.profiles.chooseModels", { on: enabled.size, all: all.length })}</Button>}>
      {/* What it can be used for now, first; the whole list only when choosing. */}
      {all.length > 0 && !choosing && (
        on.length === 0 ? <p className={shellCss.muted}>{t("web-pages.profiles.noModels")}</p> : (
          <ul className={css.modelChips}>
            {on.map((m) => <Tip key={m} label={m}><li className={css.modelChip}><ModelLogo maker={profile.makers[m]} runtime={profile.runtime} size={14} /><span>{name(m)}</span></li></Tip>)}
          </ul>
        )
      )}
      {all.length > 0 && choosing && (
        <div className={chatCss.modelPool}>
          <div className={chatCss.modelPoolTools}>
            {all.length > 10 && <input className={`${controlsCss.input} ${css.modelPoolFilter}`} placeholder={t("web-pages.profiles.filter")} autoFocus value={filter} onChange={(e) => setFilter(e.target.value)} />}
            <button type="button" className={controlsCss.textToggle} disabled={busy} onClick={() => commit(new Set([...enabled, ...shown]))}>{filter ? t("web-pages.profiles.selectFiltered") : t("web-pages.settings.members.all")}</button>
            <button type="button" className={controlsCss.textToggle} disabled={busy} onClick={() => commit(new Set([...enabled].filter((m) => !shown.includes(m))))}>{filter ? t("web-pages.profiles.unselectFiltered") : t("web-pages.settings.members.none")}</button>
          </div>
          {series.map((s) => {
            const list = s.models.filter((m) => shown.includes(m));
            if (list.length === 0) return null;
            const every = list.every((m) => enabled.has(m));
            return (
              <div key={s.name} className={modelCss.poolSeries}>
                <div className={modelCss.poolSeriesHead}>
                  <h4>{s.name}</h4>
                  <button type="button" className={controlsCss.textToggle} disabled={busy} onClick={() => commit(every ? new Set([...enabled].filter((m) => !list.includes(m))) : new Set([...enabled, ...list]))}>{every ? t("web-pages.settings.members.none") : t("web-pages.settings.members.all")}</button>
                </div>
                <ul className={chatCss.modelPoolList}>
                  {list.map((m) => (
                    <li key={m}>
                      <Tip label={m}><label className={chatCss.modelPoolItem} data-on={enabled.has(m) || undefined}>
                        <input type="checkbox" disabled={busy} checked={enabled.has(m)} onChange={() => toggle(m)} />
                        <ModelLogo maker={profile.makers[m]} runtime={profile.runtime} size={14} />
                        <span>{name(m)}</span>
                        {profile.modelsSaving?.includes(m) && <span className={`${waitingCss.spinner} ${controlsCss.iconSpinner}`} role="status" aria-label={t("web-pages.profiles.saving")} />}
                        {found && !found.includes(m) && <span className={`${shellCss.muted} ${css.modelPoolGone}`}>{t("web-pages.profiles.gone")}</span>}
                      </label></Tip>
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>
      )}
    </Section>
  );
}
