// What a film or an episode is, from its file's and folders' names (`Title (2019)`, `Title.2019.1080p.BluRay…`,
// `Show/Season 1/Show S01E02.mkv`, `1x02`, `第2集`, `E02`, an anime's ` - 02 `) and from Kodi's .nfo files beside it
// (movie.nfo, <name>.nfo, tvshow.nfo, an episode's). Names lose what releases add to them: groups and sites in brackets,
// resolution, source, codecs, audio, Chinese release words (国语中字, 蓝光…).

export type MovieName = { title: string; originalTitle?: string; year?: number };
export type EpisodeName = { show?: string; year?: number; season?: number; episode: number; episodeEnd?: number; title?: string };
export type Nfo = { kind: "movie" | "tvshow" | "episode" | "other"; title?: string; originalTitle?: string; year?: number; plot?: string; genres: string[]; runtime?: number; season?: number; episode?: number };

/// The stem of a file's name (without its extension).
export const stemOf = (name: string) => {
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(0, dot) : name;
};

const CN_DIGITS: Record<string, number> = { 零: 0, 〇: 0, 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
const CN_UNITS: Record<string, number> = { 十: 10, 百: 100, 千: 1000 };

/// A number written in digits (also full-width) or in Chinese (十二, 二十三, 一百零五).
export function numberOf(s: string): number | null {
  const ascii = s.replace(/[０-９]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0));
  if (/^\d+$/.test(ascii)) return Number(ascii);
  let total = 0;
  let digit = -1;
  for (const c of s) {
    if (c in CN_DIGITS) digit = CN_DIGITS[c]!;
    else if (c in CN_UNITS) {
      total += (digit < 0 ? 1 : digit) * CN_UNITS[c]!;
      digit = -1;
    } else return null;
  }
  if (digit > 0) total += digit;
  return s.length > 0 ? total : null;
}

const CN_NUM = "0-9０-９零〇一二两三四五六七八九十百";

/// Tokens that end a title: what a release says of its picture, sound and source.
const JUNK = new Set(
  (
    "4k 8k uhd fhd hd sd hq bluray blu-ray bdrip brrip bdremux remux bd bd25 bd50 web-dl webdl webrip web-rip hdtv hdrip dvdrip dvd dvdscr dvd5 dvd9 hdcam cam hdtc tc " +
    "amzn nf dsnp hmax atvp hulu itunes x264 x265 h264 h265 hevc avc xvid divx av1 vp9 10bit 8bit 12bit hdr hdr10 hdr10+ hdr10plus dv dovi sdr " +
    "aac aac2 ac3 dts dts-hd dts-x dtshd ddp ddp5 dd dd5 dd+ eac3 truehd atmos flac mp3 opus lpcm 2ch 6ch 5ch " +
    "extended unrated remastered proper repack limited internal imax 3d hsbs multi dual criterion " +
    "chs cht chs&eng cht&eng gb big5 mkv mp4 1080 720"
  ).split(" "),
);
const JUNK_RE = /^(?:\d{3,4}[pi]|\d+(?:\.\d+)?(?:fps|mbps|gb|mb)|(?:dd|ddp|aac|dts|truehd|ac3|eac3|flac)\d.*|h\.?26[45]|x26[45].*|[257]\.1|s\d{1,2}(?:-s?\d{1,2})?)$/i;
const CN_JUNK = /(国语|國語|粤语|粵語|国粤|國粵|国英|國英|中字|中英|双字|雙字|双语|雙語|字幕|高清|超清|蓝光|藍光|原盘|原盤|未删减|未刪減|无删减|無刪減|内封|內封|外挂|外掛|简繁|簡繁|简中|繁中|特效|修复版|修復版|完整版|无水印|無水印|网盘|網盤|压制|壓制|版本|发布|發佈|下载|下載|电影天堂|阳光电影|人人影视|中英双|收藏版|珍藏版)/;
/// A season named in a folder or a release: S01, Season 1, 第一季, Specials.
const SEASON_WORD = new RegExp(`^(?:(?:season|series|staffel|saison)[\\s._-]*(\\d{1,3})|s(\\d{1,3}))$|第\\s*([${CN_NUM}]+)\\s*季|(?:^|[\\s._\\[(-])(?:season|series)[\\s._-]*(\\d{1,3})(?:$|[\\s._\\])-])|(?:^|[\\s._\\[(-])s(\\d{1,2})(?:$|[\\s._\\])-])|^(specials?|特别篇|特別篇|sp)$`, "i");

