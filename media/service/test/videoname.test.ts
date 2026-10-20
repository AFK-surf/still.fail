// What the video library makes of names and files without ffmpeg (src/videoname.ts, subtitles.ts, hls.ts, ffmpeg.ts):
// films' and episodes' names (English and Chinese, as releases name them), seasons' and shows' folders, Kodi's .nfo,
// subtitles beside a video and their WebVTT, ffprobe's JSON, the play decision, and where a segment's fragments go.
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseProbe } from "../src/ffmpeg.ts";
import { clientOf, decide, placeFragments, splitFragmented } from "../src/hls.ts";
import { assToVtt, srtToVtt, subtitlesOf, toVtt } from "../src/subtitles.ts";
import { numberOf, parseEpisodeName, parseMovieName, parseNfo, parseSeasonDir, parseShowDir, showKey } from "../src/videoname.ts";
import { box, gb18030 } from "./helpers.ts";

test("film names: title and year out of release names, Chinese and English titles apart, sites and groups gone", () => {
  const cases: [string, { title: string; originalTitle?: string; year?: number }][] = [
    ["The.Matrix.1999.1080p.BluRay.x264-YTS", { title: "The Matrix", year: 1999 }],
    ["Inception (2010) [1080p] [BluRay] [5.1] [YTS.MX]", { title: "Inception", year: 2010 }],
    ["1917.2019.2160p.UHD.BluRay.x265-TERMiNAL", { title: "1917", year: 2019 }],
    ["2001.A.Space.Odyssey.1968.REMASTERED.1080p.BluRay", { title: "2001 A Space Odyssey", year: 1968 }],
    ["Blade Runner 2049 (2017)", { title: "Blade Runner 2049", year: 2017 }],
    ["Spider-Man.No.Way.Home.2021.1080p.WEB-DL.DDP5.1.H.264-EVO", { title: "Spider-Man No Way Home", year: 2021 }],
    ["Parasite.2019.KOREAN.1080p.BluRay.x264", { title: "Parasite", year: 2019 }],
    ["Amélie (2001)", { title: "Amélie", year: 2001 }],
    ["Avatar.The.Way.of.Water.2022.HDR.2160p.WEB.H265", { title: "Avatar The Way of Water", year: 2022 }],
    ["流浪地球.The.Wandering.Earth.2019.HD1080P.国语中字", { title: "流浪地球", originalTitle: "The Wandering Earth", year: 2019 }],
    ["【高清影视之家发布 www.HDBTHD.com】让子弹飞[国语配音+中文字幕].Let.the.Bullets.Fly.2010.BluRay.1080p.x265.10bit-DreamHD", { title: "让子弹飞", originalTitle: "Let the Bullets Fly", year: 2010 }],
    ["阳光电影www.ygdy8.com.霸王别姬.BD.720p.国语中字", { title: "霸王别姬" }],
    ["[电影天堂www.dytt89.com]寄生虫-2019_BD中韩双字", { title: "寄生虫", year: 2019 }],
    ["盗梦空间 Inception (2010)", { title: "盗梦空间", originalTitle: "Inception", year: 2010 }],
    ["流浪地球2019", { title: "流浪地球", year: 2019 }],
    ["Heat", { title: "Heat" }],
  ];
  for (const [name, want] of cases) assert.deepEqual(parseMovieName(name), want, name);
});

test("episode names: S01E02, 1x02, 第2集, E02, an anime's ` - 05`, a bare number; the show before, the title after", () => {
  const cases: [string, ReturnType<typeof parseEpisodeName>][] = [
    ["Breaking.Bad.S01E02.720p.BluRay.x264-DEMAND.mkv", { show: "Breaking Bad", season: 1, episode: 2 }],
    ["Sherlock.S02E01.A.Scandal.in.Belgravia.1080p.mkv", { show: "Sherlock", season: 2, episode: 1, title: "A Scandal in Belgravia" }],
    ["Friends.S03E15E16.720p.mkv", { show: "Friends", season: 3, episode: 15, episodeEnd: 16 }],
    ["Show.Name.2019.S01E01.mkv", { show: "Show Name", year: 2019, season: 1, episode: 1 }],
    ["The Office (US) - 2x05 - Halloween.mkv", { show: "The Office US", season: 2, episode: 5, title: "Halloween" }],
    ["权力的游戏.第一季.第02集.mkv", { show: "权力的游戏", season: 1, episode: 2 }],
    ["庆余年 第二季 第3集.mp4", { show: "庆余年", season: 2, episode: 3 }],
    ["狂飙 第12集 4K.mp4", { show: "狂飙", episode: 12 }],
    ["第三集.mkv", { episode: 3 }],
    ["[SweetSub] Frieren - 05 [1080p][HEVC].mkv", { show: "Frieren", episode: 5 }],
    ["[Group] 葬送的芙莉莲 [12][1080p].mp4", { show: "葬送的芙莉莲", episode: 12 }],
    ["EP03.mp4", { episode: 3 }],
    ["07.mkv", { episode: 7 }],
  ];
  for (const [name, want] of cases) assert.deepEqual(parseEpisodeName(name), want, name);
  for (const name of ["The.Matrix.1999.1080p.mkv", "Free.Guy.2021.mkv", "Video 1920x1080.mp4"]) assert.equal(parseEpisodeName(name), null, name);
});

