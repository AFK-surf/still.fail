import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { api, keys, useOverview, type ProfileView, type RuntimeKind } from "../api.ts";
import { RUNTIME_LABEL } from "../format.ts";
import { useToast } from "../toast.tsx";

export function ProfilesPage() {
  const { id } = useParams();
  const overview = useOverview();
  const profiles = overview.data?.profiles ?? [];
  const editing = id === "new" ? null : profiles.find((p) => p.id === id);
  return (
    <div className="settings" data-detail={Boolean(id)}>
      <section className="list-pane" aria-label="账号列表">
        <div className="page-head">
          <h1>账号</h1>
          <Link className="button button-primary" to="/profiles/new">添加账号</Link>
        </div>
        {profiles.length === 0 && <div className="empty"><p>还没有账号。bot 需要至少一个账号才能运行。</p></div>}
        {profiles.map((p) => (
          <Link key={p.id} className="row" to={`/profiles/${p.id}`} aria-current={p.id === id}>
            <div className="row-title">{p.id}</div>
            <div className="row-sub">
              {RUNTIME_LABEL[p.runtime]}{p.model ? `，${p.model}` : ""}；{p.usedBy.length ? `被 ${p.usedBy.join("、")} 使用` : "没有 bot 使用"}
            </div>
          </Link>
        ))}
      </section>
      <section className="detail-pane" aria-label="编辑账号">
        {id === "new" && <ProfileForm key="new" profile={null} />}
        {editing && <ProfileForm key={editing.id} profile={editing} />}
        {id && id !== "new" && !editing && overview.isSuccess && <div className="empty"><p>没有 id 为 {id} 的账号。</p></div>}
        {!id && <div className="empty"><p>选一个账号编辑，或者添加一个。</p></div>}
      </section>
    </div>
  );
}

interface EnvRow {
  /** Stable React key. */
  row: number;
  key: string;
  value: string;
  /** For stored secrets: what the masked value looks like. Blank input keeps it. */
  masked: string | null;
  /** The key as stored, if this row came from the server. */
  original: string | null;
}

let nextRow = 1;

