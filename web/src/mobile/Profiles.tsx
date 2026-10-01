// Profiles on a narrow screen (what the desktop's ../pages/Accounts.tsx does, in the Android app's manner): every
// station's in one list, a profile's
// page (whether it works, signing a subscription in, its allowance, which of its models may be used, who uses it, its
// key or variables; renaming, checking and deleting under "…"), and a new one.
import { useEffect, useMemo, useRef, useState } from "react";
import { useParams, useSearchParams } from "react-router";
import { stationApi, useOverview, useStationCall, useStations, type LoginJob, type Profile, type ProfileInput, type Quota, type StationView, type Tone } from "../api.ts";
import type { MachineLogin } from "../core/shapes.ts";
import { ACCESS, KEYED } from "../format.ts";
import { Check, ChevronRight, More, Plus } from "../icons.tsx";
import { CHOICES } from "../pages/Accounts.tsx";
import { QuotaBars } from "../components.tsx";
import { StationContext, stationBase, useStation } from "../station.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Presence } from "./Connects.tsx";
import { Button, Field, LargeTitle, ListCard, ListRow, Loading, NavBar, NavButton, PickRow, ProviderMark, QuotaRings, SectionHeader, SlackMark, Spinner, TopBack } from "./parts.tsx";
import { ask, CommandBox, confirm } from "./sheets.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as historyCss from "./styles/history.css.ts";
import * as css from "./Profiles.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as chatCss from "./styles/chat.css.ts";

import { NAME } from "../channel.ts";
function useApi() {
  const station = useStation();
  const call = useStationCall(station.address);
  return useMemo(() => stationApi(call), [call]);
}

/**
 * Every station's profiles on one page, from settings (./Settings.tsx), as the desktop's settings have them: each
 * station under its name, what can be added there (a profile, the machine's own logins) with it; one offline says so.
 */
