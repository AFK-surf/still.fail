# 媒体服务（第 1 期：书架；第 2 期：照片；第 3 期：影视）

媒体 app 在 station 上的那一半：一个独立的 Node 进程（`media/service/`，Node 24 直接跑 TypeScript，零依赖：`node:sqlite`、`node:zlib`、`node:http`），station 把它当作模块 `media` 启动。客户端经 `/admin/api/m/media/…` 访问，station 验证身份后去掉这个前缀，原样转给它。拆分的来由见媒体 app 的方案（三、四两节）。

## 和 station 的约定

| 环境变量 | 用途 |
|---|---|
| `STILLFAIL_MODULE_ID` | `media` |
| `STILLFAIL_MODULE_DIR` | 数据目录：`media.db` 在这里 |
| `STILLFAIL_MODULE_SOCKET` | 服务在这个 unix socket 上答 HTTP/1.1 |
| `STILLFAIL_STATION_SOCKET`、`STILLFAIL_STATION_TOKEN` | station 给模块的本机接口，每个请求带 `authorization: Bearer <token>` |
| `MEDIA_BACKUP_DIR`（可选） | 照片的备份目录，默认 `~/Pictures/still.fail` |
| `MEDIA_FFMPEG`、`MEDIA_FFPROBE`（可选） | ffmpeg、ffprobe 的路径；没有就用 `$MODULE_BIN_DIR/ffmpeg`（包里带的，station 设好），再没有就找 PATH |
| `MEDIA_HLS_CAP`（可选） | HLS 分段缓存的上限（字节），默认 20 GB |

- 每个请求带 `stillfail-viewer`：成员的 `{sub, email, name, role, workspace, home}`（`home` 是布尔：这个 workspace 是不是 station 的 home workspace），全 ASCII 的 JSON（station 把 U+007F 以上的字符都转成 `\uXXXX`，station 一侧见 docs/station-modules.md）。没有或无效：403。
- 书按 workspace 分，阅读位置和笔记按账号（`sub`）分。owner、admin、member 能改书架；`viewer` 只读，但能存自己的位置和笔记。
- 启动后 station 取 `GET /manifest` → `{viewerWrites: ["^/books/[^/]+/place$", "^/books/[^/]+/notes/[^/]+$"]}`：viewer 发往这些路径的写请求放行。服务自己也再查一遍角色。
- 读书的文件一律经 station 的本机接口（`/drive/stat`、`/drive/list`、`/drive/read`，每次最多 8 MB），带上发起导入的成员的 `stillfail-viewer`（原样转发）：pinned 目录、macOS 受保护目录、station 自己的数据这些规则只在 station 一处。服务从不直接读 drive 的路径。
- SIGTERM（SIGINT）时停止接新请求，断开事件流，等进行中的请求做完（最多 5 秒）后退出。

## 接口

出错一律 `{error: <给人看的中文>, code}`：400 `bad_request`、403 `forbidden`、404 `not_found`、405、409 `conflict`（导入时文件被改了）、413 `too_large`、415 `unsupported`、502 `station`（station 连不上或拒绝了凭证）、500 `internal`。

| 请求 | 谁 | 答 |
|---|---|---|
| `GET /books` | 成员 | `{books: [{id, title, author, format, cover: null, coverRef?, chapters, added, place?, read?}]}`；`place` 是自己的，`read` 是按字数算的进度 0..1；`coverRef` 是封面图的 ref（用下面的图片接口取） |
| `POST /books/import {root, path}` | 可写成员 | `{ids, failed?}`。文件，或目录里（不含子目录）的每个 .epub、.txt；目录里失败的那几本列在 `failed: [{path, error}]` |
| `GET /books/:id` | 成员 | `{id, title, author, toc: [{index, title, level, chars}]}`，每章一条 |
| `DELETE /books/:id` | 可写成员 | `{}`，连同所有人的位置和笔记 |
| `GET /books/:id/chapters/:index` | 成员 | `{chars, blocks}` |
| `GET /books/:id/images/:ref` | 成员 | 图片字节，`content-type` 按内容；ref 是内容的哈希，可以永久缓存 |
| `GET /books/:id/place` | 成员 | `{place: {chapter, offset, at} \| null}` |
| `PUT /books/:id/place {chapter, offset, at}` | 成员（含 viewer） | `{place}`：存下的那个。`at` 不比已存的新就不改（各端以最新的为准） |
| `GET /books/:id/notes` | 成员 | `{notes: [{id, chapter, start, end, text, note?, color, at}]}`，只有自己的，按阅读顺序 |
| `PUT /books/:id/notes/:noteId {chapter, start, end, text, note?, color, at}` | 成员（含 viewer） | `{note}`。id 由客户端生成（1–64 个字母、数字、`_`、`-`），一本书里唯一；别人的笔记 403；`at` 旧的不改 |
| `DELETE /books/:id/notes/:noteId` | 成员（含 viewer） | `{}`；别人的 403 |
| `GET /events` | 成员 | SSE：`event: shelf`（`{}`，本 workspace 的书变了）、`event: place` / `event: notes`（`{book}`，只发给同一个账号）；每 25 秒一行注释保活 |
| `GET /manifest` | station | 见上 |

