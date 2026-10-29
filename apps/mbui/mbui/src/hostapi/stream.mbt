// A picture the host decodes frame by frame (@ui's Stream: a remote screen's frames, still.fail's docs/remote-screens.md),
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
// Windows (win_stream.cpp: H.264 by Media Foundation's decoder, where the system has it; JPEG by WIC), Linux (linux_stream.c: H.264 by GStreamer's
// decodebin, live, where it has a decoder of it; JPEG by gdk-pixbuf).

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
/// Whether the host plays a stream's 48 kHz stereo PCM16 system audio.
pub fn stream_audio_here() -> Bool { st_audio_here() != 0 }

///|
/// One 20 ms packet (3840 bytes, interleaved little-endian PCM16). Empty: stop and discard queued sound.
/// Hosts bound queued audio and drop stale sound; closing the stream releases its player too.
pub fn stream_audio(id : Int, data : Bytes) -> Unit { st_audio(id, data) }

///|
/// Whether a stream's H.264 frames may be shown by a system video layer of the host's own (a native view of kind 4,
/// its argument the stream's id: @ui's Stream with `layer`), under the canvas where the app paints its hole: each
/// frame shown (`stream_show`) put on that layer as well, nothing of the app drawn for it. macOS and iOS
/// (apple_views.m: a layer whose contents are the decoded frame's IOSurface); none elsewhere.
pub fn stream_layers() -> Bool {
  st_layers() != 0
}

///|
/// A pointer drawn by the host over stream `id`'s picture on its system video layer (`stream_layers`), composited with
/// it by the system: its picture `png` (a PNG; empty: none), `w` × `h` points whatever the picture's size, its hot spot
/// (`hx`, `hy` points in from its top left) where it points. Moved by `stream_pointer_at`, nothing of the app drawn for
/// it. Hosts without layers draw none (the app draws its own).
pub fn stream_pointer(id : Int, png : Bytes, w : Double, h : Double, hx : Double, hy : Double) -> Unit {
  st_pointer(id, png, w, h, hx, hy)
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
/// it until the app routes it again. macOS and iOS (apple_stream.m); elsewhere nothing, the app takes them all.
pub fn stream_direct(id : Int, route : Double, after : Double, video~ : Bool, audio~ : Bool) -> Unit {
  st_direct(id, route, after, (if video { 1 } else { 0 }) + (if audio { 2 } else { 0 }))
}
