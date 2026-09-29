// Runs first inside an inline visualization's frame (Viz.tsx). The frame is sandboxed without its page's origin, so
// the two only talk by messages: the frame says how tall its content is, the page says when its theme changes (the
// --e-* tokens ember-viz.css maps), and the frame draws the tooltip of any element with data-tooltip.
//
// The widget's API is window.ember, named as Codex's Visualize names window.openai (which it also answers to, for a
// widget written for that): widgetState and setWidgetState keep what the widget wants back when it is shown again,
// sendFollowUpMessage puts words in the chat's composer for the person to send — only on their click or key.
(() => {
  const root = document.documentElement;
  const post = (message) => parent.postMessage({ emberViz: true, ...message }, "*");

  const given = document.getElementById("ember-viz-state");
  let state = JSON.parse(given?.textContent || "{}").widgetState ?? null;
  given?.remove();
  const api = {
    get widgetState() { return state; },
    setWidgetState(next) {
      const json = JSON.stringify(next ?? null);
      if (json.length > 16 * 1024) return Promise.reject(new Error("widgetState is over 16 KiB"));
      state = JSON.parse(json);
      post({ type: "state", state });
      return Promise.resolve();
    },
    sendFollowUpMessage({ prompt } = {}) {
      if (typeof prompt !== "string" || !prompt.trim()) return Promise.reject(new Error("sendFollowUpMessage needs a prompt"));
      // Only as the person acts: a widget cannot write to the chat by itself.
      if (navigator.userActivation && !navigator.userActivation.isActive) return Promise.reject(new Error("sendFollowUpMessage needs a click or key press"));
      post({ type: "followup", prompt });
      return Promise.resolve();
    },
  };
  Object.defineProperty(window, "ember", { value: api });
  Object.defineProperty(window, "openai", { value: api });

  let last = 0;
  const sendHeight = () => {
    const height = Math.ceil(Math.max(document.body?.scrollHeight ?? 0, document.body?.getBoundingClientRect().height ?? 0));
    if (height !== last) {
      last = height;
      post({ type: "height", height });
    }
  };
  addEventListener("message", (event) => {
    if (event.source !== parent || !event.data?.emberViz) return;
    if (event.data.type === "theme") {
      for (const [name, value] of Object.entries(event.data.tokens ?? {})) root.style.setProperty(name, value);
      root.dataset.theme = event.data.scheme;
      root.style.colorScheme = event.data.scheme;
      // For charts drawn with resolved colours (a canvas, a chart library): redraw on this.
      dispatchEvent(new CustomEvent("ember-viz:theme", { detail: { scheme: event.data.scheme } }));
    }
  });

  let tip = null;
  const place = (target) => {
    const r = target.getBoundingClientRect();
    const t = tip.getBoundingClientRect();
    const left = Math.min(Math.max(4, r.left + r.width / 2 - t.width / 2), innerWidth - t.width - 4);
    const top = r.top - t.height - 6 >= 0 ? r.top - t.height - 6 : r.bottom + 6;
    tip.style.left = `${left}px`;
    tip.style.top = `${top}px`;
  };
  const show = (target) => {
    const text = target.getAttribute("data-tooltip");
    if (!text) return hide();
    tip ??= Object.assign(document.createElement("div"), { className: "viz-tooltip", role: "tooltip" });
    tip.textContent = text;
    document.body.append(tip);
    place(target);
  };
  const hide = () => tip?.remove();
  addEventListener("pointerover", (e) => { const t = e.target.closest?.("[data-tooltip]"); t ? show(t) : hide(); });
  addEventListener("focusin", (e) => { const t = e.target.closest?.("[data-tooltip]"); t ? show(t) : hide(); });
  addEventListener("pointerleave", hide);
  addEventListener("scroll", hide, true);

  addEventListener("DOMContentLoaded", () => {
    sendHeight();
    new ResizeObserver(sendHeight).observe(document.body);
  });
  addEventListener("load", sendHeight);
  addEventListener("error", (e) => post({ type: "error", message: String(e.message ?? e) }));
})();