## 正文和偏移

`blocks` 是 `{t:"p", text}`（无样式段落）、`{t:"p", runs:[{text, b?, i?, href?, ruby?}]}`、`{t:"h", level, text}`、`{t:"img", ref, w?, h?}`、`{t:"hr"}`。

**偏移的定义**：一章的正文是各个 block 首尾相接（中间不加任何分隔）：`p` 计它文字的 UTF-16 长度（runs 的 `text` 相加；ruby 计底下的字，不计注音），`h` 计它的 `text`，`img` 和 `hr` 各计 1（相当于一个 U+FFFC），这样每个 block 都有自己的起点，停在一张整页插图上的位置也能还原。`chars` 是一章的总和；阅读位置的 `offset`、笔记的 `start`/`end` 都是这里的下标（JS 字符串下标）。

## 导入

- **EPUB**（2、3）：自带的 zip 读取（central directory，stored 和 deflate，zip64）；container.xml → OPF（标题、作者、封面）→ spine 顺序，一个文件一章，空的跳过；章名取 nav.xhtml 的 toc（没有就 toc.ncx），同一文件取第一条，层级取嵌套深度；目录里没有的取本章第一个标题。XHTML 用一个宽松的小分词器转成 blocks：`b`/`strong`、`i`/`em`、`a href`、`ruby`/`rt`，`br` 分段，空白按 HTML 折叠（两个中文字之间的换行不算空格），段首全角缩进去掉。图片（`img`、svg 里的 `image`）存进库，宽高从 PNG/JPEG/GIF/WebP 头里读。内容被 DRM 加密的 415。
- **TXT**：UTF-8（有无 BOM），UTF-16 看 BOM，否则 GB18030。一行一段，去掉行首缩进。按 `第…章/回/节/集/话`、`第…卷/部/篇`（中文数字或数字）、`Chapter N`、楔子/序章/尾声/后记这些行分章；第一个标题之前有内容就成一章「前言」；文件开头的章节目录（一串没有内容的标题）不算章；同时有卷和章时卷是第 1 层、章是第 2 层。没有标题就按约 2 万字在段落之间切。书名取文件名，作者取开头的「作者：」。
- 同一个 workspace 里同一个 root+path 再导入：大小和修改时间都没变就直接回原来的 id；变了就重新解析，id、加入时间、位置和笔记都保留。同一个文件同时导入两次会排队。
- 文件最大 512 MB；先读第一段，MOBI/AZW3 不用读完就回 415。

## 照片（第 2 期，`photos.ts`）

照片库是这台 station 的：owner、admin、member 都能看（不分 workspace，按角色），viewer 一律 403；manifest 的 `viewerWrites` 不变。接口按约定（`/photos/folders`、`timeline`、`albums`、`items/:id`、`thumbs/:id`、`thumbs?ids=`、`has`、`upload`，事件 `photos`）。

