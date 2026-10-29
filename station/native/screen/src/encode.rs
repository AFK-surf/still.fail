// H.264 with Media Foundation: the hardware encoder (an asynchronous MFT, given the D3D11 textures themselves) where
// the machine has one that takes them, else Microsoft's software encoder (given each picture's bytes). H.265 the same
// way, on the hardware only (Main; where the machine has no HEVC encoder, the view goes on in H.264). Low latency (a
// picture out for each in), no B-frames, constrained baseline where the encoder has it, a key frame when asked for and
// at least every 10 s besides. One picture is in it at a time: the view asks for the next only once one went. A still
// screen's picture sent again as a key frame (docs/remote-screens.md "Still") is encoded finer than the moving ones: its
// QP no higher than STILL_QP and twice the bit rate for it, where the link carries STILL_FROM or more.
use std::collections::VecDeque;

use windows::Win32::Graphics::Direct3D11::ID3D11Texture2D;
use windows::Win32::Media::MediaFoundation::*;
use windows::Win32::System::Com::{CLSCTX_INPROC_SERVER, CoCreateInstance, CoTaskMemFree};
use windows::Win32::System::Variant::VARIANT;
use windows::core::{GUID, Interface, PWSTR, Result};

use super::capture::Gpu;

/// One picture out: Annex B, its time (µs), whether the encoder marked it a key frame.
pub struct Encoded {
    pub stream: Vec<u8>,
    pub ts: i64,
    pub clean: bool,
    /// A key frame was asked of this one.
    pub asked: bool,
}

pub struct H264 {
    transform: IMFTransform,
    /// The asynchronous (hardware) encoder's events; none for the synchronous one.
    events: Option<IMFMediaEventGenerator>,
    codec: Option<ICodecAPI>,
    /// Takes D3D11 textures (else the picture's bytes, read back).
    gpu: bool,
    provides: bool,
    output_size: u32,
    /// Inputs the asynchronous encoder asked for and was not given yet.
    credits: u32,
    /// What was given and not come out yet: its time and whether a key frame was asked of it.
    pending: VecDeque<(i64, bool)>,
    staging: Option<ID3D11Texture2D>,
    pub width: u32,
    pub height: u32,
    pub name: String,
    /// H.265 (else H.264).
    pub hevc: bool,
    /// The parameter sets the output type names (an encoder that does not put them in band).
    pub header: Vec<u8>,
    /// The bit rate asked, and whether the picture in it is a still one's, encoded finer (`push`'s `still`).
    bitrate: u32,
    finer: bool,
    _manager: Option<IMFDXGIDeviceManager>,
}

const FPS: u32 = 60;
/// A still picture's key frame: its QP at most this (of 51), at STILL_BOOST times the bit rate, where the bit rate asked
/// is STILL_FROM or more (a narrow link's would take seconds to go).
const STILL_QP: u32 = 28;
const MOVING_QP: u32 = 51;
const STILL_BOOST: u32 = 2;
const STILL_FROM: u32 = 4_000_000;

fn set(codec: &ICodecAPI, api: &GUID, value: VARIANT) -> bool {
    unsafe { codec.SetValue(api, &value).is_ok() }
}

/// The hardware encoders that take NV12 to H.264 (or H.265), best first.
fn hardware(hevc: bool) -> Vec<IMFActivate> {
    let input = MFT_REGISTER_TYPE_INFO { guidMajorType: MFMediaType_Video, guidSubtype: MFVideoFormat_NV12 };
    let output = MFT_REGISTER_TYPE_INFO { guidMajorType: MFMediaType_Video, guidSubtype: if hevc { MFVideoFormat_HEVC } else { MFVideoFormat_H264 } };
    let mut found: *mut Option<IMFActivate> = std::ptr::null_mut();
    let mut count = 0u32;
    let mut all = Vec::new();
    unsafe {
        if MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER, Some(&input), Some(&output), &mut found, &mut count).is_err() || found.is_null() {
            return all;
        }
        for i in 0..count as usize {
            if let Some(activate) = (*found.add(i)).take() {
                all.push(activate);
            }
        }
        CoTaskMemFree(Some(found as _));
    }
    all
}

fn friendly(activate: &IMFActivate) -> String {
    let mut name = PWSTR::null();
    let mut length = 0u32;
    unsafe {
        if activate.GetAllocatedString(&MFT_FRIENDLY_NAME_Attribute, &mut name, &mut length).is_ok() && !name.is_null() {
            let s = name.to_string().unwrap_or_default();
            CoTaskMemFree(Some(name.0 as _));
            return s;
        }
    }
    "hardware".into()
}

