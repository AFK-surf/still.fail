// A connect: where people reach ember (a Slack app today), the model it is
// bound to, and how its conversations become sessions.
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { MessageCircle, Pencil, Power, RefreshCw, Slack, Trash2 } from "lucide-react";
import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { api, keys, useOverview, useSessions, type ConnectInput, type ConnectMode, type ConnectView, type Overview, type ProfileView, type RuntimeKind } from "../api.ts";
import { connectionText, MODE, modeText, presence, relativeTime, RUNTIME_LABEL, sessionStatus, sessionTitle, slug, STATUS_LABEL, statusTone } from "../format.ts";
import { SlackAppSection } from "./SlackApp.tsx";
import { CreateAppSteps, emptyTokens, TokenFields, type TokenState } from "../slack.tsx";
import { useToast } from "../toast.tsx";
import {
  Button, Choices, ConnectKindIcon, Confirm, Dialog, Empty, Field, ICON, IconButton, Menu, MobileBack, Pill, Section, Segmented, Select, StatusDot, SwitchRow,
} from "../ui.tsx";

export function ConnectPage() {
  const { id } = useParams();
  const overview = useOverview();
  const connect = overview.data?.connects.find((c) => c.id === id);
  if (!overview.data) return null;
  if (!connect) return <Empty><p>没有 ID 为 {id} 的连接。</p></Empty>;
  return <ConnectDetail key={connect.id} connect={connect} overview={overview.data} />;
}

function useSaveConnect(id: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: ConnectInput) => api.putConnect(id, input),
    onSuccess: (data: Overview) => client.setQueryData(keys.overview, data),
  });
}

export function connectSubtitle(c: ConnectView, profiles: ProfileView[]): string {
  const account = profiles.find((p) => p.id === c.bind.profiles[0]);
  return [RUNTIME_LABEL[c.bind.runtime], c.bind.model ?? account?.model ?? "默认模型"].join(" · ");
}

function ConnectDetail({ connect, overview }: { connect: ConnectView; overview: Overview }) {
  const navigate = useNavigate();
  const toast = useToast();
  const client = useQueryClient();
  const save = useSaveConnect(connect.id);
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(connect.name);
  const [deleting, setDeleting] = useState(false);
  const remove = useMutation({
    mutationFn: () => api.deleteConnect(connect.id),
    onSuccess: (data) => { client.setQueryData(keys.overview, data); toast("已删除连接"); navigate("/sessions"); },
  });
  const rename = () => {
    setEditingName(false);
    if (name.trim() && name.trim() !== connect.name) save.mutate({ name: name.trim() }, { onSuccess: () => toast("已改名") });
  };

  return (
    <div className="page page-narrow">
      <MobileBack to="/sessions" label="返回" />
      <header className="identity">
        <ConnectKindIcon kind={connect.kind} size={22} tile />
        <div className="identity-text">
          {editingName ? (
            <input className="input identity-name-input" value={name} autoFocus aria-label="名称"
              onChange={(e) => setName(e.target.value)} onBlur={rename}
              onKeyDown={(e) => { if (e.key === "Enter") rename(); if (e.key === "Escape") { setName(connect.name); setEditingName(false); } }} />
          ) : (
            <h1 className="identity-name">{connect.name}<IconButton label="改名" icon={Pencil} onClick={() => setEditingName(true)} /></h1>
          )}
          <p className="identity-sub">
            <span className="kind-tag">Slack</span>
            <span>{modeText(connect.mode, connect.requireMention)}</span>
            <span>{connectSubtitle(connect, overview.profiles)}</span>
          </p>
        </div>
        <Menu items={[
          connect.enabled
            ? { label: "停用", icon: Power, onSelect: () => save.mutate({ enabled: false }, { onSuccess: () => toast("已停用，Slack 连接已断开") }) }
            : { label: "启用", icon: Power, onSelect: () => save.mutate({ enabled: true }, { onSuccess: () => toast("已启用") }) },
          "separator",
          { label: "删除连接", icon: Trash2, danger: true, onSelect: () => setDeleting(true) },
        ]} />
      </header>
      {save.error && <p className="field-error page-error" role="alert">{save.error.message}</p>}

      <SlackSection connect={connect} />
      <ModeSection connect={connect} />
      {connect.mode === "single-session" && <BoundSession connect={connect} />}
      <BindSection connect={connect} overview={overview} />
      <SlackAppSection connect={connect} />
      <ConnectSessions connect={connect} />

      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.isPending} onConfirm={() => remove.mutate()}
        title={`删除「${connect.name}」？`} action="删除连接"
        description={`Slack 连接会断开${connect.sessions ? `；它的 ${connect.sessions} 个会话的记录会保留，但不再接收消息` : ""}。Slack 里的 app 需要你自己去删除。`} />
    </div>
  );
}

