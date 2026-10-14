// 侧边条 in 外观: which of the workspace's places the rail shows (Rail.tsx) and in what order, kept on this device (prefs
// `rail`). Each place a row in one card: dragged by its handle to where it goes, switched on or off (对话 always on).
import { useState, type DragEvent } from "react";
import { setPrefs, usePrefs } from "./prefs.ts";
import { RAIL_ICONS, RAIL_ITEMS, railItems, railLabel, type RailItem } from "./Rail.tsx";
import { Move, Server } from "./icons.tsx";
import { Button, Switch } from "./ui.tsx";
import * as css from "./Rail.css.ts";
import { t } from "./i18n.ts";

export function RailSetting() {
  const kept = usePrefs((p) => p.rail);
  const shown = railItems(kept);
  // The ones shown in their order, then the others in theirs.
  const order = [...shown, ...RAIL_ITEMS.filter((i) => !shown.includes(i))];
  // While a row is dragged: the order as it would be dropped now.
  const [dragging, setDragging] = useState<{ item: RailItem; order: RailItem[] } | null>(null);
  const rows = dragging?.order ?? order;
  const save = (next: RailItem[], on: ReadonlySet<RailItem>) => setPrefs({ rail: next.filter((i) => on.has(i)) });
  const over = (e: DragEvent, item: RailItem) => {
    if (!dragging) return;
    e.preventDefault();
    if (item === dragging.item) return;
    const to = dragging.order.indexOf(item);
    const next = dragging.order.filter((i) => i !== dragging.item);
    next.splice(to, 0, dragging.item);
    setDragging({ ...dragging, order: next });
  };
  return (
    <div className={css.setting}>
      {rows.map((item) => {
        const Icon = RAIL_ICONS[item];
        const on = shown.includes(item);
        return (
          <div key={item} className={css.settingRow} data-dragging={dragging?.item === item || undefined}
            onDragOver={(e) => over(e, item)} onDrop={(e) => { e.preventDefault(); if (dragging) save(dragging.order, new Set(shown)); setDragging(null); }}>
            <span className={css.handle} draggable aria-label={t("web-main.rail.drag")} title={t("web-main.rail.drag")}
              onDragStart={(e) => { e.dataTransfer.effectAllowed = "move"; e.dataTransfer.setData("text/plain", item); setDragging({ item, order }); }}
              onDragEnd={() => setDragging(null)}>
              <Move size={16} />
            </span>
            <span className={css.settingIcon}>{Icon ? <Icon size={18} /> : item === "decisions" ? <span className={css.zouSmall}>奏</span> : <Server size={18} />}</span>
            <span className={css.settingLabel}>{railLabel(item)}</span>
            <Switch label={`${t("web-main.rail.show")} ${railLabel(item)}`} checked={on} disabled={item === "chats"}
              onChange={(v) => { const next = new Set(shown); if (v) next.add(item); else next.delete(item); save(order, next); }} />
          </div>
        );
      })}
      {kept && <div className={css.settingFoot}><Button variant="ghost" onClick={() => setPrefs({ rail: null })}>{t("web-main.rail.reset")}</Button></div>}
    </div>
  );
}
