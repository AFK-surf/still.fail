// The chats as a page of their own (the 搜索列表 layout, layout.ts), laid out as a chat: no sidebar; the chats as the
// sidebar lists them, by day, in the chat's column (where the chat left was, pushed aside or not), 全部 / 我参与的, the
// archive and a new chat above them, and the search where the composer is, typed into at once, narrowing the list in
// place (the core's `chatSearch`). ↑/↓ pick a row from the chat last open, ↩ opens it, Esc goes back to that chat. Each chat's bar leads back here
// (ListBack), with how the others are doing.
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import { Link, NavLink, useLocation, useNavigate } from "react-router";
import { useChatSearch, useChats, type ChatItem } from "./api.ts";
import type { ChatDay } from "./core/shapes.ts";
import { chatTone, type ChatTone } from "./ChatMark.tsx";
import { Archive, Brain, Close, Compose, Monitor, Search, Settings, User } from "./icons.tsx";
import { OpenJobs } from "./OpenJobs.tsx";
import { ChatRow, rowKey, StationTrouble } from "./Sidebar.tsx";
import { stationBase, useOnlyMine } from "./station.tsx";
import { lastChat } from "./lastChat.ts";
import { shortcutOf } from "./keymap.ts";
import { ICON, SkeletonRows, Tip } from "./ui.tsx";
import * as css from "./ChatsHome.css.ts";
import * as markCss from "./ChatMark.css.ts";
import * as refCss from "./ChatRef.css.ts";
import * as sidebarCss from "./styles/sidebar.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as composerCss from "./styles/composer.css.ts";
import * as shellCss from "./styles/shell.css.ts";

