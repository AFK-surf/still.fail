// System output (never the microphone), pulled in bounded PCM packets alongside a screen view.
// WASAPI loopback stays in shared mode, so it neither changes nor takes over the person's output device.
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::Duration;
use windows::Win32::Media::Audio::*;
use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_ALL, COINIT_MULTITHREADED};
use super::{Out, audio_queue::AudioQueue};

const RATE: u32 = 48_000;
const CHANNELS: u16 = 2;
const FRAME_BYTES: usize = CHANNELS as usize * 2;
const PACKET_FRAMES: usize = 960; // 20 ms
const PACKET_BYTES: usize = PACKET_FRAMES * FRAME_BYTES;

pub struct Audio { next: Sender<()> }
impl Audio {
    pub fn start(out: Out) -> Self {
        let (tx, rx) = channel();
        std::thread::spawn(move || {
            unsafe {
                if CoInitializeEx(None, COINIT_MULTITHREADED).is_err() {
                    out.json(8, serde_json::json!({"error":"audio COM initialization failed"}));
                    return;
                }
                if let Err(e) = run(rx, &out) {
                    out.json(8, serde_json::json!({"error":e.message()}));
                }
                CoUninitialize();
            }
        });
        Self { next: tx }
    }
    pub fn next(&self) { let _ = self.next.send(()); }
}

unsafe fn run(rx: Receiver<()>, out: &Out) -> windows::core::Result<()> {
    unsafe {
        let devices: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let device = devices.GetDefaultAudioEndpoint(eRender, eConsole)?;
        let client: IAudioClient = device.Activate(CLSCTX_ALL, None)?;
        let format = WAVEFORMATEX { wFormatTag: 1, nChannels: CHANNELS, nSamplesPerSec: RATE,
            nAvgBytesPerSec: RATE * FRAME_BYTES as u32, nBlockAlign: FRAME_BYTES as u16, wBitsPerSample: 16, cbSize: 0 };
        client.Initialize(AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
            2_000_000, 0, &format, None)?;
        let capture: IAudioCaptureClient = client.GetService()?;
        client.Start()?;
        out.json(8, serde_json::json!({"codec":"pcm_s16le","sampleRate":RATE,"channels":CHANNELS}));
        let result = packets(&capture, rx, out);
        let _ = client.Stop();
        result
    }
}

unsafe fn packets(capture: &IAudioCaptureClient, rx: Receiver<()>, out: &Out) -> windows::core::Result<()> {
    // Drain WASAPI without discarding packets within a normal capture or network burst.
    let mut building = Vec::with_capacity(PACKET_BYTES);
    let mut queued = AudioQueue::new();
    let mut packet_ts = 0;
    let mut wanted = false;
    loop {
        match rx.recv_timeout(Duration::from_millis(5)) {
            Ok(()) => wanted = true,
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
        }
        while rx.try_recv().is_ok() { wanted = true; }
        unsafe {
            while capture.GetNextPacketSize()? > 0 {
                let mut data = std::ptr::null_mut();
                let mut frames = 0;
                let mut flags = 0;
                let mut qpc = 0;
                capture.GetBuffer(&mut data, &mut frames, &mut flags, None, Some(&mut qpc))?;
                if flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY.0 as u32 != 0 { building.clear(); }
                let silent = flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32 != 0;
                let size = frames as usize * FRAME_BYTES;
                // A packet from the system is bounded by its endpoint buffer. Copy before releasing that buffer.
                for offset in 0..size {
                    if building.is_empty() { packet_ts = qpc / 10 + (offset / FRAME_BYTES) as u64 * 1_000_000 / RATE as u64; }
                    building.push(if silent || data.is_null() { 0 } else { *data.add(offset) });
                    if building.len() == PACKET_BYTES {
                        queued.push((packet_ts,
                            std::mem::replace(&mut building, Vec::with_capacity(PACKET_BYTES))));
                    }
                }
                capture.ReleaseBuffer(frames)?;
            }
        }
        if wanted {
            if let Some((ts, data)) = queued.pop() {
                let mut payload = Vec::with_capacity(8 + data.len());
                payload.extend_from_slice(&ts.to_be_bytes());
                payload.extend_from_slice(&data);
                out.send(9, &payload);
                wanted = false;
            }
        }
    }
}
