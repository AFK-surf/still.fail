import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ChevronRight, KeyRound, Pencil, Plus, RefreshCw, SlidersHorizontal, UserRound } from "lucide-react";
import { useState, type ComponentType } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { api, keys, useOverview, type AccessKind, type Overview, type ProfileView, type RuntimeKind } from "../api.ts";
import { ACCESS, ACCESS_KINDS, checkTone, KEYED, relativeTime, RUNTIME_LABEL } from "../format.ts";
import { useToast } from "../toast.tsx";
import { Avatar, Button, CopyCommand, Dialog, Empty, Field, ICON, IconButton, Menu, MobileBack, Pill, Segmented } from "../ui.tsx";
import { slug } from "./NewBot.tsx";

/** OpenCode's mark: a hollow square, drawn to match the 1.7 stroke icons. */
function OpenCodeMark({ size = 16 }: { size?: number; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} aria-hidden="true">
      <rect x="6" y="4" width="12" height="16" />
    </svg>
  );
}

const ACCESS_ICON: Record<AccessKind, ComponentType<{ size?: number; strokeWidth?: number }>> = {
  "subscription": UserRound,
  "opencode-go": OpenCodeMark,
  "anthropic-api": KeyRound,
  "env": SlidersHorizontal,
};

function AccessMark({ kind, size = 32 }: { kind: AccessKind; size?: number }) {
  const Icon = ACCESS_ICON[kind];
  return <span className="mark" style={{ width: size, height: size }}><Icon {...ICON} size={Math.round(size * .55)} /></span>;
}

function useApply() {
  const client = useQueryClient();
  return (data: Overview) => client.setQueryData(keys.overview, data);
}