function SlackSection({ connect }: { connect: ConnectView }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [replacing, setReplacing] = useState(false);
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);
  const reconnect = useMutation({ mutationFn: () => api.reconnect(connect.id), onSuccess: () => toast("已重新连接") });
  const saveTokens = () => save.mutate({ slack: { appToken: tokens.appToken, botToken: tokens.botToken } }, {
    onSuccess: () => { setReplacing(false); setTokens(emptyTokens); toast("已保存 token，正在重新连接"); },
  });
  const c = connect.connection;
  const workspace = c.state === "connected" || c.state === "reconnecting" ? c.workspace : null;
  const close = () => { setReplacing(false); setTokens(emptyTokens); };

  if (c.state === "no_tokens") {
    return (
      <Section title="Slack" description="这个连接还没接上 Slack。">
        <div className="card">
          <CreateAppSteps name={connect.name} />
          <TokenFields value={tokens} onChange={setTokens} />
          <div className="card-actions">
            <Button variant="primary" disabled={!tokens.verified} busy={save.isPending} onClick={saveTokens}>保存并连接</Button>
          </div>
        </div>
      </Section>
    );
  }
  return (
    <Section title="Slack" actions={<>
      <Button icon={RefreshCw} onClick={() => reconnect.mutate()} busy={reconnect.isPending} disabled={!connect.enabled}>重新连接</Button>
      <Button onClick={() => setReplacing(true)}>更换 token</Button>
    </>}>
      <div className="card card-row">
        <StatusDot state={presence(c)} />
        <div className="card-row-text">
          <strong>{connectionText(c)}{workspace ? ` · ${workspace.team}` : ""}</strong>
          <span className="muted">
            {workspace ? `在 Slack 里是 @${workspace.botName}` : c.state === "error" ? c.error : c.state === "disabled" ? "停用后不接收新消息，已有会话保留。" : ""}
            {c.state === "reconnecting" && c.lastError ? `（${c.lastError}）` : ""}
          </span>
        </div>
        {workspace?.url && <a className="btn btn-ghost" href={workspace.url} target="_blank" rel="noopener">打开 Slack</a>}
      </div>
      <Dialog open={replacing} onClose={close} title="更换 Slack token" description="只换其中一个也可以，另一个留空会沿用已保存的。保存前先验证。"
        footer={<>
          <Button variant="ghost" onClick={close}>取消</Button>
          <Button variant="primary" disabled={!tokens.verified} busy={save.isPending} onClick={saveTokens}>保存并重新连接</Button>
        </>}>
        <TokenFields value={tokens} onChange={setTokens} connect={connect.id} masked={connect.slack} />
        {save.error && <p className="field-error" role="alert">{save.error.message}</p>}
      </Dialog>
    </Section>
  );
}

/** The mode picker, shared by the connect page and the new-connect dialog. */
export function ModeChoices({ mode, requireMention, onChange, disabled }:
  { mode: ConnectMode; requireMention: boolean; onChange(next: { mode: ConnectMode; requireMention: boolean }): void; disabled?: boolean | undefined }) {
  return (
    <Choices label="会话方式" value={mode} onChange={(m) => onChange({ mode: m, requireMention: m === "multi-session" ? true : requireMention })}
      options={(["multi-session", "single-session"] as const).map((m) => ({
        value: m, title: MODE[m].label, description: MODE[m].description, disabled,
        extra: m === "single-session" ? (
          <SwitchRow title="只在被 @ 时唤醒" checked={requireMention} disabled={disabled}
            description={requireMention ? "被 @ 的 thread 之后的回复不用再 @。" : "频道里它能看到的每条消息都会送进会话。"}
            onChange={(v) => onChange({ mode, requireMention: v })} />
        ) : undefined,
      }))} />
  );
}

