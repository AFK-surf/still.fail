// The text as a reader lays it out (reader_text.mbt, as Android's TextModel.kt's tests checked it; how the core reads
// it is its own tests', client/core-ts/test/reader.test.ts): decoded, cut into blocks, indented, a novel's and a
// Markdown file's book as the real core read them (src/sfkept), over the same made-up texts as the app's fixture
// (src/sfapp drive_fixture.mbt).

///|
fn utf8_of(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
test "decoding: UTF-8, its byte order mark, UTF-16, a character cut at the end" {
  assert_eq(@hostapi.decode_text(utf8_of("第一章 开始")).0, "第一章 开始")
  let bom = Bytes::from_array([b'\xEF', b'\xBB', b'\xBF', b'a', b'b'][:])
  assert_eq(@hostapi.decode_text(bom), ("ab", "UTF-8 BOM"))
  let le = Bytes::from_array([b'\xFF', b'\xFE', b'\x2C', b'\x7B', b'a', b'\x00'][:])
  assert_eq(@hostapi.decode_text(le), ("第a", "UTF-16LE"))
  // 第 is E7 AC AC: its last byte cut off the front of a bigger file
  let cut = Bytes::from_array([b'a', b'\xE7', b'\xAC'][:])
  assert_eq(@hostapi.decode_text(cut, truncated=true), ("a", "UTF-8"))
  // a half-copied file is still UTF-8
  assert_eq(@hostapi.decode_text(cut), ("a", "UTF-8"))
}

///|
test "decoding: a file that is not UTF-8 read as GB18030 (第一章 开始)" {
  // (as a Tester's host decodes it: the system's tables are a host's own)
  @ui.Tester::new(fn(_) {  }) |> ignore
  // 第 B5DA, 一 D2BB, 章 D5C2, a space, 开 BFAA, 始 CABC
  let gb = Bytes::from_array(
    [b'\xB5', b'\xDA', b'\xD2', b'\xBB', b'\xD5', b'\xC2', b' ', b'\xBF', b'\xAA', b'\xCA', b'\xBC'][:],
  )
  assert_eq(@hostapi.decode_text(gb), ("第一章 开始", "GB18030"))
  // the front of a bigger file, its last character cut in half: dropped
  let cut = Bytes::from_array([b'\xB5', b'\xDA', b'\xD2'][:])
  assert_eq(@hostapi.decode_text(cut, truncated=true), ("第", "GB18030"))
}

///|
test "blocks: cut at paragraph ends within the budget, found again by offset" {
  let p = "一二三四五六七八九十。\n"
  let text = p.repeat(30)
  let (chunks, starts) = chunk_text(text, budget=100)
  assert_true(chunks.length() > 1)
  assert_eq(chunks.iter().fold(init="", fn(a, s) { a + s }), text)
  for c in chunks {
    assert_true(c.length() <= 100)
    assert_true(c.has_suffix("\n"))
  }
  assert_eq(chunk_index_for(starts, starts[2] + 3), 2)
}

///|
/// The core's book of `text` (`reader.book`), as the real core answered it (src/sfkept).
fn kept_book(text : String, markdown : Bool) -> ReadBook raise {
  let params : Json = { "markdown": Json::boolean(markdown), "tree": Json::boolean(markdown), "text": Json::string(text) }
  let book = match @sfkept.answer("reader.book", params, None) {
    Some(Ok((book, _))) => book
    _ => fail("the core's book of the text is not kept")
  }
  let field = fn(k : String) -> Json? {
    match book {
      Object(o) => o.get(k)
      _ => None
    }
  }
  let int = fn(v : Json?) -> Int {
    match v {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
  }
  let list = fn(k : String) -> Array[Json] {
    match field(k) {
      Some(Array(a)) => a
      _ => []
    }
  }
  {
    id: int(field("id")),
    text,
    wrapped: int(field("wrapped")),
    chapters: list("chapters").map(fn(ch) {
      match ch {
        Object(o) =>
          {
            title: match o.get("title") {
              Some(String(s)) => s
              _ => ""
            },
            offset: int(o.get("offset")),
          }
        _ => { title: "", offset: 0 }
      }
    }),
    heads: list("heads").map(fn(h) { int(Some(h)) }),
    md: list("md"),
  }
}

///|
test "indents: a paragraph's own spacing replaced by two ideographic spaces, a heading left; offsets follow" {
  let chunk = "第一章 车站\n  他到了。\n\u{3000}\u{3000}她也到了。\n"
  // (the core says the first line is a heading: the block starts at 100 of the text)
  let heads : Map[Int, Bool] = { 100: true }
  let drawn = render_chunk(chunk, 100, heads, true)
  assert_eq(drawn, "第一章 车站\n\u{3000}\u{3000}他到了。\n\u{3000}\u{3000}她也到了。\n")
  let raw = chunk.find("他").unwrap()
  assert_eq(drawn.view(start_offset=render_offset(chunk, 100, heads, raw, true)).has_prefix("他"), true)
  let raw2 = chunk.find("她").unwrap()
  assert_eq(drawn.view(start_offset=render_offset(chunk, 100, heads, raw2, true)).has_prefix("她"), true)
  // the same block elsewhere in the text: its first line indented too
  assert_true(render_chunk(chunk, 0, heads, true).has_prefix("\u{3000}\u{3000}第一章"))
}

///|
test "a novel as the core read it: blocks, chapters by block, an offset found again" {
  let novel = book_of("小说.txt", kept_book(novel_text(), false), "UTF-8", false, false)
  assert_eq(novel.chapters.length(), 5)
  assert_eq(novel.chapters[1].0, "第二章 旧仓库")
  let (k, o) = novel.at(3000)
  assert_eq(novel.starts[k] + o, 3000)
  assert_eq(novel.offset_of(k, 0.0), novel.starts[k])
  // the core's heading lines are not indented
  assert_true(novel.heads.contains(0) || novel.heads.contains(novel_text().find("第一章").unwrap()))
}

///|
test "Markdown cut into blocks at its tree's nodes, a heading starting one, each from its line" {
  let text = fixture_markdown()
  let novel = book_of("发布清单.md", kept_book(text, true), "UTF-8", false, true)
  // 发布清单, 准备, 检查: each a block of its own from its heading's line, the contents at each
  assert_eq(novel.chapters.map(fn(ch) { (ch.0, ch.2) }), [("发布清单", 0), ("准备", 0), ("检查", 0)])
  assert_eq(novel.starts.length(), 3)
  assert_eq(novel.starts[1], text.find("## 准备").unwrap())
  assert_eq(novel.chunks.iter().fold(init="", fn(a, s) { a + s }), text)
  // a long one cut where it passes the budget, at a node's line
  let (parts, starts) = md_chunks(novel.parts.iter().flat_map(fn(p) { p.iter() }).collect(), text, budget=40)
  assert_true(parts.length() > 3)
  for at in starts {
    assert_true(at == 0 || text.at(at - 1).to_int() == 10)
  }
}

///|
/// A made-up novel of a few chapters (every sentence made up here).
fn novel_text() -> String {
  match kept_novel.val {
    Some(s) => s
    None => {
      let titles = ["第一章 雨后的车站", "第二章 旧仓库", "第三章 灯塔的钥匙", "第四章 回程", "尾声"]
      let lines = [
        "雨停的时候，站台上只剩下一盏灯还亮着，他把伞收好，靠在柱子旁边数着远处驶来的车厢。",
        "她说那封信是从北边寄来的，邮戳已经模糊，只能看出一个“七”字，像是某个月份，也像是某条街的门牌。",
        "仓库的门比想象中轻，推开时没有声音，只有一股潮湿的木头味道慢慢涌出来。",
        "他们在角落里找到一只铁皮箱子，箱子上贴着褪色的标签，写着一串谁也看不懂的编号。",
        "风从海面吹过来，把灯塔下的旗子拉得笔直，守塔的老人说今晚不会再有船经过了。",
        "钥匙并不在抽屉里，而是被缝进了一本旧账簿的封皮，摸上去能感到一点细小的凸起。",
        "回程的路上谁都没有说话，车窗外的田野一片一片地向后退去，像翻过的书页。",
        "等到天亮，他终于明白，那串编号指的不是箱子，而是车站里的一排储物柜。",
      ]
      let out = StringBuilder()
      for i, title in titles {
        out.write_string(title)
        out.write_char('\n')
        for k in 0..<14 {
          out.write_string("\u{3000}\u{3000}")
          out.write_string(lines[(i * 3 + k) % lines.length()])
          out.write_string(lines[(i + k * 5 + 1) % lines.length()])
          out.write_char('\n')
        }
        out.write_char('\n')
      }
      let s = out.to_string()
      kept_novel.val = Some(s)
      s
    }
  }
}

///|
// kept across runs: made from the words above alone, the same every time
let kept_novel : Ref[String?] = { val: None }

///|
fn fixture_markdown() -> String {
  "# 发布清单\n\n这份清单在每次发布前过一遍，**每一项**都要有人确认。\n\n## 准备\n\n- 版本号已经改好\n- 更新说明写完，交给 *两个人* 读过\n- 截图换成新的\n\n## 检查\n\n1. 在手机上装一遍，从头点到尾\n2. 看一眼 `release.log` 里有没有报错\n3. 旧版本升级上来，草稿还在\n\n> 有一项不确定，就先不发。\n\n---\n\n最后更新：十月中旬。\n"
}
