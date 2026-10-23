// One view of the main display (main.rs says the messages): the capture and the encoder on a thread of their own, a
// picture encoded only once one is asked for and only a new one (the screen changed) unless a key frame is asked for;
// the input and the clipboard on this one, in the order they come.
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender, channel};
use std::time::{Duration, Instant};

use serde_json::{Value, json};
use windows::Graphics::Capture::GraphicsCaptureSession;
use windows::Win32::Foundation::{POINT, RECT};
use windows::Win32::Graphics::Direct3D11::ID3D11Texture2D;
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT, DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_FORMAT_NV12};
use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, HMONITOR, MONITOR_DEFAULTTOPRIMARY, MONITORINFO, MonitorFromPoint};
use windows::Win32::Media::MediaFoundation::{MFSTARTUP_LITE, MFShutdown, MFStartup, MF_VERSION};
use windows::Win32::System::Com::{COINIT_MULTITHREADED, CoInitializeEx};
use windows::Win32::System::Power::{ES_CONTINUOUS, ES_DISPLAY_REQUIRED, ES_SYSTEM_REQUIRED, SetThreadExecutionState};
use windows::Win32::UI::HiDpi::{DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2, SetProcessDpiAwarenessContext};

use super::Out;
use super::avc;
use super::capture::{Capture, Gpu, Scaler, fitted};
use super::clipboard::{Clipboard, PNG_MAX};
use super::encode::H264;
use super::image::{Images, Pixels};
use super::input::Input;

/// Its coordinates in pixels, whatever the display's scale.
pub fn dpi_aware() {
    unsafe {
        let _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    }
}

/// The main display and where it is on the virtual desktop, in pixels.
pub fn main_display() -> (HMONITOR, RECT) {
    unsafe {
        let monitor = MonitorFromPoint(POINT { x: 0, y: 0 }, MONITOR_DEFAULTTOPRIMARY);
        let mut info = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
        let _ = GetMonitorInfoW(monitor, &mut info);
        (monitor, info.rcMonitor)
    }
}

pub fn status() -> Value {
    let (monitor, rect) = main_display();
    let capture = GraphicsCaptureSession::IsSupported().unwrap_or(false);
    json!({ "ok": true, "display": { "id": monitor.0 as usize, "width": rect.right - rect.left, "height": rect.bottom - rect.top }, "capture": capture })
}

pub enum Msg {
    Next,
    Keyframe,
    /// The capture has a new picture.
    Frame,
    /// The display captured went.
    Closed,
    /// Bits a second to encode at from the next frame on (the link carries no more).
    Rate(u32),
}

struct Options {
    jpeg: bool,
    max: (u32, u32),
    bitrate: Option<u32>,
    /// The software encoder even where there is hardware (a test of it): never asked by the station.
    software: bool,
}

pub fn run(request: &Value, input: &mut impl std::io::Read, out: Out) {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
    }
    let options = Options {
        jpeg: request["codec"].as_str() == Some("jpeg"),
        max: (request["maxWidth"].as_u64().unwrap_or(1920).max(16) as u32, request["maxHeight"].as_u64().unwrap_or(1080).max(16) as u32),
        bitrate: request["bitrate"].as_u64().map(|b| b as u32),
        software: request["encoder"].as_str() == Some("software"),
    };
    let (tx, rx) = channel();
    let worker = {
        let (tx, out) = (tx.clone(), out.clone());
        std::thread::spawn(move || {
            unsafe {
                let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
                let _ = MFStartup(MF_VERSION, MFSTARTUP_LITE);
                // The display on (and the machine awake) while the view is open.
                SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED);
            }
            let ended = View::open(options, tx, &out).map(|mut view| view.run(rx, &out));
            if let Err(e) = ended {
                out.json(4, json!({ "stopped": e.message() }));
            }
            unsafe {
                let _ = MFShutdown();
            }
            // The capture gone: so is the view.
            std::process::exit(0);
        })
    };
    let mut keys = Input::new();
    keys.nudge();
    let mut clipboard = Clipboard::new(out.clone());
    // A picture on the clipboard is the largest message.
    while let Some((kind, payload)) = super::message(input, 2 + PNG_MAX) {
        match kind {
            1 => drop(tx.send(Msg::Next)),
            2 => drop(tx.send(Msg::Keyframe)),
            3 => {
                if let Ok(op) = serde_json::from_slice::<Value>(&payload) {
                    keys.post(&op);
                }
            }
            4 => {
                if clipboard.set(&payload) && payload[0] & 1 == 1 {
                    keys.paste();
                }
            }
            5 => clipboard.watch(payload.first() == Some(&1)),
            6 => reveal(&String::from_utf8_lossy(&payload)),
            7 if payload.len() == 4 => drop(tx.send(Msg::Rate(u32::from_be_bytes([payload[0], payload[1], payload[2], payload[3]])))),
            _ => {}
        }
    }
    clipboard.stop();
    drop(tx);
    drop(worker);
    std::process::exit(0);
}