test("seasons' and shows' folders; Chinese numbers; a show's key", () => {
  const seasons: [string, number | null][] = [
    ["Season 1", 1],
    ["Season.10", 10],
    ["S02", 2],
    ["第三季", 3],
    ["第十二季", 12],
    ["Specials", 0],
    ["Breaking.Bad.S01.1080p.BluRay", 1],
    ["Extras", null],
  ];
  for (const [name, want] of seasons) assert.equal(parseSeasonDir(name), want, name);
  assert.deepEqual(parseShowDir("Breaking.Bad.S01.1080p.BluRay.x264"), { title: "Breaking Bad" });
  assert.deepEqual(parseShowDir("权力的游戏 第一季"), { title: "权力的游戏" });
  assert.deepEqual(parseShowDir("The Wire (2002)"), { title: "The Wire", year: 2002 });
  assert.deepEqual(parseShowDir("Friends.Complete.Series"), { title: "Friends" });
  assert.deepEqual(parseShowDir("狂飙 全集"), { title: "狂飙" });
  assert.deepEqual([numberOf("十二"), numberOf("二十三"), numberOf("一百零五"), numberOf("０７"), numberOf("x")], [12, 23, 105, 7, null]);
  assert.equal(showKey("The Office: US"), showKey("the.office us"));
});

test("Kodi .nfo: movie, tvshow, episode; actors' and sets' names not taken; entities and CDATA", () => {
  const movie = parseNfo(`<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>让子弹飞</title>
  <originaltitle>Let the Bullets Fly</originaltitle>
  <year>2010</year>
  <plot><![CDATA[民国年间，<麻匪>张牧之…]]></plot>
  <genre>剧情 / 喜剧</genre>
  <genre>动作</genre>
  <runtime>132</runtime>
  <set><name>不要</name><title>也不要</title></set>
  <actor><name>姜文</name><role>张麻子</role></actor>
</movie>`);
  assert.deepEqual(movie, { kind: "movie", title: "让子弹飞", originalTitle: "Let the Bullets Fly", year: 2010, plot: "民国年间，<麻匪>张牧之…", genres: ["剧情", "喜剧", "动作"], runtime: 7920 });
  assert.deepEqual(parseNfo(`<tvshow><title>Breaking Bad &amp; More</title><premiered>2008-01-20</premiered><outline>A teacher.</outline></tvshow>`), { kind: "tvshow", title: "Breaking Bad & More", year: 2008, plot: "A teacher.", genres: [] });
  assert.deepEqual(parseNfo(`<episodedetails><title>Pilot</title><season>1</season><episode>1</episode><aired>2008-01-20</aired></episodedetails>`), { kind: "episode", title: "Pilot", year: 2008, genres: [], season: 1, episode: 1 });
  assert.equal(parseNfo("https://www.themoviedb.org/movie/603"), null);
});

test("subtitles beside a video: by its stem, language and forced from their tags", () => {
  const names = ["Movie.2019.srt", "Movie.2019.zh.srt", "Movie.2019.chs.forced.ass", "Movie.2019.eng.vtt", "Movie.2019.简体.ssa", "Other.srt", "Movie.2019.nfo", "Movie.2019.mkv", "Movie.2019.Director.srt"];
  assert.deepEqual(subtitlesOf("Movie.2019.mkv", names), [
    { name: "Movie.2019.Director.srt", format: "srt", lang: null, title: "director", forced: false },
    { name: "Movie.2019.chs.forced.ass", format: "ass", lang: "zh-Hans", title: "简体中文", forced: true },
    { name: "Movie.2019.eng.vtt", format: "vtt", lang: "en", title: "English", forced: false },
    { name: "Movie.2019.srt", format: "srt", lang: null, title: null, forced: false },
    { name: "Movie.2019.zh.srt", format: "srt", lang: "zh", title: "中文", forced: false },
    { name: "Movie.2019.简体.ssa", format: "ssa", lang: "zh-Hans", title: "简体中文", forced: false },
  ]);
});

