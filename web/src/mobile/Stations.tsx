// The workspace's stations on a narrow screen, as the Android app has them (apps/android/…/screens/Stations.kt): each
// with the buddy's face for its state and its load as rings; one station's profiles (which models may be used) and
// connections.
import { useMemo, useState } from "react";
import { useParams } from "react-router";
import { stationApi, useStationCall, useStations, type Profile, type StationView } from "../api.ts";
import { Check, ChevronRight, More } from "../icons.tsx";
import { cloud, useWorkspace } from "../cloud/api.ts";
import { useDark } from "../theme.ts";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { ask, CommandBox, confirm } from "./sheets.tsx";
import { Button, Card, Field, Illustration, LargeTitle, ListCard, ListRow, Loading, Mark, NavBar, NavButton, PickRow, QuotaRings, Ring, SectionHeader, SlackMark, Spinner, TopBack } from "./parts.tsx";

const BASE = import.meta.env.BASE_URL;

/** The buddy's face for a station: at work, idle, or asleep. */
function Buddy({ s, size = 40 }: { s: StationView; size?: number }) {
  const dark = useDark();
  const face = !s.online ? "offline" : (s.overview?.counts.running ?? 0) > 0 ? "working" : "idle";
  return <img className="m-buddy" src={`${BASE}${face}${dark ? "-dark" : ""}.svg`} alt="" width={size} height={size} />;
}

export function StationsScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id);
  const list = stations.value;
  const manager = useManager();
  return (
    <div className="m-screen m-scroll">
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small={list ? `${app.entry.name} · ${list.filter((s) => s.online).length}/${list.length} 在线` : app.entry.name} big="Station" />
      {!list ? <p className="m-muted m-pad-20">{stations.error?.message ?? "正在读取 station…"}</p> : list.map((s) => (
        <Card key={s.station} onClick={() => app.push(app.at(`/s/${s.id}/overview`))}>
          <span className="m-station-head">
            <Buddy s={s} />
            <span className="m-grow"><b className="m-station-name">{s.name}</b><span className="m-station-summary">{s.summary}</span></span>
            <ChevronRight size={14} className="m-subtle" />
          </span>
          {s.online && s.host ? (
            <span className="m-station-rings">{s.host.meters.map((m) => <Ring key={m.label} percent={m.percent} label={m.short} level={m.level} size={40} />)}</span>
          ) : !s.online ? (
            <span className="m-station-offline"><Illustration name="station-offline" width={220} /><span>这台机器很久没联系 ember 了</span></span>
          ) : null}
        </Card>
      ))}
      {manager && list && (
        <ListCard>
          <ListRow onClick={() => app.sheet({ height: 0.72, draggable: true, content: () => <AddStationSheet known={list.map((s) => s.id)} /> })}>
            <span className="m-accent m-row-title">＋ 添加 station</span>
          </ListRow>
        </ListCard>
      )}
      <div style={{ height: 30 }} />
    </div>
  );
}

/**
 * Adding a station: a name, then the command to run on that machine (which installs ember and joins it); the sheet
 * waits for it to join.
 */
