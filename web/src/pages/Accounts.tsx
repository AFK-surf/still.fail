import { Illustration } from "../brand.tsx";
import type { MachineLogin } from "../core/shapes.ts";
import { profilesPage, useStation, useLink } from "../station.tsx";
import { ChevronRight, Edit, External, Key, LogIn, Plus, Refresh, Trash } from "../icons.tsx";
import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { useAction, useApi, useOverview, type AccessKind, type LoginJob, type Overview, type ProfileInput, type Profile, type RuntimeKind } from "../api.ts";
import { ACCESS, ACCESS_KINDS, KEYED } from "../format.ts";
import { useToast } from "../toast.tsx";
import { QuotaBars } from "../components.tsx";
import * as modelCss from "../ModelTriple.css.ts";
import { MachineLoginCard, ProfileCard } from "../ProfileCard.tsx";
import { About, Button, Choices, Confirm, ConnectAvatar, CopyCommand, Dialog, Empty, Field, FirstOne, ICON, IconButton, Loading, Menu, BackLink, MobileBack, ModelLogo, Pill, ProviderLogo, RuntimeTags, Section, Select, SwitchRow, Time, Tip } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as baseCss from "../styles/base.css.ts";
import * as css from "./Accounts.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as waitingCss from "../styles/waiting.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as chatCss from "../styles/chat.css.ts";


export function AccountsPage() {
  const link = useLink();
  const overview = useOverview(useStation().address);
  const [adding, setAdding] = useState(false);
  const [initial, setInitial] = useState<Choice>("claude-sub");
  const profiles = overview.value?.profiles ?? [];
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={link("/chats")} label="对话" />
      <header className={pagesCss.pageHead}>
        <div>
          <h1>Profile<About>Profile 是 agent 用来跑模型的账号：一份订阅，或者一个模型服务的 key。一个账号能跑哪些运行时，ember 会自己配好。</About></h1>
        </div>
        {(profiles.length > 0 || !overview.value) && <Button icon={Plus} onClick={() => setAdding(true)}>添加 Profile</Button>}
      </header>
      {overview.value && profiles.length === 0 && (
        <FirstOne art={<Illustration name="no-profile" />} title="添加第一个 Profile" lead={PROFILE_LEAD}>
          <Button variant="primary" icon={Plus} onClick={() => { setInitial("claude-sub"); setAdding(true); }}>添加 Profile</Button>
          <MachineLoginOffers logins={overview.value.machineLogins} onAdd={(c) => { setInitial(c); setAdding(true); }} />
        </FirstOne>
      )}
      {profiles.length > 0 && (
        <section className={pagesCss.section} aria-label="Profile">
        <ul className={pagesCss.list}>
          {profiles.map((p) => {
            return (
              <li key={p.id}>
                <ProfileCard profile={p} to={link(`/settings/accounts/${p.id}`)}
                  uses={p.usedBy.length ? `被 ${p.usedBy.map((id) => overview.value!.connects.find((c) => c.id === id)?.name ?? id).join("、")} 使用` : "没有连接使用"} />
              </li>
            );
          })}
        </ul>
        {/* The machine's own logins not used yet: each one offered as the first ones were. */}
        <MachineLoginOffers logins={overview.value?.machineLogins} onAdd={(c) => { setInitial(c); setAdding(true); }} />
        </section>
      )}
      <AddAccountDialog key={initial} initial={initial} open={adding} onClose={() => setAdding(false)} />
    </div>
  );
}

/** What can be added, by whose account it is; `runtime` only where the account is for one (a subscription, variables). */
export const CHOICES = {
  "claude-sub": { kind: "subscription", runtime: "claude", title: "Claude 订阅", description: "Claude Pro / Max，跑 Claude Code。在浏览器里登录一次。" },
  "chatgpt-sub": { kind: "subscription", runtime: "codex", title: "ChatGPT 订阅", description: "ChatGPT Plus / Pro，跑 Codex。用设备码登录一次。" },
  "opencode-go": { kind: "opencode-go", runtime: null, title: "OpenCode Go", description: "一个 key，Claude Code 和 Codex 都能用。" },
  "anthropic-api": { kind: "anthropic-api", runtime: null, title: "Anthropic API", description: "Anthropic 的 API key，跑 Claude Code。" },
  "env-claude": { kind: "env", runtime: "claude", title: "自定义环境变量（Claude Code）", description: "自己设置接模型服务的环境变量。" },
  "env-codex": { kind: "env", runtime: "codex", title: "自定义环境变量（Codex）", description: "自己设置接模型服务的环境变量。" },
} as const satisfies Record<string, { kind: AccessKind; runtime: RuntimeKind | null; title: string; description: string }>;
export type Choice = keyof typeof CHOICES;