/// A file shown selected in Explorer (one dropped into the view, put on the machine).
fn reveal(path: &str) {
    use std::os::windows::process::CommandExt;
    if path.is_empty() || path.contains('"') {
        return;
    }
    let _ = std::process::Command::new("explorer.exe").raw_arg(format!("/select,\"{path}\"")).spawn();
}

/// How long a picture may be in the encoder before it is taken as lost.
const STUCK: Duration = Duration::from_secs(2);

struct View {
    gpu: Gpu,
    capture: Capture,
    options: Options,
    images: Option<Images>,
    /// The newest picture, as captured (BGRA, the display's size), and when (µs).
    latest: Option<ID3D11Texture2D>,
    latest_at: i64,
    fresh: bool,
    wanted: u32,
    force_key: bool,
    last_ts: i64,
    scaler: Option<Scaler>,
    encoder: Option<H264>,
    /// The encoder made a picture asked to be a key frame without one: made anew for the next ask instead.
    force_unheeded: bool,
    config: Vec<u8>,
    sps: Vec<u8>,
    pps: Vec<u8>,
    jpeg_size: (u32, u32),
    staging: Option<ID3D11Texture2D>,
    /// When the picture in the encoder went in.
    pushed_at: Instant,
    /// When which display is the main one was looked at last.
    looked: Instant,
}

fn failed(out: &Out, error: &windows::core::Error, code: &str) -> windows::core::Error {
    out.json(1, json!({ "error": error.message(), "code": code }));
    error.clone()
}

impl View {
    fn open(options: Options, tx: Sender<Msg>, out: &Out) -> windows::core::Result<View> {
        let gpu = Gpu::new().map_err(|e| failed(out, &e, "capture"))?;
        let (monitor, rect) = main_display();
        let capture = Capture::start(&gpu, monitor, tx).map_err(|e| failed(out, &e, "capture"))?;
        let (width, height) = fitted((rect.right - rect.left) as u32, (rect.bottom - rect.top) as u32, options.max.0, options.max.1);
        let mut view = View {
            gpu,
            capture,
            images: if options.jpeg { Some(Images::new().map_err(|e| failed(out, &e, "encoder"))?) } else { None },
            options,
            latest: None,
            latest_at: 0,
            fresh: false,
            wanted: 0,
            force_key: true,
            last_ts: 0,
            scaler: None,
            encoder: None,
            force_unheeded: false,
            config: Vec::new(),
            sps: Vec::new(),
            pps: Vec::new(),
            jpeg_size: (0, 0),
            staging: None,
            pushed_at: Instant::now(),
            looked: Instant::now(),
        };
        let encoder = if view.options.jpeg {
            "JPEG, quality 0.8".to_string()
        } else {
            let made = view.make_encoder(width, height).map_err(|e| failed(out, &e, "encoder"))?;
            made
        };
        out.json(1, json!({ "width": width, "height": height, "encoder": encoder }));
        Ok(view)
    }