function ModeSection({ connect }: { connect: ConnectView }) {
  const [changing, setChanging] = useState(false);
  return (
    <Section title="会话方式" actions={<Button onClick={() => setChanging(true)}>更改会话方式</Button>}>
      <div className="card card-row">
        <div className="card-row-text">
          <strong>{MODE[connect.mode].label}</strong>
          <span className="muted">
            {MODE[connect.mode].description}
            {connect.mode === "single-session" && (connect.requireMention ? "只在被 @ 时唤醒。" : "它能看到的每条消息都会送进会话。")}
          </span>
        </div>
      </div>
      {changing && <ModeDialog connect={connect} onClose={() => setChanging(false)} />}
    </Section>
  );
}

/** What switching to `next` does to this connect's conversations, in plain words. */
function consequences(connect: ConnectView, next: { mode: ConnectMode; requireMention: boolean }, running: number): string[] {
  const out: string[] = [];
  if (connect.mode === "multi-session" && next.mode === "single-session") {
    out.push("之后它收到的消息都进同一个会话；已有的每个 thread 的会话不再收到新消息，包括这些 thread 里的回复。记录会保留。");
    out.push(connect.session ? "会接着使用之前绑定的单会话。" : "下一条消息会开始一个新的单会话；也可以在切换后选一个已有会话。");
    if (!next.requireMention) out.push("不需要 @：它能看到的所有频道和私信里的每条消息都会送给 agent，消耗会明显增加。");
  } else if (connect.mode === "single-session" && next.mode === "multi-session") {
    out.push("当前绑定的会话不再收到新消息。之后每个 thread 被 @ 时各开一个新会话。");
    out.push("在单会话里进行过的 thread，要继续就需要重新 @，会开一个新会话，不带之前的上下文。");
    out.push("以后切回单会话，会接着用原来的那个会话。");
  } else if (next.requireMention !== connect.requireMention) {
    out.push(next.requireMention
      ? "之后只有被 @ 的 thread 会进会话；已经进来的 thread 里的回复仍然会送到。"
      : "不需要 @：它能看到的所有频道和私信里的每条消息都会送给 agent，消耗会明显增加。");
  }
  if (running > 0) out.push(`现在有 ${running} 个会话正在运行，它们会跑完当前这一轮。`);
  return out;
}

function ModeDialog({ connect, onClose }: { connect: ConnectView; onClose(): void }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const sessions = useSessions().data ?? [];
  const [next, setNext] = useState({ mode: connect.mode, requireMention: connect.requireMention });
  const changed = next.mode !== connect.mode || (next.mode === "single-session" && next.requireMention !== connect.requireMention);
  const running = sessions.filter((s) => (s.connect === connect.id || s.boundTo.includes(connect.id)) && s.process === "running").length;
  const effects = changed ? consequences(connect, next, running) : [];
  return (
    <Dialog open onClose={onClose} wide title="更改会话方式"
      description="这会改变之后每条消息进哪个会话。已经开始的对话可能因此断开，请看清下面的影响再确认。"
      footer={<>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" disabled={!changed} busy={save.isPending}
          onClick={() => save.mutate(next, { onSuccess: () => { toast("已更改会话方式"); onClose(); } })}>
          {next.mode === connect.mode ? "确认更改" : `改为${next.mode === "single-session" ? "单会话" : "多会话"}`}
        </Button>
      </>}>
      <ModeChoices mode={next.mode} requireMention={next.requireMention} onChange={setNext} />
      {effects.length > 0 && (
        <div className="callout" data-tone="amber" role="note">
          <strong>更改之后</strong>
          <ul>{effects.map((e) => <li key={e}>{e}</li>)}</ul>
        </div>
      )}
      {save.error && <p className="field-error" role="alert">{save.error.message}</p>}
    </Dialog>
  );
}

