import { useEffect, useLayoutEffect, useMemo, useRef } from "react";
import { latestFrame } from "@stillfail/ui/frames.ts";

/** Keep the frame queue across renders, but draw with the latest committed gesture code. Owners flush on release
 * and cancel on interruption; hiding a page also discards a pending point. */
export function useFrameDraw<T>(draw: (value: T) => void) {
  const current = useRef(draw);
  useLayoutEffect(() => { current.current = draw; });
  const task = useMemo(() => latestFrame<T>(value => current.current(value)), []);
  useEffect(() => () => task.cancel(), [task]);
  return task;
}
