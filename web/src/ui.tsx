// The app's own parts beside @stillfail/ui's (its parts.tsx, all of which this gives too): what made an agent's model,
// a connect's kind, a time, a page's way back, the splash, page changes. The tips' keys are the app's keymap's.
import { Mark } from "./brand.tsx";
import { shortcutOf, useKeymap } from "./keymap.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import type { Badge, Maker, RuntimeKind, Stamp } from "./api.ts";
import { RUNTIME_LABEL } from "./format.ts";
import { Chat, Check, ChevronLeft, Wait, Plug, Refresh, Sliders } from "@stillfail/ui/icons.tsx";
import { setShortcuts } from "@stillfail/ui/shortcuts.ts";
import { motionMs } from "@stillfail/ui/motion.ts";
import { ICON, Tip } from "@stillfail/ui/parts.tsx";
import { flushSync } from "react-dom";
import { Link, useNavigate } from "react-router";
import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./ui.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import { t } from "./i18n.ts";
import { MONO } from "./modelMarks.ts";
import { reload } from "./reloads.ts";

export * from "@stillfail/ui/parts.tsx";
export * from "@stillfail/ui/waiting.tsx";

setShortcuts({ keys: shortcutOf, use: useKeymap });

/**
 * Keep a completed or waiting state compact while retaining its explanation and accessible name: a check, an open arc and dots
 * in its words' place. The core says it in words, in either language (client/core-ts present.ts: 做完了, 做完了：<why>;
 * Done, Done: <why>; 等待中, 在等：<what>; Waiting, Waiting: <what>).
 */
export function StatusText({ text }: { text: string }) {
  const done = /^(?:(?:做完了|已完成)(?:：|$)|Done(?:: |$))/.exec(text);
  const wait = done ? null : /^(?:在等：|等待：|等待中$|Waiting(?:: |$))/.exec(text);
  const lead = done ?? wait;
  if (!lead) return <>{text}</>;
  const label = t(done ? "web-main.status.done" : "web-main.status.waiting");
  const reason = text.slice(lead[0].length);
  return <><Tip label={label}><span className={css.doneMark} role="img" aria-label={label}>{done ? <Check size={14} strokeWidth={1.7} /> : <Wait size={14} strokeWidth={1.7} />}</span></Tip>{reason && <> {reason}</>}</>;
}

/** A back link that only phones show, where an opened page hides the sidebar. */
export function MobileBack({ to, label }: { to: string; label: string }) {
  return <Link className={css.mobileBack} to={to}><ChevronLeft {...ICON} />{label}</Link>;
}

/**
 * A detail page's way back, on every screen: to the page it was opened from (a step back in history), or when it was
 * opened directly, to `to`.
 */