- **库**：`PUT /photos/folders {folders: [{root, path}]}`（owner/admin，每个要是这个人能到的文件夹）存进 media.db；备份目录（`MEDIA_BACKUP_DIR`，默认 `~/Pictures/still.fail`，第一次扫的时候建）总在库里，是相册「手机备份」（id `backup`），其余一个文件夹一个相册（id 同条目的算法：`sha256(root+"\n"+path)` 前 20 位）。
- **以谁的身份读**：经 station 本机接口，带最后一个设置文件夹的 owner/admin 的 `stillfail-viewer`；没人设置过之前，库只有备份目录，用最后一个来看照片的可写成员的身份读。
- **索引**：递归 `drive/list`（跳过隐藏的、`@eaDir` 这类 NAS 目录、`.photoslibrary` 这类包；最深 32 层，一遍最多 10 万个目录；`truncated` 的照收前 5 万个），认 jpg/jpeg/png/heic/heif/webp/gif 和 mp4/mov/m4v。大小和 mtime 没变就不再读。之后用 `drive/watch`（不递归）跟着各相册的根目录和最近改过的目录，共最多 32 个（station 一共 256 个 watch）：一个目录变了就重列它，新目录整个扫，没了的连同下面的条目删掉；另外每小时全量对一遍（这一遍没见到的删掉，列不出来的目录下的不删）。
- **元数据**（零依赖，先读开头 ≤1 MB）：JPEG 的 EXIF（`DateTimeOriginal`+`OffsetTimeOriginal`，没有 offset 就当 station 本地时间；方向、相机、镜头、GPS）；PNG/GIF/WebP 头；HEIC/HEIF 的 `meta`（`iinf`/`iloc` 找 Exif item，不在开头就按 iloc 另读；`ipma`→`ispe`/`irot` 得主图尺寸，有 `irot` 按它转，否则按 EXIF 方向）；MP4/MOV 的 `mvhd`（创建时间、时长）和第一个有画面的 `tkhd`（宽高，矩阵是 90° 的对调）；moov 在 mdat 后面的，按盒子头找过去另读（最多 8 MB）。没有拍摄时间就用 mtime。`day` 是 station 本地时区的日期。`w`/`h` 是转正后的，不知道时为 0；`duration` 是秒。
- **时间线**：days 新的在前，一天里按 `taken` 新的在前。`around` 那天（有照片才算一天）加上它之前 `before` 个、之后 `after` 个有照片的日子；不给 `around` 就是最新那天加之前 `before` 个（`after` 不算）。默认 30，最多 366。
- **缩略图**：jpg/png/webp 用 station 的 `/thumb`（thumbhash 取它的头）；HEIC/HEIF/GIF 在 macOS 上把文件读过来（≤128 MB）放进模块目录的临时文件，`sips -s format jpeg -Z 720` 转，没有 sips 时 GIF 原样给（≤8 MB）、HEIC 没有缩略图；视频用 `/poster`。station 不给 thumbhash 的（sips 转的、封面）用 `sips -Z 100` 出一张 BMP 自己算（thumbhash 的编码，和 station 的一样是 base64）。缓存在 `<模块目录>/thumbs/<id 前两位>/<id>-<mtime>-<size>`，文件变了就换。`grid` 和 `large` 现在是同一张。索引后在后台按新到旧把缺 thumbhash 的都做一遍（做不出来的记为没有，文件变了再做），做的过程中最多每 15 秒发一次 `photos`。批量接口一次最多 64 个，做不出来的不出现在 `stillfail-index` 里。
- **上传**：`has` 和上传按 sha256 查，只有上传进来的条目有 sha256（扫到的文件不算哈希：要整个读一遍，太贵）；扫描时文件大小没变就保留它。分段写到 `<模块目录>/uploads/<账号+hash+size>.part`，`offset` 不能超过已收的（409，带 `have`），等于或小于都按位置写（重发的一段、空 body 问进度都行），一段 ≤8 MB（413）。收齐后核 sha256（不对 409 并删掉重来），移到 `<备份目录>/<邮箱>/<YYYY>/<MM>/<name>`（年月按 `taken`，没给按现在；重名加「 (1)」），mtime 设成 `taken`，马上建条目，发 `photos`。7 天没动的 `.part` 在全量对的时候删掉。
- **事件**：库变了（索引、上传、thumbhash）1 秒内没再变就给可写成员的 `/events` 发 `event: photos`（`{}`）。

