// What the badge counts (the Dock's, the core's `workspaceMarks` `badge`), in the sidebar's foot: how many chats want
// the viewer, every workspace's, and pressed, which ones: the cards waiting for them (奏) and the chats of theirs that
// went wrong, each leading to its chat; a card can be let go from here (`decision.dismiss`). What it does not count
// (the unread, chats waiting for someone else) is said under the list, so the number adds up.
import { useState } from "react";
import { Popover } from "radix-ui";
import { NavLink, useNavigate } from "react-router";
import type { MarkItem, WorkspaceMarksView } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { stationBase } from "./station.tsx";
import { useAct } from "./toast.tsx";
import { useWorkspaceMarks } from "./lastChat.ts";
import { Bell } from "./icons.tsx";
import * as nav from "./Sidebar.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as css from "./Attention.css.ts";
import { t } from "./i18n.ts";

const keyOf = (i: MarkItem) => `${i.station}/${i.session ?? i.thread}`;

/** Every workspace's counted chats, the failed first (as each workspace's are). */
function counted(marks: WorkspaceMarksView | undefined): MarkItem[] {
  const all = Object.values(marks?.workspaces ?? {}).flatMap((m) => m.items ?? []);
  return [...all.filter((i) => i.kind === "alert"), ...all.filter((i) => i.kind !== "alert")];
}

export function AttentionEntry({ scope }: { scope: string }) {
  const marks = useWorkspaceMarks(scope);
  const [open, setOpen] = useState(false);
  const [gone, setGone] = useState<Set<string>>(new Set());
  const navigate = useNavigate();
  const call = useCall();
  const act = useAct();
  const items = counted(marks).filter((i) => !gone.has(keyOf(i)));
  const counts = marks?.badgeCounts ?? "attention";
  const shown = counts === "decisions" ? items.filter((i) => i.kind === "wait") : items;
  const unread = Object.values(marks?.workspaces ?? {}).reduce((n, m) => n + m.unread, 0);
  const elsewhere = Object.values(marks?.workspaces ?? {}).reduce((n, m) => n + (m.elsewhere ?? 0), 0);
  const n = Math.max(0, (marks?.badge ?? 0) - gone.size);
  if (!marks || (n <= 0 && !open)) return null;
  const several = Object.keys(marks.workspaces).length > 1;
  const go = (i: MarkItem) => {
    setOpen(false);
    navigate(`${stationBase(i.station)}/chats/${encodeURIComponent(i.session ?? `thread:${i.thread}`)}`);
  };
  const dismiss = (i: MarkItem) => {
    if (i.thread == null || i.seq == null) return;
    const key = keyOf(i);
    setGone((was) => new Set(was).add(key));
    act(call("decision.dismiss", { station: i.station, thread: i.thread, seq: i.seq }).catch((e: unknown) => {
      setGone((was) => { const now = new Set(was); now.delete(key); return now; });
      throw e;
    }), t("web-main.decisions.dismissWhat"));
  };
  const left = [
    counts !== "all" && unread > 0 ? t("web-main.attention.unread", { n: unread }) : null,
    elsewhere > 0 ? t("web-main.attention.elsewhere", { n: elsewhere }) : null,
  ].filter(Boolean).join(" · ");
  const group = (kind: "alert" | "wait") => {
    const of = shown.filter((i) => i.kind === kind);
    if (!of.length) return null;
    return (
      <>
        <div className={css.group}><span className={css.dot} style={{ background: kind === "alert" ? "var(--red)" : "var(--amber)" }} />{t(`web-main.attention.${kind}`, { n: of.length })}</div>
        {of.map((i) => (
          <div key={keyOf(i)} role="button" tabIndex={0} className={css.item} onClick={() => go(i)} onKeyDown={(e) => { if (e.key === "Enter") go(i); }}>
            <span className={css.itemText}>
              <span className={css.itemTitle}>{i.title || t("web-main.attention.untitled")}</span>
              <span className={css.itemLine}>{several ? `${i.workspaceName} · ` : ""}{i.text || i.stationName}</span>
            </span>
            {i.kind === "wait" && i.seq != null && (
              <button type="button" className={css.dismiss} title={t("web-main.attention.dismissNote")}
                onClick={(e) => { e.stopPropagation(); dismiss(i); }}>{t("web-main.attention.dismiss")}</button>
            )}
          </div>
        ))}
      </>
    );
  };
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <button type="button" className={`${nav.navRow} ${css.entry}`} aria-label={t("web-main.attention.label", { n })}>
          <span className={css.lead}><Bell size={14} /></span>
          <span className={css.count}>{t("web-main.attention.entry")}</span>
          <span className={css.pill}>{n}</span>
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.panel}`} side="top" align="start" sideOffset={6} collisionPadding={8}>
          {shown.length === 0 && <div className={css.empty}>{t("web-main.attention.empty")}</div>}
          {group("alert")}
          {group("wait")}
          <div className={controlsCss.menuSep} />
          <div className={css.foot}>
            {left && <span>{t("web-main.attention.left", { what: left })}</span>}
            <span className={css.footLinks}>
              <NavLink className={css.link} to={`/w/${scope}/decisions`} onClick={() => setOpen(false)}>{t("web-main.attention.desk")}</NavLink>
              <NavLink className={css.link} to={`/w/${scope}/settings/notifications`} onClick={() => setOpen(false)}>{t("web-main.attention.settings")}</NavLink>
            </span>
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