export function BackLink({ to, label }: { to: string; label: string }) {
  const navigate = useNavigate();
  return (
    // In a row of its own, which takes the page's column (the link alone would not line up with it).
    <div className={css.pageBackRow}>
      <Link className={css.pageBack} to={to} onClick={(e) => {
        if (((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0) { e.preventDefault(); navigate(-1); }
      }}><ChevronLeft {...ICON} />{label}</Link>
    </div>
  );
}

const KIND_ICON = { slack: SlackLogo, feishu: FeishuLogo, wechat: Chat } as const;

/** What a connect connects to, as an icon: its kind, not its identity. */
export function ConnectKindIcon({ kind, size = 16, tile }: { kind: string; size?: number; tile?: boolean }) {
  const Icon = KIND_ICON[kind as keyof typeof KIND_ICON] ?? Chat;
  const icon = <Icon size={size} strokeWidth={1.7} aria-hidden="true" />;
  return tile ? <span className={`${pagesCss.mark} ${css.kindMark}`} style={{ width: size * 2.4, height: size * 2.4 }}>{icon}</span> : <span className={css.kindIcon}>{icon}</span>;
}

/** A connect as its people see it in Slack: its bot's picture; its kind's icon until Slack has said what that is. */
export function ConnectAvatar({ connect, size = 28 }: { connect: { kind: string; botImage?: string | null | undefined }; size?: number }) {
  if (!connect.botImage) return <ConnectKindIcon kind={connect.kind} size={Math.round(size * 0.6)} tile={size > 32} />;
  return <img className={chatCss.botAvatar} src={connect.botImage} width={size} height={size} alt="" loading="lazy" referrerPolicy="no-referrer" />;
}

/** Slack's mark in its own colours, sized like the line icons around it. */
export function SlackLogo({ size = 16 }: { size?: number; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 54 54" aria-hidden="true" className="slack-logo">
      <path fill="#36C5F0" d="M19.712.133a5.381 5.381 0 0 0-5.376 5.387 5.381 5.381 0 0 0 5.376 5.386h5.376V5.52A5.381 5.381 0 0 0 19.712.133m0 14.365H5.376A5.381 5.381 0 0 0 0 19.884a5.381 5.381 0 0 0 5.376 5.387h14.336a5.381 5.381 0 0 0 5.376-5.387 5.381 5.381 0 0 0-5.376-5.386" />
      <path fill="#2EB67D" d="M53.76 19.884a5.381 5.381 0 0 0-5.376-5.386 5.381 5.381 0 0 0-5.376 5.386v5.387h5.376a5.381 5.381 0 0 0 5.376-5.387m-14.336 0V5.52A5.381 5.381 0 0 0 34.048.133a5.381 5.381 0 0 0-5.376 5.387v14.364a5.381 5.381 0 0 0 5.376 5.387 5.381 5.381 0 0 0 5.376-5.387" />
      <path fill="#ECB22E" d="M34.048 54a5.381 5.381 0 0 0 5.376-5.387 5.381 5.381 0 0 0-5.376-5.386h-5.376v5.386A5.381 5.381 0 0 0 34.048 54m0-14.365h14.336a5.381 5.381 0 0 0 5.376-5.386 5.381 5.381 0 0 0-5.376-5.387H34.048a5.381 5.381 0 0 0-5.376 5.387 5.381 5.381 0 0 0 5.376 5.386" />
      <path fill="#E01E5A" d="M0 34.249a5.381 5.381 0 0 0 5.376 5.386 5.381 5.381 0 0 0 5.376-5.386v-5.387H5.376A5.381 5.381 0 0 0 0 34.249m14.336 0v14.364A5.381 5.381 0 0 0 19.712 54a5.381 5.381 0 0 0 5.376-5.387V34.249a5.381 5.381 0 0 0-5.376-5.387 5.381 5.381 0 0 0-5.376 5.387" />
    </svg>
  );
}

/** Where a thread elsewhere is (a place's `surface`, a connect's kind): Feishu's mark for Feishu, else Slack's. */
export function ElsewhereLogo({ kind, size = 16 }: { kind: string | null | undefined; size?: number }) {
  return kind === "feishu" || kind?.startsWith("feishu:") ? <FeishuLogo size={size} /> : <SlackLogo size={size} />;
}

/** Feishu's (Lark's) mark in its own colours: the bird of the open platform's logo (open.feishu.cn), as Feishu draws it. */
export function FeishuLogo({ size = 16 }: { size?: number; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="2.5 2 28 28" aria-hidden="true" className="feishu-logo">
      <path fill="#00D6B9" d="M16.9508 16.5619L17.0173 16.4982C17.0615 16.4556 17.1055 16.4127 17.1492 16.3695L17.2384 16.2813L17.5093 16.0137L17.8769 15.6505L18.1927 15.3384L18.4893 15.0453L18.7988 14.7395L19.0827 14.459L19.478 14.0684C19.5532 13.9947 19.6297 13.9223 19.7074 13.8512C19.8508 13.7201 19.9983 13.5938 20.1501 13.4721C20.2891 13.3605 20.4315 13.2532 20.5772 13.1499C20.7813 13.0053 20.9915 12.8692 21.2079 12.7416C21.4195 12.6169 21.6365 12.5008 21.8589 12.3933C22.0677 12.2924 22.2809 12.1996 22.4984 12.1147C22.6196 12.0675 22.7421 12.0229 22.8658 11.9808C22.9277 11.9598 22.9899 11.9394 23.0525 11.9197C22.5039 9.76089 21.499 7.74477 20.1055 6.00713C19.9723 5.84151 19.8036 5.70792 19.6119 5.61623C19.4201 5.52455 19.2103 5.47711 18.9977 5.47742L7.61416 5.47729C7.56922 5.47726 7.52542 5.49145 7.48903 5.51783C7.45265 5.54421 7.42555 5.58144 7.41161 5.62416C7.39768 5.66689 7.39763 5.71293 7.41146 5.75569C7.42529 5.79845 7.45231 5.83574 7.48863 5.8622C11.3746 8.71031 14.5944 12.3696 16.925 16.5864L16.9508 16.5619Z" />
      <path fill="#133C9A" d="M26.107 18.5437L26.0994 18.5572L26.108 18.5443L26.1605 18.4456C26.1426 18.4782 26.1251 18.5112 26.107 18.5437Z" />
      <path fill="#133C9A" d="M26.3523 18.0848L26.3663 18.0584L26.3731 18.0449L26.3523 18.0848Z" />
      <path fill="#133C9A" d="M29.7006 12.4233C27.7171 11.4515 25.4452 11.244 23.3184 11.8404C23.2292 11.8655 23.1405 11.8919 23.0524 11.9197C22.9899 11.9394 22.9277 11.9598 22.8657 11.9809C22.742 12.0229 22.6196 12.0675 22.4984 12.1148C22.281 12.1995 22.0678 12.2924 21.8589 12.3933C21.6366 12.5007 21.4196 12.6168 21.2079 12.7417C20.9917 12.8691 20.7815 13.0052 20.5772 13.15C20.4315 13.2532 20.2892 13.3605 20.1501 13.4721C19.9984 13.5937 19.8508 13.7201 19.7074 13.8513C19.6297 13.9223 19.5532 13.9947 19.478 14.0685L19.0827 14.4591L18.7988 14.7396L18.4893 15.0454L18.1927 15.3385L17.8768 15.6506L17.5092 16.0138L17.2384 16.2814L17.1491 16.3696C17.1054 16.4127 17.0615 16.4556 17.0173 16.4982L16.9508 16.562C16.9175 16.5938 16.884 16.6254 16.8504 16.6569C16.8133 16.6916 16.776 16.7262 16.7385 16.7607C15.7597 17.66 14.6705 18.4313 13.4971 19.0559C13.5671 19.0889 13.6374 19.1217 13.7077 19.1543C13.7634 19.1801 13.8191 19.2057 13.8749 19.2312C13.9288 19.2557 13.9828 19.2802 14.0369 19.3046C14.0901 19.3285 14.1435 19.3523 14.1969 19.376C14.2552 19.4019 14.3137 19.4276 14.3722 19.4532C14.4397 19.4826 14.5072 19.5119 14.5749 19.5409C14.6397 19.5687 14.7046 19.5963 14.7696 19.6236C14.8537 19.6591 14.9381 19.6942 15.0226 19.7291C15.0905 19.757 15.1585 19.7847 15.2266 19.8123C15.3313 19.8546 15.4363 19.8964 15.5416 19.9377C15.6409 19.9767 15.7404 20.0152 15.8403 20.0533C15.9148 20.0818 15.9895 20.11 16.0644 20.1379C16.193 20.186 16.3221 20.2333 16.4516 20.2799C16.517 20.3034 16.5824 20.3268 16.648 20.3499C16.7395 20.3822 16.8313 20.4142 16.9233 20.4458C16.9989 20.4717 17.0746 20.4974 17.1505 20.5229C17.2613 20.5601 17.3725 20.5967 17.484 20.6329C17.601 20.6708 17.7184 20.7082 17.8361 20.745C17.9798 20.7899 18.1239 20.8339 18.2686 20.877C18.3651 20.9058 18.4619 20.9342 18.559 20.9622C18.7534 21.0184 18.9487 21.073 19.1449 21.126C19.2154 21.145 19.2858 21.1629 19.3562 21.1797C19.49 21.2116 19.6234 21.2394 19.7565 21.263C19.9097 21.2903 20.0622 21.3122 20.2141 21.3288C20.4212 21.3515 20.6268 21.3644 20.8308 21.3676C21.017 21.3705 21.2016 21.3655 21.3844 21.3526C21.5587 21.3403 21.7312 21.3209 21.9018 21.2944C22.1368 21.258 22.3695 21.208 22.5987 21.1445C22.7523 21.1019 22.9035 21.0534 23.0525 20.9991C23.1903 20.9488 23.3259 20.8936 23.4593 20.8335C23.613 20.7642 23.7635 20.6885 23.9109 20.6063C23.9833 20.5659 24.0549 20.524 24.1257 20.4806C24.1937 20.4388 24.2609 20.3957 24.3272 20.3512C24.432 20.2809 24.5347 20.2072 24.6352 20.13C24.7211 20.0642 24.8054 19.9958 24.888 19.925C25.0366 19.7977 25.1795 19.6626 25.3169 19.5197C25.3843 19.4494 25.4503 19.3774 25.5149 19.3034C25.5966 19.2099 25.6759 19.1134 25.7528 19.0141C25.814 18.9348 25.8737 18.8538 25.9317 18.771C26.0955 18.5368 26.2439 18.2923 26.3761 18.0389L26.5284 17.7351L27.9046 14.9917L27.9023 14.9973C28.3405 14.0373 28.9499 13.165 29.7006 12.4233Z" />
      <path fill="#3370FF" d="M12.4363 26.5826C15.2248 26.5836 17.9629 25.8387 20.3666 24.4252C22.7703 23.0117 24.7523 20.981 26.1069 18.5437C26.2007 18.3753 26.2915 18.2051 26.3792 18.0329C26.2462 18.2884 26.0967 18.5348 25.9316 18.7708C25.8736 18.8537 25.8139 18.9347 25.7526 19.0139C25.6758 19.1132 25.5965 19.2097 25.5147 19.3033C25.4502 19.3772 25.3842 19.4493 25.3167 19.5195C25.1795 19.6624 25.0365 19.7975 24.8878 19.9249C24.8052 19.9957 24.721 20.064 24.6351 20.1299C24.5345 20.207 24.4319 20.2807 24.3271 20.351C24.2607 20.3955 24.1935 20.4387 24.1255 20.4804C24.0548 20.5238 23.9832 20.5658 23.9107 20.6062C23.7634 20.6883 23.6129 20.764 23.4591 20.8333C23.3258 20.8935 23.1902 20.9487 23.0524 20.9989C22.9035 21.0533 22.7522 21.1017 22.5986 21.1443C22.3694 21.2078 22.1367 21.2579 21.9017 21.2943C21.7311 21.3207 21.5587 21.3401 21.3842 21.3524C21.2015 21.3653 21.017 21.3703 20.8307 21.3674C20.6268 21.3642 20.4212 21.3513 20.2139 21.3287C20.0621 21.3121 19.9095 21.2901 19.7563 21.2629C19.6233 21.2392 19.4898 21.2114 19.356 21.1795C19.2857 21.1628 19.2152 21.1449 19.1447 21.1258C18.9485 21.0728 18.7532 21.0182 18.5588 20.9621C18.4618 20.9341 18.365 20.9057 18.2684 20.8768C18.1237 20.8337 17.9796 20.7897 17.836 20.7448C17.7182 20.708 17.6009 20.6707 17.4838 20.6327C17.3723 20.5966 17.2612 20.5599 17.1503 20.5227C17.0744 20.4973 16.9987 20.4716 16.9231 20.4456C16.8311 20.414 16.7393 20.3821 16.6478 20.3498C16.5822 20.3266 16.5168 20.3033 16.4514 20.2798C16.3219 20.2332 16.1928 20.1858 16.0642 20.1378C15.9893 20.1098 15.9146 20.0816 15.8401 20.0532C15.7403 20.0151 15.6407 19.9765 15.5414 19.9376C15.4361 19.8962 15.3311 19.8544 15.2264 19.8121C15.1583 19.7846 15.0903 19.7569 15.0224 19.7289C14.9379 19.6941 14.8535 19.659 14.7694 19.6235C14.7043 19.5961 14.6395 19.5685 14.5747 19.5408C14.507 19.5117 14.4395 19.4825 14.372 19.453C14.3135 19.4275 14.255 19.4017 14.1967 19.3759C14.1433 19.3522 14.0899 19.3284 14.0367 19.3044C13.9826 19.2801 13.9286 19.2556 13.8747 19.231C13.8188 19.2055 13.7631 19.1799 13.7075 19.1542C13.6371 19.1216 13.5669 19.0888 13.4968 19.0557C13.4233 19.021 13.35 18.9861 13.2768 18.951C13.1983 18.9133 13.12 18.8753 13.0419 18.837C12.9753 18.8043 12.9089 18.7714 12.8425 18.7384C9.34942 16.9956 6.19515 14.6438 3.5279 11.7934C3.49868 11.7622 3.46077 11.7406 3.41908 11.7312C3.3774 11.7219 3.33387 11.7253 3.29415 11.741C3.25444 11.7568 3.22038 11.7841 3.19639 11.8194C3.17241 11.8548 3.15961 11.8965 3.15967 11.9393L3.16533 21.9846V22.7996C3.16467 23.0328 3.22163 23.2625 3.33115 23.4683C3.44067 23.6742 3.59936 23.8498 3.79311 23.9795C6.3538 25.6817 9.36125 26.5875 12.4361 26.5825" />
    </svg>
  );
}

/**
 * How long a splash may stand before it offers to load the page again: past it, something is stuck (a core that never
 * answers, a load that never ends), and an app on the home screen has no reload of its own.
 */
const SPLASH_STUCK_MS = 10_000;

/**
 * The app starting (or waiting for what every page needs): the buddy, floating. What it waits for is said only when
 * it takes a while (after a second), or at once when `now` (a failure); standing too long, it offers a reload.
 */
export function Splash({ label, now = false, children }: { label?: string; now?: boolean; children?: ReactNode }) {
  const [stuck, setStuck] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setStuck(true), SPLASH_STUCK_MS);
    return () => clearTimeout(timer);
  }, []);
  return (
    <div className="splash" role="status" aria-live="polite">
      <Mark size={56} className="splash-mark" />
      {label && <p className={css.splashLabel} data-now={now || undefined}>{label}</p>}
      {children}
      {stuck && <button type="button" className={css.splashReload} onClick={() => reload("button")}><Refresh size={14} />{t("common.reload")}</button>}
    </div>
  );
}

