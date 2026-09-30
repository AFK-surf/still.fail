import { useEffect, useState } from "react";

/**
 * Whose pictures lead a chat's row: its agents' or its people's. 自动 by the scope: alone (a station's own page, a
 * workspace of one), the agents, the people beside them only when someone else is in the chat; with others, the people,
 * the agents beside them. Kept in this browser.
 */
export type RowPicture = "auto" | "agents" | "people";

const KEY = "stillfail.rowPicture";
const EVENT = "stillfail-row-picture";

export function readRowPicture(): RowPicture {
  const value = localStorage.getItem(KEY);
  return value === "agents" || value === "people" ? value : "auto";
}

export function useRowPicture(): [RowPicture, (value: RowPicture) => void] {
  const [value, setValue] = useState(readRowPicture);
  useEffect(() => {
    const update = () => setValue(readRowPicture());
    window.addEventListener(EVENT, update);
    window.addEventListener("storage", update);
    return () => { window.removeEventListener(EVENT, update); window.removeEventListener("storage", update); };
  }, []);
  return [value, (next) => { localStorage.setItem(KEY, next); window.dispatchEvent(new Event(EVENT)); }];
}

/** What leads in a scope of `members` people (unknown: as if alone, the agents as ever). */
export function leading(setting: RowPicture, members: number | undefined): "agents" | "people" {
  if (setting !== "auto") return setting;
  return (members ?? 1) > 1 ? "people" : "agents";
}

