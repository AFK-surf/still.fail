// Connects, as a settings page: on a station's own page its connects; in
// ember cloud every station's connects in the workspace. Each shows who added
// it, and the list can be narrowed to the viewer's own.
import { Illustration } from "../brand.tsx";
import { Key, Plug, Plus } from "../icons.tsx";
import { DropdownMenu } from "radix-ui";
import { useState } from "react";
import { Link } from "react-router";
import { useAction, useApi, useConnects, useStations, type MadeSlackApp } from "../api.ts";
import { MineFilter, OwnerLabel } from "../components.tsx";
import { profilesPage, StationContext, stationBase, useOnlyMine, type Station } from "../station.tsx";
import { About, Button, Confirm, ConnectAvatar, FirstOne, Menu, MobileBack, SlackLogo, StatusDot } from "../ui.tsx";
import { NewConnectDialog } from "./Connect.tsx";
import * as controlsCss from "../styles/controls.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Connects.css.ts";
import * as cloudCss from "../styles/cloud.css.ts";

/** The connects of a scope (a workspace, or "local"), from the core's `connects` view; `settings` is where the scope's settings live. */
export function ConnectList({ scope, settings }: { scope: string; settings: string }) {
  const [onlyMine] = useOnlyMine();
  const connects = useConnects(scope, onlyMine);
  const stations = useStations(scope);
  // A connect being added on a station: from the start, or (`resume`) from a Slack app made before.
  const [adding, setAdding] = useState<{ station: Station; resume?: string } | null>(null);
  const shown = connects.value?.items ?? [];
  const loading = !connects.value || connects.value.loading;
  const showStation = scope !== "local";
  const targets: Station[] = (stations.value ?? []).filter((s) => s.online).map((s) => ({
    id: s.id, name: s.name, base: stationBase(s.station), address: s.station, online: true, settings,
  }));
  // The Slack apps the viewer made that no connect has taken yet, each on its station: to be finished any time.
  const waiting = (stations.value ?? []).flatMap((s) => (s.overview?.slackApps ?? []).map((app) => ({ app, station: targets.find((t) => t.address === s.station) ?? null, stationName: s.name })));
  // None at all yet (not only none of the viewer's): the page is about adding the first.
  const first = !loading && !connects.error && shown.length === 0 && !onlyMine && waiting.length === 0;
  // A connect runs a profile's model: with none on any station (each read), the first step is a profile.
  const listed = stations.value ?? [];
  const noProfile = listed.length > 0 && listed.every((s) => s.overview && s.overview.profiles.length === 0);
  const profiles = profilesPage({ id: "", name: "", base: "", address: scope === "local" ? "local" : "", online: true, settings });
  // Adding one: on the one station there is, or on one picked.
  const add = (label: string, primary = false) => targets.length === 1 ? <Button variant={primary ? "primary" : "secondary"} icon={Plus} onClick={() => setAdding({ station: targets[0]! })}>{label}</Button> : targets.length > 1 && (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger asChild><Button variant={primary ? "primary" : "secondary"} icon={Plus}>{label}</Button></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} align={primary ? "center" : "end"} sideOffset={4}>
          <DropdownMenu.Label className={controlsCss.menuLabel}>加在哪台 station 上</DropdownMenu.Label>
          {targets.map((s) => <DropdownMenu.Item key={s.id} className={controlsCss.menuItem} onSelect={() => setAdding({ station: s })}>{s.name}</DropdownMenu.Item>)}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );

  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={settings} label="设置" />
      <header className={pagesCss.pageHead}>
        <div>
          <h1>连接<About>连接是人找到 still.fail 的地方，比如一个 Slack app。每个连接在一台 station 上，绑定一个模型。</About></h1>
        </div>
        {!first && add("添加连接")}
      </header>
      <div>
      {first && noProfile ? (
        <FirstOne art={<Illustration name="no-profile" />} title="先添加一个 Profile" lead="连接要用 Profile 来跑模型。先添加一个，再来加连接。">
          <Link className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} to={profiles}>去添加 Profile</Link>
        </FirstOne>
      ) : first ? (
        <FirstOne art={<Illustration name="no-connect" />} title="添加第一个连接" lead="连接让大家在 Slack 里 @ 到 agent：一个 Slack app，接到一台 station 上。">
          {add("添加连接", true) || <p className={shellCss.muted}>{stations.value?.length ? "没有在线的 station，等它上线再加。" : "先添加一台 station。"}</p>}
        </FirstOne>
      ) : <MineFilter label="连接" />}
      {waiting.length > 0 && (
        <section className={pagesCss.section} aria-label="还没连上的 Slack app">
          <h2 className={css.sectionTitleQuiet}>还没连上的 Slack app</h2>
          <ul className={pagesCss.list}>
            {waiting.map(({ app, station, stationName }) => (
              <li key={`${stationName}/${app.appId}`}>
                {station ? (
                  <StationContext.Provider value={station}>
                    <WaitingApp app={app} stationName={showStation ? stationName : null} onGo={() => setAdding({ station, resume: app.appId })} />
                  </StationContext.Provider>
                ) : <WaitingApp app={app} stationName={showStation ? stationName : null} onGo={null} />}
              </li>
            ))}
          </ul>
        </section>
      )}
      {first ? null : shown.length === 0 ? (
        <p className={connects.error ? controlsCss.fieldError : shellCss.muted}>{connects.error?.message ?? (loading ? "正在读取…" : onlyMine ? "没有你添加的连接。" : "还没有连接。")}</p>
      ) : (
        <ul className={pagesCss.list}>
          {shown.map(({ connect: c, station, stationName }) => (
            <li key={`${station}/${c.id}`}>
              <Link className={pagesCss.listRow} to={`${stationBase(station)}/connects/${c.id}`}>
                <ConnectAvatar connect={c} />
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{c.name}{c.team && <span className={css.connectTeam}><SlackLogo size={11} />{c.team}</span>}</span>
                  <span className={shellCss.muted}>{c.modeText} · {c.runtimeText}{c.bind.model ? ` · ${c.modelName ?? c.bind.model}` : ""}</span>
                </span>
                <span className={css.connectFacts}>
                  {showStation && <span className={cloudCss.stationTag}>{stationName}</span>}
                  <OwnerLabel owner={c.createdBy} />
                </span>
                <span className={css.navNote}>{c.statusText}</span>
                <StatusDot state={c.presence} label={c.statusText} />
              </Link>
            </li>
          ))}
        </ul>
      )}
      </div>
      {adding && (
        <StationContext.Provider value={adding.station}>
          <NewConnectDialog open onClose={() => setAdding(null)} resume={adding.resume} />
        </StationContext.Provider>
      )}
    </div>
  );
}