function AddStationSheet({ known }: { known: string[] }) {
  const app = useApp();
  const me = app.entry.account;
  const stations = useStations(app.entry.id).value ?? [];
  const [name, setName] = useState("");
  const [made, setMade] = useState<{ install: string; command: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const joined = made && stations.find((s) => !known.includes(s.id));
  return (
    <>
      <SheetGrab />
      <SheetHead title="添加 station" />
      <div className="m-sheet-scroll m-form">
        {!made ? (
          <>
            <p className="m-muted">station 是一台运行 ember 的机器。给它起个名字，然后在那台机器的终端里执行生成的一行命令，它会装好 ember 并加入。</p>
            <b className="m-form-label">名字</b>
            <Field value={name} onChange={setName} placeholder="比如机器名：studio、mac-mini" />
            {error && <p className="m-error">{error}</p>}
            <div className="m-form-actions">
              <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
              <Button label="生成命令" primary busy={busy} enabled={!!name.trim()} onClick={() => {
                setBusy(true); setError(null);
                cloud.enroll(me.sub, app.entry.id, name.trim()).then(setMade, (e: Error) => setError(e.message)).finally(() => setBusy(false));
              }} />
            </div>
          </>
        ) : joined ? (
          <>
            <p>「{joined.name}」已加入，现在可以打开它了。</p>
            <div className="m-form-actions"><Button label="完成" primary onClick={() => app.sheet(null)} /></div>
          </>
        ) : (
          <>
            <p>在要当 station 的机器（macOS，Apple 芯片）上打开「终端」，执行：</p>
            <CommandBox text={made.install} />
            <p className="m-muted m-small">它会装好 ember、加入这个 workspace，并在后台一直运行（开机自动启动）。之后在电脑上的「设置 → Profile」里登录 Claude Code 或 Codex 的账号。</p>
            <b className="m-form-label">这台机器上已经有 ember 了</b>
            <p className="m-muted m-small">在 ember 的目录里执行下面这行，然后重启 ember：</p>
            <CommandBox text={`bin/${made.command}`} />
            <p className="m-muted m-small m-waiting"><Spinner size={10} />等待 station 加入… 命令 1 小时内有效，只能用一次。</p>
          </>
        )}
      </div>
    </>
  );
}

export function StationScreen() {
  const app = useApp();
  const { station: id = "" } = useParams();
  const stations = useStations(app.entry.id);
  const s = stations.value?.find((x) => x.id === id);
  const manager = useManager();
  return (
    <div className="m-screen">
      <NavBar back="Station" onBack={app.pop} title={s?.name ?? id} sub={s ? <span className="m-navbar-note">{s.host?.cpuModel || (s.online ? "在线" : "离线")}</span> : undefined}
        trailing={s && manager ? <NavButton icon={More} label="更多" onClick={() => app.sheet({ height: 0.34, content: () => <StationMenu s={s} /> })} /> : undefined} />
      {!s ? <Loading text={stations.error?.message ?? "正在读取…"} /> : (
        <div className="m-scroll m-station-page">
          {s.online && s.host ? (
            <Card>
              <span className="m-station-rings m-rings-18">{s.host.meters.map((m) => <Ring key={m.label} percent={m.percent} label={m.short} level={m.level} />)}</span>
              <span className="m-station-line">{s.host.line}</span>
              {s.overview?.processesText && <span className="m-station-line">{s.overview.processesText}</span>}
            </Card>
          ) : !s.online ? (
            <Card><span className="m-station-offline"><Illustration name="station-offline" width={220} /><span>离线：在这台机器上打开 ember 就会重新连上</span></span></Card>
          ) : null}
          {s.overview && (
            <>
              <SectionHeader title="Profile" start={24} />
              {s.overview.profiles.length === 0
                ? <Card><span className="m-muted">这台机器还没有 Profile。</span></Card>
                : <ListCard>{s.overview.profiles.map((p) => <ProfileRow key={p.id} station={s} p={p} />)}</ListCard>}
              <SectionHeader title="连接" start={24} />
              <ListCard>
                {s.overview.connects.map((c) => (
                  <ListRow key={c.id}>
                    {c.kind === "slack" ? <SlackMark size={14} /> : <Mark size={14} />}
                    <span className="m-grow m-row-title">{c.name}</span>
                    <span className="m-row-note">{connectionText(c.connection.state)}</span>
                  </ListRow>
                ))}
                <ListRow><Mark size={14} /><span className="m-grow m-row-title">ember 对话</span><span className="m-row-note">内置</span></ListRow>
              </ListCard>
            </>
          )}
          <div style={{ height: 30 }} />
        </div>
      )}
    </div>
  );
}

/** Whether the viewer may add, rename and remove stations: the workspace's owner and admins. */
function useManager(): boolean {
  const app = useApp();
  const role = useWorkspace(app.entry.id).value?.role;
  return role === "owner" || role === "admin";
}

function StationMenu({ s }: { s: StationView }) {
  const app = useApp();
  const me = app.entry.account;
  return (
    <>
      <SheetGrab />
      <SheetHead title={s.name} />
      <div className="m-sheet-scroll">
        <PickRow label="改名" onClick={() => ask(app, { title: "station 的名字", value: s.name, placeholder: "比如机器名：studio", action: "保存",
          run: (name) => cloud.renameStation(me.sub, app.entry.id, s.id, name).then(() => app.toast("已改名")) })} />
        <PickRow label="从 workspace 移除" accent onClick={() => confirm(app, {
          title: `移除「${s.name}」？`, action: "移除 station", danger: true,
          text: "它会断开与 ember cloud 的连接，成员不能再从这里访问它。那台机器上的 ember 和数据不受影响，之后可以重新添加。",
          run: () => cloud.removeStation(me.sub, app.entry.id, s.id).then(() => { app.toast("已移除 station"); app.pop(); }),
        })} />
      </div>
    </>
  );
}

function connectionText(state: string): string {
  return ({ connected: "在线", reconnecting: "重连中", starting: "连接中", error: "连接失败", no_tokens: "未连接 Slack" } as Record<string, string>)[state] ?? "已停用";
}

/** A profile on its station's page: its allowance and how many of its models are enabled; its page picks them. */
function ProfileRow({ station, p }: { station: StationView; p: Profile }) {
  const app = useApp();
  return (
    <ListRow onClick={() => app.push(app.at(`/s/${station.id}/settings/accounts/${encodeURIComponent(p.id)}`))}>
      <span className="m-grow m-row-text"><span className="m-row-title">{p.name}</span><span className="m-row-note">{p.modelsText}</span></span>
      <QuotaRings quota={p.quota} />
      <ChevronRight size={14} className="m-subtle" />
    </ListRow>
  );
}

/** Which of a profile's models may be used: one per line, a filter when there are many, and all / none of what is shown. */
export function ProfileScreen() {
  const app = useApp();
  const { station: sid = "", id = "" } = useParams();
  const stations = useStations(app.entry.id);
  const s = stations.value?.find((x) => x.id === sid);
  const p = s?.overview?.profiles.find((x) => x.id === id);
  const call = useStationCall(s?.station ?? `${app.entry.id}/${sid}`);
  const api = useMemo(() => stationApi(call), [call]);
  const [filter, setFilter] = useState("");
  if (!s || !p) return <div className="m-screen"><NavBar back={s?.name ?? "Station"} onBack={app.pop} title={p?.name ?? "Profile"} /><Loading text={stations.error?.message ?? "正在读取…"} /></div>;
  const available = [...new Set([...(p.check?.models ?? []), ...p.models])];
  const all = [...new Set([...available, ...p.models])].sort();
  const shown = all.filter((m) => m.toLowerCase().includes(filter.trim().toLowerCase()));
  const save = (models: string[]) => { api.putProfile(p.id, { models: [...new Set(models)].sort() } as Parameters<typeof api.putProfile>[1]).catch((e: unknown) => app.toast(`没改成：${e instanceof Error ? e.message : String(e)}`)); };
  const suffix = filter.trim() ? "筛选结果" : "";
  return (
    <div className="m-screen">
      <NavBar back={s.name} onBack={app.pop} title={p.name} />
      <div className="m-scroll">
        <p className="m-profile-note">{all.length === 0 ? "检查过 Profile 后，这里会列出它能用的模型，勾选后才能使用。" : `只有勾选的模型能在新对话和连接里选。${p.modelsText}。`}</p>
        {all.length > 0 && (
          <div className="m-profile-tools">
            {all.length > 10 ? <span className="m-grow"><Field value={filter} onChange={setFilter} placeholder="筛选模型" /></span> : <span className="m-grow" />}
            <button type="button" className="m-link" onClick={() => save([...p.models, ...shown])}>全选{suffix}</button>
            <button type="button" className="m-link" onClick={() => save(p.models.filter((m) => !shown.includes(m)))}>全不选{suffix}</button>
          </div>
        )}
        {/* Plain rows on the page, no card behind them. */}
        {shown.map((m) => {
          const on = p.models.includes(m);
          return (
            <button key={m} type="button" className="m-model-row" onClick={() => save(on ? p.models.filter((x) => x !== m) : [...p.models, m])}>
              <span className="m-check" data-on={on || undefined}>{on && <Check size={13} />}</span>
              <span className="m-grow m-mono">{m}</span>
              {!available.includes(m) && available.length > 0 && <span className="m-row-note">检查里没有了</span>}
            </button>
          );
        })}
      </div>
    </div>
  );
}
