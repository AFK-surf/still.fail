// Connects, as a settings page: on a station's own page its connects; in
// ember cloud every station's connects in the workspace. Each shows who added
// it, and the list can be narrowed to the viewer's own.
import { Plus } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useState } from "react";
import { Link } from "react-router";
import { useOverview, type ConnectView } from "../api.ts";
import { MineFilter, OwnerLabel, useOnlyMine } from "../components.tsx";
import { connectionText, modeText, presence, RUNTIME_LABEL } from "../format.ts";
import { StationContext, useIsMine, useStation, type Station } from "../station.tsx";
import { Button, ConnectKindIcon, MobileBack, StatusDot } from "../ui.tsx";
import { NewConnectDialog } from "./Connect.tsx";

export interface ConnectItem { connect: ConnectView; station: Station }

export function ConnectList({ items, stations, showStation, loading, back }: { items: ConnectItem[]; stations: Station[]; showStation: boolean; loading?: boolean; back: string }) {
  const [onlyMine] = useOnlyMine();
  const isMine = useIsMine();
  const [adding, setAdding] = useState<Station | null>(null);
  const shown = items.filter((i) => !onlyMine || isMine(i.connect.createdBy ? { ...i.connect.createdBy, email: i.connect.createdBy.id } : null));
  const targets = stations.filter((s) => s.online);

  return (
    <div className="page page-narrow">
      <MobileBack to={back} label="设置" />
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
        <p className="muted">{loading ? "正在读取…" : onlyMine ? "没有你添加的连接。" : "还没有连接。"}</p>
      ) : (
        <ul className="list">
          {shown.map(({ connect: c, station }) => (
            <li key={`${station.id}/${c.id}`}>
              <Link className="list-row" to={`${station.base}/connects/${c.id}`}>
                <ConnectKindIcon kind={c.kind} />
                <span className="list-row-text">
                  <span className="list-row-title">{c.name}</span>
                  <span className="muted">{modeText(c.mode, c.requireMention)} · {RUNTIME_LABEL[c.bind.runtime]}{c.bind.model ? ` · ${c.bind.model}` : ""}</span>
                </span>
                <span className="connect-facts">
                  {showStation && <span className="station-tag">{station.name}</span>}
                  <OwnerLabel owner={c.createdBy} />
                </span>
                <span className="nav-note">{connectionText(c.connection)}</span>
                <StatusDot state={presence(c.connection)} label={connectionText(c.connection)} />
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
  const station = useStation();
  const overview = useOverview();
  return <ConnectList items={(overview.data?.connects ?? []).map((connect) => ({ connect, station }))} stations={[station]} showStation={false} loading={overview.isPending} back="/settings" />;
}

