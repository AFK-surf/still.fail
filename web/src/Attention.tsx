// What wants the viewer (the core's `workspaceMarks`), in the sidebar's foot: 待处理, with how many came since they
// last looked (the badge, the Dock's number), and pressed, which chats: the cards and needs waiting for them (奏) and
// the chats of theirs that went wrong, every workspace's, each leading to its chat. One looked at stays listed, quiet,
// until it is answered or let go here (忽略, `decision.dismiss`). A station's trouble is the same: looked at, it no
// longer lights the bell; let go, it is no longer listed, both until the trouble changes (kept on this device).
import { useEffect, useState } from "react";
import { Popover } from "radix-ui";
import { NavLink, useNavigate } from "react-router";
import type { MarkItem, WorkspaceMarksView } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { stationBase } from "./station.tsx";
import { useAct } from "@stillfail/ui/toast.tsx";
import { useWorkspaceMarks } from "./lastChat.ts";
import { useStationTrouble } from "./Sidebar.tsx";
import { OpenJobs, useLongJobs } from "./OpenJobs.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { Bell } from "@stillfail/ui/icons.tsx";
import { ICON } from "./ui.tsx";
import * as nav from "./Sidebar.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./Attention.css.ts";
import { t } from "./i18n.ts";

/** Its state line without its lead (要你帮忙：, 出问题：, 奏 · ): the dot before it says that. */
const line = (i: MarkItem) => i.text.replace(/^(?:要你帮忙|需要你处理|出问题|出错|Needs you|Went wrong|Failed)[：:]\s*|^(?:奏|Decision) · /, "") || i.stationName;

const keyOf = (i: MarkItem) => `${i.station}/${i.session ?? i.thread}`;

/** Each workspace's listed chats (the one in view first), as the badge counts them: the cards alone with `decisions`. */
function groups(marks: WorkspaceMarksView | undefined, scope: string): { workspace: string; name: string; items: MarkItem[] }[] {
  const only = marks?.badgeCounts === "decisions";
  return Object.entries(marks?.workspaces ?? {})
    .sort(([a], [b]) => (a === scope ? -1 : b === scope ? 1 : 0))
    .map(([workspace, m]) => {
      const items = (m.items ?? []).filter((i) => !only || i.kind === "wait");
      return { workspace, name: items[0]?.workspaceName ?? workspace, items };
    })
    .filter((g) => g.items.length > 0);
}

/** What this device last did with a scope's station trouble, by its words: `seen` looked at, `gone` let go. */
const troubleKey = (scope: string, what: "seen" | "gone") => `stillfail.trouble.${what}.${scope}`;
const troubleRead = (scope: string, what: "seen" | "gone") => {
  try { return localStorage.getItem(troubleKey(scope, what)); } catch { return null; }
};
const troubleKeep = (scope: string, what: "seen" | "gone", text: string) => {
  try { localStorage.setItem(troubleKey(scope, what), text); } catch { /* private mode: for this page only */ }
};

/**
 * `rail`: drawn in the rail (Rail.tsx) as its bell, there even with none, a dot on it while some came since they last
 * looked (how many in its label) or a station is in trouble or services were left up long, which it lists too.
 */
