// The extension's one setting: where still.fail is (a dev cloud while working on it; the app's by default).
const ORIGIN = "https://app.still.fail";
const said = document.getElementById("said");
const field = document.getElementById("origin");

for (const el of document.querySelectorAll("[data-i18n]")) el.textContent = chrome.i18n.getMessage(el.dataset.i18n);

chrome.storage.sync.get({ origin: ORIGIN }).then(({ origin }) => { field.value = origin; });

document.getElementById("form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const typed = field.value.trim() || ORIGIN;
  let origin, pattern;
  try {
    const url = new URL(typed);
    if (url.protocol !== "https:" && url.protocol !== "http:") throw new Error("not a web address");
    origin = url.origin;
    pattern = `${url.protocol}//${url.hostname}/*`;
  } catch {
    said.dataset.error = "";
    said.textContent = chrome.i18n.getMessage("optionsInvalid");
    return;
  }
  // Another still.fail: leave asked for to reach its tabs (to open a chat picked there in place), while the click is
  // still one (before anything is waited on). Not given, a chat picked opens in a new tab instead.
  const allowed = origin === ORIGIN ? Promise.resolve(true) : chrome.permissions.request({ origins: [pattern] }).catch(() => false);
  await allowed;
  await chrome.storage.sync.set({ origin });
  field.value = origin;
  delete said.dataset.error;
  said.textContent = chrome.i18n.getMessage("optionsSaved");
});