/** What a profile is, in a line, where the first one is asked for. */
export const PROFILE_LEAD = <>agent 用它来跑模型：<span className={baseCss.phrase}>一份订阅（Claude、ChatGPT），</span>或者一个模型服务的 key。</>;

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
  const overview = useOverview(useStation().address);
  const use = useAction((runtime: MachineLogin["runtime"]) => api.useMachineLogin(runtime), ({ id }) => {
    toast("已添加 Profile，用的是这台机器的登录");
    navigate(link(`/settings/accounts/${id}`));
  });
  const taken = new Set(overview.value?.profiles.filter((p) => p.machine).map((p) => p.runtime));
  const offers = (logins ?? []).filter((l) => l.loggedIn && l.plan && !taken.has(l.runtime));
  if (!offers.length) return null;
  return (
    <div className={css.machineLogins}>
      <p className={css.machineLoginsHead}>这台机器上已经登录了</p>
      {offers.map((l) => (
        // A refused account is said so, with nothing to do with it here.
        <MachineLoginCard key={l.runtime} login={l} action={l.quota?.state === "blocked" ? null : l.usable
          ? <Tip label="直接用这台机器的登录，不用再登录；在这台机器上换号或登出，它也跟着变"><Button disabled={use.busy} onClick={() => void use.run(l.runtime)}>用这个账号</Button></Tip>
          : <Tip label="这份登录存在钥匙串里，不能直接用：为 ember 单独登录一次，这台机器上原来的登录不受影响"><Button onClick={() => onAdd(l.runtime === "claude" ? "claude-sub" : "chatgpt-sub")}>登录</Button></Tip>} />
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
  useEffect(() => { if (pending?.created) go(pending.created, "已登录，添加了 Profile"); }, [pending?.created]); // eslint-disable-line react-hooks/exhaustive-deps
  const start = useAction(() => api.newLogin(runtime!), ({ id }) => setLogin(id));
  const send = useAction(() => api.newLoginCode(login!, code), () => setCode(""));
  const add = useAction(() => api.addProfile({ ...(runtime ? { runtime } : {}), access: { kind, ...(KEYED.has(kind) ? { key } : {}) } }), ({ id }) => go(id, "已验证并添加 Profile"));
  const job = pending?.job ?? null;
  const signing = login !== null;
  return (
    <Dialog open={open} onClose={close} title={station.name ? `给 ${station.name} 添加 Profile` : "添加 Profile"}
      footer={<>
        <Button variant="ghost" onClick={close}>取消</Button>
        {!signing && (kind === "subscription"
          ? <Button variant="primary" icon={LogIn} busy={start.busy} onClick={() => void start.run()}>登录 {provider}</Button>
          : <Button variant="primary" disabled={KEYED.has(kind) && !key.trim()} busy={add.busy} onClick={() => void add.run()}>{KEYED.has(kind) ? "验证并添加" : "添加"}</Button>)}
      </>}>
      {signing ? (
        job?.state === "failed" || job?.state === "cancelled"
          ? <div className={pagesCss.card}><p className={controlsCss.fieldError}>{job.error ?? "登录没有完成。"}</p><Button onClick={() => { void api.dropLogin(login!).catch(() => {}); setLogin(null); }}>重新开始</Button></div>
          : <LoginSteps job={job} provider={provider} code={code} setCode={setCode} send={() => void send.run()} sending={send.busy} sendError={send.error?.message ?? null} />
      ) : (
        <>
          <Field label="账号">
            <Choices label="账号" value={choice} onChange={(v) => setChoice(v as Choice)}
              options={(Object.keys(CHOICES) as Choice[]).map((c) => ({
                value: c, title: CHOICES[c].title, description: CHOICES[c].description,
                icon: <span className={pagesCss.mark} style={{ width: 28, height: 28 }}><ProviderLogo runtime={CHOICES[c].runtime ?? "claude"} kind={CHOICES[c].kind} size={16} /></span>,
              }))} />
          </Field>
          {KEYED.has(kind) && (
            <Field label={kind === "opencode-go" ? "OpenCode Go key" : "API key"} htmlFor="account-key" hint="先验证能用，再添加。">
              <input id="account-key" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} type="password" autoComplete="off" value={key} onChange={(e) => setKey(e.target.value.trim())} />
            </Field>
          )}
          {kind === "subscription" && <p className={shellCss.muted}>登录在运行 ember 的机器上完成，你只需要在浏览器里授权；登录成功后才会添加这个 Profile。</p>}
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
  if (!overview.value) return overview.error ? <Empty><p>{overview.error.message}</p></Empty> : <Loading label="正在读取 Profile…" />;
  if (!profile) return <Empty><p>没有 ID 为 {id} 的 Profile。</p></Empty>;
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
  const remove = useAction(() => api.deleteProfile(profile.id), () => { toast(profile.machine ? "已停用" : "已删除 Profile"); navigate(profilesPage(station)); });
  // One on the machine's login is stopped rather than deleted: the login stays the machine's, to be used again.
  const removal = profile.machine
    ? { item: "停用", title: `停用「${profile.name}」？`, action: "停用", description: `ember 不再用这台机器上 ${MACHINE_RUNTIME[profile.runtime]} 的登录；这台机器上的登录不受影响，之后可以再用。` }
    : { item: "删除 Profile", title: `删除「${profile.name}」？`, action: "删除 Profile", description: "只从 ember 的配置里移除；配置目录和里面的登录状态不会删除。" };
  const check = useAction(() => api.checkProfile(profile.id));
  const saveThen = (input: ProfileInput, done: () => void) => void save.run(input).then((ok) => { if (ok) done(); });
  const rename = () => {
    setEditingName(false);
    if (name.trim() && name.trim() !== profile.name) saveThen({ name: name.trim() }, () => toast("已改名"));
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
            <input className={`${controlsCss.input} ${css.identityNameInput}`} value={name} autoFocus aria-label="名称" onChange={(e) => setName(e.target.value)} onBlur={rename}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) rename(); if (e.key === "Escape") { setName(profile.name); setEditingName(false); } }} />
          ) : (
            <h1 className={pagesCss.identityName}>{profile.name}<RuntimeTags runtimes={profile.runtimes} />{!profile.machine && <IconButton label="改名" icon={Edit} onClick={() => setEditingName(true)} />}</h1>
          )}
          <p className={`${pagesCss.identitySub} ${css.profileState}`}>
            <Pill tone={profile.checkTone}>{profile.checkText}</Pill>
            {/* The pill already says it works; the detail says what else it found. */}
            <span>{latest ? latest.detail.replace(/^可用[，,]\s*/, "") : "还没检查过"}</span>
            {latest && <span className={shellCss.muted}><Time stamp={latest.time?.checkedAt} />检查</span>}
            <IconButton label={check.busy ? "正在检查…" : "重新检查"} icon={Refresh} disabled={check.busy} data-busy={check.busy || undefined} onClick={() => void check.run()} />
          </p>
        </div>
        <Menu items={[{ label: profile.usedBy.length ? `${removal.item}（还有连接在用）` : removal.item, icon: Trash, danger: true, disabled: profile.usedBy.length > 0, onSelect: () => setDeleting(true) }]} />
      </header>
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
      {/* A subscription that needs signing in, or is signing in: that comes first. */}
      {signIn && !profile.machine && (latest?.state === "login" || signingIn) && <section className={pagesCss.section}><SignIn profile={profile} needed /></section>}

      <QuotaSection profile={profile} />

      <ModelPool profile={profile} found={latest?.models ?? null} onSave={(models) => void save.run({ models })} />

      {/* A station older than the setting says nothing of it. */}
      {profile.runtimes.includes("claude") && profile.backgroundOnMessage !== undefined && (
        <Section title="运行">
          <SwitchRow title="新消息到来时，把正在执行的命令转到后台" checked={profile.backgroundOnMessage} disabled={save.busy}
            description={profile.backgroundOnMessage
              ? "Claude Code 正在等命令或 subagent 时，新消息会让它们转到后台继续跑（像按 Ctrl+B），agent 马上读到消息，跑完再回来处理结果。"
              : "新消息要等正在执行的命令或 subagent 结束后才会读到。"}
            onChange={(on) => saveThen({ backgroundOnMessage: on }, () => toast(on ? "已打开" : "已关闭"))} />
        </Section>
      )}

      <Section title="使用它的连接">
        {users.length === 0 ? <p className={shellCss.muted}>还没有连接使用这个 Profile。</p> : (
          <ul className={pagesCss.list}>
            {users.map((c) => (
              <li key={c.id}><Link className={pagesCss.listRow} to={link(`/connects/${c.id}`)}><ConnectAvatar connect={c} size={24} /><span className={pagesCss.listRowTitle}>{c.name}</span><span className={shellCss.muted}>{c.modelName ?? (profile.model ? profile.names[profile.model] ?? profile.model : "默认模型")}</span></Link></li>
            ))}
          </ul>
        )}
      </Section>

      {profile.machine ? <MachineAccount profile={profile} /> : <AccountSection profile={profile} signedIn={latest?.state !== "login" && !signingIn}
        onSave={(input, done) => saveThen(input, () => { toast("已保存，正在检查"); done(); })} busy={save.busy} />}

      {profile.access.kind === "env" && <EnvSection profile={profile} onSave={(input) => saveThen(input, () => toast("已保存"))} busy={save.busy} />}
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
    <Section title="账号">
      <p>{station.name ? `${station.name} 上` : "这台机器上"} {runtime} 的登录<About>要换号、重新登录或登出，在这台机器的 {runtime} 里做，这个 Profile 跟着它变；不想用了就停用（右上角菜单）。</About></p>
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
    <Section title="账号">
      {keyed ? (
        <div className={pagesCss.card}>
          {!replacing ? (
            <div className={pagesCss.cardRow}>
              <div className={pagesCss.cardRowText}>
                <strong>{profile.access.kind === "opencode-go" ? "OpenCode Go key" : "API key"}</strong>
                <span className={`${shellCss.muted} ${shellCss.mono}`}>{profile.access.key || "没有保存"}</span>
              </div>
              <Button onClick={() => setReplacing(true)}>更换</Button>
            </div>
          ) : (
            <Field label={profile.access.kind === "opencode-go" ? "新的 OpenCode Go key" : "新的 API key"} htmlFor="access-key" hint="保存后会重新检查。">
              <div className={additionsCss.inputRow}>
                <input id="access-key" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} type="password" autoComplete="off" autoFocus value={key} onChange={(e) => setKey(e.target.value.trim())} placeholder="粘贴 key" />
                <Button variant="ghost" onClick={() => { setReplacing(false); setKey(""); }}>取消</Button>
                <Button variant="primary" disabled={!key} busy={busy} onClick={() => onSave({ access: { kind: profile.access.kind, key } }, () => { setKey(""); setReplacing(false); })}>保存</Button>
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
    <Section title="环境变量" description="运行时启动时带上这些变量，用来接到你的模型服务。值里的 {route} 会换成会话的路由 ID。">
      <div className={pagesCss.card}>
        <div className={css.envTable}>
          {rows.map((r) => {
            const secret = r.masked !== null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(r.key);
            return (
              <div key={r.row} className={css.envRow}>
                <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} aria-label="变量名" value={r.key} onChange={(e) => update(r.row, { key: e.target.value })} placeholder="NAME" />
                <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} aria-label={`${r.key || "变量"} 的值`} type={secret ? "password" : "text"} autoComplete="off" value={r.value}
                  onChange={(e) => update(r.row, { value: e.target.value })} placeholder={r.masked !== null ? `已保存 ${r.masked}，留空保持不变` : "值"} />
                <Button variant="ghost" onClick={() => setRows(rows.filter((x) => x.row !== r.row))}>删除</Button>
              </div>
            );
          })}
          <div><Button variant="ghost" icon={Plus} onClick={() => setRows([...rows, { row: nextRow++, key: "", value: "", masked: null, original: null }])}>添加变量</Button></div>
        </div>
        <div className={pagesCss.cardActions}>
          <Button variant="primary" busy={busy} onClick={() => onSave({ env: patch() })}>保存</Button>
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
    if (job?.state === "done" && previous.current && previous.current !== "done") toast("登录成功");
    previous.current = job?.state;
  }, [job?.state, toast]);

  if (!active) {
    return (
      <div className={pagesCss.card}>
        <div className={pagesCss.cardRow}>
          <div className={pagesCss.cardRowText}>
            <strong>{needed ? `还没登录 ${provider} 账号` : `${provider} 订阅登录`}</strong>
            <span className={shellCss.muted}>
              {job?.state === "failed" ? `上次登录没成功：${job.error}` : job?.state === "done" ? "已登录。换账号的话重新登录一次。" : "登录在运行 ember 的机器上完成，你只需要在浏览器里授权。"}
            </span>
          </div>
          <Button variant={needed ? "primary" : "secondary"} icon={LogIn} busy={start.busy} onClick={() => void start.run()}>
            {job?.state === "done" || !needed ? "重新登录" : "登录"}
          </Button>
        </div>
        {start.error && <p className={controlsCss.fieldError} role="alert">{start.error.message}</p>}
        <button type="button" className={controlsCss.textToggle} onClick={() => setManual(!manual)}>{manual ? "收起" : "也可以在服务器上手动登录"}</button>
        {manual && <CopyCommand text={profile.loginCommand} />}
      </div>
    );
  }

  return (
    <div className={`${pagesCss.card} ${css.signIn}`} aria-live="polite">
      <div className={pagesCss.cardRow}>
        <div className={pagesCss.cardRowText}><strong>正在登录 {provider}</strong><span className={shellCss.muted}>15 分钟内完成，过期会自动取消。</span></div>
        <Button variant="ghost" busy={cancel.busy} onClick={() => void cancel.run()}>取消</Button>
      </div>
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
  const go = () => {
    void navigator.clipboard.writeText(code).then(() => setCopied(true), () => {}).finally(() => window.open(url, "_blank", "noopener"));
  };
  return (
    <div className={css.deviceCode}>
      <span className={`${css.deviceCodeValue} ${shellCss.mono}`}>{code}</span>
      <Button variant="primary" icon={External} onClick={go}>{copied ? "已复制，重新打开登录页" : "复制代码并打开登录页"}</Button>
      <p className={shellCss.muted}>在打开的 OpenAI 页面用要给 ember 使用的 ChatGPT 账号登录，粘贴代码。完成后这里会自动继续，不用回来点。如果页面说设备码登录没开启，先在 ChatGPT 的安全设置里打开它。</p>
    </div>
  );
}

/** What the person does in the browser for a sign-in under way: the link and the code to paste (Claude), or the link
 * and the one-time code to enter (Codex). */
function LoginSteps({ job, provider, code, setCode, send, sending, sendError }: {
  job: LoginJob | null; provider: string; code: string; setCode(code: string): void; send(): void; sending: boolean; sendError: string | null;
}) {
  if (!job || job.state === "starting") return <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />正在生成 {provider} 的登录链接…</p>;
  return (
    <>
      {job.state === "needs_code" && job.url && (
        <ol className={controlsCss.steps}>
          <li>
            <span>打开授权页面，用要给 ember 使用的 Claude 账号登录并同意。</span>
            <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href={job.url} target="_blank" rel="noopener"><External {...ICON} />打开授权页面</a>
          </li>
          <li>
            <span>同意后页面上会显示一段授权码，复制过来：</span>
            <div className={additionsCss.inputRow}>
              <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} autoComplete="off" value={code} onChange={(e) => setCode(e.target.value)} placeholder="粘贴授权码" aria-label="授权码"
                onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && code.trim()) send(); }} />
              <Button variant="primary" disabled={!code.trim()} busy={sending} onClick={() => send()}>完成登录</Button>
            </div>
            {sendError && <p className={controlsCss.fieldError} role="alert">{sendError}</p>}
          </li>
        </ol>
      )}
      {job.state === "needs_approval" && job.url && job.userCode && <DeviceCode url={job.url} code={job.userCode} />}
      {job.state === "verifying" && <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />正在完成登录…</p>}
      {job.state === "done" && <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />已登录，正在添加…</p>}
    </>
  );
}