/**
 * A Slack app made and not connected yet: where it stands (to install, or only its app-level token left), going on from
 * there (`onGo`, when its station is online), or dropping it (it stays in Slack).
 */
function WaitingApp({ app, stationName, onGo }: { app: MadeSlackApp; stationName: string | null; onGo: (() => void) | null }) {
  const api = useApi();
  const [dropping, setDropping] = useState(false);
  const drop = useAction(() => api.dropSlackApp(app.appId), () => setDropping(false));
  const where = app.installed ? `已装进「${app.installedTeam ?? app.team ?? "工作区"}」，还差 App-Level Token` : app.install ? "还没安装到工作区" : "还差 token";
  return (
    <div className={pagesCss.listRow}>
      <SlackLogo size={18} />
      <span className={pagesCss.listRowText}>
        <span className={pagesCss.listRowTitle}>{app.name}{app.team && <span className={css.connectTeam}><SlackLogo size={11} />{app.team}</span>}</span>
        <span className={shellCss.muted}>{where}</span>
      </span>
      {stationName && <span className={css.connectFacts}><span className={cloudCss.stationTag}>{stationName}</span></span>}
      {onGo ? <Button onClick={onGo}>继续</Button> : <span className={css.navNote}>station 离线</span>}
      {onGo && <Menu items={[{ label: "从这里移除", danger: true, onSelect: () => setDropping(true) }]} />}
      <Confirm open={dropping} onClose={() => setDropping(false)} busy={drop.busy} onConfirm={() => void drop.run()} error={drop.error?.message}
        title={`移除「${app.name}」？`} action="移除" description="只从 still.fail 里移除；这个 app 还在 Slack 里，不用了可以去 Slack 的 app 设置页删除。" />
    </div>
  );
}

/** A station's own page: its connects. */
export function ConnectsPage() {
  return <ConnectList scope="local" settings="/settings" />;
}

