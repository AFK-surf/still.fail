// The workspace's stations on a narrow screen, as the Android app has them (apps/android/…/screens/Stations.kt): each
// with the buddy's face for its state and its load as rings; one station's profiles (which models may be used) and
// connections.
import { useMemo, useState } from "react";
import { useParams } from "react-router";
import { stationApi, useStationCall, useStations, type Profile, type StationView } from "../api.ts";
import { Check, ChevronRight } from "../icons.tsx";
import { useDark } from "../theme.ts";
import { useApp } from "./app.tsx";
import { Card, Field, Illustration, LargeTitle, ListCard, ListRow, Loading, Mark, NavBar, QuotaRings, Ring, SectionHeader, SlackMark, TopBack } from "./parts.tsx";

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
      <div style={{ height: 30 }} />
    </div>
  );
}

export function StationScreen() {
  const app = useApp();
  const { station: id = "" } = useParams();
  const stations = useStations(app.entry.id);
  const s = stations.value?.find((x) => x.id === id);
  return (
    <div className="m-screen">
      <NavBar back="Station" onBack={app.pop} title={s?.name ?? id} sub={s ? <span className="m-navbar-note">{s.host?.cpuModel || (s.online ? "在线" : "离线")}</span> : undefined} />
      {!s ? <Loading text={stations.error?.message ?? "正在读取…"} /> : (
        <div className="m-scroll m-station-page">
          {s.online && s.host ? (
            <Card>
              <span className="m-station-rings m-rings-18">{s.host.meters.map((m) => <Ring key={m.label} percent={m.percent} label={m.short} level={m.level} />)}</span>
              <span className="m-station-line">{s.host.line}</span>
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
