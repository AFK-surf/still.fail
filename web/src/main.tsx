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
  const { CloudApp } = await import("./cloud/CloudApp.tsx");
  root.render(<StrictMode><CloudApp /></StrictMode>);
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
