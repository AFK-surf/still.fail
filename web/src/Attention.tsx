// What wants the viewer (the core's `workspaceMarks` items), in the sidebar's foot: 待处理, with how many, and pressed,
// which chats: the cards and needs waiting for them not read since they came, and the chats of theirs that went
// wrong until they run again, every workspace's, each leading to its chat. A card read is no longer here (its row
// still says it); one let go here neither (忽略: a card's `decision.dismiss`, a failure's `prefs.failsGone` until it
// fails again). A station's trouble is the same:
// listed until the bell has shown it, then the stations' marks say it, until the trouble changes (kept on this device).
import { useEffect, useState } from "react";
import { Popover } from "radix-ui";
import { NavLink, useNavigate } from "react-router";
import type { MarkItem, WorkspaceMarksView } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { stationBase } from "./station.tsx";
import { useAct } from "@stillfail/ui/toast.tsx";
import { useWorkspaceMarks } from "./lastChat.ts";
import { useStationTrouble } from "./Sidebar.tsx";
import { StationInWords } from "./StationNamed.tsx";
import { OpenJobs, useLongJobs } from "./OpenJobs.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { Bell } from "@stillfail/ui/icons.tsx";
import { ICON } from "./ui.tsx";
import * as nav from "./Sidebar.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./Attention.css.ts";
import { t } from "./i18n.ts";
import { WorkspaceNamed } from "./WorkspaceMark.tsx";

/** Its state line without its lead (the core's `what`): the dot before it says that. */
const line = (i: MarkItem) => i.what || i.stationName;

/** A chat in 待处理 by its station and chat (a failure by itself: the same chat failing again is listed anew). */
const keyOf = (i: MarkItem) => i.failure ?? `${i.station}/${i.session ?? i.thread}`;

/** Each workspace's chats in 待处理 (the one in view first). */
function groups(marks: WorkspaceMarksView | undefined, scope: string): { workspace: string; name: string; emoji?: string | undefined; icon?: string | undefined; items: MarkItem[] }[] {
  return Object.entries(marks?.workspaces ?? {})
    .sort(([a], [b]) => (a === scope ? -1 : b === scope ? 1 : 0))
    .map(([workspace, m]) => {
      const items = m.items ?? [];
      return { workspace, name: items[0]?.workspaceName ?? workspace, emoji: items[0]?.workspaceEmoji, icon: items[0]?.workspaceIcon, items };
    })
    .filter((g) => g.items.length > 0);
}

/** What this device last did with a scope's station trouble, by its words: `seen` looked at (`gone`: let go, from before
 * one looked at was no longer listed). */
const troubleKey = (scope: string, what: "seen" | "gone") => `stillfail.trouble.${what}.${scope}`;
const troubleRead = (scope: string) => {
  try { return localStorage.getItem(troubleKey(scope, "seen")); } catch { return null; }
};
const troubleKeep = (scope: string, text: string) => {
  try { localStorage.setItem(troubleKey(scope, "seen"), text); } catch { /* private mode: for this page only */ }
};

