// Words with things drawn inside them (a time, a link, a name in bold): the catalog's sentence, each `{name}` given as
// a node put in its place, so that the order of the words is the language's.
import { Fragment, type ReactNode } from "react";
import { t } from "../i18n.ts";

/**
 * The words for `key` as an element, read when it is drawn: for words kept in a value other modules take (an element
 * made once is drawn again in the language of the time).
 */
export function Words({ k, args }: { k: string; args?: Record<string, string | number> }) {
  return <>{t(k, args)}</>;
}

/** The words for `key` in the language now, a node in place of each `{name}` given one (strings and numbers as `t`). */
export function tx(key: string, args: Record<string, ReactNode>): ReactNode {
  const plain: Record<string, string | number> = {};
  for (const [name, value] of Object.entries(args)) if (typeof value === "string" || typeof value === "number") plain[name] = value;
  // What is left in braces is a node's place: the odd pieces are their names.
  return t(key, plain).split(/\{(\w+)\}/).map((piece, i) => (i % 2 ? <Fragment key={i}>{args[piece]}</Fragment> : piece));
}
