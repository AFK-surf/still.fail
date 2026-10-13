// Functions handed down that stay the same: a memoized child (memo) given one is not drawn again because its parent was.
import { useRef, useState } from "react";

/**
 * A function that stays the same while the component lives and calls the one given in its latest render: for handlers
 * handed to memoized children, which are then not drawn again each time the parent is. Called during a child's render
 * (a lookup handed down, as a chat's `owner` of a file is), it is the one the parent's latest render gave.
 */
export function useEvent<A extends unknown[], R>(fn: (...args: A) => R): (...args: A) => R {
  const latest = useRef(fn);
  latest.current = fn;
  const [stable] = useState(() => (...args: A) => latest.current(...args));
  return stable;
}
