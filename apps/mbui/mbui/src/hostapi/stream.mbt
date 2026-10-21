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
// Hosts: Android (Streams.java: MediaCodec onto a SurfaceTexture, copied into a texture of the frame's size as it is
// shown; JPEG by BitmapFactory), macOS and iOS (apple_stream.m: VideoToolbox into Metal-compatible pixel buffers;
// JPEG by ImageIO), the browser (web/host.js: WebCodecs' VideoDecoder where there is one; JPEG by createImageBitmap),
// Windows (win_stream.cpp: JPEG by WIC; no H.264, `h264_here` false).

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
