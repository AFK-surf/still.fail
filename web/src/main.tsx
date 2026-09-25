import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import { ApiError } from "./api.ts";
import "@fontsource-variable/inter";
import { App } from "./App.tsx";
import "./theme.css";
import "./app.css";

const root = createRoot(document.getElementById("app")!);

// Built twice: served by a station at /admin (talks to it directly), and as
// ember cloud's web app at / (sign-in, workspaces; stations over iroh).
if (import.meta.env.MODE === "cloud") {
  const station = /^\/w\/([0-9A-HJKMNP-TV-Z]{26})\/s\/([0-9a-f]{64})(\/|$)/.exec(location.pathname);
  if (station) {
    const { StationFrame } = await import("./cloud/frame.tsx");
    root.render(<StrictMode><StationFrame ws={station[1]!} station={station[2]!} /></StrictMode>);
  } else {
    const { CloudApp } = await import("./cloud/CloudApp.tsx");
    root.render(<StrictMode><CloudApp /></StrictMode>);
  }
} else {
  const client = new QueryClient({
    defaultOptions: {
      queries: {
        // Live updates arrive over SSE; refetching on every focus would only add noise.
        refetchOnWindowFocus: false,
        retry: (count, error) => !(error instanceof ApiError && error.status < 500) && count < 2,
      },
    },
  });
  root.render(
    <StrictMode>
      <QueryClientProvider client={client}>
        <BrowserRouter basename="/admin">
          <App />
        </BrowserRouter>
      </QueryClientProvider>
    </StrictMode>,
  );
}
