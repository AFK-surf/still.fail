// Whether the page runs as an app on the home screen (a PWA: display-mode standalone, or iOS's own navigator.standalone):
// no browser round it, so no reload, address or back button of its own.

export function standalone(): boolean {
  return matchMedia("(display-mode: standalone)").matches || (navigator as { standalone?: boolean }).standalone === true;
}