/**
 * The agent runtimes' marks: Claude's in its orange, OpenAI's (Codex), DeepSeek Harness's, xAI's (Grok Build), Cursor's and
 * Devin's in the text colour. Claude's, OpenAI's and Cursor's paths from simple-icons (CC0); DeepSeek Harness's from its
 * repository (MIT); xAI's the maker mark Grok's models have (public/models/xai.svg); Devin's from devin.ai's favicon.
 */
export function RuntimeLogo({ runtime, size = 16 }: { runtime: RuntimeKind; size?: number }) {
  if (runtime === "devin") return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Devin" role="img" className={css.runtimeLogo}><path fill="currentColor" d="M1.984 8.248V3.495C1.984 3.287 2.096 3.093 2.277 2.989L6.391 0.613C6.572 0.509 6.795 0.509 6.976 0.613L11.091 2.989C11.272 3.093 11.383 3.287 11.383 3.495V5.923C11.402 6.729 11.828 7.507 12.578 7.94C13.327 8.373 14.214 8.353 14.922 7.965L17.024 6.752C17.205 6.647 17.428 6.647 17.609 6.752L21.723 9.128C21.904 9.232 22.016 9.425 22.016 9.634V14.385C22.016 14.594 21.904 14.787 21.723 14.892L17.609 17.268C17.428 17.372 17.205 17.372 17.024 17.268L14.939 16.064C14.228 15.667 13.334 15.643 12.578 16.08C11.828 16.513 11.402 17.291 11.384 18.097V20.524C11.384 20.733 11.272 20.926 11.091 21.03L6.976 23.406C6.795 23.51 6.573 23.51 6.392 23.406L2.277 21.03C2.096 20.926 1.984 20.733 1.984 20.524V15.772C1.984 15.563 2.096 15.37 2.277 15.266L6.392 12.89C6.573 12.786 6.795 12.786 6.976 12.89L9.083 14.106C9.79 14.491 10.674 14.51 11.422 14.078C12.178 13.642 12.605 12.855 12.617 12.042C12.598 11.235 12.172 10.374 11.422 9.941C10.673 9.508 9.786 9.528 9.078 9.915L6.967 11.142C6.785 11.247 6.561 11.247 6.379 11.141L2.275 8.754C2.095 8.649 1.984 8.456 1.984 8.248Z" /></svg>
  );
  if (runtime === "cursor") return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Cursor" role="img" className={css.runtimeLogo}><path fill="currentColor" d="M11.503.131 1.891 5.678a.84.84 0 0 0-.42.726v11.188c0 .3.162.575.42.724l9.609 5.55a1 1 0 0 0 .998 0l9.61-5.55a.84.84 0 0 0 .42-.724V6.404a.84.84 0 0 0-.42-.726L12.497.131a1.01 1.01 0 0 0-.996 0M2.657 6.338h18.55c.263 0 .43.287.297.515L12.23 22.918c-.062.107-.229.064-.229-.06V12.335a.59.59 0 0 0-.295-.51l-9.11-5.257c-.109-.063-.064-.23.061-.23" /></svg>
  );
  if (runtime === "grok") return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Grok Build" role="img" className={css.runtimeLogo}><path fill="currentColor" fillRule="evenodd" d="M6.469 8.776L16.512 23h-4.464L2.005 8.776H6.47zm-.004 7.9l2.233 3.164L6.467 23H2l4.465-6.324zM22 2.582V23h-3.659V7.764L22 2.582zM22 1l-9.952 14.095-2.233-3.163L17.533 1H22z" /></svg>
  );
  if (runtime === "dsh") return (
    <svg width={size} height={size} viewBox="0 0 50 50" aria-label="DeepSeek Harness" role="img" className={css.runtimeLogo}><path fill="currentColor" d="M48.8354 10.0479C48.3232 9.79199 48.1025 10.2798 47.8032 10.5278C47.7007 10.6079 47.6143 10.7119 47.5273 10.8076C46.7793 11.624 45.9048 12.1597 44.7622 12.0957C43.0923 12 41.666 12.5356 40.4058 13.8398C40.1377 12.2319 39.2476 11.272 37.8926 10.6558C37.1836 10.3359 36.4668 10.0156 35.9702 9.31982C35.6235 8.82373 35.5293 8.27197 35.356 7.72754C35.2456 7.3999 35.1353 7.06396 34.7651 7.00781C34.3633 6.94385 34.2056 7.2876 34.0479 7.57568C33.418 8.75195 33.1733 10.0479 33.1973 11.3599C33.2524 14.312 34.4736 16.6641 36.8999 18.3359C37.1758 18.5278 37.2466 18.7197 37.1597 19C36.9946 19.5757 36.7974 20.1357 36.624 20.7119C36.5137 21.0801 36.3486 21.1597 35.9624 21C34.6309 20.4321 33.481 19.5918 32.4644 18.5757C30.7393 16.8721 29.1792 14.9917 27.2334 13.52C26.7764 13.1758 26.3193 12.856 25.8467 12.5518C23.8618 10.584 26.1069 8.96777 26.627 8.77588C27.1704 8.57568 26.8159 7.8877 25.0591 7.896C23.3022 7.90381 21.6953 8.50391 19.647 9.30371C19.3477 9.42383 19.0322 9.51172 18.7095 9.58398C16.8501 9.22363 14.9199 9.14355 12.9033 9.37598C9.10596 9.80762 6.07275 11.6396 3.84326 14.7681C1.16455 18.5278 0.53418 22.7998 1.30664 27.2559C2.11768 31.9521 4.46582 35.8398 8.07373 38.8799C11.8159 42.0322 16.1255 43.5762 21.041 43.2803C24.0269 43.104 27.3516 42.6963 31.1016 39.4561C32.0469 39.936 33.0396 40.1279 34.686 40.272C35.9546 40.3921 37.1758 40.208 38.1211 40.0078C39.6021 39.688 39.4995 38.2881 38.9639 38.0322C34.623 35.9678 35.5762 36.8081 34.71 36.1279C36.9155 33.4639 40.2402 30.6958 41.54 21.728C41.6426 21.0161 41.5557 20.5679 41.54 19.9917C41.5322 19.6396 41.6108 19.5039 42.0049 19.4639C43.0923 19.3359 44.1479 19.0317 45.1167 18.4878C47.9292 16.9199 49.064 14.3438 49.3315 11.2559C49.3711 10.7837 49.3237 10.2959 48.8354 10.0479ZM24.3262 37.8398C20.1196 34.4639 18.0791 33.3521 17.2358 33.3999C16.4482 33.4482 16.5898 34.3682 16.7632 34.9678C16.9443 35.5601 17.1812 35.9683 17.5117 36.4878C17.7402 36.832 17.8979 37.3442 17.2832 37.728C15.9282 38.584 13.5728 37.4399 13.4624 37.3838C10.7207 35.7358 8.42822 33.5601 6.81348 30.584C5.25342 27.7197 4.34766 24.6479 4.19775 21.3677C4.1582 20.5757 4.38672 20.2959 5.15869 20.1519C6.17529 19.96 7.22314 19.9199 8.23926 20.0718C12.5327 20.7119 16.1885 22.6719 19.2529 25.7759C21.002 27.5439 22.3252 29.6558 23.6885 31.7202C25.1377 33.9121 26.6978 36 28.6831 37.7119C29.3843 38.312 29.9434 38.7681 30.479 39.104C28.8643 39.2881 26.1699 39.3281 24.3262 37.8398ZM26.3433 24.6001C26.3433 24.248 26.6191 23.9678 26.9658 23.9678C27.0444 23.9678 27.1152 23.9839 27.1782 24.0078C27.2651 24.04 27.3438 24.0879 27.4067 24.1602C27.5171 24.272 27.5801 24.4321 27.5801 24.6001C27.5801 24.9521 27.3042 25.2319 26.9575 25.2319C26.6108 25.2319 26.3433 24.9521 26.3433 24.6001ZM32.6064 27.8799C32.2046 28.0479 31.8027 28.1919 31.4165 28.208C30.8179 28.2397 30.1641 27.9922 29.8096 27.688C29.2583 27.2158 28.8643 26.9521 28.6987 26.1279C28.6279 25.7759 28.6675 25.2319 28.7305 24.9199C28.8721 24.248 28.7144 23.8159 28.2495 23.4238C27.8716 23.104 27.3911 23.0161 26.8633 23.0161C26.666 23.0161 26.4849 22.9277 26.3511 22.856C26.1304 22.7441 25.9492 22.4639 26.1226 22.1201C26.1777 22.0078 26.4458 21.7358 26.5088 21.688C27.2256 21.272 28.0527 21.4077 28.8169 21.7197C29.5259 22.0161 30.0615 22.5601 30.834 23.3281C31.6216 24.2559 31.7632 24.5117 32.2124 25.208C32.5669 25.752 32.8901 26.312 33.1104 26.9521C33.2446 27.3521 33.0713 27.6802 32.6064 27.8799Z" /></svg>
  );
  return runtime === "claude" ? (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Claude Code" role="img" className={css.runtimeLogo}><path fill="#D97757" d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z" /></svg>
  ) : (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Codex" role="img" className={css.runtimeLogo}><path fill="currentColor" d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z" /></svg>
  );
}

