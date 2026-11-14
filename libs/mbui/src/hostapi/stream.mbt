// A picture the host decodes frame by frame (@ui's Stream: a remote screen's frames),
// drawn by the app as an image: H.264 (a config, the avcC and the picture's size, then access units in AVCC, each NAL
// after its length) or JPEG frames, each with its time `ts` (the sender's, only compared and handed back).
//
// The host decodes off the app's thread and says what came of each frame as an event (`stream_next`, taken as a frame
// begins): "f TS W H" a frame decoded, W × H pixels, ready to be shown; "d TS" frames up to TS let go undecoded (one a
// decoder could not take, one it held back behind another, those inside it as it started anew); "b" the decoder lost
// its state (an error, started anew): the next frame it can take is a key frame. Which frame the stream shows is the
// app's to say (`stream_show`, as it takes a decoded one's event): the host keeps a decoded frame until then, and draws
// the stream (an instance of kind 4 whose image is `stream_tex_base` + its id) with the last one shown. A host asks for
// a frame as an event comes.
//
// A host may have its H.264 decoder driven by the framework instead (`stream_feeds`: @ui's stream_feed.mbt): it then
// says what its decoder and its surface said ("c ..." events) and does what it is told (`stream_codec`), deciding
// nothing; its frames come as "queue" commands, not `stream_frame`, and its first config makes its first surface (1).
//
// Hosts: Android (Streams.java: MediaCodec onto a SurfaceTexture, driven by the framework, copied into a texture of the
// frame's size as it is shown; JPEG by BitmapFactory), macOS and iOS (apple_stream.m: VideoToolbox into Metal-compatible pixel buffers;
// JPEG by ImageIO), the browser (web/host.js: WebCodecs' VideoDecoder where there is one; JPEG by createImageBitmap),
// Windows (win_stream.cpp: H.264 by Media Foundation's decoder, where the system has it, H.265 and AV1 by the system's
// own where installed; JPEG by WIC), Linux (linux_stream.c: H.264 by GStreamer's
// decodebin, live, where it has a decoder of it; JPEG by gdk-pixbuf).
//
// A frame decoded and not shown (`stream_frame_shown`: what a seek decodes up to its picture) and a decoder emptied
// (`stream_flush`) are Windows' alone so far, as are its sound's clock and volume (`stream_audio_played`, `_queued`,
// `_volume`). The other hosts that decode take a frame not to be shown as any (decoded, so what comes after it has
// what it refers to; said "f", which ui's Stream takes as "d" and never shows) and have nothing for the rest; a host
// with no decoder at all (Host's defaults) does not take one.

///|
/// What an instance's image (scene.mbt's slot 20) is when it draws a stream: this plus the stream's id (images' own ids
/// stay below it; exact in the renderers' 32-bit floats).
pub let stream_tex_base : Int = 4194304

///|
/// A new stream: its id (from 1, in the order opened, as every host numbers them), 0 where the host has none.
pub fn stream_open() -> Int {
  st_open()
}

///|
/// A config for H.264: its avcC and the picture's size. The decoder starts anew (what was in it let go: "d"), from the
/// next key frame.
pub fn stream_h264(id : Int, avcc : Bytes, w : Int, h : Int) -> Unit {
  st_h264(id, avcc, w, h)
}

///|
/// An H.264 access unit (AVCC), a key frame or not.
pub fn stream_frame(id : Int, data : Bytes, key : Bool, ts : Double) -> Unit {
  st_frame(id, data, if key { 1 } else { 0 }, ts)
}

///|
/// An access unit as `stream_frame`'s, `show` false one decoded for the frames after it (what they refer to) and never
/// shown: once out of the decoder it is not copied, kept or shown, and is said "d TS" with no frame asked for it (the app
/// takes it as its next frame begins). Windows' alone decodes one unseen; the other hosts that decode take it as any
/// frame (said "f": ui's Stream lets it go and never shows it). Whether the host took it: false only where it decodes
/// nothing (the app lets it go itself then).
pub fn stream_frame_shown(id : Int, data : Bytes, key : Bool, ts : Double, show : Bool) -> Bool {
  st_frame_shown(id, data, if key { 1 } else { 0 }, ts, if show { 1 } else { 0 }) != 0
}