export function AccountsPage() {
  const overview = useOverview();
  const [adding, setAdding] = useState(false);
  const profiles = overview.data?.profiles ?? [];
  const groups = (["claude", "codex"] as RuntimeKind[]).map((runtime) => ({ runtime, items: profiles.filter((p) => p.runtime === runtime) }));
  return (
    <div className="page page-narrow">
      <MobileBack to="/sessions" label="会话" />
      <header className="page-head">
        <div>
          <h1>运行时账号</h1>
          <p className="page-sub">bot 通过这些账号运行 Claude Code 或 Codex：用哪份订阅，或者接到哪个模型服务。</p>
        </div>
        <Button icon={Plus} onClick={() => setAdding(true)}>添加账号</Button>
      </header>
      {profiles.length === 0 && <Empty><p>还没有账号。bot 至少需要一个账号才能运行。</p></Empty>}
      {groups.filter((g) => g.items.length).map((g) => (
        <section key={g.runtime} className="section" aria-label={RUNTIME_LABEL[g.runtime]}>
          <div className="group-head"><strong>{RUNTIME_LABEL[g.runtime]}</strong><span className="muted">{g.items.length} 个账号</span></div>
          <ul className="list">
            {g.items.map((p) => {
              const tone = checkTone(p.check);
              return (
                <li key={p.id}>
                  <Link className="list-row account-row" to={`/settings/accounts/${p.id}`}>
                    <AccessMark kind={p.access.kind} />
                    <span className="list-row-text">
                      <span className="list-row-title">{p.name}</span>
                      <span className="muted">{ACCESS[p.access.kind].label}{p.usedBy.length ? ` · 被 ${p.usedBy.map((id) => overview.data!.bots.find((b) => b.id === id)?.name ?? id).join("、")} 使用` : " · 没有 bot 使用"}</span>
                    </span>
                    <Pill tone={tone.tone}>{tone.label}</Pill>
                    <ChevronRight {...ICON} className="list-row-chevron" />
                  </Link>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
      <AddAccountDialog open={adding} onClose={() => setAdding(false)} />
    </div>
  );
}

function AddAccountDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  const overview = useOverview();
  const navigate = useNavigate();
  const apply = useApply();
  const toast = useToast();
  const [runtime, setRuntime] = useState<RuntimeKind>("claude");
  const [kind, setKind] = useState<AccessKind>("subscription");
  const [name, setName] = useState("");
  const [key, setKey] = useState("");
  const id = slug(name) || `${runtime}-${kind}`;
  const taken = overview.data?.profiles.some((p) => p.id === id) ?? false;
  const close = () => { setName(""); setKey(""); setKind("subscription"); onClose(); };
  const add = useMutation({
    mutationFn: () => api.putProfile(id, { name: name.trim() || `${RUNTIME_LABEL[runtime]} · ${ACCESS[kind].label}`, runtime, access: { kind, key } }),
    onSuccess: (data) => { apply(data); toast("已添加账号，正在检查"); close(); navigate(`/settings/accounts/${id}`); },
  });
  return (
    <Dialog open={open} onClose={close} title="添加运行时账号"
      footer={<>
        <Button variant="ghost" onClick={close}>取消</Button>
        <Button variant="primary" disabled={taken || (KEYED.has(kind) && !key.trim())} busy={add.isPending} onClick={() => add.mutate()}>添加</Button>
      </>}>
      <Field label="运行时">
        <Segmented label="运行时" value={runtime} onChange={(r) => { setRuntime(r); if (!ACCESS_KINDS[r].includes(kind)) setKind("subscription"); }}
          options={[{ value: "claude", label: "Claude Code" }, { value: "codex", label: "Codex" }]} />
      </Field>
      <Field label="接入方式">
        <div className="choices" role="radiogroup" aria-label="接入方式">
          {ACCESS_KINDS[runtime].map((k) => (
            <button key={k} type="button" role="radio" aria-checked={k === kind} className="choice" onClick={() => setKind(k)}>
              <AccessMark kind={k} size={28} />
              <span className="choice-text"><strong>{k === "subscription" ? (runtime === "claude" ? "Claude 订阅" : "ChatGPT 订阅") : ACCESS[k].label}</strong><span className="muted">{ACCESS[k].description}</span></span>
            </button>
          ))}
        </div>
      </Field>
      {KEYED.has(kind) && (
        <Field label={kind === "opencode-go" ? "OpenCode Go key" : "API key"} htmlFor="account-key">
          <input id="account-key" className="input mono" type="password" autoComplete="off" value={key} onChange={(e) => setKey(e.target.value.trim())} />
        </Field>
      )}
      <Field label="名称" htmlFor="account-name" error={taken ? "已经有同名的账号了" : undefined}
        hint={kind === "subscription" ? "添加后按页面上的命令在服务器上登录一次。" : undefined}>
        <input id="account-name" className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder={`${RUNTIME_LABEL[runtime]} · ${ACCESS[kind].label}`} />
      </Field>
      {add.error && <p className="field-error" role="alert">{add.error.message}</p>}
    </Dialog>
  );
}

export function AccountPage() {
  const { id } = useParams();
  const overview = useOverview();
  const profile = overview.data?.profiles.find((p) => p.id === id);
  if (!overview.data) return null;
  if (!profile) return <Empty><p>没有 ID 为 {id} 的账号。</p></Empty>;
  return <AccountView key={profile.id} profile={profile} overview={overview.data} />;
}

function AccountView({ profile, overview }: { profile: ProfileView; overview: Overview }) {
  const navigate = useNavigate();
  const apply = useApply();
  const toast = useToast();
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(profile.name);
  const save = useMutation({ mutationFn: (input: Parameters<typeof api.putProfile>[1]) => api.putProfile(profile.id, input), onSuccess: apply });
  const remove = useMutation({
    mutationFn: () => api.deleteProfile(profile.id),
    onSuccess: (data) => { apply(data); toast("已删除账号"); navigate("/settings/accounts"); },
  });
  const check = useMutation({ mutationFn: () => api.checkProfile(profile.id) });
  const rename = () => {
    setEditingName(false);
    if (name.trim() && name.trim() !== profile.name) save.mutate({ name: name.trim() }, { onSuccess: () => toast("已改名") });
  };
  const latest = check.data ?? profile.check;
  const tone = checkTone(latest);
  const users = profile.usedBy.map((id) => overview.bots.find((b) => b.id === id)).filter((b) => b !== undefined);

  return (
    <div className="page page-narrow">
      <MobileBack to="/settings/accounts" label="运行时账号" />
      <header className="identity">
        <AccessMark kind={profile.access.kind} size={48} />
        <div className="identity-text">
          {editingName ? (
            <input className="input identity-name-input" value={name} autoFocus aria-label="名称" onChange={(e) => setName(e.target.value)} onBlur={rename}
              onKeyDown={(e) => { if (e.key === "Enter") rename(); if (e.key === "Escape") { setName(profile.name); setEditingName(false); } }} />
          ) : (
            <h1 className="identity-name">{profile.name}<IconButton label="改名" icon={Pencil} onClick={() => setEditingName(true)} /></h1>
          )}
          <p className="identity-sub">{RUNTIME_LABEL[profile.runtime]} · {ACCESS[profile.access.kind].label} · <span className="mono">{profile.id}</span></p>
        </div>
        <Menu items={[{
          label: "删除账号", danger: true, disabled: profile.usedBy.length > 0,
          onSelect: () => { if (window.confirm(`删除「${profile.name}」？配置目录不会删除。`)) remove.mutate(); },
        }]} />
      </header>
      {(save.error || remove.error) && <p className="field-error" role="alert">{(save.error ?? remove.error)!.message}</p>}

      <section className="section" aria-labelledby="state-heading">
        <div className="section-head">
          <h2 id="state-heading">状态</h2>
          <Button icon={RefreshCw} busy={check.isPending} onClick={() => check.mutate()}>重新检查</Button>
        </div>
        <div className="card card-row">
          <Pill tone={tone.tone}>{tone.label}</Pill>
          <div className="card-row-text">
            <span>{latest?.detail ?? "还没检查过。"}</span>
            {latest && <span className="muted">{relativeTime(latest.checkedAt)}检查</span>}
          </div>
        </div>
        {latest?.state === "login" && (
          <div className="card">
            <p className="card-lead">在运行 ember 的机器上执行这条命令登录，然后回来点「重新检查」：</p>
            <CopyCommand text={profile.loginCommand} />
          </div>
        )}
      </section>

      <AccessSection profile={profile} onSave={(input, done) => save.mutate(input, { onSuccess: () => { toast("已保存，正在检查"); done(); } })} busy={save.isPending} />

      {latest?.models && latest.models.length > 0 && (
        <section className="section" aria-labelledby="models-heading">
          <div className="section-head"><h2 id="models-heading">可用模型</h2><span className="muted">{latest.models.length} 个</span></div>
          <div className="chips">{latest.models.map((m) => <span key={m} className="chip mono">{m}</span>)}</div>
        </section>
      )}

      <section className="section" aria-labelledby="users-heading">
        <div className="section-head"><h2 id="users-heading">使用它的 bot</h2></div>
        {users.length === 0 ? <p className="muted">还没有 bot 使用这个账号。</p> : (
          <ul className="list">
            {users.map((b) => (
              <li key={b.id}><Link className="list-row" to={`/bots/${b.id}`}><Avatar id={b.id} name={b.name} /><span className="list-row-title">{b.name}</span><span className="muted">{b.model ?? "默认模型"}</span></Link></li>
            ))}
          </ul>
        )}
      </section>

      <Advanced profile={profile} onSave={(input) => save.mutate(input, { onSuccess: () => toast("已保存") })} busy={save.isPending} />
    </div>
  );
}

function AccessSection({ profile, onSave, busy }: { profile: ProfileView; onSave(input: Parameters<typeof api.putProfile>[1], done: () => void): void; busy: boolean }) {
  const [kind, setKind] = useState<AccessKind>(profile.access.kind);
  const [key, setKey] = useState("");
  const changedKind = kind !== profile.access.kind;
  const needsKey = KEYED.has(kind) && (changedKind || !profile.access.key);
  const dirty = changedKind || key.length > 0;
  return (
    <section className="section" aria-labelledby="access-heading">
      <div className="section-head"><h2 id="access-heading">接入</h2></div>
      <div className="card">
        <Field label="接入方式" htmlFor="access-kind" hint={ACCESS[kind].description}>
          <select id="access-kind" className="select" value={kind} onChange={(e) => { setKind(e.target.value as AccessKind); setKey(""); }}>
            {ACCESS_KINDS[profile.runtime].map((k) => <option key={k} value={k}>{ACCESS[k].label}</option>)}
          </select>
        </Field>
        {KEYED.has(kind) && (
          <Field label={kind === "opencode-go" ? "OpenCode Go key" : "API key"} htmlFor="access-key">
            <input id="access-key" className="input mono" type="password" autoComplete="off" value={key} onChange={(e) => setKey(e.target.value.trim())}
              placeholder={!changedKind && profile.access.key ? `已保存 ${profile.access.key}，留空保持不变` : "粘贴 key"} />
          </Field>
        )}
        {dirty && (
          <div className="card-actions">
            <Button variant="ghost" onClick={() => { setKind(profile.access.kind); setKey(""); }}>还原</Button>
            <Button variant="primary" busy={busy} disabled={needsKey && !key} onClick={() => onSave({ access: { kind, key } }, () => setKey(""))}>保存</Button>
          </div>
        )}
      </div>
    </section>
  );
}

interface EnvRow { row: number; key: string; value: string; masked: string | null; original: string | null }
let nextRow = 1;

function Advanced({ profile, onSave, busy }: { profile: ProfileView; onSave(input: Parameters<typeof api.putProfile>[1]): void; busy: boolean }) {
  const [home, setHome] = useState(profile.home);
  const [model, setModel] = useState(profile.model ?? "");
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
    <details className="section advanced">
      <summary><h2>高级</h2></summary>
      <div className="card">
        <Field label="配置目录" htmlFor="adv-home" hint={`${profile.runtime === "claude" ? "作为 CLAUDE_CONFIG_DIR" : "作为 CODEX_HOME"}。相对路径以 ember 数据目录为基准。${profile.homeExists ? "" : "目录还不存在。"}`}>
          <input id="adv-home" className="input mono" value={home} onChange={(e) => setHome(e.target.value)} />
        </Field>
        <Field label="默认模型" htmlFor="adv-model" hint="bot 没指定模型时使用。">
          <input id="adv-model" className="input mono" value={model} onChange={(e) => setModel(e.target.value)} placeholder="运行时默认" />
        </Field>
        <Field label="自定义环境变量" hint="在接入方式生成的变量之外追加；同名时以这里为准。值里的 {route} 会换成会话的路由 ID。">
          <div className="env-table">
            {rows.map((r) => {
              const secret = r.masked !== null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(r.key);
              return (
                <div key={r.row} className="env-row">
                  <input className="input mono" aria-label="变量名" value={r.key} onChange={(e) => update(r.row, { key: e.target.value })} placeholder="NAME" />
                  <input className="input mono" aria-label={`${r.key || "变量"} 的值`} type={secret ? "password" : "text"} autoComplete="off" value={r.value}
                    onChange={(e) => update(r.row, { value: e.target.value })} placeholder={r.masked !== null ? `已保存 ${r.masked}，留空保持不变` : "值"} />
                  <Button variant="ghost" onClick={() => setRows(rows.filter((x) => x.row !== r.row))}>删除</Button>
                </div>
              );
            })}
            <div><Button variant="ghost" icon={Plus} onClick={() => setRows([...rows, { row: nextRow++, key: "", value: "", masked: null, original: null }])}>添加变量</Button></div>
          </div>
        </Field>
        <div className="card-actions">
          <Button variant="primary" busy={busy} onClick={() => onSave({ home: home.trim(), model: model.trim(), env: patch() })}>保存高级设置</Button>
        </div>
      </div>
    </details>
  );
}
