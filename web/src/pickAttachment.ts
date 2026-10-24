/** Keep the native picker owned by the document until it returns, including while iOS suspends the PWA. */
export function pickAttachment(accept: string, capture: boolean, onPicked: (files: FileList) => void): void {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = accept;
  input.multiple = !capture;
  input.hidden = true;
  if (capture) input.setAttribute("capture", "environment");
  const cleanup = () => {
    input.onchange = null;
    input.oncancel = null;
    input.remove();
  };
  input.onchange = () => {
    try {
      if (input.files?.length) onPicked(input.files);
    } finally {
      cleanup();
    }
  };
  input.oncancel = cleanup;
  // The document keeps the input reachable while the system photo picker is open (WebKit bug 201289).
  document.body.append(input);
  try {
    input.click();
  } catch (error) {
    cleanup();
    throw error;
  }
}
