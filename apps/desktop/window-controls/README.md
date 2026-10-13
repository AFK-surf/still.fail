# Windows window controls

The page draws the three controls with the toolbar's 32px buttons and 16px icons, centred in its 44px row. This Node-API addon only owns the maximize button's mouse input. A transparent, non-painting child HWND sits above Chromium's input window and returns `HTMAXBUTTON`. Non-client hover messages go to the parent window's default procedure so Windows 11 can show its own Snap Layouts menu. The menu and its layouts are not recreated in HTML.

Bounds come from the actual DOM rectangle, multiplied by `devicePixelRatio` (monitor scale and page zoom). The main process accepts bounds/actions only from its own main frame. The addon accepts only HWNDs owned by its UI thread, hides out-of-client rectangles, and is destroyed with the window. Capturing the mouse between press and release lets dragging out cancel activation. Hover/press/click notifications go through `WM_APP + 71`; `src/window-controls.ts` relays state to the page. Keyboard activation stays on the DOM button.

`scripts/native.ts` builds the Windows-only `window-controls` part, using the same MinGW/Node-API recipe as the mesh addon. `build.sh --win` packs it beside `mesh.node`. A missing addon falls back to native window controls. Other platforms do not load it.

## Local integration test (Windows)

Start `pnpm dev:web --host 127.0.0.1 --port 5198`. Build this crate with `cargo build --release --manifest-path apps/desktop/window-controls/Cargo.toml`, copy the resulting DLL to a `.node` path, and set `STILLFAIL_WINDOW_CONTROLS` to that absolute path. Run `electron apps/desktop/test/window-controls.cjs`. `SHOTS` optionally names a directory for actual-window screenshots.

The test uses the production component, preload, adapter and addon with a disposable profile. It checks real HWND geometry and hit tests at several zoom levels; native press/release and drag-out cancellation; maximize/restore, resize, full screen, reload, modal overlays, and DOM activation. It does not move the user's pointer. Verify the actual shell flyout and layout selection interactively on Windows 11 with Snap Layouts enabled; `HTMAXBUTTON` alone is not evidence that the shell displayed its menu.

Microsoft's requirement: https://learn.microsoft.com/windows/apps/desktop/modernize/apply-snap-layout-menu
