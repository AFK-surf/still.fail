// Profiles on a narrow screen (what the desktop's ../pages/Accounts.tsx does, in the Android app's manner): a profile's
// page (whether it works, signing a subscription in, its allowance, which of its models may be used, who uses it, its
// key or variables; renaming, checking and deleting under "…"), and a new one.
import { useEffect, useMemo, useRef, useState } from "react";
import { useParams } from "react-router";
import { stationApi, useOverview, useStationCall, type LoginJob, type Profile, type ProfileInput } from "../api.ts";
import { ACCESS, KEYED } from "../format.ts";
import { Check, More } from "../icons.tsx";
import { CHOICES } from "../pages/Accounts.tsx";
import { stationBase, useStation } from "../station.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Button, Field, ListCard, ListRow, Loading, NavBar, NavButton, PickRow, ProviderMark, QuotaRing, SectionHeader, SlackMark, Spinner } from "./parts.tsx";
import { ask, CommandBox, confirm } from "./sheets.tsx";

function useApi() {
  const station = useStation();
  const call = useStationCall(station.address);
  return useMemo(() => stationApi(call), [call]);
}

/** A profile of the station in context, by the page's :id. */
export function ProfileScreen() {
  const app = useApp();
  const station = useStation();
  const { id = "" } = useParams();
  const overview = useOverview(station.address);
  const p = overview.value?.profiles.find((x) => x.id === id);
  if (!p) return <div className="m-screen"><NavBar back={station.name || "Station"} onBack={app.pop} title="Profile" /><Loading text={overview.error?.message ?? (overview.value ? "没有这个 Profile。" : "正在读取…")} /></div>;
  return <ProfilePage p={p} />;
}