/**
 * The mark of the company that made a model (the core says which); the runtime's mark when it does not know. No tip of
 * its own: it sits in tabs, rows and buttons that have theirs, and one thing shows one tip.
 */
export function ModelLogo({ maker, runtime, size = 14 }: { maker: Maker | null | undefined; runtime: RuntimeKind; size?: number }) {
  if (!maker) return <RuntimeLogo runtime={runtime} size={size} />;
  return <img className={css.modelLogo} src={`${import.meta.env.BASE_URL}models/${maker.id}.svg`} alt={maker.name} width={size} height={size} data-mono={MONO.has(maker.id) || undefined} />;
}

/** OpenCode's mark: a hollow square, drawn to match the 1.7 stroke icons. */
function OpenCodeMark({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} aria-hidden="true">
      <rect x="6" y="4" width="12" height="16" />
    </svg>
  );
}

/** Whose service a profile runs on: Anthropic, OpenAI or xAI for a subscription or an API key, OpenCode for OpenCode Go. */
export function ProviderLogo({ runtime, kind, mark, size = 16 }: { runtime: RuntimeKind; kind: string; mark?: string | null | undefined; size?: number }) {
  if (kind === "opencode-go" || mark === "opencode") return <OpenCodeMark size={size} />;
  if (kind === "env") return <Sliders size={size} strokeWidth={1.7} aria-hidden="true" />;
  // A key on a listed provider: its maker's mark, or the generic plug where there is none.
  if (kind === "api-provider") return mark ? <ModelLogo maker={{ id: mark, name: mark }} runtime={runtime} size={size} /> : <Plug size={size} strokeWidth={1.7} aria-hidden="true" />;
  const maker = runtime === "claude" || kind === "anthropic-api" ? { id: "anthropic", name: "Anthropic" } : runtime === "grok" ? { id: "xai", name: "xAI" } : runtime === "cursor" ? { id: "cursor", name: "Cursor" } : runtime === "devin" ? { id: "devin", name: "Devin" } : { id: "openai", name: "OpenAI" };
  return <ModelLogo maker={maker} runtime={runtime} size={size} />;
}

