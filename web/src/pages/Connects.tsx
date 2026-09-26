// Connects, as a settings page: on a station's own page its connects; in
// ember cloud every station's connects in the workspace. Each shows who added
// it, and the list can be narrowed to the viewer's own.
import { Plus } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useState } from "react";
import { Link } from "react-router";
import { useConnects, useStations } from "../api.ts";
import { MineFilter, OwnerLabel } from "../components.tsx";
import { StationContext, stationBase, useOnlyMine, type Station } from "../station.tsx";
import { Button, ConnectKindIcon, MobileBack, SlackLogo, StatusDot } from "../ui.tsx";
import { NewConnectDialog } from "./Connect.tsx";

/** The connects of a scope (a workspace, or "local"), from the core's `connects` view; `settings` is where the scope's settings live. */
export function ConnectList({ scope, settings }: { scope: string; settings: string }) {
  const [onlyMine] = useOnlyMine();
  const connects = useConnects(scope, onlyMine);
  const stations = useStations(scope);
  const [adding, setAdding] = useState<Station | null>(null);
  const shown = connects.value?.items ?? [];
  const loading = !connects.value || connects.value.loading;
  const showStation = scope !== "local";
  const targets: Station[] = (stations.value ?? []).filter((s) => s.online).map((s) => ({
    id: s.id, name: s.name, base: stationBase(s.station), address: s.station, online: true, settings,
  }));

  return (
    <div className="page page-narrow">
      <MobileBack to={settings} label="设置" />
      <header className="page-head">
        <div>
          <h1>连接</h1>
          <p className="page-sub">连接是人找到 ember 的地方，比如一个 Slack app。每个连接在一台 station 上，绑定一个模型。</p>
        </div>
        {targets.length === 1 ? <Button icon={Plus} onClick={() => setAdding(targets[0]!)}>添加连接</Button> : targets.length > 1 && (
          <DropdownMenu.Root modal={false}>
            <DropdownMenu.Trigger asChild><Button icon={Plus}>添加连接</Button></DropdownMenu.Trigger>
            <DropdownMenu.Portal>
              <DropdownMenu.Content className="popover menu-list" align="end" sideOffset={4}>
                <DropdownMenu.Label className="menu-label">加在哪台 station 上</DropdownMenu.Label>
                {targets.map((s) => <DropdownMenu.Item key={s.id} className="menu-item" onSelect={() => setAdding(s)}>{s.name}</DropdownMenu.Item>)}
              </DropdownMenu.Content>
            </DropdownMenu.Portal>
          </DropdownMenu.Root>
        )}
      </header>
      <div>
      <MineFilter label="连接" />
      {shown.length === 0 ? (
        <p className={connects.error ? "field-error" : "muted"}>{connects.error?.message ?? (loading ? "正在读取…" : onlyMine ? "没有你添加的连接。" : "还没有连接。")}</p>
      ) : (
        <ul className="list">
          {shown.map(({ connect: c, station, stationName }) => (
            <li key={`${station}/${c.id}`}>
              <Link className="list-row" to={`${stationBase(station)}/connects/${c.id}`}>
                <ConnectKindIcon kind={c.kind} />
                <span className="list-row-text">
                  <span className="list-row-title">{c.name}{c.team && <span className="connect-team"><SlackLogo size={11} />{c.team}</span>}</span>
                  <span className="muted">{c.modeText} · {c.runtimeText}{c.bind.model ? ` · ${c.bind.model}` : ""}</span>
                </span>
                <span className="connect-facts">
                  {showStation && <span className="station-tag">{stationName}</span>}
                  <OwnerLabel owner={c.createdBy} />
                </span>
                <span className="nav-note">{c.statusText}</span>
                <StatusDot state={c.presence} label={c.statusText} />
              </Link>
            </li>
          ))}
        </ul>
      )}
      </div>
      {adding && (
        <StationContext.Provider value={adding}>
          <NewConnectDialog open onClose={() => setAdding(null)} />
        </StationContext.Provider>
      )}
    </div>
  );
}

/** A station's own page: its connects. */
export function ConnectsPage() {
  return <ConnectList scope="local" settings="/settings" />;
}