const isCjk = (s: string) => /[぀-ヿ㐀-鿿豈-﫿]/.test(s);
const isLatin = (s: string) => /^[\p{Script=Latin}\d'’&:,!?·-]+$/u.test(s);
const thisYear = () => new Date().getFullYear();
const yearOf = (t: string) => {
  const m = /^(19\d\d|20\d\d)$/.exec(t);
  return m && Number(m[1]) <= thisYear() + 2 ? Number(m[1]) : null;
};
const junk = (t: string) => JUNK.has(t.toLowerCase()) || JUNK_RE.test(t) || CN_JUNK.test(t);

/// A name's release dressing taken off: sites, groups and tags in brackets at its start, 《》.
function undress(name: string): string {
  let s = name.normalize("NFC");
  // Sites: www.ygdy8.com, 阳光电影www.ygdy8.com, dygod.org.
  s = s.replace(/[^\s.[\]【】()（）]*?(?:www\.)?[a-z0-9-]+\.(?:com|net|org|cn|cc|tv|me|la|xyz|vip|top|info)(?![a-z])/gi, (m) => (/www\.|\.(com|net|org|cn|cc|la|xyz|vip|top)$/i.test(m) ? " " : m));
  // Groups at the start: [YTS.MX], 【高清影视之家发布】, [电影天堂].
  for (;;) {
    const m = /^\s*(?:\[[^\]]*\]|【[^】]*】)\s*[-.]?/.exec(s);
    if (!m || m[0].length >= s.length) break;
    s = s.slice(m[0].length);
  }
  // Groups anywhere that only tell of the release: [1080p], [国语配音+中文字幕], (BD).
  s = s.replace(/[[【(（]([^\]】)）]*)[\]】)）]/g, (all, inner: string) => {
    const t = tokensOf(inner);
    return CN_JUNK.test(inner) || (t.length > 0 && t.every(junk)) ? " " : all;
  });
  return s.replace(/[《》「」『』]/g, " ");
}

const tokensOf = (s: string) =>
  s
    .replace(/[[\]【】()（）{}]/g, " ")
    .split(/[\s._]+/)
    .map((t) => t.replace(/^[-–—]+|[-–—]+$/g, ""))
    .filter((t) => t !== "");

/// A film's name from its file's (or folder's) name: the title until its year or the first release token, the year
/// when it is one (not the first word: 1917, 2001 A Space Odyssey); a Chinese title and an English one, both given,
/// split into the title and the original title.
export function parseMovieName(name: string): MovieName {
  let s = undress(name);
  // 流浪地球2019, 寄生虫-2019: a year right after Chinese.
  s = s.replace(/([㐀-鿿])[-–—]?((?:19|20)\d\d)(?!\d)/g, "$1 $2");
  const tokens = tokensOf(s);
  let end = tokens.findIndex((t, i) => i > 0 && junk(t));
  if (end < 0) end = tokens.length;
  let year: number | undefined;
  let titleEnd = end;
  for (let i = end - 1; i >= 1; i--) {
    const y = yearOf(tokens[i]!);
    if (y !== null) {
      year = y;
      titleEnd = i;
      break;
    }
  }
  const words = tokens.slice(0, titleEnd);
  const title = words.join(" ").trim();
  const split = splitTitles(words);
  if (split) return { title: split.title, originalTitle: split.original, ...(year ? { year } : {}) };
  return { title: title || stemOf(name).trim(), ...(year ? { year } : {}) };
}

/// 流浪地球 The Wandering Earth (or the other way round): the Chinese title and the Latin one.
function splitTitles(words: string[]): { title: string; original: string } | null {
  if (words.length < 2) return null;
  const cjk = words.map((w) => isCjk(w));
  const latin = words.map((w) => !isCjk(w) && isLatin(w));
  for (const chineseFirst of [true, false]) {
    let k = 0;
    if (chineseFirst) while (k < words.length && cjk[k]) k++;
    else while (k < words.length && latin[k]) k++;
    if (k === 0 || k === words.length) continue;
    const rest = words.slice(k);
    if (chineseFirst ? !rest.every((_, i) => latin[k + i]) : !rest.every((_, i) => cjk[k + i])) continue;
    if (chineseFirst && !rest.some((w) => /\p{Script=Latin}/u.test(w))) continue;
    const a = words.slice(0, k).join(" ");
    const b = rest.join(" ");
    return chineseFirst ? { title: a, original: b } : { title: b, original: a };
  }
  return null;
}