/** A runtime's name, short, for the tags after a profile's name. */
const RUNTIME_TAG: Record<RuntimeKind, string> = { claude: "CC", codex: "Codex", dsh: "DSH", grok: "GROK", cursor: "Cursor", devin: "Devin" };

/** The runtimes a profile runs, as small marks after its name (CC for Claude Code, Codex, DSH for DeepSeek Harness, GROK for Grok Build, Cursor, Devin), and 自动决策 where it serves the automatic decisions. */
export function RuntimeTags({ runtimes, decision = false }: { runtimes: RuntimeKind[]; decision?: boolean | undefined }) {
  return (
    <span className={waitingCss.runtimeTags}>
      {runtimes.map((r) => <Tip key={r} label={RUNTIME_LABEL[r]}><span className={waitingCss.runtimeTag}><RuntimeLogo runtime={r} size={12} />{RUNTIME_TAG[r]}</span></Tip>)}
      {decision && <Tip label={t("common.decisionLong")}><span className={waitingCss.runtimeTag}>{t("common.decision")}</span></Tip>}
    </span>
  );
}

/**
 * An agent as the phone shows it: its model's maker on a tile, and where it stands as a badge. `children`: the station it
 * runs on, on the same tile after the maker (its icon, or its name where it has none); `wrap` then puts the maker in its
 * own control, the station's part being one of its own.
 */
