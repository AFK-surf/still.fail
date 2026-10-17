// The extension's one setting: where still.fail is (a dev cloud while working on it; the app's by default).
const ORIGIN = "https://app.still.fail";
const said = document.getElementById("said");
const field = document.getElementById("origin");

for (const el of document.querySelectorAll("[data-i18n]")) el.textContent = chrome.i18n.getMessage(el.dataset.i18n);

chrome.storage.sync.get({ origin: ORIGIN }).then(({ origin }) => { field.value = origin; });

document.getElementById("form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const typed = field.value.trim() || ORIGIN;
  let origin;
  try {
    const url = new URL(typed);
    if (url.protocol !== "https:" && url.protocol !== "http:") throw new Error("not a web address");
    origin = url.origin;
  } catch {
    said.dataset.error = "";
    said.textContent = chrome.i18n.getMessage("optionsInvalid");
    return;
  }
  await chrome.storage.sync.set({ origin });
  field.value = origin;
  delete said.dataset.error;
  said.textContent = chrome.i18n.getMessage("optionsSaved");
});