/** A single-session connect's session: the one its messages go into, which people can switch or start afresh. */
function BoundSession({ connect }: { connect: ConnectView }) {
  const sessions = useSessions().data ?? [];
  const [choosing, setChoosing] = useState(false);
  const bound = sessions.find((s) => s.key === connect.session);
  return (
    <Section title="当前会话" description="单会话模式下，消息都进这个会话。可以换成另一个会话，或者新开一个。"
      actions={<Button onClick={() => setChoosing(true)}>换一个会话</Button>}>
      {bound ? (
        <Link className="card card-row card-link" to={`/sessions/${encodeURIComponent(bound.key)}`}>
          <div className="card-row-text">
            <strong>{sessionTitle(bound, connect.name)}</strong>
            <span className="muted">{RUNTIME_LABEL[bound.runtime]} · {bound.turns} 轮 · 最近活动 {relativeTime(bound.lastActiveAt)}</span>
          </div>
          <Pill tone={statusTone(sessionStatus(bound))}>{STATUS_LABEL[sessionStatus(bound)]}</Pill>
        </Link>
      ) : (
        <div className="card card-row"><span className="muted">还没有会话；下一条消息会开始一个新的。</span></div>
      )}
      {choosing && <ChooseSessionDialog connect={connect} onClose={() => setChoosing(false)} />}
    </Section>
  );
}

function ChooseSessionDialog({ connect, onClose }: { connect: ConnectView; onClose(): void }) {
  const toast = useToast();
  const client = useQueryClient();
  const all = useSessions().data ?? [];
  const overview = useOverview().data;
  const candidates = all.filter((s) => s.runtime === connect.bind.runtime).sort((a, b) => b.lastActiveAt - a.lastActiveAt);
  const [choice, setChoice] = useState<string>(connect.session ?? "new");
  const [title, setTitle] = useState("");
  const bind = useMutation({
    mutationFn: () => api.bindSession(connect.id, choice === "new" ? null : choice, title),
    onSuccess: () => {
      void client.invalidateQueries();
      toast(choice === "new" ? "已新建会话" : "已换成这个会话");
      onClose();
    },
  });
  const nameOf = (id: string) => overview?.connects.find((c) => c.id === id)?.name ?? id;
  return (
    <Dialog open onClose={onClose} wide title="选择会话"
      description={`之后「${connect.name}」收到的消息都进选中的会话。原来的会话保留，但不再收到这个连接的新消息。`}
      footer={<>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" busy={bind.isPending} disabled={choice === connect.session}
          onClick={() => bind.mutate()}>{choice === "new" ? "新建并使用" : "使用这个会话"}</Button>
      </>}>
      <div className="session-choices">
        <Choices label="会话" value={choice} onChange={setChoice} options={[
          {
            value: "new", title: "新建会话", description: "从空白上下文开始。",
            extra: <input className="input" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="给它起个名字（可选），例如：值班" aria-label="新会话的名字" />,
          },
          ...candidates.map((s) => ({
            value: s.key,
            title: <>{sessionTitle(s, nameOf(s.connect))}{s.key === connect.session && <span className="choice-badge">当前</span>}</>,
            description: `${s.scope === "all" ? "单会话" : "来自一个 thread"} · ${nameOf(s.connect)} · ${s.turns} 轮 · ${relativeTime(s.lastActiveAt)}${s.boundTo.filter((c) => c !== connect.id).length ? ` · 也被 ${s.boundTo.filter((c) => c !== connect.id).map(nameOf).join("、")} 使用` : ""}`,
          })),
        ]} />
      </div>
      {bind.error && <p className="field-error" role="alert">{bind.error.message}</p>}
    </Dialog>
  );
}

/** Model choice: the account's model list when it has been checked, free text otherwise. */
export function ModelPicker({ id, account, value, onChange }: { id: string; account: ProfileView | undefined; value: string; onChange(value: string): void }) {
  const models = account?.check?.models ?? [];
  const fallback = account?.model ? `账号默认（${account.model}）` : "运行时默认";
  if (models.length === 0) {
    return <input id={id} className="input mono" spellCheck={false} value={value} onChange={(e) => onChange(e.target.value)} placeholder={fallback} />;
  }
  const options = [{ value: "", label: fallback }, ...[...new Set([...(value ? [value] : []), ...models])].map((m) => ({ value: m, label: m }))];
  return <Select id={id} value={value} onChange={onChange} options={options} label="模型" />;
}