test("SubRip, ASS and WebVTT made WebVTT: times, tags taken off, text made safe; GB18030 and a BOM read", () => {
  const srt = "1\r\n00:00:01,000 --> 00:00:02,500\r\n<font color=\"#fff\">你好</font>，{\\an8}世界\r\n\r\n2\r\n00:01:02,05 --> 00:01:03,100\r\n<i>a < b & c</i>\r\nsecond line\r\n\r\n3\r\nbroken\r\n";
  assert.equal(srtToVtt(srt.replace(/\r\n/g, "\n")), "WEBVTT\n\n00:00:01.000 --> 00:00:02.500\n你好，世界\n\n00:01:02.050 --> 00:01:03.100\n<i>a &lt; b &amp; c</i>\nsecond line\n");
  const ass = `[Script Info]
Title: x

[V4+ Styles]
Format: Name, Fontname
Style: Default,Arial

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:05.00,0:00:06.50,Default,,0,0,0,,{\\pos(10,10)}第二句，有逗号, 对\\N下一行
Dialogue: 0,0:00:01.20,0:00:02.00,Default,,0,0,0,,{\\fad(100,100)}第一句\\hhere
Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,{\\p1}m 0 0 l 100 0 100 100{\\p0}
Comment: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,不要`;
  assert.equal(assToVtt(ass), "WEBVTT\n\n00:00:01.200 --> 00:00:02.000\n第一句 here\n\n00:00:05.000 --> 00:00:06.500\n第二句，有逗号, 对\n下一行\n");
  assert.equal(toVtt(gb18030("1\n00:00:01,000 --> 00:00:02,000\n中文字幕\n"), "srt"), "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n中文字幕\n");
  assert.equal(toVtt(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("WEBVTT\n\n00:01.000 --> 00:02.000\nhi")]), "vtt"), "WEBVTT\n\n00:01.000 --> 00:02.000\nhi\n");
});

test("ffprobe's JSON: the video (not a cover picture), HDR, audio and subtitle tracks with languages", () => {
  const p = parseProbe(
    JSON.stringify({
      streams: [
        { index: 0, codec_type: "video", codec_name: "mjpeg", disposition: { attached_pic: 1 } },
        { index: 1, codec_type: "video", codec_name: "hevc", profile: "Main 10", width: 3840, height: 2160, pix_fmt: "yuv420p10le", color_transfer: "smpte2084", avg_frame_rate: "24000/1001" },
        { index: 2, codec_type: "audio", codec_name: "eac3", channels: 6, tags: { language: "eng", title: "Atmos" }, disposition: { default: 1 } },
        { index: 3, codec_type: "audio", codec_name: "aac", channels: 2, tags: { LANGUAGE: "chi" } },
        { index: 4, codec_type: "subtitle", codec_name: "subrip", tags: { language: "chi", title: "简体" }, disposition: { forced: 0 } },
        { index: 5, codec_type: "subtitle", codec_name: "hdmv_pgs_subtitle", tags: { language: "und" } },
      ],
      format: { format_name: "matroska,webm", duration: "7260.5", bit_rate: "25000000", start_time: "0.000000" },
    }),
  );
  assert.deepEqual(p.video, { index: 1, codec: "hevc", profile: "Main 10", width: 3840, height: 2160, hdr: "hdr10", fps: 23.976, bitDepth: 10, mime: null });
  assert.deepEqual(p.audio, [
    { index: 2, codec: "eac3", lang: "eng", title: "Atmos", channels: 6, default: true },
    { index: 3, codec: "aac", lang: "chi", title: null, channels: 2, default: false },
  ]);
  assert.deepEqual(
    p.subtitles.map((s) => [s.index, s.lang, s.text]),
    [
      [4, "chi", true],
      [5, null, false],
    ],
  );
  assert.equal(p.duration, 7260.5);
  assert.equal(p.container, "matroska,webm");
});