export function ProfilesScreen() {
  const app = useApp();
  // From a station's page (?station=<id>): that station's only, back to it.
  const [params] = useSearchParams();
  const only = params.get("station");
  const listed = useStations(app.entry.id).value;
  const stations = only ? listed?.filter((s) => s.id === only) : listed;
  const one = only ? stations?.[0] : undefined;
  const online = stations?.filter((s) => s.online) ?? [];
  const add = () => online.length === 1
    ? app.push(app.at(`/s/${online[0]!.id}/profiles/new`))
    : app.sheet({ height: 0.5, content: () => <PickStation title="添加 Profile" stations={online} to={(s) => `/s/${s.id}/profiles/new`} /> });
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={one?.name ?? "设置"} onBack={app.pop} trailing={online.length > 0 ? <NavButton icon={Plus} iconSize={20} label="添加 Profile" onClick={add} /> : undefined} />
      <LargeTitle small={one ? `${one.name} 上的` : ""} big="Profile" />
      <p className={settingsCss.mPageNote}>agent 跑模型用的账号：一份订阅，或者一个模型服务的 key。每个 Profile 在它所在的 station 上运行。</p>
      {!stations ? <Loading text="正在读取 station…" /> : stations.map((s) => (
        <StationContext.Provider key={s.id} value={{ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${app.entry.id}/settings` }}>
          {!one && <SectionHeader title={s.online ? s.name : `${s.name} · 离线`} start={24} />}
          <ListCard>
            {!s.overview ? <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{s.online ? "正在读取…" : "station 离线，读不到它的 Profile"}</span></ListRow>
              : s.overview.profiles.length === 0 ? <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>这台机器还没有 Profile</span></ListRow>
              : s.overview.profiles.map((p) => <ProfileRow key={p.id} station={s} p={p} />)}
          </ListCard>
          {/* The machine's own logins not used yet, each offered as a profile. */}
          {s.online && s.overview && <MachineLoginOffers logins={s.overview.machineLogins} onSignIn={(kind) => app.push(app.at(`/s/${s.id}/profiles/new?kind=${kind}`))} />}
        </StationContext.Provider>
      ))}
      <div style={{ height: 30 }} />
    </div>
  );
}

/** Where something is added: one of the stations online, in a sheet. */
export function PickStation({ title, stations, to }: { title: string; stations: StationView[]; to: (s: StationView) => string }) {
  const app = useApp();
  return (
    <>
      <SheetGrab />
      <SheetHead title={title} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>加在哪台 station 上</p>
        {stations.map((s) => <PickRow key={s.id} label={s.name} onClick={() => { app.sheet(null); app.push(app.at(to(s))); }} />)}
      </div>
    </>
  );
}

/**
 * A profile in the list of profiles: whether it works (a dot before its name, its state in words, why when its provider
 * refuses it), what it is, how many of its models are enabled, and its allowance; its page picks them.
 */
export function ProfileRow({ station, p }: { station: StationView; p: Profile }) {
  const app = useApp();
  const trouble = quotaTrouble(p.quota);
  return (
    <ListRow onClick={() => app.push(app.at(`/s/${station.id}/settings/accounts/${encodeURIComponent(p.id)}`))}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}><Presence state={toneDot(p.checkTone)} /> {p.name}</span>
        <span className={listsCss.mRowNote}>{p.checkText} · {accessLabel(p)} · {p.modelsText}</span>
        {trouble && <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{trouble}</span>}
      </span>
      <QuotaRings quota={p.quota} />
      <ChevronRight size={14} className={partsCss.mSubtle} />
    </ListRow>
  );
}

/** A check's tone as a presence dot (./Connects.tsx): green up, red failing, the rest on its way or unknown. */
export function toneDot(tone: Tone | string): string {
  return tone === "green" ? "online" : tone === "red" ? "error" : tone === "neutral" ? "offline" : "busy";
}

/** Why an allowance could not be read (an account its provider refuses, a sign-in gone stale), when that is so. */
export function quotaTrouble(quota: Quota | null | undefined): string | null {
  return quota && (quota.state === "blocked" || quota.state === "unavailable") ? quota.detail ?? (quota.state === "blocked" ? "这个账号被服务商停用了。" : "查不到额度。") : null;
}

/** What a profile is, in a word: the machine's own login, or its kind of access. */
export function accessLabel(p: Profile): string {
  return p.machine ? "本机登录" : ACCESS[p.access.kind].label;
}

/** A profile of the station in context, by the page's :id. */
export function ProfileScreen() {
  const app = useApp();
  const station = useStation();
  const { id = "" } = useParams();
  const overview = useOverview(station.address);
  const p = overview.value?.profiles.find((x) => x.id === id);
  if (!p) return <div className={pagesCss.mScreen}><NavBar back={station.name || "Station"} onBack={app.pop} title="Profile" /><Loading text={overview.error?.message ?? (overview.value ? "没有这个 Profile。" : "正在读取…")} /></div>;
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
    <div className={pagesCss.mScreen}>
      <NavBar back={station.name || "Station"} onBack={app.pop} title={p.name} sub={<span className={barsCss.mNavbarNote}>{accessLabel(p)}</span>}
        trailing={<NavButton icon={More} label="更多" onClick={() => app.sheet({ height: 0.5, content: () => <ProfileMenu p={p} /> })} />} />
      <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
        <div className={`${listsCss.mCard} ${settingsCss.mProfileHead}`}>
          <ProviderMark runtime={p.runtime} kind={p.access.kind} size={26} />
          <span className={partsCss.mGrow}>
            <span className={`${historyCss.mPill} ${css.mCheckPill}`} data-tone={p.checkTone}>{p.checkText}</span>
            <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{p.check ? p.check.detail.replace(/^可用[，,]\s*/, "") : "还没检查过"}{p.check?.time?.checkedAt ? ` · ${p.check.time.checkedAt.ago}检查` : ""}</span>
          </span>
        </div>
        {p.access.kind === "subscription" && !p.machine && <SignIn p={p} needed={p.check?.state === "login" || signingIn} />}
        <Quota p={p} />
        <Models p={p} onSave={(models) => void save({ models }, "已保存")} />
        {/* A station older than the setting says nothing of it. */}
        {p.runtimes.includes("claude") && p.backgroundOnMessage !== undefined && (
          <>
            <SectionHeader title="运行" start={24} />
            <ListCard>
              <ListRow onClick={() => void save({ backgroundOnMessage: !p.backgroundOnMessage }, p.backgroundOnMessage ? "已关闭" : "已打开")}>
                <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                  <span className={listsCss.mRowTitle}>新消息到来时，把正在执行的命令转到后台</span>
                  <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{p.backgroundOnMessage ? "命令和 subagent 转到后台继续跑，agent 马上读到消息。" : "新消息要等正在执行的命令或 subagent 结束后才会读到。"}</span>
                </span>
                <span className={connectsCss.mSwitch} data-on={p.backgroundOnMessage || undefined} />
              </ListRow>
            </ListCard>
          </>
        )}
        <SectionHeader title="使用它的连接" start={24} />
        <ListCard>
          {users.length === 0 && <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>还没有连接使用这个 Profile。</span></ListRow>}
          {users.map((c) => (
            <ListRow key={c.id} onClick={() => app.push(`${stationBase(station.address)}/connects/${encodeURIComponent(c.id)}`)}>
              <SlackMark size={15} /><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{c.name}</span><span className={listsCss.mRowNote}>{c.modelName ?? (p.model ? p.names[p.model] ?? p.model : "默认模型")}</span>
            </ListRow>
          ))}
        </ListCard>
        {keyed && (
          <>
            <SectionHeader title="账号" start={24} />
            <ListCard>
              <ListRow onClick={() => ask(app, { title: p.access.kind === "opencode-go" ? "新的 OpenCode Go key" : "新的 API key", value: "", placeholder: "粘贴 key", action: "保存", secret: true,
                hint: "保存后会重新检查。", run: (key) => api.putProfile(p.id, { access: { kind: p.access.kind, key } }).then(() => app.toast("已保存，正在检查")) })}>
                <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{p.access.kind === "opencode-go" ? "OpenCode Go key" : "API key"}</span><span className={`${listsCss.mRowNote} ${css.mMono}`}>{p.access.key || "没有保存"}</span></span>
                <span className={partsCss.mLink}>更换</span>
              </ListRow>
            </ListCard>
          </>
        )}
        {p.access.kind === "env" && (
          <>
            <SectionHeader title="环境变量" start={24} />
            <ListCard>
              {p.env.map((e) => <ListRow key={e.key}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={`${listsCss.mRowTitle} ${css.mMono}`}>{e.key}</span><span className={`${listsCss.mRowNote} ${css.mMono}`}>{e.value}</span></span></ListRow>)}
              <ListRow onClick={() => app.sheet({ height: 0.8, draggable: true, content: () => <EnvSheet p={p} /> })}><span className={`${partsCss.mAccent} ${listsCss.mRowTitle}`}>编辑变量</span></ListRow>
            </ListCard>
          </>
        )}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

/** Renaming, checking, refreshing its allowance, deleting it (stopping one on the machine's login); not while a connect uses it. */
function ProfileMenu({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const failed = (e: Error) => app.toast(e.message);
  return (
    <>
      <SheetGrab />
      <SheetHead title={p.name} />
      <div className={sheetsCss.mSheetScroll}>
        {!p.machine && <PickRow label="改名" onClick={() => ask(app, { title: "Profile 的名字", value: p.name, placeholder: "名字", action: "保存", run: (name) => api.putProfile(p.id, { name }).then(() => app.toast("已改名")) })} />}
        <PickRow label="重新检查" onClick={() => { app.sheet(null); api.checkProfile(p.id).then(() => app.toast("已检查"), failed); }} />
        <PickRow label="刷新额度" onClick={() => { app.sheet(null); api.refreshQuota(p.id).then(() => app.toast("已刷新额度"), failed); }} />
        <PickRow label={`${p.machine ? "停用" : "删除 Profile"}${p.usedBy.length ? "（还有连接在用）" : ""}`} accent enabled={p.usedBy.length === 0} onClick={() => confirm(app, p.machine ? {
          title: `停用「${p.name}」？`, text: `${NAME} 不再用这台机器上的这份登录；机器上的登录不受影响，之后可以再用。`, action: "停用", danger: true,
          run: () => api.deleteProfile(p.id).then(() => { app.toast("已停用"); app.pop(); }),
        } : {
          title: `删除「${p.name}」？`, text: `只从 ${NAME} 的配置里移除；配置目录和里面的登录状态不会删除。`, action: "删除 Profile", danger: true,
          run: () => api.deleteProfile(p.id).then(() => { app.toast("已删除 Profile"); app.pop(); }),
        })} />
      </div>
    </>
  );
}

/** Its allowance, window by window: what is left and when it refills; why it cannot be read, when the provider says. */
function Quota({ p }: { p: Profile }) {
  const windows = p.quota?.state === "ok" ? p.quota.windows : [];
  const trouble = quotaTrouble(p.quota);
  if (trouble) {
    return (
      <>
        <SectionHeader title="额度" trailing={p.quota?.time?.checkedAt ? `${p.quota.time.checkedAt.ago}查询` : undefined} start={24} />
        <ListCard>
          <ListRow>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}><Presence state={p.quota?.state === "blocked" ? "error" : "offline"} /> {p.quota?.state === "blocked" ? "被停用" : "查不到额度"}</span>
              <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{trouble}</span>
            </span>
          </ListRow>
        </ListCard>
      </>
    );
  }
  if (!windows.length) return null;
  return (
    <>
      <SectionHeader title="额度" trailing={p.quota?.time?.checkedAt ? `${p.quota.time.checkedAt.ago}查询` : undefined} start={24} />
      <ListCard><div className={css.mQuotaDials}><QuotaBars quota={p.quota} /></div></ListCard>
    </>
  );
}

/** Which of its models may be used: one per line, a filter when there are many, and all / none of what is shown. */
function Models({ p, onSave }: { p: Profile; onSave: (models: string[]) => void }) {
  const [filter, setFilter] = useState("");
  const all = [...(p.available ?? [])].sort();
  const shown = all.filter((m) => [m, p.names[m] ?? m].some((s) => s.toLowerCase().includes(filter.trim().toLowerCase())));
  const save = (models: string[]) => onSave([...new Set(models)].sort());
  const suffix = filter.trim() ? "筛选结果" : "";
  return (
    <>
      <SectionHeader title={`模型 · 启用 ${p.models.length} / ${all.length}`} start={24} />
      <p className={css.mProfileNote}>{all.length === 0 ? "检查过 Profile 后，这里会列出它能用的模型，勾选后才能使用。" : "只有勾选的模型能在新对话和连接里选。"}</p>
      {all.length > 0 && (
        <div className={settingsCss.mProfileTools}>
          {all.length > 10 ? <span className={partsCss.mGrow}><Field value={filter} onChange={setFilter} placeholder="筛选模型" /></span> : <span className={partsCss.mGrow} />}
          <button type="button" className={partsCss.mLink} onClick={() => save([...p.models, ...shown])}>全选{suffix}</button>
          <button type="button" className={partsCss.mLink} onClick={() => save(p.models.filter((m) => !shown.includes(m)))}>全不选{suffix}</button>
        </div>
      )}
      {/* By series, newest first (the core's). */}
      {p.series.map((s) => {
        const list = s.models.filter((m) => shown.includes(m));
        if (list.length === 0) return null;
        return (
          <div key={s.name}>
            <div className={listsCss.mGroupLabel} style={{ paddingLeft: 24, paddingRight: 24 }}>{s.name}</div>
            {list.map((m) => {
              const on = p.models.includes(m);
              return (
                <button key={m} type="button" className={settingsCss.mModelRow} onClick={() => save(on ? p.models.filter((x) => x !== m) : [...p.models, m])}>
                  <span className={settingsCss.mCheck} data-on={on || undefined}>{on && <Check size={14} />}</span>
                  <span className={partsCss.mGrow}>{p.names[m] ?? m}</span>
                </button>
              );
            })}
          </div>
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
      <div className={`${listsCss.mCard} ${settingsCss.mFormGroup}`}>
        {active ? (
          <>
            <LoginSteps job={job} provider={provider} send={(code) => api.loginCode(p.id, code)} />
            <Button label="取消登录" primary={false} onClick={() => void api.cancelLogin(p.id)} />
          </>
        ) : (
          <>
            <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{job?.state === "failed" ? `上次登录没成功：${job.error}` : job?.state === "done" ? "已登录。换账号的话重新登录一次。" : `登录在运行 ${NAME} 的机器上完成，你只需要在浏览器里授权。`}</p>
            <Button label={job?.state === "done" || !needed ? "重新登录" : "登录"} primary={needed} busy={busy}
              onClick={() => { setBusy(true); api.startLogin(p.id).catch((e: Error) => app.toast(e.message)).finally(() => setBusy(false)); }} />
            <details className={css.mDetails}><summary>也可以在那台机器上手动登录</summary><CommandBox text={p.loginCommand} /></details>
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
  if (!job || job.state === "starting") return <p className={`${partsCss.mMuted} ${chatCss.mWaiting}`}><Spinner size={13} />正在生成 {provider} 的登录链接…</p>;
  if (job.state === "verifying") return <p className={`${partsCss.mMuted} ${chatCss.mWaiting}`}><Spinner size={13} />正在完成登录…</p>;
  if (job.state === "done") return <p className={`${partsCss.mMuted} ${chatCss.mWaiting}`}><Spinner size={13} />已登录，正在添加…</p>;
  if (job.state === "needs_approval" && job.url && job.userCode) {
    return (
      <>
        <span className={css.mDeviceCode}>{job.userCode}</span>
        <Button label={copied ? "已复制，重新打开登录页" : "复制代码并打开登录页"} primary
          onClick={() => { void navigator.clipboard.writeText(job.userCode!).then(() => setCopied(true), () => {}).finally(() => window.open(job.url!, "_blank", "noopener")); }} />
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>在打开的 OpenAI 页面用要给 {NAME} 使用的 ChatGPT 账号登录，粘贴代码。完成后这里会自动继续。如果页面说设备码登录没开启，先在 ChatGPT 的安全设置里打开它。</p>
      </>
    );
  }
  if (job.state === "needs_code" && job.url) {
    return (
      <>
        <p className={partsCss.mSmall}>1. <a href={job.url} target="_blank" rel="noopener">打开授权页面</a>，用要给 {NAME} 使用的 Claude 账号登录并同意。</p>
        <p className={partsCss.mSmall}>2. 同意后页面上会显示一段授权码，复制过来：</p>
        <input className={listsCss.mField} data-mono autoComplete="off" spellCheck={false} value={code} placeholder="粘贴授权码" onChange={(e) => setCode(e.target.value)} />
        {error && <p className={partsCss.mError}>{error}</p>}
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
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>运行时启动时带上这些变量，用来接到你的模型服务。值里的 {"{route}"} 会换成会话的路由 ID。</p>
        {rows.map((r) => (
          <div key={r.row} className={css.mEnvRow}>
            <input className={listsCss.mField} data-mono spellCheck={false} value={r.key} placeholder="NAME" onChange={(e) => update(r.row, { key: e.target.value })} />
            <input className={listsCss.mField} data-mono spellCheck={false} autoComplete="off" type={r.masked !== null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(r.key) ? "password" : "text"}
              value={r.value} placeholder={r.masked !== null ? `已保存 ${r.masked}，留空不变` : "值"} onChange={(e) => update(r.row, { value: e.target.value })} />
            <button type="button" className={partsCss.mLink} onClick={() => setRows(rows.filter((x) => x.row !== r.row))}>删除</button>
          </div>
        ))}
        <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => setRows([...rows, { row: next.current++, key: "", value: "", masked: null, original: null }])}>＋ 添加变量</button>
        <div className={sheetsCss.mFormActions}>
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
  // `?kind=`: the kind chosen as it opens (a machine login kept in the keychain, signed in again for ember).
  const [params] = useSearchParams();
  const [choice, setChoice] = useState<Choice>(() => { const k = params.get("kind"); return k && k in CHOICES ? k as Choice : "claude-sub"; });
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
    <div className={pagesCss.mScreen}>
      <NavBar back="取消" onBack={leave} title="添加 Profile" sub={<span className={barsCss.mNavbarNote}>{station.name}</span>} />
      <div className={`${pagesCss.mScroll} ${partsCss.mPadX18} ${settingsCss.mSteps}`}>
        {login ? (
          pending?.error || job?.state === "failed" || job?.state === "cancelled" ? (
            <>
              <p className={partsCss.mError}>{pending?.error ?? job?.error ?? "登录没有完成。"}</p>
              <Button label="重新开始" primary={false} onClick={() => { void api.dropLogin(login).catch(() => {}); setLogin(null); }} />
            </>
          ) : <LoginSteps job={job} provider={provider} send={(code) => api.newLoginCode(login, code)} />
        ) : (
          <>
            {overview && (
              <MachineLoginOffers inForm logins={overview.machineLogins}
                onSignIn={(c) => { setChoice(c); setBusy(true); setError(null); api.newLogin(CHOICES[c].runtime!).then(({ id }) => setLogin(id), (e: Error) => setError(e.message)).finally(() => setBusy(false)); }} />
            )}
            {overview && machineOffers(overview.machineLogins).length > 0 && <b className={sheetsCss.mFormLabel}>或者添加一个新的</b>}
            <ListCard>
              {(Object.keys(CHOICES) as Choice[]).map((c) => (
                <PickRow key={c} label={CHOICES[c].title} sub={CHOICES[c].description} checked={choice === c} onClick={() => setChoice(c)}
                  leading={<ProviderMark runtime={CHOICES[c].runtime ?? "claude"} kind={CHOICES[c].kind} size={18} />} />
              ))}
            </ListCard>
            {KEYED.has(kind) && (
              <>
                <b className={sheetsCss.mFormLabel}>{kind === "opencode-go" ? "OpenCode Go key" : "API key"}</b>
                <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} value={key} placeholder="先验证能用，再添加" onChange={(e) => setKey(e.target.value.trim())} />
              </>
            )}
            {kind === "subscription" && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>登录在运行 {NAME} 的机器上完成，你只需要在浏览器里授权；登录成功后才会添加这个 Profile。</p>}
            {error && <p className={partsCss.mError}>{error}</p>}
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

/** The machine's logins no profile is on yet. */
/** The machine's own logins a profile could use now (the core's `offered`). */
function machineOffers(logins: MachineLogin[] | undefined): MachineLogin[] {
  return (logins ?? []).filter((l) => l.offered);
}

const MACHINE_RUNTIME: Record<MachineLogin["runtime"], string> = { claude: "Claude Code", codex: "Codex" };

/**
 * The accounts the station machine's own Claude Code and Codex are signed in with, not used by a profile yet (as the
 * desktop's MachineLoginOffers, ../pages/Accounts.tsx): one kept in a file is used as it is (a profile on the machine's
 * login, which follows it); one kept only in the keychain is offered as a sign-in with the same account (`onSignIn`); a
 * refused account is said so, with its reason, and nothing to do with it. The station in context.
 */
export function MachineLoginOffers({ logins, onSignIn, inForm = false }: { logins: MachineLogin[] | undefined; onSignIn: (choice: Choice) => void; inForm?: boolean }) {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const [busy, setBusy] = useState(false);
  const offers = machineOffers(logins);
  if (!offers.length) return null;
  const use = (l: MachineLogin) => {
    setBusy(true);
    api.useMachineLogin(l.runtime).then(({ id }) => {
      app.toast("已添加 Profile，用的是这台机器的登录");
      app.replace(`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(id)}`);
    }, (e: Error) => app.toast(e.message)).finally(() => setBusy(false));
  };
  return (
    <>
      {inForm ? <b className={sheetsCss.mFormLabel}>这台机器上已经登录了</b> : <SectionHeader title="这台机器上已经登录了" start={24} />}
      <ListCard>
        {offers.map((l) => {
          const blocked = l.quota?.state === "blocked";
          const trouble = quotaTrouble(l.quota);
          const plan = l.plan ? `${l.plan[0]!.toUpperCase()}${l.plan.slice(1)}` : null;
          return (
            <ListRow key={l.runtime}>
              <ProviderMark runtime={l.runtime} kind="subscription" size={18} />
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}><Presence state={blocked ? "error" : "online"} /> {MACHINE_RUNTIME[l.runtime]}{plan && <span className={settingsCss.mRowAside}> · {plan}</span>}</span>
                <span className={listsCss.mRowNote}>{blocked ? "被停用" : "本机已登录"}{l.email ? ` · ${l.email}` : ""}</span>
                {trouble && <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{trouble}</span>}
              </span>
              <QuotaRings quota={l.quota} />
              {blocked ? null : l.usable
                ? <button type="button" className={partsCss.mLink} disabled={busy} onClick={() => use(l)}>用这个账号</button>
                : <button type="button" className={partsCss.mLink} onClick={() => onSignIn(l.runtime === "claude" ? "claude-sub" : "chatgpt-sub")}>登录</button>}
            </ListRow>
          );
        })}
      </ListCard>
      <p className={inForm ? `${partsCss.mSmall} ${partsCss.mMuted}` : settingsCss.mPageNote}>「用这个账号」直接用这台机器的登录，在这台机器上换号或登出，它也跟着变；station 读不到的登录（Codex 存在钥匙串里的，或者钥匙串没解锁）不能直接用，要为 {NAME} 单独登录一次，原来的登录不受影响。</p>
    </>
  );
}