function BindSection({ connect, overview }: { connect: ConnectView; overview: Overview }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const accounts = overview.profiles.filter((p) => p.runtime === connect.bind.runtime);
  const [account, setAccount] = useState(connect.bind.profiles[0] ?? "");
  const [model, setModel] = useState(connect.bind.model ?? "");
  const chosen = accounts.find((p) => p.id === account);
  const dirty = account !== (connect.bind.profiles[0] ?? "") || model.trim() !== (connect.bind.model ?? "");
  const reset = () => { setAccount(connect.bind.profiles[0] ?? ""); setModel(connect.bind.model ?? ""); };
  return (
    <Section title="模型" description="新会话用这里的设置；进行中的会话继续用开始时的账号和模型。">
      <div className="card">
        <div className="field-grid">
          <Field label="运行时">
            <p className="static-value">{RUNTIME_LABEL[connect.bind.runtime]}</p>
          </Field>
          <Field label="运行时账号" htmlFor="bind-account">
            <Select id="bind-account" value={account} onChange={(v) => { setAccount(v); setModel(""); }}
              options={accounts.map((p) => ({ value: p.id, label: p.name }))} />
          </Field>
        </div>
        <Field label="模型" htmlFor="bind-model" hint={chosen?.check?.models?.length ? `这个账号有 ${chosen.check.models.length} 个可用模型。` : "账号检查过后这里会列出可用模型。"}>
          <ModelPicker id="bind-model" account={chosen} value={model} onChange={setModel} />
        </Field>
        {dirty && (
          <div className="card-actions">
            <Button variant="ghost" onClick={reset}>还原</Button>
            <Button variant="primary" busy={save.isPending} onClick={() => save.mutate(
              { bind: { profiles: [account, ...connect.bind.profiles.filter((p) => p !== account)], model: model.trim() } },
              { onSuccess: () => toast("已保存，新会话会用新的模型") },
            )}>保存</Button>
          </div>
        )}
        <p className="card-foot muted">运行时在创建后不能换；要用另一种运行时，新建一个连接。</p>
      </div>
    </Section>
  );
}