照片只给这台 station 的主 workspace 里能写的成员看（owner、admin、member）：只读成员，以及 station 另外加入的 workspace 的成员，都回 403，也收不到 `photos` 事件。

## 影视（第 3 期，`videos.ts`、`hls.ts`）

片库和照片一样是这台 station 的，只给主 workspace 里能写的成员（owner、admin、member）；viewer 和别的 workspace 的成员 403，也收不到事件。接口按约定（`/videos/folders`、`library`、`titles/:id`、`episodes/:id`、`posters/:id`、`:id/play`、`:id/hls/…`、`:id/subtitles/:sub.vtt`、`:id/progress`，事件 `videos`、`progress`）。

- **片库**：`PUT /videos/folders {folders: [{root, path, kind: "movies"|"shows"}]}`（owner/admin），以最后设置的人的身份经 station 读。扫描同照片：递归 `drive/list`，`drive/watch` 跟着变，每小时全量对一遍；认 mkv/mp4/m4v/mov/avi/webm/ts/m2ts，跳过 `Extras`/`花絮` 这类目录和 `-sample`。
- **认片**（`videoname.ts`）：电影取文件名（`GENERIC` 的像 `movie.mkv` 取所在文件夹名）里年份或第一个发布标记之前的部分，去掉网站、`[组名]`、`【…发布】`、分辨率/编码/音轨、`国语中字` 这类词，中英文片名各一半时拆成 `title`/`originalTitle`；同目录的 `<名字>.nfo`（只有一部片时也认 `movie.nfo`）优先。剧：`剧名/Season 1/…`（季目录也认 `S01`、`第一季`、`Specials`，剧名目录里的 `S01`、`第一季`、`全集` 去掉），集号认 `S01E02`（`E02E03`）、`1x02`、`第2集`/`第二集`/`第02话`、`E02`/`EP02`、动画的 ` - 05`、`[05]`、只有数字的文件名；`tvshow.nfo` 和每集的 nfo 优先。散放在剧集文件夹根上的按文件名里的剧名归。
- **ffprobe**：只在服务自己能读到这个文件时直接读绝对路径（macOS 受保护、要经 still.fail Helper 读的文件夹不读，记 `probe: "unreadable"`）；没有 ffprobe 记 `no-ffprobe`。这时只有文件名和 nfo 里的信息，只能直接播放，`/videos/library` 里 `ffmpeg: false`。有了之后下一遍全量会补上。
- **海报**：同目录的 `<名字>-poster.jpg`，只有一部片时也认 `poster`/`folder`/`cover`/`movie`/`fanart`（jpg/png/webp），经 station 的 `/thumb`；没有就 ffmpeg 在 10% 处截一帧（720 框的 JPEG）；再没有就用 station 的 `/poster`。剧的海报在剧目录里找，没有就用第一集的。ThumbHash 先用 station 给的，否则用 sips（macOS）出的小 BMP 算，开发用的 ffmpeg 也行；包里的 ffmpeg 读不了 JPEG，Linux 上这时海报没有 ThumbHash：列表里 `poster: null`、`hasPoster: true`。
- **播放**：`play?client=h264,hevc,aac,ac3,mkv…`：容器（`client` 里没列容器时只当 mp4 能放）、视频编码、默认音轨的编码都在里面就 `direct: true`，客户端经 drive 分段读原文件；否则给 `hls`（要有 ffmpeg、ffprobe 读过、服务能读到文件）。HLS 是 fMP4：视频编码客户端能解（h264/hevc/av1/vp9）就 remux，分段从关键帧开始（ffprobe 读一遍关键帧，存在缓存里），否则转成 H.264（`h264_videotoolbox`，Linux 上 `libopenh264`，开发用的 ffmpeg 有 `libx264` 也行；一个编码器失败就换下一个），最高 1080p，GOP 6 秒；音频是 1–2 声道的 AAC 就原样带，否则转 AAC 立体声。每段由一次 ffmpeg 单独做：ffmpeg 输出的每条轨都从 0 开始，服务改写各 `tfdt`，视频放在分段的起点，其他轨放在视频第一帧显示的时间（B 帧的 composition offset），init 段用第一次做出来的。播放器要哪段先做哪段，后面 3 段接着做；同时最多 2 个 ffmpeg，同一部片 1 个。缓存在 `<模块目录>/hls/<id>-<mtime>-<size>/<变体>/`，超过上限按最久没用的删到 90%。
- **字幕**：外挂的 srt/ass/ssa/vtt（`名字.zh.srt`、`名字.chs.forced.ass`，语言从文件名里认）经 station 读来在 JS 里转 WebVTT（编码同 TXT），id `x<n>`；内嵌的文字字幕用 ffmpeg 转（id `s<轨号>`，转好的存在模块目录里）；图形字幕（PGS、DVD）415。
- **进度**：`PUT /videos/:id/progress {position, at, duration?, done?}`，每个账号自己的，`at` 新的才存；到时长的 90%（时长取 ffprobe，没有就 nfo 的 runtime，再没有就请求里的 `duration`）或 `done: true` 算看完。`library.recent` 是有进度没看完的（最多 20 个，按 `at` 新的在前）。进度变了只给这个账号发 `event: progress {id}`；片库变了 1 秒内没再变就给可写成员发 `event: videos`。