export function ChatsHome({ scope, newChat, settings, archive }: { scope: string; newChat: string; settings: string; archive: string }) {
  const navigate = useNavigate();
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const [query, setQuery] = useState("");
  // `/` and a few letters: a menu of ways to narrow the list (FILTERS), the one picked a chip before what is typed.
  const slash = /(?:^|\s)\/(\S*)$/.exec(query);
  const typed = (slash ? query.slice(0, slash.index) : query).trim();
  // Come from a state's count in a chat's bar: only those chats, for this visit.
  const from = (useLocation().state as { tone?: ChatTone } | null)?.tone;
  const [filters, setFilters] = useState<Filter[]>(() => TONES.filter(([t]) => t === from).map(([tone, label]) => toneFilter(tone, label)));
  const chats = useChats(scope, onlyMine);
  const search = useChatSearch({ scope, query: typed });
  const view = chats.value;
  const lead = view?.leading ?? "agents";
  // What is shown, in order: the list's rows, day by day as the sidebar has them; while something is typed, only those
  // the search found (in the list's order still), then any it found the list has not; then only those the filters let
  // through (any of a kind, every kind).
  const found = search.value?.items;
  const days = useMemo(() => {
    const listed = view?.days ?? [];
    const kinds = [...new Set(filters.map((f) => f.kind))];
    const passes = (i: ChatItem) => kinds.every((k) => filters.some((f) => f.kind === k && f.test(i)));
    const narrow = (d: ChatDay[]) => d.map((day) => ({ ...day, items: day.items.filter(passes) })).filter((day) => day.items.length > 0);
    if (!typed) return narrow(listed);
    if (!found) return [];
    const keys = new Set(found.map(rowKey));
    const kept = listed.map((d) => ({ ...d, items: d.items.filter((i) => keys.has(rowKey(i))) })).filter((d) => d.items.length > 0);
    const shown = new Set(kept.flatMap((d) => d.items.map(rowKey)));
    const rest = onlyMine ? [] : found.filter((i) => !shown.has(rowKey(i)));
    return narrow(rest.length ? [...kept, { label: "更早", daysAgo: 1e9, at: 0, items: rest }] : kept);
  }, [view, typed, found, onlyMine, filters]);
  // The ways to narrow it: whose, what state, which station, which agent (those its chats have), and the archive.
  const offered = useMemo(() => {
    const all = (view?.days ?? []).flatMap((d) => d.items);
    const stations = [...new Map(all.map((i) => [i.station, i.stationName])).entries()];
    const runtimes = [...new Set(all.flatMap((i) => i.agents.map((a) => a.runtime)))];
    const list: Filter[] = [
      { key: "mine", kind: "who", label: "我参与的", test: () => true },
      ...TONES.map(([tone, label]) => toneFilter(tone, label)),
      ...(stations.length > 1 ? stations.map(([id, name]) => ({ key: `station:${id}`, kind: "station", label: name || id, test: (i: ChatItem) => i.station === id })) : []),
      ...(runtimes.length > 1 ? runtimes.map((r) => ({ key: `runtime:${r}`, kind: "runtime", label: RUNTIME[r] ?? r, test: (i: ChatItem) => i.agents.some((a) => a.runtime === r) })) : []),
      { key: "archive", kind: "go", label: "已归档", test: () => true },
    ];
    const on = new Set([...filters.map((f) => f.key), ...(onlyMine ? ["mine"] : [])]);
    const words = slash?.[1] ?? "";
    return list.filter((f) => !on.has(f.key) && (!words || f.label.toLowerCase().includes(words.toLowerCase())));
  }, [view, filters, onlyMine, slash?.[1]]);
  const [option, setOption] = useState(0);
  useEffect(() => setOption(0), [slash?.[1], slash === null]);
  const chips = [...(onlyMine ? [{ key: "mine", label: "我参与的" }] : []), ...filters];
  const unchip = (key: string) => key === "mine" ? setOnlyMine(false) : setFilters((fs) => fs.filter((f) => f.key !== key));
  const choose = (f: Filter | undefined) => {
    if (!f) return;
    setQuery(slash ? query.slice(0, slash.index) + (slash.index > 0 ? " " : "") : query);
    if (f.key === "archive") navigate(archive);
    else if (f.key === "mine") setOnlyMine(true);
    else setFilters((fs) => [...fs, f]);
  };
  const rows = useMemo(() => days.flatMap((d) => d.items), [days]);
  // The chat last open is the one picked to begin with: ↑/↓ move on from it.
  const last = decodeURIComponent(lastChat(scope, ""));
  const active = rows.findIndex((i) => decodeURIComponent(`${stationBase(i.station)}/chats/${encodeURIComponent(i.id)}`) === last);
  const [picked, setPicked] = useState<string | null>(null);
  const at = picked === null ? active : rows.findIndex((i) => rowKey(i) === picked);
  const pick = (i: number) => { const item = rows[i]; if (item) setPicked(rowKey(item)); };
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => {
    list.current?.querySelector(`[data-at="${at}"]`)?.scrollIntoView({ block: "nearest" });
  }, [at]);
  const open = (item: ChatItem | undefined) => {
    if (item) navigate(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`);
  };
  const keys = shortcutOf("chat.switch");
  // Where the chat left was (its column, pushed aside by a panel or a preview), if the window is as it was.
  const main = useRef<HTMLDivElement>(null);
  const [place, setPlace] = useState<CSSProperties | undefined>(undefined);
  useLayoutEffect(() => {
    const width = main.current?.getBoundingClientRect().width;
    if (!column || width === undefined || Math.abs(width - column.main) >= 1) return;
    // As wide as ever (the chat's may be narrowed), as near the chat's as the window lets it be.
    const wide = Math.min(760, width - 64);
    setPlace({ marginLeft: Math.max(32, Math.min(column.left, width - 32 - wide)), marginRight: 0, width: wide });
  }, []);
  let n = 0;
  return (
    <div ref={main} className={css.home} data-avoid-previews="">
      <header className={`${sidebarCss.pageBar} ${css.bar}`}>
        <div className={css.tools} style={place}>
          <Link className={`${controlsCss.btn} ${controlsCss.btnGhost}`} to={archive}><Archive size={15} />已归档</Link>
          <Link className={`${controlsCss.btn} ${controlsCss.btnGhost} ${css.newChat}`} to={newChat}><Compose size={15} />新建对话</Link>
        </div>
        <div className={css.barActions}>
          <div className={css.station}><StationTrouble scope={scope} to={settings} /></div>
          <Tip label="设置"><Link className={pagesCss.iconBtn} to={settings} aria-label="设置"><Settings {...ICON} /></Link></Tip>
        </div>
      </header>
      <div className={css.scroll}>
        <div className={css.column} style={place}>
          {!typed && <div className={css.jobs}><OpenJobs scope={scope} /></div>}
          <div ref={list} className={css.list}>
            {!typed && !view && !chats.error && <SkeletonRows />}
            {chats.error && !view && <p className={css.none}>{chats.error.message}</p>}
            {typed && search.error && !found && <p className={css.none}>更新 still.fail 后才能搜索对话</p>}
            {typed && found && rows.length === 0 && <p className={css.none}>没有找到对话</p>}
            {!typed && view && rows.length === 0 && <p className={css.none}>{onlyMine ? "没有你参与的对话" : "还没有对话"}</p>}
            {days.map((day) => (
              <section key={day.daysAgo} aria-label={day.label}>
                <div className={css.day}>{day.label}</div>
                {day.items.map((item) => {
                  const i = n++;
                  return <div key={rowKey(item)} className={css.row} data-at={i} data-picked={i === at || undefined}><ChatRow item={item} lead={lead} /></div>;
                })}
              </section>
            ))}
          </div>
        </div>
      </div>
      {/* The search where a chat's composer is, and as it looks. */}
      <div className={css.bottom}>
        <div className={css.searchWrap} style={place}>
          {/* Beside the search, not in it: its glass would leave nothing behind the menu's to blur. */}
          {slash && (
            <div className={`${refCss.refMenu} ${css.filterMenu}`} role="listbox" aria-label="过滤" onMouseDown={(e) => e.preventDefault()}>
              <div className={refCss.refHead}>过滤{slash[1] && <span className={refCss.refQuery}>{slash[1]}</span>}</div>
              {offered.length === 0 ? <p className={refCss.refEmpty}>没有这样的过滤</p> : offered.map((f, i) => (
                <button type="button" key={f.key} className={`${refCss.refItem} ${css.filterItem}`} role="option" aria-selected={i === option} data-active={i === option || undefined}
                  onMouseMove={() => { if (i !== option) setOption(i); }} onClick={(e) => { e.preventDefault(); choose(f); }}>
                  <span className={refCss.refLogo}>{f.tone ? <span className={markCss.chatMarkInline} data-tone={f.tone} /> : <FilterIcon kind={f.kind} />}</span>
                  <span className={refCss.refTitle}>{f.label}</span>
                  <span className={refCss.refTime}>{KIND[f.kind]}</span>
                </button>
              ))}
            </div>
          )}
        <label className={css.searchBox}>
          <Search size={16} />
          {chips.map((c) => (
            <span key={c.key} className={css.chip}>{c.label}
              <button type="button" className={css.chipOff} aria-label={`去掉「${c.label}」`} onMouseDown={(e) => e.preventDefault()} onClick={(e) => { e.preventDefault(); unchip(c.key); }}><Close size={12} /></button>
            </span>
          ))}
          <input className={css.searchInput} autoFocus placeholder={chips.length ? "" : "搜索对话，/ 过滤"} aria-label="搜索对话" value={query} spellCheck={false}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.nativeEvent.isComposing) return;
              const step = e.key === "ArrowDown" || e.ctrlKey && e.key === "n" ? 1 : e.key === "ArrowUp" || e.ctrlKey && e.key === "p" ? -1 : 0;
              // The filters' menu open: the keys are its.
              if (slash) {
                if (step) { e.preventDefault(); setOption((o) => Math.max(0, Math.min(offered.length - 1, o + step))); return; }
                if (e.key === "Enter" || e.key === "Tab") { e.preventDefault(); choose(offered[option]); return; }
                if (e.key === "Escape") { e.preventDefault(); setQuery(query.slice(0, slash.index)); return; }
              }
              if (step) { e.preventDefault(); pick(at < 0 ? (step > 0 ? 0 : rows.length - 1) : Math.max(0, Math.min(rows.length - 1, at + step))); }
              else if (e.key === "Enter") { e.preventDefault(); open(rows[Math.max(at, 0)]); }
              // Backspace with nothing typed takes the last filter off.
              else if (e.key === "Backspace" && !query && chips.length) { e.preventDefault(); unchip(chips[chips.length - 1]!.key); }
              // Esc: what was typed goes; with nothing typed, back to the chat last open.
              else if (e.key === "Escape") {
                e.preventDefault();
                if (query) setQuery("");
                else if (lastChat(scope, "")) { navigate(lastChat(scope, "")); focusComposer(); }
              }
            }} />
          {keys && !query && <kbd className={css.searchKeys}>{keys}</kbd>}
        </label>
        </div>
      </div>
    </div>
  );
}

/** A way to narrow the list, offered after `/`: its kind (any of a kind lets a chat through, every kind must). */
type Filter = { key: string; kind: string; label: string; tone?: ChatTone; test(item: ChatItem): boolean };
const TONES: [ChatTone, string][] = [["alert", "要处理"], ["busy", "工作中"], ["done", "有新消息"]];
const toneFilter = (tone: ChatTone, label: string): Filter => ({ key: `tone:${tone}`, kind: "tone", label, tone, test: (i: ChatItem) => chatTone(i) === tone });
const RUNTIME: Record<string, string> = { claude: "Claude Code", codex: "Codex" };
const KIND: Record<string, string> = { who: "谁的", tone: "状态", station: "Station", runtime: "Agent", go: "打开" };

function FilterIcon({ kind }: { kind: string }) {
  if (kind === "who") return <User size={14} />;
  if (kind === "station") return <Monitor size={14} />;
  if (kind === "runtime") return <Brain size={14} />;
  if (kind === "go") return <Archive size={14} />;
  return null;
}

/**
 * Puts the cursor in the composer once the chat gone back to is there: its page takes a moment (it waits for the chat),
 * and the search's field, still focused meanwhile, leaves nothing focused as it goes.
 */
export function focusComposer(): void {
  const until = performance.now() + 1500;
  const step = () => {
    const field = document.querySelector<HTMLTextAreaElement>(`.${composerCss.composerBox} textarea`);
    if (field && field.getClientRects().length && document.activeElement !== field) field.focus();
    if (field && document.activeElement === field && !document.querySelector(`.${css.home}`)) return;
    if (performance.now() < until) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

/** Where the chat's column was as it was left for the list (in the page's main area), for the list to take its place. */
let column: { left: number; width: number; main: number } | null = null;

/** Notes where the chat in view has its column (its composer's width): called on the way to the list. */
export function rememberColumn(): void {
  const box = document.querySelector(`.${composerCss.composerBox}`)?.getBoundingClientRect();
  const main = document.querySelector(`.${shellCss.main}`)?.getBoundingClientRect();
  column = box && main && box.width > 0 ? { left: box.left - main.left, width: box.width, main: main.width } : null;
}

const ORDER: ChatTone[] = ["alert", "busy", "done"];
const SAID: Record<ChatTone, string> = { alert: "要处理", busy: "工作中", done: "有新消息" };

/**
 * A chat's ways back to the list (the 搜索列表 layout), left of its title: how the other chats are doing, a dot of each
 * state with how many (as their rows' marks, ChatMark.tsx), so a chat that wants you is seen without leaving this one;
 * each leads to the list showing only those. With nothing to say, 对话.
 */
export function ListBack({ scope, to }: { scope: string; to: string }) {
  const view = useChats(scope, false).value;
  const here = decodeURIComponent(useLocation().pathname);
  const counts = new Map<ChatTone, number>();
  for (const day of view?.days ?? []) for (const item of day.items) {
    if (`${stationBase(item.station)}/chats/${item.id}` === here) continue;
    const tone = chatTone(item);
    if (tone) counts.set(tone, (counts.get(tone) ?? 0) + 1);
  }
  const said = ORDER.filter((t) => counts.get(t)).map((t) => `${counts.get(t)} 个${SAID[t]}`).join("，");
  const shown = ORDER.filter((t) => counts.get(t));
  return (
    <div className={css.back}>
      {shown.length === 0 && (
        <Tip label="对话列表"><NavLink className={css.backItem} to={to} onClick={rememberColumn}>对话</NavLink></Tip>
      )}
      {/* Each state its own way back: to the list showing only those chats (a filter for this visit only). */}
      {shown.map((t) => (
        <Tip key={t} label={`${counts.get(t)} 个${SAID[t]}`}>
          <NavLink className={css.backItem} to={to} state={{ tone: t }} onClick={rememberColumn} aria-label={`对话列表：${counts.get(t)} 个${SAID[t]}`}>
            <span className={markCss.chatMarkInline} data-tone={t} />{counts.get(t)}
          </NavLink>
        </Tip>
      ))}
    </div>
  );
}
