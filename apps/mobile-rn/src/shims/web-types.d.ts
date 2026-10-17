// What the web modules the app type-checks through import from packages only the web app has (web/src/telemetry.ts,
// which src/shims/telemetry.ts stands in for when bundling): enough for the checker to read them.
declare module "posthog-js" {
  export type CaptureResult = any;
  export type PostHog = any;
  export type Properties = Record<string, any>;
  export const posthog: any;
}
declare module "react-router" {
  export function useLocation(): { pathname: string };
}
