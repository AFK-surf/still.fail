# 媒体服务（第 1 期：书架）

媒体 app 在 station 上的那一半：一个独立的 Node 进程（`media/service/`，Node 24 直接跑 TypeScript，零依赖：`node:sqlite`、`node:zlib`、`node:http`），station 把它当作模块 `media` 启动。客户端经 `/admin/api/m/media/…` 访问，station 验证身份后去掉这个前缀，原样转给它。拆分的来由见媒体 app 的方案（三、四两节）。

## 和 station 的约定

| 环境变量 | 用途 |
|---|---|
| `STILLFAIL_MODULE_ID` | `media` |
| `STILLFAIL_MODULE_DIR` | 数据目录：`media.db` 在这里 |
| `STILLFAIL_MODULE_SOCKET` | 服务在这个 unix socket 上答 HTTP/1.1 |
| `STILLFAIL_STATION_SOCKET`、`STILLFAIL_STATION_TOKEN` | station 给模块的本机接口，每个请求带 `authorization: Bearer <token>` |

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

## 存储

`<STILLFAIL_MODULE_DIR>/media.db`（WAL，外键级联删除），自己的 `user_version`（`store.ts` 的 `MIGRATIONS`，按顺序往前迁；比代码新的库拒绝打开）。表：`books`（workspace、root、path 唯一）、`chapters`（blocks 存 JSON，原样发出）、`images`、`places`（book+sub）、`notes`（book+id，带 sub）。

## 测试

`cd media/service && node --test test/*.test.ts`：测试里自己写 EPUB（zip 写入）和 GB18030 的 TXT，用一个假的 station 本机接口（unix socket，查 token，每次只回 4 KB，逼出分段读）。类型检查：`tsgo -p media/service/tsconfig.json`。

## 还没做

- MOBI / AZW3（415）。
- 封面的 ThumbHash（`cover` 现在总是 `null`，先用 `coverRef` 取原图）。
- 书里的内部链接（`href` 是书里原样的写法，没有换成章节下标）、脚注弹出。
- 目录里同一文件内的小节（只取每个文件的第一条）。
- JPEG 的 EXIF 方向（宽高按存储方向）。
- 按 drive 的 watch 自动更新书架；书内搜索。