    fn make_encoder(&mut self, width: u32, height: u32) -> windows::core::Result<String> {
        self.encoder = None;
        let bitrate = self.options.bitrate.unwrap_or((width * height * 3).max(1_000_000));
        let encoder = H264::new(&self.gpu, width, height, bitrate, self.options.software)?;
        let name = encoder.name.clone();
        // The parameter sets the output type names, for an encoder that puts none in band.
        let header = avc::picture(&encoder.header);
        if let (Some(sps), Some(pps)) = (header.sps, header.pps) {
            (self.sps, self.pps) = (sps, pps);
        }
        self.encoder = Some(encoder);
        self.force_key = true;
        Ok(name)
    }

    fn run(&mut self, rx: Receiver<Msg>, out: &Out) {
        loop {
            // Waiting on the encoder: looked at again in a moment; else until something comes.
            let busy = self.encoder.as_ref().is_some_and(|e| e.busy()) || (self.wanted > 0 && self.fresh);
            let msg = if busy {
                match rx.recv_timeout(Duration::from_millis(1)) {
                    Ok(m) => Some(m),
                    Err(RecvTimeoutError::Timeout) => None,
                    Err(RecvTimeoutError::Disconnected) => return,
                }
            } else {
                match rx.recv() {
                    Ok(m) => Some(m),
                    Err(_) => return,
                }
            };
            match msg {
                Some(Msg::Next) => self.wanted += 1,
                Some(Msg::Rate(bits)) => {
                    let bits = bits.max(100_000);
                    self.options.bitrate = Some(bits);
                    if let Some(encoder) = self.encoder.as_mut() {
                        encoder.rate(bits);
                    }
                }
                Some(Msg::Keyframe) => {
                    self.force_key = true;
                    // The same picture again, as a key frame, when the screen does not change.
                    if self.latest.is_some() {
                        self.fresh = true;
                    }
                }
                Some(Msg::Closed) => {
                    out.json(4, json!({ "stopped": "the display went" }));
                    return;
                }
                Some(Msg::Frame) => match self.capture.take(&self.gpu, &mut self.latest) {
                    Ok(Some(at)) => {
                        self.latest_at = at;
                        self.fresh = true;
                    }
                    Ok(None) => {}
                    Err(e) => {
                        out.json(4, json!({ "stopped": e.message() }));
                        return;
                    }
                },
                None => {}
            }
            // Another display made the main one: this view ends (the station opens the main one again), as its
            // input would go to the other.
            if self.looked.elapsed() > Duration::from_secs(1) {
                self.looked = Instant::now();
                if main_display().0 != self.capture.monitor {
                    out.json(4, json!({ "stopped": "another display is the main one now" }));
                    return;
                }
            }
            if let Err(e) = self.pump(out) {
                out.json(4, json!({ "stopped": e.message() }));
                return;
            }
        }
    }

    /// The scaler for the latest picture into `to`, made anew when either changed.
    fn scaled(&mut self, to: (u32, u32), format: DXGI_FORMAT) -> windows::core::Result<ID3D11Texture2D> {
        let latest = self.latest.clone().unwrap();
        let mut desc = Default::default();
        unsafe { latest.GetDesc(&mut desc) };
        let from = (desc.Width, desc.Height);
        if !self.scaler.as_ref().is_some_and(|s| s.from == from && s.to == to && s.format == format) {
            self.scaler = Some(Scaler::new(&self.gpu, from, to, format)?);
        }
        self.scaler.as_mut().unwrap().run(&self.gpu, &latest)
    }

    fn size_now(&self) -> (u32, u32) {
        let mut desc = Default::default();
        unsafe { self.latest.as_ref().unwrap().GetDesc(&mut desc) };
        fitted(desc.Width, desc.Height, self.options.max.0, self.options.max.1)
    }

    fn timestamp(&mut self) -> i64 {
        let ts = (self.last_ts + 1).max(self.latest_at);
        self.last_ts = ts;
        ts
    }

