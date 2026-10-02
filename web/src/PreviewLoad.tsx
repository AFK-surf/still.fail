import { useRef, useState, useEffect } from "react";
import { Popover } from "radix-ui";
import { useTopic } from "./core/react.ts";
import * as css from "./Preview.css.ts";
import * as pages from "./styles/pages.css.ts";

export interface ResourceLoad {
  percent: number; total: number; finished: number; failed: number;
  resources: { id: number; method: string; path: string; since: number; ended: number | null; status: number | null; error: string | null }[];
}

export function PreviewLoad({ station, port }: { station: string; port: number }) {
  const { value } = useTopic<ResourceLoad>({ topic: "previewLoad", station, port });
  return value ? <LoadRing value={value} /> : null;
}

/** The core owns the counts; only the popover's presentation lives here. */
export function LoadRing({ value }: { value: ResourceLoad }) {
  const [open, setOpen] = useState(false);
  const close = useRef<ReturnType<typeof setTimeout> | null>(null);
  const hold = () => { if (close.current) clearTimeout(close.current); };
  const leave = () => { hold(); close.current = setTimeout(() => setOpen(false), 160); };
  useEffect(() => () => { if (close.current) clearTimeout(close.current); }, []);
  const label = `资源加载 ${value.percent}% · ${value.finished}/${value.total}${value.failed ? ` · ${value.failed} 个失败` : ""}`;
  return <Popover.Root open={open} onOpenChange={setOpen}>
    <Popover.Trigger asChild>
      <button type="button" className={`${pages.iconBtn} ${css.loadRing}`} data-failed={value.failed > 0 || undefined} aria-label={label}
        onPointerEnter={(e) => { if (e.pointerType === "mouse") { hold(); setOpen(true); } }} onPointerLeave={(e) => { if (e.pointerType === "mouse") leave(); }}>
        <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
          <circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" strokeWidth="2" opacity="0.18" />
          <circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" strokeWidth="2" pathLength="100" strokeDasharray={`${value.percent} 100`} transform="rotate(-90 10 10)" />
        </svg>
      </button>
    </Popover.Trigger>
    <Popover.Portal><Popover.Content className={css.loadDetails} sideOffset={6} collisionPadding={8} align="start"
      onPointerEnter={hold} onPointerLeave={(e) => { if (e.pointerType === "mouse") leave(); }} onOpenAutoFocus={(e) => e.preventDefault()} onCloseAutoFocus={(e) => e.preventDefault()}>
      <div className={css.loadHeading}>{label}</div>
      <div className={css.loadHint}>按已发现的服务请求计算 · 新资源出现时更新</div>
      <div className={css.loadList}>
        {!value.total && <div className={css.loadHint}>等待页面请求</div>}
        {value.resources.map((r) => <div className={css.loadRow} key={r.id} data-failed={!!r.error || (r.status ?? 0) >= 400 || undefined}>
          <span className={css.loadPath} title={`${r.method} ${r.path}`}>{r.path}</span>
          <span>{r.ended === null ? "加载中" : r.error ? "失败" : r.status}</span>
          <span>{r.ended === null ? "" : `${Math.max(0, Math.round(r.ended - r.since))} ms`}</span>
          {r.error && <span className={css.loadError}>{r.error}</span>}
        </div>)}
      </div>
      {value.total > value.resources.length && <div className={css.loadHint}>仅保留最近资源及未完成请求</div>}
    </Popover.Content></Popover.Portal>
  </Popover.Root>;
}