export function AgentMark({ maker, runtime, badge, badgeText, size = 20, wrap, children }: {
  maker: Maker | null | undefined; runtime: RuntimeKind; badge: Badge | undefined; badgeText?: string | undefined; size?: number;
  wrap?: ((logo: ReactNode) => ReactNode) | undefined; children?: ReactNode;
}) {
  const logo = <ModelLogo maker={maker} runtime={runtime} size={Math.round(size * 0.62)} />;
  if (children == null) {
    return <span className={css.agentMark} style={{ "--mark": `${size}px` } as CSSProperties} data-badge={badge ?? undefined} role="img" aria-label={badgeText ?? undefined}>{logo}</span>;
  }
  return (
    <span className={`${css.agentMark} ${css.agentMarkJoined}`} style={{ "--mark": `${size}px` } as CSSProperties} data-badge={badge ?? undefined}>
      {wrap ? wrap(logo) : logo}{children}
    </span>
  );
}

/** Every relative time on the page follows one switch, kept on this device (prefs.ts): a click on any of them flips all between "3 分钟前" and the date. */
function useAbsoluteTime(): [boolean, () => void] {
  const absolute = usePrefs((p) => p.absoluteTime);
  return [absolute, () => setPrefs({ absoluteTime: !absolute })];
}

/** A time as the core says it (fresh each minute): relative by default; clicking flips every time on the page to absolute and back. `fixed`: always relative, not a switch (the sidebar's), the date on hover. */
export function Time({ stamp, className, fixed = false }: { stamp: Stamp | undefined; className?: string; fixed?: boolean }) {
  const [switched, flip] = useAbsoluteTime();
  if (!stamp) return null;
  const absolute = switched && !fixed;
  return (
    <Tip label={absolute ? stamp.ago : stamp.full}><time className={`${fixed ? "" : css.timeToggle}${className ? ` ${className}` : ""}`.trim()} dateTime={new Date(stamp.at).toISOString()}
      onClick={fixed ? undefined : (e) => { e.preventDefault(); e.stopPropagation(); flip(); }}>
      {absolute ? stamp.full : stamp.ago}
    </time></Tip>
  );
}

