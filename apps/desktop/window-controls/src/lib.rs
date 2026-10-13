//! Only hit testing is native: the page paints the maximize button. Chromium's child HWND takes mouse input before
//! Electron's top-level window, so a non-painting child above it answers HTMAXBUTTON for Windows 11's Snap Layouts.
//! https://learn.microsoft.com/windows/apps/desktop/modernize/apply-snap-layout-menu
use napi::bindgen_prelude::Buffer;
use napi_derive::napi;
use windows_sys::{
    Win32::{
        Foundation::*,
        Graphics::Gdi::*,
        System::Threading::GetCurrentThreadId,
        UI::{Input::KeyboardAndMouse::*, WindowsAndMessaging::*},
    },
    core::w,
};

const CLASS: *const u16 = w!("StillfailSnapTarget");
// apps/desktop/src/window-controls.ts receives these: 0 idle, 1 hover, 2 pressed, 3 click.
const NOTIFY: u32 = WM_APP + 71;
const DOWN: isize = 4;

unsafe fn visual(hwnd: HWND, state: isize) {
    unsafe {
        let old = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, (old & DOWN) | state);
        if old & 3 != state {
            PostMessageW(GetParent(hwnd), NOTIFY, state as usize, 0);
        }
    }
}

unsafe fn inside(hwnd: HWND, lp: LPARAM, screen: bool) -> bool {
    unsafe {
        let mut point = POINT {
            x: lp as u16 as i16 as i32,
            y: (lp >> 16) as u16 as i16 as i32,
        };
        if screen {
            ScreenToClient(hwnd, &mut point);
        }
        let mut rect = RECT::default();
        GetClientRect(hwnd, &mut rect);
        point.x >= 0 && point.y >= 0 && point.x < rect.right && point.y < rect.bottom
    }
}

unsafe extern "system" fn window_proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    unsafe {
        let parent = GetParent(hwnd);
        match msg {
            WM_NCHITTEST => return HTMAXBUTTON as isize,
            // No pixels are painted here: the page's icon, hover and modal shade remain visible.
            WM_ERASEBKGND => return 1,
            WM_PAINT => {
                ValidateRect(hwnd, std::ptr::null());
                return 0;
            }
            WM_NCMOUSEMOVE => {
                visual(hwnd, 1);
                let mut tracking = TRACKMOUSEEVENT {
                    cbSize: size_of::<TRACKMOUSEEVENT>() as u32,
                    dwFlags: TME_LEAVE | TME_NONCLIENT,
                    hwndTrack: hwnd,
                    dwHoverTime: 0,
                };
                TrackMouseEvent(&mut tracking);
                // The flyout belongs to the app window, not this tiny input child.
                return DefWindowProcW(parent, msg, wp, lp);
            }
            WM_NCMOUSELEAVE => {
                visual(hwnd, 0);
                return DefWindowProcW(parent, msg, wp, lp);
            }
            WM_NCLBUTTONDOWN | WM_NCLBUTTONDBLCLK if wp == HTMAXBUTTON as usize => {
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, DOWN);
                SetCapture(hwnd);
                visual(hwnd, 2);
                return 0;
            }
            WM_MOUSEMOVE if GetCapture() == hwnd => {
                visual(hwnd, if inside(hwnd, lp, false) { 2 } else { 0 });
                return 0;
            }
            WM_LBUTTONUP | WM_NCLBUTTONUP => {
                let click = GetWindowLongPtrW(hwnd, GWLP_USERDATA) & DOWN != 0
                    && inside(hwnd, lp, msg == WM_NCLBUTTONUP);
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
                if GetCapture() == hwnd {
                    ReleaseCapture();
                }
                PostMessageW(parent, NOTIFY, if click { 3 } else { 0 }, 0);
                return 0;
            }
            WM_CAPTURECHANGED | WM_CANCELMODE => {
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
                PostMessageW(parent, NOTIFY, 0, 0);
            }
            WM_NCDESTROY => {
                if GetPropW(parent, CLASS) == hwnd {
                    RemovePropW(parent, CLASS);
                }
            }
            _ => {}
        }
        DefWindowProcW(hwnd, msg, wp, lp)
    }
}

fn parent(handle: &Buffer) -> napi::Result<HWND> {
    let bytes: [u8; size_of::<usize>()] = handle
        .as_ref()
        .try_into()
        .map_err(|_| napi::Error::from_reason("invalid window handle size"))?;
    let hwnd = usize::from_le_bytes(bytes) as HWND;
    // No other process or UI thread may be subclassed/manipulated by an addon call.
    if unsafe {
        IsWindow(hwnd) == 0
            || GetWindowThreadProcessId(hwnd, std::ptr::null_mut()) != GetCurrentThreadId()
    } {
        return Err(napi::Error::from_reason(
            "window must belong to this UI thread",
        ));
    }
    Ok(hwnd)
}

/// Renderer bounds in physical client pixels, including display scale and browser zoom. A zero size hides the target.
#[napi]
pub fn set_bounds(handle: Buffer, x: i32, y: i32, width: i32, height: i32) -> napi::Result<()> {
    let parent = parent(&handle)?;
    unsafe {
        let mut child = GetPropW(parent, CLASS);
        let mut client = RECT::default();
        GetClientRect(parent, &mut client);
        let visible = width > 0
            && height > 0
            && x >= 0
            && y >= 0
            && x.checked_add(width)
                .is_some_and(|right| right <= client.right)
            && y.checked_add(height)
                .is_some_and(|bottom| bottom <= client.bottom);
        if !visible {
            if !child.is_null() {
                if GetCapture() == child {
                    ReleaseCapture();
                }
                visual(child, 0);
                ShowWindow(child, SW_HIDE);
            }
            return Ok(());
        }
        if child.is_null() {
            let class = WNDCLASSW {
                lpfnWndProc: Some(window_proc),
                lpszClassName: CLASS,
                hCursor: LoadCursorW(std::ptr::null_mut(), IDC_HAND),
                hbrBackground: GetStockObject(NULL_BRUSH) as _,
                ..std::mem::zeroed()
            };
            if RegisterClassW(&class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
                return Err(napi::Error::from_reason("could not register snap target"));
            }
            child = CreateWindowExW(
                0,
                CLASS,
                CLASS,
                WS_CHILD | WS_CLIPSIBLINGS,
                x,
                y,
                width,
                height,
                parent,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null(),
            );
            if child.is_null() {
                return Err(napi::Error::from_reason("could not create snap target"));
            }
            if SetPropW(parent, CLASS, child) == 0 {
                DestroyWindow(child);
                return Err(napi::Error::from_reason("could not retain snap target"));
            }
        }
        if SetWindowPos(
            child,
            HWND_TOP,
            x,
            y,
            width,
            height,
            SWP_SHOWWINDOW | SWP_NOACTIVATE,
        ) == 0
        {
            return Err(napi::Error::from_reason("could not position snap target"));
        }
    }
    Ok(())
}

/// The child is otherwise destroyed automatically with its parent HWND.
#[napi]
pub fn detach(handle: Buffer) -> napi::Result<()> {
    let parent = parent(&handle)?;
    unsafe {
        let child = GetPropW(parent, CLASS);
        if !child.is_null() {
            DestroyWindow(child);
        }
    }
    Ok(())
}