/**
 * `rail`: drawn in the rail (Rail.tsx) as its bell, there even with none, a dot on it while it lists any (how many
 * chats in its label): besides the chats, a station's trouble not looked at yet and the services left up long it has not
 * shown yet.
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
  const n = all.length;
  // In the rail's bell, besides: the stations' trouble and the services left up long (the sidebar's foot had them).
  const stationTrouble = useStationTrouble(scope);
  const [troubleSeen, setTroubleSeen] = useState(() => troubleRead(scope));
  // (as it was before the bell opened while it is open: listed while it is first read)
  const trouble = stationTrouble && stationTrouble.text !== troubleSeen ? stationTrouble : undefined;
  const long = useLongJobs(scope, useToast());
  const jobs = long.groups.reduce((sum, g) => sum + g.jobs.length, 0);
  // (the services left up long light it only until it has shown them; listed while there)
  const more = !!rail && (!!trouble || long.lit);
  // Looked at as the bell opens (kept at once), no longer listed once it closes.
  const opened = (on: boolean) => {
    setOpen(on);
    if (on && rail && trouble) troubleKeep(scope, trouble.text);
    if (on && rail && long.lit) long.seen();
    if (!on) setTroubleSeen(troubleRead(scope));
  };
  // Its stations all reached again: a trouble later in the same words is new.
  useEffect(() => {
    if (stationTrouble !== null || troubleSeen === null) return;
    for (const what of ["seen", "gone"] as const) try { localStorage.removeItem(troubleKey(scope, what)); } catch { /* not kept */ }
    setTroubleSeen(null);
  }, [scope, stationTrouble, troubleSeen]);
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
    const said = i.kind === "alert" && i.failure != null
      ? call("prefs.set", { failsGone: { [i.workspace]: [i.failure] } })
      : i.thread != null && i.seq != null ? call("decision.dismiss", { station: i.station, thread: i.thread, seq: i.seq }) : null;
    if (said === null) return;
    const key = keyOf(i);
    setGone((was) => new Set(was).add(key));
    act(said.catch((e: unknown) => {
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
            {(n > 0 || more) && <span className={rail.count} />}
          </button>
        ) : (
        <button type="button" className={`${nav.navRow} ${css.entry}`} aria-label={n > 0 ? t("web-main.attention.label", { n }) : t("web-main.attention.entry")}>
          <Bell {...ICON} />
          <span className={css.name}>{t("web-main.attention.entry")}</span>
          <span className={css.slot}>{n > 0 && <span className={css.count}>{n}</span>}</span>
        </button>
        )}
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.panel}`} side={rail ? "right" : "bottom"} align="start" sideOffset={rail ? 10 : 6} collisionPadding={8}
          onOpenAutoFocus={(e) => e.preventDefault()}>
          {all.length === 0 && !more && !(rail && jobs > 0) && <div className={css.empty}>{t("web-main.attention.empty")}</div>}
          {rail && trouble && (
            <div className={css.group}>
              <div className={css.groupName}>Station</div>
              <div role="button" tabIndex={0} className={css.item}
                onClick={() => goStations()} onKeyDown={(e) => { if (e.key === "Enter") goStations(); }}>
                <span className={css.dot} data-kind="alert" role="img" aria-hidden="true" />
                <span className={css.itemText}><span className={css.itemTitle}><StationInWords station={trouble.station} text={trouble.text} /></span></span>
              </div>
            </div>
          )}
          {rail && jobs > 0 && <div className={css.group}><OpenJobs scope={scope} /></div>}
          {listed.map((g) => (
            <div key={g.workspace} className={css.group}>
              {several && <div className={css.groupName}><WorkspaceNamed w={g} size={14} /></div>}
              {g.items.map((i) => (
                <div key={keyOf(i)} role="button" tabIndex={0} className={css.item} onClick={() => go(i)} onKeyDown={(e) => { if (e.key === "Enter") go(i); }}>
                  <span className={css.dot} data-kind={i.kind} aria-label={t(i.kind === "alert" ? "web-main.attention.alertOne" : "web-main.attention.waitOne")} role="img" />
                  <span className={css.itemText}>
                    <span className={css.itemTitle}>{i.title || t("web-main.attention.untitled")}</span>
                    <span className={css.itemLine}>{line(i)}</span>
                  </span>
                  {(i.kind === "wait" ? i.seq != null : i.failure != null) && (
                    <button type="button" className={css.dismiss} title={t(i.kind === "alert" ? "web-main.attention.dismissFailNote" : "web-main.attention.dismissNote")}
                      onClick={(e) => { e.stopPropagation(); dismiss(i); }}>{t("web-main.attention.dismiss")}</button>
                  )}
                </div>
              ))}
            </div>
          ))}
          <div className={css.foot}>
            <NavLink className={css.link} to={`/w/${scope}/settings/notifications`} onClick={() => setOpen(false)}>{t("web-main.attention.settings")}</NavLink>
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