///|
/// Stream `id`'s decoder emptied, in its place among the frames handed over (a seek). `drain` false: what is in it let
/// go, each said "d" and none shown. `drain` true: what is in it decoded out first, each said as it would have been
/// ("f", or "d" for one not to be shown), then emptied. Either way the decoder is kept, the frame shown stays, and the
/// next frame it takes is a key frame (one that is not, let go: "d"). Windows' alone; elsewhere nothing.
pub fn stream_flush(id : Int, drain : Bool) -> Unit {
  st_flush(id, if drain { 1 } else { 0 })
}

///|
/// A JPEG frame.
pub fn stream_jpeg(id : Int, data : Bytes, ts : Double) -> Unit {
  st_jpeg(id, data, ts)
}

///|
/// The oldest event not taken yet ("f TS W H", "d TS", "b"), "" when there is none.
pub fn stream_next(id : Int) -> String {
  st_next(id)
}

///|
/// The stream shows its decoded frame of `ts` from now on (its "f" event taken): those decoded before it let go.
pub fn stream_show(id : Int, ts : Double) -> Unit {
  st_show(id, ts)
}

///|
/// Gone: its decoder stopped, its frames let go, nothing more said of it.
pub fn stream_close(id : Int) -> Unit {
  st_close(id)
}

///|
/// Whether this host decodes H.264 (else a stream takes JPEG only: the sender is asked for that).
pub fn h264_here() -> Bool {
  st_h264_here() != 0
}

///|
/// Whether this host's H.264 decoder is driven by the framework (@ui's stream_feed.mbt): its events "c ...", its
/// commands `stream_codec`.
pub fn stream_feeds() -> Bool {
  st_feeds() != 0
}

///|
/// A command for stream `id`'s decoder or surface (@ui's stream_feed.mbt says which), with a frame's bytes for "queue".
pub fn stream_codec(id : Int, cmd : String, data : Bytes) -> Unit {
  st_codec(id, cmd, data)
}

///|
/// Whether this host decodes H.265 (a stream's sender is then asked for it first).
pub fn h265_here() -> Bool { st_h265_here() != 0 }

///|
/// A config for H.265: its hvcC and the picture's size, as `stream_h264`'s; its access units go to `stream_frame`
/// (each NAL after its length). Only where `h265_here`.
pub fn stream_hevc(id : Int, hvcc : Bytes, w : Int, h : Int) -> Unit { st_hevc(id, hvcc, w, h) }

///|
/// Whether this host decodes AV1 (8-bit 4:2:0: a recording's picture). Asked before an AV1 stream is opened: where it
/// does not (Windows without the AV1 Video Extension, every other host so far) the app plays it another way.
pub fn av1_here() -> Bool { st_av1_here() != 0 }

///|
/// A config for AV1: its av1C (AV1-ISOBMFF's AV1CodecConfigurationRecord, as an MP4's `av1C` box holds it after its
/// header) or its OBUs alone (a sequence header), and the picture's size, as `stream_h264`'s; its temporal units go to
/// `stream_frame` as an MP4's samples hold them (OBUs, each with its size; no temporal delimiter needed), a key frame
/// with no sequence header of its own given the config's. Only where `av1_here`. Windows' alone so far.
pub fn stream_av1(id : Int, av1c : Bytes, w : Int, h : Int) -> Unit { st_av1(id, av1c, w, h) }

///|
/// Whether the host plays a stream's 48 kHz stereo PCM16 system audio.
pub fn stream_audio_here() -> Bool { st_audio_here() != 0 }

///|
/// One 20 ms packet (3840 bytes, interleaved little-endian PCM16). Empty: stop and discard queued sound.
/// Hosts bound queued audio and drop stale sound; closing the stream releases its player too.
pub fn stream_audio(id : Int, data : Bytes) -> Unit { st_audio(id, data) }

