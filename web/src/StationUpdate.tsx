import { Popover } from "radix-ui";
import type { StationUpdateNotice } from "./core/shapes.ts";
import { core } from "./core/react.ts";
import { stationApi, useStationCall } from "./api.ts";
import { useAct } from "./toast.tsx";
import { useDoing } from "./doing.ts";
import { DoingMark } from "./DoingMark.tsx";
import { Close } from "./icons.tsx";
import * as css from "./StationUpdate.css.ts";

export function StationUpdate({ station, notice }: { station: string; notice?: StationUpdateNotice | null | undefined }) {
  const api = stationApi(useStationCall(station));
  const act = useAct();
  const busy = useDoing("software.update", { station, id: "station" });
  const control = (action: string) => act(core().call("station.updateNotice", { station, action, version: notice?.version }), "设置更新提醒");
  if (!notice) return null;
  return <Popover.Root open={notice.open ?? false} onOpenChange={(open) => control(open ? "open" : "close")}>
    <Popover.Trigger className={css.trigger} data-tone={notice.tone} aria-label={notice.text}>
      <span className={css.dot} />{notice.label ?? notice.text}
    </Popover.Trigger>
    <Popover.Portal>
      <Popover.Content className={css.popover} side="bottom" align="end" sideOffset={10} collisionPadding={12} onOpenAutoFocus={(e) => e.preventDefault()}>
        <div className={css.words}><span className={css.title}>{notice.text}</span>{notice.detail && <span className={css.detail}>{notice.detail}</span>}</div>
        {notice.canUpdate && <button className={css.update} disabled={busy} onClick={() => act(api.updateSoftware("station"), "更新 station")}>
          <DoingMark calls="software.update" on={{ station, id: "station" }} size={12} />{busy ? "更新中" : "现在更新"}
        </button>}
        <button className={css.dismiss} aria-label={notice.dismissible ? "不再提醒此版本" : "收起更新详情"} title={notice.dismissible ? "不再提醒此版本" : "收起更新详情"} onClick={() => control(notice.dismissible ? "dismiss" : "close")}><Close size={18} /></button>
        <Popover.Arrow className={css.arrow} width={12} height={6} />
      </Popover.Content>
    </Popover.Portal>
  </Popover.Root>;
}
