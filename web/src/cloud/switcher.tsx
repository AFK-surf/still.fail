// Where a station opened from ember cloud sits, and the sidebar header that shows it.
import { ArrowLeft, Check, ChevronsUpDown } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { createContext, useContext, type ReactNode } from "react";
import { ICON, StatusDot } from "../ui.tsx";
import type { WorkspaceView } from "./api.ts";
import { online } from "./gate.tsx";

export interface Frame { workspace: WorkspaceView; station: string }
export const FrameContext = createContext<Frame | null>(null);

export function useFrame(): Frame | null {
  return useContext(FrameContext);
}

/** The sidebar header inside a station: which station of which workspace, and a way out. */
export function FrameSwitcher(): ReactNode {
  const frame = useFrame();
  if (!frame) return null;
  const current = frame.workspace.stations.find((s) => s.id === frame.station);
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger asChild>
        <button type="button" className="account-trigger frame-trigger">
          <span className="ws-mark" aria-hidden="true">{([...frame.workspace.name][0] ?? "?").toUpperCase()}</span>
          <span className="account-text">
            <span className="account-name">{current?.name ?? "station"}</span>
            <span className="account-email">{frame.workspace.name}</span>
          </span>
          <ChevronsUpDown {...ICON} size={14} />
        </button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="popover menu-list account-menu" align="start" sideOffset={4}>
          <DropdownMenu.Label className="menu-label">{frame.workspace.name} 的 station</DropdownMenu.Label>
          {frame.workspace.stations.map((s) => (
            <DropdownMenu.Item key={s.id} className="menu-item" onSelect={() => location.assign(`/w/${frame.workspace.id}/s/${s.id}/sessions`)}>
              <StatusDot state={online(s) ? "online" : "offline"} />
              <span className="nav-text">{s.name}</span>
              {s.id === frame.station && <Check {...ICON} size={14} />}
            </DropdownMenu.Item>
          ))}
          <DropdownMenu.Separator className="menu-sep" />
          <DropdownMenu.Item className="menu-item" onSelect={() => location.assign(`/w/${frame.workspace.id}`)}><ArrowLeft {...ICON} />回到 workspace</DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