function QuotaSection({ profile }: { profile: Profile }) {
  const api = useApi();
  // A refresh comes back with the overview.
  const refresh = useAction(() => api.refreshQuota(profile.id));
  const quota = profile.quota;
  return (
    <Section title={<>额度{quota?.time?.checkedAt && <About>{quota.time.checkedAt.ago}查询，每几分钟自动更新</About>}</>}
      actions={<Button variant="ghost" icon={Refresh} busy={refresh.busy} onClick={() => void refresh.run()}>刷新</Button>}>
      <QuotaBars quota={quota} />
    </Section>
  );
}

/**
 * Which of the profile's models may be used: none until picked here. Chats
 * and connects offer only enabled models, and the account pool sends a chat
 * only to a profile that has its model enabled.
 */
function ModelPool({ profile, found, onSave }: { profile: Profile; found: string[] | null; onSave(models: string[]): void }) {
  const [enabled, setEnabled] = useState(() => new Set(profile.models));
  const [filter, setFilter] = useState("");
  useEffect(() => setEnabled(new Set(profile.models)), [profile.models.join("\n")]);
  const all = [...new Set([...(found ?? []), ...profile.models])].sort();
  const name = (m: string) => profile.names[m] ?? m;
  const shown = all.filter((m) => [m, name(m)].some((s) => s.toLowerCase().includes(filter.trim().toLowerCase())));
  const commit = (next: Set<string>) => {
    setEnabled(next);
    onSave([...next].sort());
  };
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
    <Section title={<>模型<About>{all.length ? "只有启用的模型能在新对话和连接里选。" : "检查过 Profile 后，这里会列出它能用的模型，启用后才能使用。"}</About></>}
      actions={all.length > 0 && <Button variant="ghost" onClick={() => setChoosing(!choosing)}>{choosing ? "收起" : `选择模型（${enabled.size} / ${all.length}）`}</Button>}>
      {/* What it can be used for now, first; the whole list only when choosing. */}
      {all.length > 0 && !choosing && (
        on.length === 0 ? <p className={shellCss.muted}>还没有启用模型。</p> : (
          <ul className={css.modelChips}>
            {on.map((m) => <Tip key={m} label={m}><li className={css.modelChip}><ModelLogo maker={profile.makers[m]} runtime={profile.runtime} size={14} /><span>{name(m)}</span></li></Tip>)}
          </ul>
        )
      )}
      {all.length > 0 && choosing && (
        <div className={chatCss.modelPool}>
          <div className={chatCss.modelPoolTools}>
            {all.length > 10 && <input className={`${controlsCss.input} ${css.modelPoolFilter}`} placeholder="筛选模型" autoFocus value={filter} onChange={(e) => setFilter(e.target.value)} />}
            <button type="button" className={controlsCss.textToggle} onClick={() => commit(new Set([...enabled, ...shown]))}>全选{filter ? "筛选结果" : ""}</button>
            <button type="button" className={controlsCss.textToggle} onClick={() => commit(new Set([...enabled].filter((m) => !shown.includes(m))))}>全不选{filter ? "筛选结果" : ""}</button>
          </div>
          {series.map((s) => {
            const list = s.models.filter((m) => shown.includes(m));
            if (list.length === 0) return null;
            const every = list.every((m) => enabled.has(m));
            return (
              <div key={s.name} className={modelCss.poolSeries}>
                <div className={modelCss.poolSeriesHead}>
                  <h4>{s.name}</h4>
                  <button type="button" className={controlsCss.textToggle} onClick={() => commit(every ? new Set([...enabled].filter((m) => !list.includes(m))) : new Set([...enabled, ...list]))}>{every ? "全不选" : "全选"}</button>
                </div>
                <ul className={chatCss.modelPoolList}>
                  {list.map((m) => (
                    <li key={m}>
                      <Tip label={m}><label className={chatCss.modelPoolItem} data-on={enabled.has(m) || undefined}>
                        <input type="checkbox" checked={enabled.has(m)} onChange={() => toggle(m)} />
                        <ModelLogo maker={profile.makers[m]} runtime={profile.runtime} size={14} />
                        <span>{name(m)}</span>
                        {found && !found.includes(m) && <span className={`${shellCss.muted} ${css.modelPoolGone}`}>检查里没有了</span>}
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