export function AttentionEntry({ scope, rail }: { scope: string; rail?: { item: string; count: string; label: string } }) {
  const marks = useWorkspaceMarks(scope);
  const [open, setOpen] = useState(false);
  const [gone, setGone] = useState<Set<string>>(new Set());
  const navigate = useNavigate();
  const call = useCall();
  const act = useAct();
  const listed = groups(marks, scope).map((g) => ({ ...g, items: g.items.filter((i) => !gone.has(keyOf(i))) })).filter((g) => g.items.length > 0);
  const all = listed.flatMap((g) => g.items);
  const goneFresh = groups(marks, scope).flatMap((g) => g.items).filter((i) => gone.has(keyOf(i)) && !i.seen).length;
  const n = Math.max(0, (marks?.badge ?? 0) - goneFresh);
  // In the rail's bell, besides: the stations' trouble and the services left up long (the sidebar's foot had them).
  const stationTrouble = useStationTrouble(scope);
  const [troubleSeen, setTroubleSeen] = useState(() => troubleRead(scope, "seen"));
  const [troubleGone, setTroubleGone] = useState(() => troubleRead(scope, "gone"));
  const trouble = stationTrouble && stationTrouble.text !== troubleGone ? stationTrouble : undefined;
  const troubleNew = !!trouble && trouble.text !== troubleSeen;
  const jobs = useLongJobs(scope, useToast()).groups.reduce((sum, g) => sum + g.jobs.length, 0);
  const more = !!rail && (!!trouble || jobs > 0);
  const lit = !!rail && (troubleNew || jobs > 0);
  const opened = (on: boolean) => {
    setOpen(on);
    if (on && rail && trouble) {
      troubleKeep(scope, "seen", trouble.text);
      setTroubleSeen(trouble.text);
    }
  };
  // Its stations all reached again: a trouble later in the same words is new.
  useEffect(() => {
    if (stationTrouble !== null || (troubleSeen === null && troubleGone === null)) return;
    for (const what of ["seen", "gone"] as const) try { localStorage.removeItem(troubleKey(scope, what)); } catch { /* not kept */ }
    setTroubleSeen(null);
    setTroubleGone(null);
  }, [scope, stationTrouble, troubleSeen, troubleGone]);
  const letTroubleGo = (text: string) => {
    troubleKeep(scope, "gone", text);
    setTroubleGone(text);
  };
  if (!rail && (!marks || (all.length === 0 && !open))) return null;
  const several = listed.length > 1 || listed.some((g) => g.workspace !== scope);
  const go = (i: MarkItem) => {
    setOpen(false);
    navigate(`${stationBase(i.station)}/chats/${encodeURIComponent(i.session ?? `thread:${i.thread}`)}`);
  };
  const goStations = () => {
    setOpen(false);
    navigate(`/w/${scope}/settings/stations`);
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
  return (
    <Popover.Root open={open} onOpenChange={opened}>
      <Popover.Trigger asChild>
        {rail ? (
          <button type="button" className={rail.item} data-on={open || undefined} title={rail.label} aria-label={n > 0 ? t("web-main.attention.label", { n }) : rail.label}>
            <Bell size={20} />
            {(n > 0 || lit) && <span className={rail.count} />}
          </button>
        ) : (
        <button type="button" className={`${nav.navRow} ${css.entry}`} aria-label={n > 0 ? t("web-main.attention.label", { n }) : t("web-main.attention.entry")}>
          <Bell {...ICON} />
          <span className={css.name}>{t("web-main.attention.entry")}</span>
          <span className={css.slot}>{n > 0 ? <span className={css.count}>{n}</span> : <span className={css.quiet}>{all.length}</span>}</span>
        </button>
        )}
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.panel}`} side={rail ? "right" : "bottom"} align="start" sideOffset={rail ? 10 : 6} collisionPadding={8}
          onOpenAutoFocus={(e) => e.preventDefault()}>
          {all.length === 0 && !more && <div className={css.empty}>{t("web-main.attention.empty")}</div>}
          {rail && trouble && (
            <div className={css.group}>
              <div className={css.groupName}>Station</div>
              <div role="button" tabIndex={0} className={css.item} data-seen={!troubleNew || undefined}
                onClick={() => goStations()} onKeyDown={(e) => { if (e.key === "Enter") goStations(); }}>
                <span className={css.dot} data-kind="alert" role="img" aria-hidden="true" />
                <span className={css.itemText}><span className={css.itemTitle}>{trouble.text}</span></span>
                <button type="button" className={css.dismiss} title={t("web-main.attention.dismissTrouble")}
                  onClick={(e) => { e.stopPropagation(); letTroubleGo(trouble.text); }}>{t("web-main.attention.dismiss")}</button>
              </div>
            </div>
          )}
          {rail && jobs > 0 && <div className={css.group}><OpenJobs scope={scope} /></div>}
          {listed.map((g) => (
            <div key={g.workspace} className={css.group}>
              {several && <div className={css.groupName}>{g.name}</div>}
              {g.items.map((i) => (
                <div key={keyOf(i)} role="button" tabIndex={0} className={css.item} data-seen={i.seen || undefined} onClick={() => go(i)} onKeyDown={(e) => { if (e.key === "Enter") go(i); }}>
                  <span className={css.dot} data-kind={i.kind} aria-label={t(i.kind === "alert" ? "web-main.attention.alertOne" : "web-main.attention.waitOne")} role="img" />
                  <span className={css.itemText}>
                    <span className={css.itemTitle}>{i.title || t("web-main.attention.untitled")}</span>
                    <span className={css.itemLine}>{line(i)}</span>
                  </span>
                  {i.kind === "wait" && i.seq != null && (
                    <button type="button" className={css.dismiss} title={t("web-main.attention.dismissNote")}
                      onClick={(e) => { e.stopPropagation(); dismiss(i); }}>{t("web-main.attention.dismiss")}</button>
                  )}
                </div>
              ))}
            </div>
          ))}
          <div className={css.foot}>
            <NavLink className={css.link} to={`/w/${scope}/decisions`} onClick={() => setOpen(false)}>{t("web-main.attention.desk")}</NavLink>
            <NavLink className={css.link} to={`/w/${scope}/settings/notifications`} onClick={() => setOpen(false)}>{t("web-main.attention.settings")}</NavLink>
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