impl H264 {
    /// The best H.265 encoder there is for `width`×`height`, on the hardware; an error where there is none.
    pub fn hevc(gpu: &Gpu, width: u32, height: u32, bitrate: u32) -> Result<H264> {
        let mut last = None;
        for activate in hardware(true) {
            let name = friendly(&activate);
            match unsafe { activate.ActivateObject::<IMFTransform>() }.and_then(|t| H264::open(gpu, t, true, true, width, height, bitrate, name)) {
                Ok(encoder) => return Ok(encoder),
                Err(error) => {
                    unsafe {
                        let _ = activate.ShutdownObject();
                    }
                    last = Some(error);
                }
            }
        }
        Err(last.unwrap_or_else(|| windows::core::Error::new(MF_E_TOPO_CODEC_NOT_FOUND, "no H.265 encoder on this machine's hardware")))
    }

    /// The best encoder there is for `width`×`height`: hardware first (unless `software`), then software.
    pub fn new(gpu: &Gpu, width: u32, height: u32, bitrate: u32, software: bool) -> Result<H264> {
        let mut last = None;
        for activate in if software { Vec::new() } else { hardware(false) } {
            let name = friendly(&activate);
            match unsafe { activate.ActivateObject::<IMFTransform>() }.and_then(|t| H264::open(gpu, t, true, false, width, height, bitrate, name)) {
                Ok(encoder) => return Ok(encoder),
                Err(error) => {
                    unsafe {
                        let _ = activate.ShutdownObject();
                    }
                    last = Some(error);
                }
            }
        }
        let software: Result<IMFTransform> = unsafe { CoCreateInstance(&CLSID_MSH264EncoderMFT, None, CLSCTX_INPROC_SERVER) };
        match software.and_then(|t| H264::open(gpu, t, false, false, width, height, bitrate, "Microsoft H.264 (software)".into())) {
            Ok(encoder) => Ok(encoder),
            Err(error) => Err(last.unwrap_or(error)),
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn open(gpu: &Gpu, transform: IMFTransform, hardware: bool, hevc: bool, width: u32, height: u32, bitrate: u32, name: String) -> Result<H264> {
        unsafe {
            let attributes = transform.GetAttributes().ok();
            let asynchronous = attributes.as_ref().and_then(|a| a.GetUINT32(&MF_TRANSFORM_ASYNC).ok()).unwrap_or(0) != 0;
            if asynchronous {
                attributes.as_ref().unwrap().SetUINT32(&MF_TRANSFORM_ASYNC_UNLOCK, 1)?;
            }
            if let Some(a) = attributes.as_ref() {
                let _ = a.SetUINT32(&MF_LOW_LATENCY, 1);
            }
            // The hardware encoder reads the textures on the device; without it, it is not used (the software one is).
            let mut manager = None;
            let mut gpu_input = false;
            if hardware {
                let mut token = 0u32;
                let mut made = None;
                MFCreateDXGIDeviceManager(&mut token, &mut made)?;
                let made = made.unwrap();
                made.ResetDevice(&gpu.device, token)?;
                transform.ProcessMessage(MFT_MESSAGE_SET_D3D_MANAGER, made.as_raw() as usize)?;
                manager = Some(made);
                gpu_input = true;
            }
            let codec = transform.cast::<ICodecAPI>().ok();
            if let Some(c) = codec.as_ref() {
                set(c, &CODECAPI_AVLowLatencyMode, VARIANT::from(true));
                let _ = set(c, &CODECAPI_AVEncCommonRateControlMode, VARIANT::from(eAVEncCommonRateControlMode_LowDelayVBR.0 as u32))
                    || set(c, &CODECAPI_AVEncCommonRateControlMode, VARIANT::from(eAVEncCommonRateControlMode_CBR.0 as u32));
                set(c, &CODECAPI_AVEncCommonMeanBitRate, VARIANT::from(bitrate));
                set(c, &CODECAPI_AVEncMPVDefaultBPictureCount, VARIANT::from(0u32));
                set(c, &CODECAPI_AVEncMPVGOPSize, VARIANT::from(FPS * 10));
            }
            let size = ((width as u64) << 32) | height as u64;
            let rate = ((FPS as u64) << 32) | 1;
            // H.264: constrained baseline, as every decoder takes it; baseline, then main (no B-frames asked) where not.
            // H.265: Main, 8 bits 4:2:0.
            let mut profile = "";
            let profiles: &[(u32, &str)] = if hevc {
                &[(eAVEncH265VProfile_Main_420_8.0 as u32, "H.265 main")]
            } else {
                &[(eAVEncH264VProfile_ConstrainedBase.0 as u32, "constrained baseline"), (eAVEncH264VProfile_Base.0 as u32, "baseline"), (eAVEncH264VProfile_Main.0 as u32, "main")]
            };
            for &(p, named) in profiles {
                let output = MFCreateMediaType()?;
                output.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
                output.SetGUID(&MF_MT_SUBTYPE, if hevc { &MFVideoFormat_HEVC } else { &MFVideoFormat_H264 })?;
                output.SetUINT32(&MF_MT_AVG_BITRATE, bitrate)?;
                output.SetUINT64(&MF_MT_FRAME_SIZE, size)?;
                output.SetUINT64(&MF_MT_FRAME_RATE, rate)?;
                output.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, (1u64 << 32) | 1)?;
                output.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
                output.SetUINT32(&MF_MT_MPEG2_PROFILE, p)?;
                output.SetUINT32(&MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709.0 as u32)?;
                output.SetUINT32(&MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709.0 as u32)?;
                output.SetUINT32(&MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709.0 as u32)?;
                output.SetUINT32(&MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235.0 as u32)?;
                if transform.SetOutputType(0, &output, 0).is_ok() {
                    profile = named;
                    break;
                }
            }
            if profile.is_empty() {
                return Err(windows::core::Error::new(MF_E_INVALIDMEDIATYPE, "the encoder takes no profile asked"));
            }
            let input = MFCreateMediaType()?;
            input.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
            input.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_NV12)?;
            input.SetUINT64(&MF_MT_FRAME_SIZE, size)?;
            input.SetUINT64(&MF_MT_FRAME_RATE, rate)?;
            input.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, (1u64 << 32) | 1)?;
            input.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
            transform.SetInputType(0, &input, 0)?;
            let info = transform.GetOutputStreamInfo(0)?;
            let provides = info.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES.0 as u32 | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES.0 as u32) != 0;
            transform.ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0)?;
            transform.ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0)?;
            let header = transform
                .GetOutputCurrentType(0)
                .ok()
                .and_then(|t| {
                    let n = t.GetBlobSize(&MF_MT_MPEG_SEQUENCE_HEADER).ok()?;
                    let mut blob = vec![0u8; n as usize];
                    t.GetBlob(&MF_MT_MPEG_SEQUENCE_HEADER, &mut blob, None).ok()?;
                    Some(blob)
                })
                .unwrap_or_default();
            let events = if asynchronous { Some(transform.cast::<IMFMediaEventGenerator>()?) } else { None };
            Ok(H264 {
                transform,
                events,
                codec,
                gpu: gpu_input,
                provides,
                output_size: info.cbSize.max(width * height * 2),
                credits: 0,
                pending: VecDeque::new(),
                staging: None,
                width,
                height,
                name: format!("{name}, {profile}, {bitrate} bps"),
                hevc,
                header,
                bitrate,
                finer: false,
                _manager: manager,
            })
        }
    }

    /// From the next frame on, about this many bits a second (an encoder that cannot change it as it goes keeps its own).
    pub fn rate(&mut self, bitrate: u32) {
        self.bitrate = bitrate;
        if let Some(c) = self.codec.as_ref() {
            set(c, &CODECAPI_AVEncCommonMeanBitRate, VARIANT::from(if self.finer { bitrate.saturating_mul(STILL_BOOST) } else { bitrate }));
        }
    }

    /// The pictures from the next on encoded finer (a still one's key frame) or as the moving ones are. An encoder that
    /// takes no QP bound keeps its own (the bit rate's rise alone).
    fn finer(&mut self, on: bool) {
        if on == self.finer {
            return;
        }
        self.finer = on;
        if let Some(c) = self.codec.as_ref() {
            set(c, &CODECAPI_AVEncVideoMaxQP, VARIANT::from(if on { STILL_QP } else { MOVING_QP }));
            set(c, &CODECAPI_AVEncCommonMeanBitRate, VARIANT::from(if on { self.bitrate.saturating_mul(STILL_BOOST) } else { self.bitrate }));
        }
    }

    /// A picture is in it, not out yet.
    pub fn busy(&self) -> bool {
        !self.pending.is_empty()
    }

    /// Whether it takes a picture now (the asynchronous encoder: once it asked for one).
    pub fn ready(&mut self, out: &mut Vec<Encoded>) -> Result<bool> {
        self.drain(out)?;
        Ok(self.pending.is_empty() && (self.events.is_none() || self.credits > 0))
    }

    /// `texture` (NV12, its size) in, at `ts` (µs), a key frame when `key`; `still`: the same picture again (the screen
    /// at rest), encoded finer.
    pub fn push(&mut self, gpu: &Gpu, texture: &ID3D11Texture2D, ts: i64, key: bool, still: bool) -> Result<()> {
        self.finer(key && still && self.bitrate >= STILL_FROM);
        unsafe {
            let buffer = if self.gpu {
                let buffer = MFCreateDXGISurfaceBuffer(&ID3D11Texture2D::IID, texture, 0, false)?;
                if let Ok(two) = buffer.cast::<IMF2DBuffer>() {
                    buffer.SetCurrentLength(two.GetContiguousLength()?)?;
                }
                buffer
            } else {
                let (bytes, pitch) = gpu.read(texture, &mut self.staging)?;
                let (w, h) = (self.width as usize, self.height as usize);
                let length = w * h * 3 / 2;
                let buffer = MFCreateMemoryBuffer(length as u32)?;
                let mut to = std::ptr::null_mut();
                buffer.Lock(&mut to, None, None)?;
                for row in 0..h * 3 / 2 {
                    std::ptr::copy_nonoverlapping(bytes.as_ptr().add(row * pitch), to.add(row * w), w);
                }
                buffer.Unlock()?;
                buffer.SetCurrentLength(length as u32)?;
                buffer
            };
            let sample = MFCreateSample()?;
            sample.AddBuffer(&buffer)?;
            sample.SetSampleTime(ts * 10)?;
            sample.SetSampleDuration(10_000_000 / FPS as i64)?;
            if key {
                if let Some(c) = self.codec.as_ref() {
                    set(c, &CODECAPI_AVEncVideoForceKeyFrame, VARIANT::from(1u32));
                }
            }
            self.transform.ProcessInput(0, &sample, 0)?;
            self.credits = self.credits.saturating_sub(1);
            self.pending.push_back((ts, key));
        }
        Ok(())
    }

    /// What came out since.
    pub fn poll(&mut self) -> Result<Vec<Encoded>> {
        let mut out = Vec::new();
        self.drain(&mut out)?;
        if self.events.is_none() {
            while let Some(e) = self.output()? {
                out.push(e);
            }
        }
        Ok(out)
    }

    fn drain(&mut self, out: &mut Vec<Encoded>) -> Result<()> {
        let Some(events) = self.events.clone() else { return Ok(()) };
        loop {
            let event = match unsafe { events.GetEvent(MF_EVENT_FLAG_NO_WAIT) } {
                Ok(e) => e,
                Err(e) if e.code() == MF_E_NO_EVENTS_AVAILABLE => return Ok(()),
                Err(e) => return Err(e),
            };
            let kind = unsafe { event.GetType()? };
            if kind == METransformNeedInput.0 as u32 {
                self.credits += 1;
            } else if kind == METransformHaveOutput.0 as u32 {
                if let Some(e) = self.output()? {
                    out.push(e);
                }
            }
        }
    }

    fn output(&mut self) -> Result<Option<Encoded>> {
        unsafe {
            let given = if self.provides {
                None
            } else {
                let sample = MFCreateSample()?;
                sample.AddBuffer(&MFCreateMemoryBuffer(self.output_size)?)?;
                Some(sample)
            };
            let mut buffers = [MFT_OUTPUT_DATA_BUFFER { dwStreamID: 0, pSample: std::mem::ManuallyDrop::new(given), dwStatus: 0, pEvents: std::mem::ManuallyDrop::new(None) }];
            let mut status = 0u32;
            let done = self.transform.ProcessOutput(0, &mut buffers, &mut status);
            let [buffer] = buffers;
            let sample = std::mem::ManuallyDrop::into_inner(buffer.pSample);
            drop(std::mem::ManuallyDrop::into_inner(buffer.pEvents));
            match done {
                Ok(()) => {}
                Err(e) if e.code() == MF_E_TRANSFORM_NEED_MORE_INPUT => return Ok(None),
                Err(e) if e.code() == MF_E_TRANSFORM_STREAM_CHANGE => {
                    // The encoder chose its output anew: taken as it offers it.
                    let offered = self.transform.GetOutputAvailableType(0, 0)?;
                    self.transform.SetOutputType(0, &offered, 0)?;
                    return Ok(None);
                }
                Err(e) => return Err(e),
            }
            let Some(sample) = sample else { return Ok(None) };
            let contiguous = sample.ConvertToContiguousBuffer()?;
            let mut from = std::ptr::null_mut();
            let mut length = 0u32;
            contiguous.Lock(&mut from, None, Some(&mut length))?;
            let stream = std::slice::from_raw_parts(from, length as usize).to_vec();
            contiguous.Unlock()?;
            let clean = sample.GetUINT32(&MFSampleExtension_CleanPoint).unwrap_or(0) != 0;
            let time = sample.GetSampleTime().map(|t| t / 10).ok();
            // Matched to what went in: the oldest given (its time, as the encoder may round it).
            let (ts, asked) = self.pending.pop_front().unwrap_or((time.unwrap_or(0), false));
            Ok(Some(Encoded { stream, ts, clean, asked }))
        }
    }
}

impl Drop for H264 {
    fn drop(&mut self) {
        unsafe {
            let _ = self.transform.ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
            let _ = self.transform.ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
            if let Ok(shutdown) = self.transform.cast::<IMFShutdown>() {
                let _ = shutdown.Shutdown();
            }
        }
    }
}
