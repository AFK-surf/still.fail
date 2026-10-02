// What a page shows until what it lists has come (Android screens/Loading.kt draws the same): grey placeholders where
// the rows or messages will be, breathing, and over them a pill saying what it waits on (a spinner before it), or in
// red what is wrong (the placeholders then faded and still). The pill is drawn as a chat's system messages are.
import { Spinner } from "./parts.tsx";
import * as css from "./Loading.css.ts";

/** What is waited on (a spinner before it), or with `error` what is wrong (in red): centred, a grey capsule. */
export function LoadingPill({ text, error = false }: { text: string; error?: boolean }) {
  return (
    <div className={css.mPillRow}>
      <span className={css.mPill} data-error={error || undefined} role="status" aria-live="polite">{!error && <Spinner size={12} />}{text}</span>
    </div>
  );
}

const TITLES = [150, 110, 170, 130, 96, 160, 120];
const LINES = [230, 190, 250, 170, 210, 200, 180];
const MESSAGES: [boolean, number, number][] = [[false, 220, 40], [false, 160, 58], [true, 180, 40], [false, 240, 76], [true, 120, 40], [false, 200, 40]];

/** The chat list's rows to come (Home.tsx ChatRow's size: 66 high, its title and line, who is in it at the end). */
export function PlaceholderRows({ count, still = false }: { count: number; still?: boolean }) {
  return (
    <div className={css.mPlaceholders} data-still={still || undefined} aria-hidden="true">
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className={css.mPlaceRow}>
          <div className={css.mPlaceLines}>
            <span className={css.mPlaceTitle} style={{ width: TITLES[i % TITLES.length] }} />
            <span className={css.mPlaceLine} style={{ width: LINES[i % LINES.length] }} />
          </div>
          <span className={css.mPlacePicture} />
        </div>
      ))}
    </div>
  );
}

/** A chat's messages to come: theirs with a picture on the left, the viewer's on the right. */
export function PlaceholderMessages({ still = false }: { still?: boolean }) {
  return (
    <div className={`${css.mPlaceholders} ${css.mPlaceMessages}`} data-still={still || undefined} aria-hidden="true">
      {MESSAGES.map(([mine, w, h], i) => (
        <div key={i} className={css.mPlaceMessage} data-mine={mine || undefined}>
          {!mine && <span className={css.mPlaceFace} />}
          <span className={css.mPlaceBubble} style={{ width: w, height: h }} />
        </div>
      ))}
    </div>
  );
}