function ProfilePage({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const overview = useOverview(station.address).value;
  const users = p.usedBy.map((id) => overview?.connects.find((c) => c.id === id)).filter((c) => c !== undefined);
  const save = (input: ProfileInput, done: string) => api.putProfile(p.id, input).then(() => app.toast(done), (e: Error) => app.toast(e.message));
  const signingIn = !!p.login && ["starting", "needs_code", "needs_approval", "verifying"].includes(p.login.state);
  const keyed = KEYED.has(p.access.kind);
  return (
    <div className="m-screen">
      <NavBar back={station.name || "Station"} onBack={app.pop} title={p.name} sub={<span className="m-navbar-note">{ACCESS[p.access.kind].label}</span>}
        trailing={<NavButton icon={More} label="更多" onClick={() => app.sheet({ height: 0.5, content: () => <ProfileMenu p={p} /> })} />} />
      <div className="m-scroll m-station-page">
        <div className="m-card m-profile-head">
          <ProviderMark runtime={p.runtime} kind={p.access.kind} size={26} />
          <span className="m-grow">
            <span className="m-pill m-check-pill" data-tone={p.checkTone}>{p.checkText}</span>
            <span className="m-row-note m-wrap">{p.check ? p.check.detail.replace(/^可用[，,]\s*/, "") : "还没检查过"}{p.check?.time?.checkedAt ? ` · ${p.check.time.checkedAt.ago}检查` : ""}</span>
          </span>
        </div>
        {p.access.kind === "subscription" && !p.machine && <SignIn p={p} needed={p.check?.state === "login" || signingIn} />}
        <Quota p={p} />
        <Models p={p} onSave={(models) => void save({ models }, "已保存")} />
        <SectionHeader title="使用它的连接" start={24} />
        <ListCard>
          {users.length === 0 && <ListRow><span className="m-muted m-row-title">还没有连接使用这个 Profile。</span></ListRow>}
          {users.map((c) => (
            <ListRow key={c.id} onClick={() => app.push(`${stationBase(station.address)}/connects/${encodeURIComponent(c.id)}`)}>
              <SlackMark size={15} /><span className="m-grow m-row-title">{c.name}</span><span className="m-row-note">{c.bind.model ?? p.model ?? "默认模型"}</span>
            </ListRow>
          ))}
        </ListCard>
        {keyed && (
          <>
            <SectionHeader title="账号" start={24} />
            <ListCard>
              <ListRow onClick={() => ask(app, { title: p.access.kind === "opencode-go" ? "新的 OpenCode Go key" : "新的 API key", value: "", placeholder: "粘贴 key", action: "保存", secret: true,
                hint: "保存后会重新检查。", run: (key) => api.putProfile(p.id, { access: { kind: p.access.kind, key } }).then(() => app.toast("已保存，正在检查")) })}>
                <span className="m-grow m-row-text"><span className="m-row-title">{p.access.kind === "opencode-go" ? "OpenCode Go key" : "API key"}</span><span className="m-row-note m-mono">{p.access.key || "没有保存"}</span></span>
                <span className="m-link">更换</span>
              </ListRow>
            </ListCard>
          </>
        )}
        {p.access.kind === "env" && (
          <>
            <SectionHeader title="环境变量" start={24} />
            <ListCard>
              {p.env.map((e) => <ListRow key={e.key}><span className="m-grow m-row-text"><span className="m-row-title m-mono">{e.key}</span><span className="m-row-note m-mono">{e.value}</span></span></ListRow>)}
              <ListRow onClick={() => app.sheet({ height: 0.8, draggable: true, content: () => <EnvSheet p={p} /> })}><span className="m-accent m-row-title">编辑变量</span></ListRow>
            </ListCard>
          </>
        )}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

/** Renaming, checking, refreshing its allowance, deleting it (not while a connect uses it; never one on the machine's login). */
function ProfileMenu({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const failed = (e: Error) => app.toast(e.message);
  return (
    <>
      <SheetGrab />
      <SheetHead title={p.name} />
      <div className="m-sheet-scroll">
        {!p.machine && <PickRow label="改名" onClick={() => ask(app, { title: "Profile 的名字", value: p.name, placeholder: "名字", action: "保存", run: (name) => api.putProfile(p.id, { name }).then(() => app.toast("已改名")) })} />}
        <PickRow label="重新检查" onClick={() => { app.sheet(null); api.checkProfile(p.id).then(() => app.toast("已检查"), failed); }} />
        <PickRow label="刷新额度" onClick={() => { app.sheet(null); api.refreshQuota(p.id).then(() => app.toast("已刷新额度"), failed); }} />
        {!p.machine && <PickRow label={p.usedBy.length ? "删除 Profile（还有连接在用）" : "删除 Profile"} accent enabled={p.usedBy.length === 0} onClick={() => confirm(app, {
          title: `删除「${p.name}」？`, text: "只从 ember 的配置里移除；配置目录和里面的登录状态不会删除。", action: "删除 Profile", danger: true,
          run: () => api.deleteProfile(p.id).then(() => { app.toast("已删除 Profile"); app.pop(); }),
        })} />}
      </div>
    </>
  );
}

/** Its allowance, window by window: what is left and when it refills. */
function Quota({ p }: { p: Profile }) {
  const windows = p.quota?.state === "ok" ? p.quota.windows : [];
  if (!windows.length) return null;
  return (
    <>
      <SectionHeader title="额度" trailing={p.quota?.time?.checkedAt ? `${p.quota.time.checkedAt.ago}查询` : undefined} start={24} />
      <ListCard>
        {windows.map((w) => (
          <ListRow key={w.mark}>
            <QuotaRing left={w.left} level={w.level} size={26} />
            <span className="m-grow m-row-text"><span className="m-row-title">{w.label}</span>{w.refills && <span className="m-row-note">{w.refills}</span>}</span>
            <span className="m-row-note">剩 {w.left}%</span>
          </ListRow>
        ))}
      </ListCard>
    </>
  );
}

/** Which of its models may be used: one per line, a filter when there are many, and all / none of what is shown. */
function Models({ p, onSave }: { p: Profile; onSave: (models: string[]) => void }) {
  const [filter, setFilter] = useState("");
  const available = [...new Set([...(p.check?.models ?? []), ...p.models])];
  const all = [...available].sort();
  const shown = all.filter((m) => m.toLowerCase().includes(filter.trim().toLowerCase()));
  const save = (models: string[]) => onSave([...new Set(models)].sort());
  const suffix = filter.trim() ? "筛选结果" : "";
  return (
    <>
      <SectionHeader title={`模型 · 启用 ${p.models.length} / ${all.length}`} start={24} />
      <p className="m-profile-note">{all.length === 0 ? "检查过 Profile 后，这里会列出它能用的模型，勾选后才能使用。" : "只有勾选的模型能在新对话和连接里选。"}</p>
      {all.length > 0 && (
        <div className="m-profile-tools">
          {all.length > 10 ? <span className="m-grow"><Field value={filter} onChange={setFilter} placeholder="筛选模型" /></span> : <span className="m-grow" />}
          <button type="button" className="m-link" onClick={() => save([...p.models, ...shown])}>全选{suffix}</button>
          <button type="button" className="m-link" onClick={() => save(p.models.filter((m) => !shown.includes(m)))}>全不选{suffix}</button>
        </div>
      )}
      {shown.map((m) => {
        const on = p.models.includes(m);
        return (
          <button key={m} type="button" className="m-model-row" onClick={() => save(on ? p.models.filter((x) => x !== m) : [...p.models, m])}>
            <span className="m-check" data-on={on || undefined}>{on && <Check size={13} />}</span>
            <span className="m-grow m-mono">{m}</span>
          </button>
        );
      })}
    </>
  );
}

/** A subscription's sign-in: run on the station's machine, the browser steps relayed here. */
function SignIn({ p, needed }: { p: Profile; needed: boolean }) {
  const app = useApp();
  const api = useApi();
  const job = p.login;
  const active = !!job && ["starting", "needs_code", "needs_approval", "verifying"].includes(job.state);
  const provider = p.runtime === "claude" ? "Claude" : "ChatGPT";
  const [busy, setBusy] = useState(false);
  const previous = useRef(job?.state);
  useEffect(() => {
    if (job?.state === "done" && previous.current && previous.current !== "done") app.toast("登录成功");
    previous.current = job?.state;
  }, [job?.state]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <>
      <SectionHeader title={active ? `正在登录 ${provider}` : needed ? `还没登录 ${provider} 账号` : `${provider} 订阅`} start={24} />
      <div className="m-card m-form-group">
        {active ? (
          <>
            <LoginSteps job={job} provider={provider} send={(code) => api.loginCode(p.id, code)} />
            <Button label="取消登录" primary={false} onClick={() => void api.cancelLogin(p.id)} />
          </>
        ) : (
          <>
            <p className="m-muted m-small">{job?.state === "failed" ? `上次登录没成功：${job.error}` : job?.state === "done" ? "已登录。换账号的话重新登录一次。" : "登录在运行 ember 的机器上完成，你只需要在浏览器里授权。"}</p>
            <Button label={job?.state === "done" || !needed ? "重新登录" : "登录"} primary={needed} busy={busy}
              onClick={() => { setBusy(true); api.startLogin(p.id).catch((e: Error) => app.toast(e.message)).finally(() => setBusy(false)); }} />
            <details className="m-details"><summary>也可以在那台机器上手动登录</summary><CommandBox text={p.loginCommand} /></details>
          </>
        )}
      </div>
    </>
  );
}

/** What the person does in the browser for a sign-in under way: open the page and paste the code back (Claude), or copy the code and open the page (Codex). */
function LoginSteps({ job, provider, send }: { job: LoginJob | null | undefined; provider: string; send: (code: string) => Promise<unknown> }) {
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  if (!job || job.state === "starting") return <p className="m-muted m-waiting"><Spinner size={12} />正在生成 {provider} 的登录链接…</p>;
  if (job.state === "verifying") return <p className="m-muted m-waiting"><Spinner size={12} />正在完成登录…</p>;
  if (job.state === "done") return <p className="m-muted m-waiting"><Spinner size={12} />已登录，正在添加…</p>;
  if (job.state === "needs_approval" && job.url && job.userCode) {
    return (
      <>
        <span className="m-device-code">{job.userCode}</span>
        <Button label={copied ? "已复制，重新打开登录页" : "复制代码并打开登录页"} primary
          onClick={() => { void navigator.clipboard.writeText(job.userCode!).then(() => setCopied(true), () => {}).finally(() => window.open(job.url!, "_blank", "noopener")); }} />
        <p className="m-muted m-small">在打开的 OpenAI 页面用要给 ember 使用的 ChatGPT 账号登录，粘贴代码。完成后这里会自动继续。如果页面说设备码登录没开启，先在 ChatGPT 的安全设置里打开它。</p>
      </>
    );
  }
  if (job.state === "needs_code" && job.url) {
    return (
      <>
        <p className="m-small">1. <a href={job.url} target="_blank" rel="noopener">打开授权页面</a>，用要给 ember 使用的 Claude 账号登录并同意。</p>
        <p className="m-small">2. 同意后页面上会显示一段授权码，复制过来：</p>
        <input className="m-field" data-mono autoComplete="off" spellCheck={false} value={code} placeholder="粘贴授权码" onChange={(e) => setCode(e.target.value)} />
        {error && <p className="m-error">{error}</p>}
        <Button label="完成登录" primary busy={busy} enabled={!!code.trim()}
          onClick={() => { setBusy(true); setError(null); send(code.trim()).then(() => setCode(""), (e: Error) => setError(e.message)).finally(() => setBusy(false)); }} />
      </>
    );
  }
  return null;
}

interface EnvRow { row: number; key: string; value: string; masked: string | null; original: string | null }

/** The variables a custom profile runs with: what reaches its runtime's model service, set by hand. */
function EnvSheet({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const next = useRef(1);
  const [rows, setRows] = useState<EnvRow[]>(() => p.env.map((e) => ({ row: next.current++, key: e.key, value: e.secret ? "" : e.value, masked: e.secret ? e.value : null, original: e.key })));
  const [busy, setBusy] = useState(false);
  const patch = (): Record<string, string | null> => {
    const out: Record<string, string | null> = {};
    const kept = new Set(rows.map((r) => r.key.trim()));
    for (const e of p.env) if (!kept.has(e.key)) out[e.key] = null;
    for (const r of rows) {
      const key = r.key.trim();
      if (!key) continue;
      if (r.original && r.original !== key) out[r.original] = null;
      if (r.masked !== null && r.value === "" && r.original === key) continue;
      out[key] = r.value;
    }
    return out;
  };
  const update = (row: number, change: Partial<EnvRow>) => setRows(rows.map((r) => (r.row === row ? { ...r, ...change } : r)));
  return (
    <>
      <SheetGrab />
      <SheetHead title="环境变量" />
      <div className="m-sheet-scroll m-form">
        <p className="m-muted m-small">运行时启动时带上这些变量，用来接到你的模型服务。值里的 {"{route}"} 会换成会话的路由 ID。</p>
        {rows.map((r) => (
          <div key={r.row} className="m-env-row">
            <input className="m-field" data-mono spellCheck={false} value={r.key} placeholder="NAME" onChange={(e) => update(r.row, { key: e.target.value })} />
            <input className="m-field" data-mono spellCheck={false} autoComplete="off" type={r.masked !== null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(r.key) ? "password" : "text"}
              value={r.value} placeholder={r.masked !== null ? `已保存 ${r.masked}，留空不变` : "值"} onChange={(e) => update(r.row, { value: e.target.value })} />
            <button type="button" className="m-link" onClick={() => setRows(rows.filter((x) => x.row !== r.row))}>删除</button>
          </div>
        ))}
        <button type="button" className="m-link m-step-alt" onClick={() => setRows([...rows, { row: next.current++, key: "", value: "", masked: null, original: null }])}>＋ 添加变量</button>
        <div className="m-form-actions">
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <Button label="保存" primary busy={busy} onClick={() => { setBusy(true); api.putProfile(p.id, { env: patch() }).then(() => { app.toast("已保存"); app.sheet(null); }, (e: Error) => app.toast(e.message)).finally(() => setBusy(false)); }} />
        </div>
      </div>
    </>
  );
}

type Choice = keyof typeof CHOICES;

/**
 * A new profile on the station in context: a subscription is signed in first and the station makes the profile once
 * that succeeds (named by the account); a key is checked first and the profile made only if it works.
 */
export function NewProfileScreen() {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const overview = useOverview(station.address).value;
  const [choice, setChoice] = useState<Choice>("claude-sub");
  const { kind, runtime } = CHOICES[choice];
  const [key, setKey] = useState("");
  const [login, setLogin] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const pending = login ? overview?.logins.find((l) => l.id === login) : undefined;
  const go = (id: string, message: string) => { app.toast(message); app.replace(`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(id)}`); };
  // The sign-in made its profile: on to it.
  useEffect(() => { if (pending?.created) go(pending.created, "已登录，添加了 Profile"); }, [pending?.created]); // eslint-disable-line react-hooks/exhaustive-deps
  // Leaving before a sign-in made its profile leaves nothing behind.
  const leave = () => { if (login && !pending?.created) void api.dropLogin(login).catch(() => {}); app.pop(); };
  const provider = runtime === "claude" ? "Claude" : "ChatGPT";
  const job = pending?.job ?? null;
  return (
    <div className="m-screen">
      <NavBar back="取消" onBack={leave} title="添加 Profile" sub={<span className="m-navbar-note">{station.name}</span>} />
      <div className="m-scroll m-pad-x-18 m-steps">
        {login ? (
          job?.state === "failed" || job?.state === "cancelled" ? (
            <>
              <p className="m-error">{job.error ?? "登录没有完成。"}</p>
              <Button label="重新开始" primary={false} onClick={() => { void api.dropLogin(login).catch(() => {}); setLogin(null); }} />
            </>
          ) : <LoginSteps job={job} provider={provider} send={(code) => api.newLoginCode(login, code)} />
        ) : (
          <>
            <ListCard>
              {(Object.keys(CHOICES) as Choice[]).map((c) => (
                <PickRow key={c} label={CHOICES[c].title} sub={CHOICES[c].description} checked={choice === c} onClick={() => setChoice(c)}
                  leading={<ProviderMark runtime={CHOICES[c].runtime ?? "claude"} kind={CHOICES[c].kind} size={18} />} />
              ))}
            </ListCard>
            {KEYED.has(kind) && (
              <>
                <b className="m-form-label">{kind === "opencode-go" ? "OpenCode Go key" : "API key"}</b>
                <input className="m-field" data-mono type="password" autoComplete="off" spellCheck={false} value={key} placeholder="先验证能用，再添加" onChange={(e) => setKey(e.target.value.trim())} />
              </>
            )}
            {kind === "subscription" && <p className="m-muted m-small">登录在运行 ember 的机器上完成，你只需要在浏览器里授权；登录成功后才会添加这个 Profile。</p>}
            {error && <p className="m-error">{error}</p>}
            {kind === "subscription"
              ? <Button label={`登录 ${provider}`} primary busy={busy} onClick={() => { setBusy(true); setError(null); api.newLogin(runtime!).then(({ id }) => setLogin(id), (e: Error) => setError(e.message)).finally(() => setBusy(false)); }} />
              : <Button label={KEYED.has(kind) ? "验证并添加" : "添加"} primary busy={busy} enabled={!KEYED.has(kind) || !!key}
                  onClick={() => { setBusy(true); setError(null); api.addProfile({ ...(runtime ? { runtime } : {}), access: { kind, ...(KEYED.has(kind) ? { key } : {}) } }).then(({ id }) => go(id, "已验证并添加 Profile"), (e: Error) => setError(e.message)).finally(() => setBusy(false)); }} />}
          </>
        )}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