///|
/// Samples (48 kHz frames) of stream `id`'s sound played since its sound began: counted on across its sound stopped
/// and started again (an empty packet), set back only as the stream closes, so an app keeps its own base where it wants
/// another start. 0 where the host plays none (Windows' alone counts it).
pub fn stream_audio_played(id : Int) -> Double { st_audio_played(id) }

///|
/// Milliseconds of stream `id`'s sound queued and not played yet (20 a packet). 0 where there is none, or the host
/// says none (Windows' alone says it).
pub fn stream_audio_queued(id : Int) -> Double { st_audio_queued(id) }

///|
/// Stream `id`'s sound played at volume `v` (1 as it came, 0 silent), from now and for its sound started later too.
/// Windows' alone; elsewhere nothing.
pub fn stream_audio_volume(id : Int, v : Double) -> Unit { st_audio_volume(id, v) }

///|
/// Whether a stream's H.264 frames may be shown by a system video layer of the host's own (a native view of kind 4,
/// its argument the stream's id: @ui's Stream with `layer`), under the canvas where the app paints its hole: each
/// frame shown (`stream_show`) put on that layer as well, nothing of the app drawn for it. macOS and iOS
/// (apple_views.m: a layer whose contents are the decoded frame's IOSurface), Windows (win_stream.cpp: a composition
/// swap chain in the views' DirectComposition tree, the frame put there by the GPU); none elsewhere.
pub fn stream_layers() -> Bool {
  st_layers() != 0
}

///|
/// Whether that layer shows a frame in the colours its stream is tagged with (Display P3's wider than sRGB's): the
/// host's st_layers 1 (Apple's); 2 a layer that shows it as sRGB (Windows'), whose station is not asked for more.
pub fn stream_layers_tagged() -> Bool {
  st_layers() == 1
}

///|
/// A pointer drawn by the host over stream `id`'s picture on its system video layer (`stream_layers`), composited with
/// it by the system: its picture named `key`, `png` making it (a PNG; empty: none), `w` × `h` points whatever the picture's size, its hot spot
/// (`hx`, `hy` points in from its top left) where it points. Moved by `stream_pointer_at`, nothing of the app drawn for
/// it. Hosts without layers draw none (the app draws its own).
pub fn stream_pointer(
  id : Int,
  key : String,
  png : () -> Bytes,
  w : Double,
  h : Double,
  hx : Double,
  hy : Double,
) -> Unit {
  current.val.st_pointer_named(id, key, png, w, h, hx, hy)
}

///|
/// Where stream `id`'s pointer (`stream_pointer`) points: (`x`, `y`) of its picture on its layer (0..1 of the rect the
/// layer is placed at, outside it too), `shown` false none; it goes where the layer goes (zoomed, panned) by itself.
pub fn stream_pointer_at(id : Int, x : Double, y : Double, shown : Bool) -> Unit {
  st_pointer_at(id, x, y, if shown { 1 } else { 0 })
}

///|
/// Stream `id` takes the frames (`video`) and the sound (`audio`) of route `route` straight from the app's engine, where
/// one reads them itself (still.fail's shell reads a remote screen: its view's call is the route), from the record after
/// the `after`th it offered, when that one is the last it offered (nothing of the route left in the app's queue: else
/// nothing changes, and the app routes it again as it takes the next); those not asked for no longer. Taken so, a frame
/// is decoded, shown and acknowledged by the host, a packet played, nothing of the app's run for them; the app is told
/// what came in one event when it next reads the stream's (`D TS N BYTES`: @ui's Stream). A config of the route stops
/// it until the app routes it again. macOS and iOS (apple_stream.m), Windows (win_stream.cpp), Android
/// (android_host.c); elsewhere nothing, the app takes them all.
pub fn stream_direct(id : Int, route : Double, after : Double, video~ : Bool, audio~ : Bool) -> Unit {
  st_direct(id, route, after, (if video { 1 } else { 0 }) + (if audio { 2 } else { 0 }))
}