/// The season a folder's name names (Season 1, S01, 第一季, Specials → 0), or null.
export function parseSeasonDir(name: string): number | null {
  const m = SEASON_WORD.exec(undress(name).trim());
  if (!m) return null;
  if (m[6]) return 0;
  const n = numberOf(m[1] ?? m[2] ?? m[3] ?? m[4] ?? m[5] ?? "");
  return n !== null && n < 1000 ? n : null;
}

/// A show's folder name made its title: its season (a season's pack: Show.S01.1080p…, 权力的游戏 第一季) and the
/// release's tokens taken off; the year kept apart.
export function parseShowDir(name: string): MovieName {
  const s = undress(name)
    .replace(new RegExp(`第\\s*[${CN_NUM}]+\\s*季.*$`), " ")
    .replace(/(?:^|[\s._-])(?:season|series)[\s._-]*\d{1,3}.*$/i, " ")
    .replace(/(?:^|[\s._-])s\d{1,2}(?:[\s._-]*-?[\s._-]*s?\d{1,2})?(?=$|[\s._\])-]).*$/i, " ")
    .replace(/(?:全集|全\d+集|完结|完結|complete(?:[\s._-]+series)?)[\s._-]*$/i, " ");
  return parseMovieName(s.trim() || name);
}

/// An episode from its file's name: S01E02 (S01E02E03, S01E02-E03), 1x02, 第2集 (第二集, 第02话), E02 / EP02, an anime's
/// ` - 02`, `[02]`, or a name that is only its number; the show's name before it and the episode's title after it.
/// Null when it names no episode.
export function parseEpisodeName(name: string): EpisodeName | null {
  const s = undress(stemOf(name)).trim();
  const found = matchEpisode(s);
  if (!found) return null;
  const before = s.slice(0, found.at).replace(/[\s._-]+$/, "");
  const after = s.slice(found.at + found.length).replace(/^[\s._-]+/, "");
  const out: EpisodeName = { episode: found.episode };
  if (found.season !== undefined) out.season = found.season;
  if (found.end !== undefined && found.end > found.episode) out.episodeEnd = found.end;
  if (before) {
    const show = parseShowDir(before);
    if (show.title && !/^\d+$/.test(show.title)) out.show = show.title;
    if (show.year) out.year = show.year;
  }
  if (after) {
    const tokens = tokensOf(after);
    const end = tokens.findIndex((t) => junk(t) || yearOf(t) !== null);
    const title = tokens.slice(0, end < 0 ? tokens.length : end).join(" ").trim();
    if (title && !/^\d+$/.test(title)) out.title = title;
  }
  return out;
}

type Found = { at: number; length: number; episode: number; season?: number; end?: number };

