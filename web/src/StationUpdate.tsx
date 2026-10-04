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
      <Popover.Anchor asChild><span className={css.dot} /></Popover.Anchor>{notice.label ?? notice.text}
    </Popover.Trigger>
    <Popover.Portal>
      <Popover.Content className={css.popover} data-tone={notice.tone} side="bottom" align="end" alignOffset={-30} sideOffset={10} collisionPadding={12} arrowPadding={22} onOpenAutoFocus={(e) => e.preventDefault()}>
        <div className={css.head}>
          <div className={css.words}>
            {notice.station
              ? <span className={css.title}><span className={css.name}>{notice.station}</span>{notice.label && <span className={css.state}>{notice.label}</span>}</span>
              : <span className={css.name}>{notice.text}</span>}
            {notice.detail && <span className={css.detail}>{notice.detail}</span>}
          </div>
          <button className={css.dismiss} aria-label={notice.dismissible ? "不再提醒此版本" : "收起更新详情"} title={notice.dismissible ? "不再提醒此版本" : "收起更新详情"} onClick={() => control(notice.dismissible ? "dismiss" : "close")}><Close size={14} /></button>
        </div>
        {notice.tone === "busy" && notice.station && <div className={css.bar}>
          {notice.percent != null ? <span className={css.fill} style={{ width: `${notice.percent}%` }} /> : <span className={`${css.fill} ${css.sweeping}`} />}
        </div>}
        {(notice.from || notice.to || notice.canUpdate) && <div className={css.foot}>
          {(notice.from || notice.to) && <span className={css.versions}>{[notice.from, notice.to].filter(Boolean).join(" → ")}</span>}
          {notice.canUpdate && <button className={css.update} disabled={busy} onClick={() => act(api.updateSoftware("station"), "更新 station")}>
            <DoingMark calls="software.update" on={{ station, id: "station" }} size={12} />{busy ? "更新中" : notice.tone === "trouble" ? "重试" : "现在更新"}
          </button>}
        </div>}
        <Popover.Arrow className={css.arrow} width={12} height={6} />
      </Popover.Content>
    </Popover.Portal>
  </Popover.Root>;
}