    fn pump(&mut self, out: &Out) -> windows::core::Result<()> {
        if self.options.jpeg {
            return self.pump_jpeg(out);
        }
        let mut done = Vec::new();
        if let Some(encoder) = self.encoder.as_mut() {
            done = encoder.poll()?;
        }
        for encoded in done {
            self.sent(encoded, out);
        }
        // A picture the encoder never gave back (a driver that dropped it): the view would wait for it for ever. The
        // encoder is made anew, and the picture owed comes from it as a key frame.
        if self.encoder.as_ref().is_some_and(|e| e.busy()) && self.pushed_at.elapsed() > STUCK {
            out.json(4, json!({ "encoder": "gave nothing back; made anew" }));
            self.encoder = None;
            self.wanted += 1;
            self.force_key = true;
            self.fresh = self.latest.is_some();
        }
        if self.wanted == 0 || !self.fresh || self.latest.is_none() {
            return Ok(());
        }
        let size = self.size_now();
        let remake = self.encoder.as_ref().is_none_or(|e| (e.width, e.height) != size) || (self.force_key && self.force_unheeded);
        if remake {
            if self.encoder.as_ref().is_some_and(|e| e.busy()) {
                return Ok(());
            }
            self.force_unheeded = false;
            self.make_encoder(size.0, size.1)?;
        }
        let mut early = Vec::new();
        let ready = self.encoder.as_mut().unwrap().ready(&mut early)?;
        for encoded in early {
            self.sent(encoded, out);
        }
        if !ready {
            return Ok(());
        }
        let texture = self.scaled(size, DXGI_FORMAT_NV12)?;
        let ts = self.timestamp();
        let key = self.force_key;
        self.encoder.as_mut().unwrap().push(&self.gpu, &texture, ts, key)?;
        self.pushed_at = Instant::now();
        self.wanted -= 1;
        self.fresh = false;
        self.force_key = false;
        Ok(())
    }

    /// One picture out: its config first when it changed.
    fn sent(&mut self, encoded: super::encode::Encoded, out: &Out) {
        let picture = avc::picture(&encoded.stream);
        if picture.data.is_empty() {
            return;
        }
        if let Some(sps) = picture.sps {
            self.sps = sps;
        }
        if let Some(pps) = picture.pps {
            self.pps = pps;
        }
        let key = picture.key || encoded.clean;
        if encoded.asked && !key {
            self.force_unheeded = true;
            self.force_key = true;
            self.fresh = self.latest.is_some();
        }
        if self.sps.len() < 4 || self.pps.is_empty() {
            return;
        }
        let (width, height) = self.encoder.as_ref().map(|e| (e.width, e.height)).unwrap_or((0, 0));
        let mut config = Vec::new();
        config.extend_from_slice(&width.to_be_bytes());
        config.extend_from_slice(&height.to_be_bytes());
        config.extend_from_slice(&avc::avcc(&self.sps, &self.pps));
        if config != self.config {
            out.send(2, &config);
            self.config = config;
        }
        let mut payload = Vec::with_capacity(9 + picture.data.len());
        payload.push(key as u8);
        payload.extend_from_slice(&(encoded.ts as u64).to_be_bytes());
        payload.extend_from_slice(&picture.data);
        out.send(3, &payload);
    }

    /// The latest picture as one JPEG, when one is wanted and it is new (or a key frame was asked for: every one is).
    fn pump_jpeg(&mut self, out: &Out) -> windows::core::Result<()> {
        while self.wanted > 0 && self.fresh && self.latest.is_some() {
            let size = self.size_now();
            let texture = self.scaled(size, DXGI_FORMAT_B8G8R8A8_UNORM)?;
            let (bytes, pitch) = self.gpu.read(&texture, &mut self.staging)?;
            let images = self.images.as_ref().unwrap();
            let jpeg = images.jpeg(&Pixels { width: size.0, height: size.1, pitch: pitch as u32, bytes: &bytes })?;
            self.wanted -= 1;
            self.fresh = false;
            self.force_key = false;
            if size != self.jpeg_size {
                self.jpeg_size = size;
                let mut config = Vec::new();
                config.extend_from_slice(&size.0.to_be_bytes());
                config.extend_from_slice(&size.1.to_be_bytes());
                out.send(2, &config);
            }
            let ts = self.timestamp();
            let mut payload = vec![1u8];
            payload.extend_from_slice(&(ts as u64).to_be_bytes());
            payload.extend_from_slice(&jpeg);
            out.send(3, &payload);
        }
        Ok(())
    }
}