test("play: direct when the client decodes the container and the codecs, else HLS remuxed or made H.264", () => {
  const probe = (codec: string, audio: string | null) => parseProbe(JSON.stringify({ streams: [{ index: 0, codec_type: "video", codec_name: codec, width: 1920, height: 1080 }, ...(audio ? [{ index: 1, codec_type: "audio", codec_name: audio, channels: 2 }] : [])], format: { duration: "60" } }));
  assert.deepEqual([...clientOf("H264, hvc1,ec-3 aac")], ["h264", "hevc", "eac3", "aac"]);
  assert.deepEqual(decide("a/Film.mp4", probe("h264", "aac"), clientOf("h264,aac")), { direct: true, mode: "copy" });
  assert.deepEqual(decide("a/Film.m4v", probe("h264", null), clientOf("h264")), { direct: true, mode: "copy" });
  assert.deepEqual(decide("a/Film.mkv", probe("h264", "aac"), clientOf("h264,aac")), { direct: false, mode: "copy" });
  assert.deepEqual(decide("a/Film.mkv", probe("h264", "aac"), clientOf("h264,aac,mkv")), { direct: true, mode: "copy" });
  assert.deepEqual(decide("a/Film.mp4", probe("h264", "ac3"), clientOf("h264,aac")), { direct: false, mode: "copy" });
  assert.deepEqual(decide("a/Film.mp4", probe("hevc", "aac"), clientOf("h264,aac")), { direct: false, mode: "h264" });
  assert.deepEqual(decide("a/Film.avi", probe("mpeg4", "mp3"), clientOf("h264,hevc,aac,mp3,avi")), { direct: false, mode: "h264" });
  assert.deepEqual(decide("a/Film.mkv", null, clientOf("h264")), { direct: true, mode: "h264" });
});

test("a segment's fragments: the video's first tfdt where the segment begins, the audio where its first frame shows", () => {
  const u32 = (v: number) => {
    const b = Buffer.alloc(4);
    b.writeUInt32BE(v);
    return b;
  };
  const u64 = (v: number) => {
    const b = Buffer.alloc(8);
    b.writeBigUInt64BE(BigInt(v));
    return b;
  };
  const trak = (id: number, timescale: number, handler: string) =>
    box("trak", [
      box("tkhd", [u32(0), u32(0), u32(id), u32(0), u32(0)], { version: 0, flags: 3 }),
      box("mdia", [box("mdhd", [u32(0), u32(0), u32(timescale), u32(0)], { version: 0 }), box("hdlr", [u32(0), Buffer.from(handler, "latin1"), Buffer.alloc(12)], { version: 0 })]),
    ]);
  // A video sample: duration, size, flags, composition offset (2 frames of 512 at 12800).
  const traf = (id: number, tfdt: number, cto: number | null) =>
    box("traf", [
      box("tfhd", u32(id), { version: 0, flags: 0x20000 }),
      box("tfdt", u64(tfdt), { version: 1 }),
      cto === null ? box("trun", [u32(1), u32(0), u32(1024)], { version: 0, flags: 0x101 }) : box("trun", [u32(1), u32(0), u32(512), u32(100), u32(0), u32(cto)], { version: 0, flags: 0xf01 }),
    ]);
  const moof = (seq: number, v: number, a: number) => box("moof", [box("mfhd", u32(seq), { version: 0 }), traf(1, v, 1024), traf(2, a, null)]);
  const file = Buffer.concat([box("ftyp", Buffer.from("isom", "latin1")), box("moov", [trak(1, 12800, "vide"), trak(2, 48000, "soun")]), moof(1, 0, 0), box("mdat", Buffer.alloc(8)), moof(2, 38400, 144000), box("mdat", Buffer.alloc(8))]);
  const { init, media, tracks } = splitFragmented(file);
  assert.equal(init.toString("latin1", 4, 8), "ftyp");
  assert.deepEqual([...tracks], [
    [1, { timescale: 12800, video: true }],
    [2, { timescale: 48000, video: false }],
  ]);
  const placed = placeFragments(media, 12, tracks, 20_000);
  const tfdts: number[] = [];
  const seqs: number[] = [];
  for (let i = placed.indexOf("tfdt"); i > 0; i = placed.indexOf("tfdt", i + 1)) tfdts.push(Number(placed.readBigUInt64BE(i + 8)));
  for (let i = placed.indexOf("mfhd"); i > 0; i = placed.indexOf("mfhd", i + 1)) seqs.push(placed.readUInt32BE(i + 8));
  // Video at 12 s, 3 s later in the next fragment; audio at 12 s + 1024/12800 s (the first frame's composition offset).
  assert.deepEqual(tfdts, [12 * 12800, (12 + 0.08) * 48000, 15 * 12800, (12 + 0.08) * 48000 + 144000]);
  assert.deepEqual(seqs, [20_001, 20_002]);
});