let changing: { settle: (() => void)[]; moving: Promise<void>; done: Promise<void> } | null = null;
/**
 * While a page change (transitionTo) is under way: `settle` is run once the next page is there, as its picture is about
 * to be taken; `moving` is when the change starts to move, `done` when it is over. Else null.
 */
export function pageChanging(): { settle: (() => void)[]; moving: Promise<void>; done: Promise<void> } | null {
  return changing;
}

/**
 * One page becoming another in a view transition (what both have and name moves between them; the rest crossfades):
 * `go` navigates, rendered at once; with `ready`, the new page is waited for (a little) until it shows what the
 * transition lands on. `patience`: how long (ms) the new page is waited for at most. Plainly without the API; with
 * motion reduced, the same, over at once (styles/global.css.ts).
 * Resolves when it is over.
 */
export function transitionTo(go: () => void, ready?: () => boolean, patience = 800): Promise<void> {
  if (!document.startViewTransition) { go(); return Promise.resolve(); }
  // What is named for it only while it runs (its styles): a named element blurs nothing behind it (the composer's glass).
  document.documentElement.dataset.transitioning = "";
  const transition = document.startViewTransition(async () => {
    flushSync(go);
    const until = performance.now() + patience;
    while (ready && !ready() && performance.now() < until) await new Promise((r) => setTimeout(r, 16));
    for (const settle of now.settle.splice(0)) settle();
  });
  const now = { settle: [] as (() => void)[], moving: transition.ready.catch(() => {}), done: transition.finished.catch(() => {}) };
  changing = now;
  return transition.finished.catch(() => {}).finally(() => { if (changing === now) changing = null; delete document.documentElement.dataset.transitioning; });
}

/** A page change whose leaving elements are kept by its caller: no document snapshot or rendering freeze. */
export function transitionLive(go: () => void, ready: () => boolean, duration: number): Promise<void> {
  let begin!: () => void;
  const moving = new Promise<void>((resolve) => { begin = resolve; });
  const now = { settle: [] as (() => void)[], moving, done: Promise.resolve() };
  changing = now;
  now.done = Promise.resolve().then(async () => {
    flushSync(go);
    // Composer layout effects queue their own setup; let them join settle before measuring the destination.
    await Promise.resolve();
    const until = performance.now() + 800;
    while (!ready() && performance.now() < until) await new Promise((resolve) => setTimeout(resolve, 16));
    for (const settle of now.settle.splice(0)) settle();
    begin();
    await new Promise((resolve) => setTimeout(resolve, motionMs(duration)));
  }).finally(() => {
    begin();
    if (changing === now) changing = null;
  });
  return now.done;
}
