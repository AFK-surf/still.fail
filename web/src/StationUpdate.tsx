import { Popover } from "radix-ui";
import type { StationUpdateNotice } from "./core/shapes.ts";
import { core } from "./core/react.ts";
import { stationApi, useStationCall } from "./api.ts";
import { useAct } from "./toast.tsx";
import { useDoing } from "./doing.ts";
import { DoingMark } from "./DoingMark.tsx";
import { Close } from "./icons.tsx";
import { t } from "./i18n.ts";
import * as css from "./StationUpdate.css.ts";

export function StationUpdate({ station, notice }: { station: string; notice?: StationUpdateNotice | null | undefined }) {
  const api = stationApi(useStationCall(station));
  const act = useAct();
  const busy = useDoing("software.update", { station, id: "station" });
  const control = (action: string) => act(core().call("station.updateNotice", { station, action, version: notice?.version }), t("web-main.stationUpdate.noticeAction"));
  if (!notice) return null;
  return <Popover.Root open={notice.open ?? false} onOpenChange={(open) => control(open ? "open" : "close")}>
    <Popover.Trigger className={css.trigger} data-tone={notice.tone} aria-label={notice.text}>
      <Popover.Anchor asChild><span className={css.dot} /></Popover.Anchor>{notice.label ?? notice.text}
    </Popover.Trigger>
    <Popover.Portal>
      <Popover.Content className={css.popover} data-tone={notice.tone} side="bottom" align="center" sideOffset={6} collisionPadding={12} onOpenAutoFocus={(e) => e.preventDefault()}>
        <div className={css.head}>
          <div className={css.words}>
            {notice.station
              ? <span className={css.title}><span className={css.name}>{notice.station}</span>{notice.label && <span className={css.state}>{notice.label}</span>}</span>
              : <span className={css.name}>{notice.text}</span>}
            {notice.detail && <span className={css.detail}>{notice.detail}</span>}
          </div>
          <button className={css.dismiss} aria-label={notice.dismissible ? t("web-main.stationUpdate.dismiss") : t("web-main.stationUpdate.collapse")} title={notice.dismissible ? t("web-main.stationUpdate.dismiss") : t("web-main.stationUpdate.collapse")} onClick={() => control(notice.dismissible ? "dismiss" : "close")}><Close size={14} /></button>
        </div>
        {notice.tone === "busy" && notice.station && <div className={css.bar}>
          {notice.percent != null ? <span className={css.fill} style={{ width: `${notice.percent}%` }} /> : <span className={`${css.fill} ${css.sweeping}`} />}
        </div>}
        {(notice.from || notice.to || notice.canUpdate) && <div className={css.foot}>
          {(notice.from || notice.to) && <span className={css.versions}>{[notice.from, notice.to].filter(Boolean).join(" → ")}</span>}
          {notice.canUpdate && <button className={css.update} disabled={busy} onClick={() => act(api.updateSoftware("station"), t("web-main.stationUpdate.updateAction"))}>
            <DoingMark calls="software.update" on={{ station, id: "station" }} size={12} />{busy ? t("web-main.stationUpdate.updating") : notice.tone === "trouble" ? t("common.retry") : t("web-main.stationUpdate.updateNow")}
          </button>}
        </div>}
      </Popover.Content>
    </Popover.Portal>
  </Popover.Root>;
}
