// Naming a chat by hand, where its name is shown: the name turns into a field; Enter or leaving it keeps what was
// typed, Escape leaves the name as it was. An empty name gives the chat back its own (its agent's, else its first message).
import { useEffect, useRef } from "react";
import { stationApi, useStationCall } from "./api.ts";
import { useToast } from "./toast.tsx";
import * as css from "./Rename.css.ts";

export function TitleInput({ value, onDone, className }: { value: string; onDone: (title: string | null) => void; className?: string }) {
  const input = useRef<HTMLInputElement>(null);
  const done = useRef(false);
  // After whatever opened it (a menu closing) is done with the focus.
  useEffect(() => {
    const frame = requestAnimationFrame(() => { input.current?.focus(); input.current?.select(); });
    return () => cancelAnimationFrame(frame);
  }, []);
  const finish = (title: string | null) => {
    if (done.current) return;
    done.current = true;
    onDone(title === null || title.trim() === value.trim() ? null : title.trim());
  };
  return (
    <input ref={input} className={`${css.titleInput} ${className ?? ""}`} defaultValue={value} maxLength={80} aria-label="对话名称"
      placeholder="留空则自动起名"
      // Inside a chat's row (a link): pressing and clicking here stay in the field.
      onMouseDown={(e) => e.stopPropagation()} onClick={(e) => { e.preventDefault(); e.stopPropagation(); }}
      onKeyDown={(e) => {
        e.stopPropagation();
        if (e.nativeEvent.isComposing) return;
        if (e.key === "Enter") { e.preventDefault(); finish(e.currentTarget.value); }
        if (e.key === "Escape") { e.preventDefault(); finish(null); }
      }}
      onBlur={(e) => finish(e.currentTarget.value)} />
  );
}

/** Names a chat on a station (null: nothing changed), saying so if it did not go. */
export function useRename(station: string) {
  const api = stationApi(useStationCall(station));
  const toast = useToast();
  return (of: { thread?: number | null; session: string }, title: string | null) => {
    if (title === null) return;
    api.rename(of, title).catch((error: unknown) => toast(`没能改名：${error instanceof Error ? error.message : String(error)}`));
  };
}