function matchEpisode(s: string): Found | null {
  const at = (m: RegExpExecArray, lead = 0) => ({ at: m.index + lead, length: m[0].length - lead });
  let m = /(^|[^a-z0-9])s(\d{1,3})[\s._-]*e(\d{1,4})(?:(?:[\s._-]*-?[\s._-]*e|-)(\d{1,4}))?(?![0-9])/i.exec(s);
  if (m) return { ...at(m, m[1]!.length), season: Number(m[2]), episode: Number(m[3]), ...(m[4] ? { end: Number(m[4]) } : {}) };
  m = /(^|[^a-z0-9])(\d{1,2})x(\d{2,3})(?![0-9p])/i.exec(s);
  if (m) return { ...at(m, m[1]!.length), season: Number(m[2]), episode: Number(m[3]) };
  m = new RegExp(`第\\s*([${CN_NUM}]+)\\s*[集话話回](?:\\s*[-~～至到]\\s*第?\\s*([${CN_NUM}]+)\\s*[集话話回]?)?`).exec(s);
  if (m) {
    const episode = numberOf(m[1]!);
    if (episode !== null) {
      const season = new RegExp(`第\\s*([${CN_NUM}]+)\\s*季`).exec(s);
      const sn = season ? numberOf(season[1]!) : null;
      const end = m[2] ? numberOf(m[2]) : null;
      // The show's name ends before the season, when it is named first.
      const start = season && season.index < m.index ? season.index : m.index;
      return { at: start, length: m.index + m[0].length - start, episode, ...(sn !== null ? { season: sn } : {}), ...(end !== null ? { end } : {}) };
    }
  }
  m = /(^|[^a-z0-9])(?:ep?|episode)[\s._-]?(\d{1,4})(?:-(?:ep?)?(\d{1,4}))?(?![0-9p])/i.exec(s);
  if (m) return { ...at(m, m[1]!.length), episode: Number(m[2]), ...(m[3] ? { end: Number(m[3]) } : {}) };
  m = /\s[-–]\s(\d{1,4})(?:v\d)?(?=$|[\s[(])/.exec(s);
  if (m && !yearOf(m[1]!)) return { ...at(m), episode: Number(m[1]) };
  m = /\[(\d{1,3})(?:v\d)?\]/.exec(s);
  if (m) return { ...at(m), episode: Number(m[1]) };
  m = /^(\d{1,3})(?=$|[\s._-])/.exec(s);
  if (m) return { ...at(m), episode: Number(m[1]) };
  return null;
}

/// The key two names of one show share: its letters and digits, lowercase.
export const showKey = (title: string) => title.normalize("NFKC").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");

// Kodi's .nfo.

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
const unescape = (s: string) =>
  s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (all, e: string) => {
      if (e[0] === "#") {
        const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : Number(e.slice(1));
        return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : all;
      }
      return ENTITIES[e.toLowerCase()] ?? all;
    })
    .trim();

/// A Kodi .nfo (XML: <movie>, <tvshow>, <episodedetails>; the first one when a file has several): title,
/// originaltitle, year (else premiered's / aired's), plot (else outline), genres, runtime (minutes, made seconds),
/// season and episode. Null when it is no XML (some are only a link).
export function parseNfo(text: string): Nfo | null {
  const root = /<(movie|tvshow|episodedetails|musicvideo)[\s>]/i.exec(text);
  if (!root) return null;
  const kind = root[1]!.toLowerCase();
  const close = text.indexOf(`</${root[1]}>`, root.index);
  const body = text.slice(root.index, close < 0 ? undefined : close);
  // Not inside what an actor, a set or a rating says.
  const flat = body.replace(/<(actor|set|ratings|fileinfo|uniqueid|thumb|fanart|director|credits)\b[\s\S]*?<\/\1>/gi, "");
  const one = (tag: string) => {
    const m = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`, "i").exec(flat);
    const v = m ? unescape(m[1]!) : "";
    return v || undefined;
  };
  const all = (tag: string) => [...flat.matchAll(new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`, "gi"))].map((m) => unescape(m[1]!)).filter((x) => x !== "");
  const int = (v: string | undefined) => (v && /^\d+$/.test(v.trim()) ? Number(v.trim()) : undefined);
  const out: Nfo = { kind: kind === "movie" ? "movie" : kind === "tvshow" ? "tvshow" : kind === "episodedetails" ? "episode" : "other", genres: [] };
  const title = one("title");
  if (title) out.title = title;
  const original = one("originaltitle");
  if (original && original !== title) out.originalTitle = original;
  const year = int(one("year")) ?? int(/^(\d{4})-/.exec(one("premiered") ?? one("aired") ?? "")?.[1]);
  if (year && year > 1800 && year < 3000) out.year = year;
  const plot = one("plot") ?? one("outline");
  if (plot) out.plot = plot;
  out.genres = [...new Set(all("genre").flatMap((g) => g.split(/\s*[/|,]\s*/)).filter((g) => g !== ""))];
  const runtime = int(one("runtime"));
  if (runtime && runtime > 0) out.runtime = runtime * 60;
  const season = int(one("season"));
  if (season !== undefined) out.season = season;
  const episode = int(one("episode"));
  if (episode !== undefined) out.episode = episode;
  return out;
}