## 存储

`<STILLFAIL_MODULE_DIR>/media.db`（WAL，外键级联删除），自己的 `user_version`（`store.ts` 的 `MIGRATIONS`，按顺序往前迁；比代码新的库拒绝打开）。表：`books`（workspace、root、path 唯一）、`chapters`（blocks 存 JSON，原样发出）、`images`、`places`（book+sub）、`notes`（book+id，带 sub）；第 2 版加了 `photo_items`（照片和视频，按 day、相册、目录、sha256 建索引）和 `photo_settings`（文件夹、读库用的身份；片库的文件夹和身份也存在这里，键 `videos.*`）；第 3 版加了 `video_items`（电影和每一集：认出来的名字、ffprobe 的 JSON、外挂字幕、海报的 ThumbHash）、`video_shows`、`video_progress`（item+sub）。

## 测试

`cd media/service && node --test test/*.test.ts`：测试里自己写 EPUB（zip 写入）和 GB18030 的 TXT，用一个假的 station 本机接口（unix socket，查 token，每次只回 4 KB，逼出分段读）。照片的测试自己拼 EXIF（两种字节序）、HEIF 的盒子（Exif item 放在 1 MB 之后）、MP4（moov 在后面），假 station 还从磁盘上的临时目录答 `drive/list`/`read`/`watch`/`/thumb`/`/poster`，sips 用一个测试自己的脚本。影视的测试（`videos.test.ts`、`videoname.test.ts`）不靠 ffmpeg 的部分（认片、nfo、字幕转换、播放的判断、`tfdt` 改写、片库、进度、权限）总跑；PATH 里有 ffmpeg/ffprobe（开发用的，要有 lavfi 造测试片）时再跑 ffprobe、截帧、HLS（remux 和转码，检查各段的 `tfdt`、拼起来能解出全部的帧）、内嵌字幕、缓存上限。类型检查：`tsgo -p media/service/tsconfig.json`。

## 还没做

- MOBI / AZW3（415）。
- 封面的 ThumbHash（`cover` 现在总是 `null`，先用 `coverRef` 取原图）。
- 书里的内部链接（`href` 是书里原样的写法，没有换成章节下标）、脚注弹出。
- 目录里同一文件内的小节（只取每个文件的第一条）。
- JPEG 的 EXIF 方向（宽高按存储方向）。
- 按 drive 的 watch 自动更新书架；书内搜索。
- 影视：TMDB 之类的在线元数据（只用文件名、nfo 和片子本身）；图形字幕；HDR 转 SDR（转码不做色调映射）；主列表的 `CODECS`；多码率；每段单独转码的音频（不是 AAC 的）在段与段之间有约一帧（~21 ms）的重叠；受保护文件夹里的片子不 ffprobe、不出 HLS。
- 照片：`grid` 小图（现在和 `large` 一样）；Linux 上的 HEIC 缩略图；扫到的文件的 sha256；iPhone MOV 里 `com.apple.quicktime.creationdate` 带的时区（现在用 mvhd 的 UTC 时间）；动态照片（Live Photo）的配对。