function ProfileForm({ profile }: { profile: ProfileView | null }) {
  const navigate = useNavigate();
  const client = useQueryClient();
  const toast = useToast();
  const [id, setId] = useState(profile?.id ?? "");
  const [runtime, setRuntime] = useState<RuntimeKind>(profile?.runtime ?? "claude");
  const [home, setHome] = useState(profile?.home ?? "");
  const [model, setModel] = useState(profile?.model ?? "");
  const [rows, setRows] = useState<EnvRow[]>(() => (profile?.env ?? []).map((e) => ({
    row: nextRow++, key: e.key, value: e.secret ? "" : e.value, masked: e.secret ? e.value : null, original: e.key,
  })));
  const inUse = (profile?.usedBy.length ?? 0) > 0;

  const envPatch = (): Record<string, string | null> => {
    const patch: Record<string, string | null> = {};
    const kept = new Set(rows.map((r) => r.key.trim()));
    for (const e of profile?.env ?? []) if (!kept.has(e.key)) patch[e.key] = null;
    for (const r of rows) {
      const key = r.key.trim();
      if (!key) continue;
      if (r.original && r.original !== key) patch[r.original] = null;
      if (r.masked !== null && r.value === "" && r.original === key) continue; // untouched secret
      patch[key] = r.value;
    }
    return patch;
  };

  const save = useMutation({
    mutationFn: () => api.putProfile(id.trim(), { runtime, home: home.trim(), model: model.trim(), env: envPatch() }),
    onSuccess: (data) => {
      client.setQueryData(keys.overview, data);
      toast(profile ? "已保存" : "已添加账号");
      if (!profile) navigate(`/profiles/${id.trim()}`);
    },
  });
  const remove = useMutation({
    mutationFn: () => api.deleteProfile(profile!.id),
    onSuccess: (data) => {
      client.setQueryData(keys.overview, data);
      toast("已删除账号");
      navigate("/profiles");
    },
  });

  const submit = (event: FormEvent) => {
    event.preventDefault();
    save.mutate();
  };
  const update = (row: number, patch: Partial<EnvRow>) => setRows(rows.map((r) => (r.row === row ? { ...r, ...patch } : r)));
  const idValid = /^[a-z0-9][a-z0-9-]*$/.test(id.trim());

  return (
    <form className="form" onSubmit={submit}>
      <Link className="back" to="/profiles">返回账号列表</Link>
      <h2>{profile ? profile.id : "添加账号"}</h2>
      <p className="lead">账号是 bot 运行时使用的一套身份和配置：一个独立的配置目录，加上启动时注入的环境变量。</p>

      <div className="field">
        <label htmlFor="profile-id">ID</label>
        <input id="profile-id" className="input" value={id} onChange={(e) => setId(e.target.value)} disabled={Boolean(profile)} required
          pattern="[a-z0-9][a-z0-9\-]*" placeholder="例如 claude-team、codex-main" />
      </div>
      <div className="field">
        <label htmlFor="profile-runtime">运行时</label>
        <select id="profile-runtime" className="select" value={runtime} onChange={(e) => setRuntime(e.target.value as RuntimeKind)} disabled={inUse}>
          <option value="claude">Claude Code</option>
          <option value="codex">Codex</option>
        </select>
        {inUse && <span className="hint">正在被 {profile!.usedBy.join("、")} 使用，不能改运行时。</span>}
      </div>
      <div className="field">
        <label htmlFor="profile-home">配置目录</label>
        <input id="profile-home" className="input" value={home} onChange={(e) => setHome(e.target.value)} placeholder={`留空则用 homes/${id || "<id>"}`} />
        <span className="hint">
          {runtime === "claude" ? "作为 CLAUDE_CONFIG_DIR。" : "作为 CODEX_HOME；模型服务商在其中的 config.toml 里配置。"}
          相对路径以 ember 数据目录为基准。用订阅账号时，在服务器上对这个目录登录一次
          （{runtime === "claude" ? "CLAUDE_CONFIG_DIR=<目录> claude" : "CODEX_HOME=<目录> codex login"}）。
          {profile && !profile.homeExists && " 这个目录现在还不存在。"}
        </span>
      </div>
      <div className="field">
        <label htmlFor="profile-model">默认模型</label>
        <input id="profile-model" className="input" value={model} onChange={(e) => setModel(e.target.value)} placeholder="bot 没指定模型时使用" />
      </div>
      <div className="field">
        <span className="label">环境变量</span>
        <div className="env-table">
          {rows.map((r) => (
            <EnvRowView key={r.row} row={r} onChange={(patch) => update(r.row, patch)} onRemove={() => setRows(rows.filter((x) => x.row !== r.row))} />
          ))}
        </div>
        <div><button type="button" className="button" onClick={() => setRows([...rows, { row: nextRow++, key: "", value: "", masked: null, original: null }])}>添加变量</button></div>
        <span className="hint">
          值里的 {"{route}"} 会替换成会话的路由 ID，用于 OpenCode Go 这类需要会话亲和的服务。
          {runtime === "codex" && " Codex 的进程由同一账号的会话共享，改动在它下次启动时生效。"}
        </span>
      </div>

      <div className="form-actions">
        <button type="submit" className="button button-primary" disabled={save.isPending || !idValid}>{profile ? "保存" : "添加账号"}</button>
        {profile && (
          <button type="button" className="button button-danger" disabled={inUse || remove.isPending}
            title={inUse ? "先把它从使用它的 bot 上移除" : undefined}
            onClick={() => window.confirm(`删除账号「${profile.id}」？配置目录不会被删除。`) && remove.mutate()}>删除</button>
        )}
      </div>
      {[save, remove].map((m, i) => m.error && <p key={i} className="error" role="alert">{m.error.message}</p>)}
    </form>
  );
}

function EnvRowView({ row, onChange, onRemove }: { row: EnvRow; onChange: (patch: Partial<EnvRow>) => void; onRemove: () => void }) {
  const secret = row.masked !== null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(row.key);
  return (
    <>
      <input className="input inline-code" aria-label="变量名" value={row.key} onChange={(e) => onChange({ key: e.target.value })} placeholder="NAME" />
      <input className="input inline-code" aria-label={`${row.key || "变量"} 的值`} type={secret ? "password" : "text"} autoComplete="off"
        value={row.value} onChange={(e) => onChange({ value: e.target.value })}
        placeholder={row.masked !== null ? `已设置（${row.masked}），留空保持不变` : "值"} />
      <button type="button" className="button" onClick={onRemove} aria-label={`删除 ${row.key || "这一行"}`}>删除</button>
    </>
  );
}