function ConnectSessions({ connect }: { connect: ConnectView }) {
  const sessions = (useSessions().data ?? []).filter((s) => s.connect === connect.id).sort((a, b) => b.lastActiveAt - a.lastActiveAt).slice(0, 12);
  return (
    <Section title="最近的会话">
      {sessions.length === 0 ? <p className="muted">还没有会话。在 Slack 里 @{connect.name} 就会开始。</p> : (
        <ul className="list">
          {sessions.map((s) => {
            const status = sessionStatus(s);
            return (
              <li key={s.key}>
                <Link className="list-row" to={`/sessions/${encodeURIComponent(s.key)}`}>
                  <span className="list-row-title">{sessionTitle(s, connect.name)}</span>
                  <Pill tone={statusTone(status)}>{STATUS_LABEL[status]}</Pill>
                  <span className="muted list-row-time">{relativeTime(s.lastActiveAt)}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </Section>
  );
}

const KINDS = [
  { value: "slack", title: "Slack", description: "一个 Slack app，用 Socket Mode 连接，不需要公网地址。", icon: <span className="mark"><Slack {...ICON} size={16} /></span> },
  { value: "wechat", title: "微信", description: "即将支持。", disabled: true, icon: <span className="mark"><MessageCircle {...ICON} size={16} /></span> },
];

export function NewConnectDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  const overview = useOverview();
  const client = useQueryClient();
  const navigate = useNavigate();
  const toast = useToast();
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [name, setName] = useState("");
  const [id, setId] = useState("");
  const [idTouched, setIdTouched] = useState(false);
  const [runtime, setRuntime] = useState<RuntimeKind>("claude");
  const [account, setAccount] = useState("");
  const [model, setModel] = useState("");
  const [mode, setMode] = useState<{ mode: ConnectMode; requireMention: boolean }>({ mode: "multi-session", requireMention: true });
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);

  const accounts = (overview.data?.profiles ?? []).filter((p) => p.runtime === runtime);
  const chosen = accounts.find((p) => p.id === account) ?? accounts[0];
  const connectId = idTouched ? id : slug(name);
  const taken = overview.data?.connects.some((c) => c.id === connectId) ?? false;
  const idValid = /^[a-z0-9][a-z0-9-]*$/.test(connectId) && !taken;

  const close = () => {
    setStep(1); setName(""); setId(""); setIdTouched(false); setAccount(""); setModel(""); setTokens(emptyTokens);
    setMode({ mode: "multi-session", requireMention: true });
    onClose();
  };
  const create = useMutation({
    mutationFn: (withTokens: boolean) => api.putConnect(connectId, {
      name: name.trim(), kind: "slack", ...mode,
      bind: { runtime, profiles: chosen ? [chosen.id] : [], model: model.trim() },
      ...(withTokens ? { slack: { appToken: tokens.appToken, botToken: tokens.botToken } } : {}),
    }),
    onSuccess: (data, withTokens) => {
      client.setQueryData(keys.overview, data);
      toast(withTokens ? "已添加连接，正在连接 Slack" : "已添加连接");
      close();
      navigate(`/connects/${connectId}`);
    },
  });

  const titles = { 1: "添加连接", 2: "绑定模型", 3: "连接 Slack" } as const;
  const footer = step === 1 ? (
    <>
      <Button variant="ghost" onClick={close}>取消</Button>
      <Button variant="primary" disabled={!name.trim() || !idValid} onClick={() => setStep(2)}>下一步</Button>
    </>
  ) : step === 2 ? (
    <>
      <Button variant="ghost" onClick={() => setStep(1)}>上一步</Button>
      <Button variant="primary" disabled={!chosen} onClick={() => setStep(3)}>下一步</Button>
    </>
  ) : (
    <>
      <Button variant="ghost" onClick={() => setStep(2)}>上一步</Button>
      <Button onClick={() => create.mutate(false)} busy={create.isPending && create.variables === false}>稍后连接</Button>
      <Button variant="primary" disabled={!tokens.verified} busy={create.isPending && create.variables === true} onClick={() => create.mutate(true)}>添加并连接</Button>
    </>
  );

  return (
    <Dialog open={open} onClose={close} wide title={<>{titles[step]}<span className="dialog-step">{step} / 3</span></>} footer={footer}
      description={step === 1 ? "连接是人找到 ember 的地方。每个连接绑定一个模型，在哪个连接说话就由哪个模型来做。" : undefined}>
      {step === 1 && (
        <>
          <Field label="连接到">
            <Choices label="连接到" value="slack" onChange={() => {}} options={KINDS} />
          </Field>
          <div className="field-grid">
            <Field label="名称" htmlFor="new-connect-name" hint="Slack 里显示的名字，也是 agent 对自己的称呼。">
              <input id="new-connect-name" className="input" value={name} autoFocus onChange={(e) => setName(e.target.value)} placeholder="例如 ember-claude" />
            </Field>
            <Field label="ID" htmlFor="new-connect-id" error={taken ? "这个 ID 已经被别的连接用了" : undefined} hint="会话记录用它区分连接，创建后不能改。">
              <input id="new-connect-id" className="input mono" spellCheck={false} value={connectId} onChange={(e) => { setIdTouched(true); setId(e.target.value); }} />
            </Field>
          </div>
        </>
      )}
      {step === 2 && (
        <>
          <Field label="运行时">
            <Segmented label="运行时" value={runtime} onChange={(r) => { setRuntime(r); setAccount(""); setModel(""); }}
              options={[{ value: "claude", label: "Claude Code" }, { value: "codex", label: "Codex" }]} />
          </Field>
          <div className="field-grid">
            <Field label="运行时账号" htmlFor="new-connect-account"
              error={accounts.length === 0 ? `还没有 ${RUNTIME_LABEL[runtime]} 账号，先到「设置 → 运行时账号」添加。` : undefined}>
              <Select id="new-connect-account" value={chosen?.id ?? ""} onChange={(v) => { setAccount(v); setModel(""); }} disabled={accounts.length === 0}
                options={accounts.map((p) => ({ value: p.id, label: p.name }))} placeholder="没有可用账号" />
            </Field>
            <Field label="模型" htmlFor="new-connect-model">
              <ModelPicker id="new-connect-model" account={chosen} value={model} onChange={setModel} />
            </Field>
          </div>
          <Field label="会话方式">
            <ModeChoices mode={mode.mode} requireMention={mode.requireMention} onChange={setMode} />
          </Field>
        </>
      )}
      {step === 3 && (
        <>
          <CreateAppSteps name={name} />
          <TokenFields value={tokens} onChange={setTokens} />
          {create.error && <p className="field-error" role="alert">{create.error.message}</p>}
        </>
      )}
    </Dialog>
  );
}
