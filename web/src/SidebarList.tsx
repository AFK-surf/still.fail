// What the sidebar's lists are made of, the chats' and the others' (stations, folders, profiles) alike: the action over
// them in the frosted top band (新建对话, 添加 Station, …), the list under it, its sections each under a heading (the
// chats' days, the profiles' kinds), and a row of a station, a folder or a profile: its mark, its title and what is at
// the end of that line, then any lines under them (a chat's row is its own, ChatRow).
import type { HTMLAttributes, MouseEvent, ReactNode, Ref } from "react";
import { Link, NavLink } from "react-router";
import * as nav from "./Sidebar.css.ts";
import * as css from "./SidebarList.css.ts";

/** The top band over a list: `top` the brand, then the list's action (NavAction), `below` anything under it. */
export function NavTop({ top, action, below }: { top?: ReactNode; action?: ReactNode; below?: ReactNode }) {
  return (
    <div className={nav.navTop}>
      {top}
      {action}
      {below}
    </div>
  );
}

/** The action over a list: a page (`to`) or a dialog (`onClick`); `beside` it, the list's menu. */
export function NavAction({ icon, label, beside, ...target }: { icon: ReactNode; label: ReactNode; beside?: ReactNode } & (
  | { to: string; onClick?: (e: MouseEvent<HTMLAnchorElement>) => void }
  | { to?: never; onClick: () => void }
)) {
  const body = <>{icon}<span className={nav.navText}>{label}</span></>;
  return (
    <div className={nav.navNew}>
      {target.to !== undefined
        ? <NavLink className={nav.navRow} to={target.to} onClick={target.onClick}>{body}</NavLink>
        : <button type="button" className={`${nav.navRow} ${css.button}`} onClick={target.onClick}>{body}</button>}
      {beside}
    </div>
  );
}

/** A section of a list, under its heading. */
export function NavSection({ title, flip, children }: { title: string; flip?: string; children: ReactNode }) {
  return (
    <section aria-label={title}>
      <div className={nav.navHeading} data-flip={flip}>{title}</div>
      {children}
    </section>
  );
}

/** A row: its `mark`, its `title` and what is at that line's `end`, then the lines under them (`children`, NavLine
 * each). A page (`to`), lit while it is the one in view (`current`; left out, while its path is), or a button
 * (`onClick`); the rest goes on the element (a Tip round it). `away`: what it is is not there now (its title faint). */
export function NavItem({ mark, title, end, away, tip, children, to, current, disabled, ...rest }: Omit<HTMLAttributes<HTMLElement>, "title" | "style" | "className"> & {
  mark: ReactNode; title: ReactNode; end?: ReactNode; away?: boolean; tip?: string | undefined; children?: ReactNode;
  to?: string; current?: boolean; disabled?: boolean; ref?: Ref<never>;
}) {
  const body = (
    <>
      <span className={css.mark}>{mark}</span>
      <span className={css.text}>
        <span className={css.head}>
          <span className={css.title}>{title}</span>
          {end != null && end !== false && <span className={css.end}>{end}</span>}
        </span>
        {children}
      </span>
    </>
  );
  const shared = { ...rest, className: `${nav.navRow} ${css.button} ${css.item}`, title: tip, "data-away": away ? "" : undefined };
  if (to === undefined) return <button type="button" {...shared} disabled={disabled}>{body}</button>;
  // A Link where the caller says which is lit (rows differing in their query alone, which a NavLink does not look at).
  if (current !== undefined) return <Link {...shared} to={to} aria-current={current ? "page" : undefined}>{body}</Link>;
  return <NavLink {...shared} to={to}>{body}</NavLink>;
}

/** A line under a row's title; `fill` the words that give way first. */
export function NavLine({ children, className }: { children: ReactNode; className?: string }) {
  return <span className={className ? `${css.line} ${className}` : css.line}>{children}</span>;
}

export const navFill = css.fill;
