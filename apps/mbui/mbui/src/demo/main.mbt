// The prototype's demo: a chat screen with 10,000 messages in a virtual
// list, a composer that takes the system input method, and tabs whose
// indicator moves on a spring.

///|
struct Msg {
  author : Int
  text : String
  time : String
}

///|
let names : Array[String] = ["Ada", "林小雨", "Grace", "陈默", "Linus", "王珂"]

///|
let colors : Array[Int64] = [
  0xFF9F0AFFL, 0x30D158FFL, 0x0A84FFFFL, 0xBF5AF2FFL, 0xFF375FFFL, 0x64D2FFFFL,
]

///|
let phrases : Array[String] = [
  "好的，我晚点看一下这个 PR。",
  "The layout pass is about 0.3 ms for this screen.",
  "输入法的候选框现在会跟着光标走了 🎉",
  "Can you check whether the list keeps its position when rows grow?",
  "我把滚动的惯性改成了指数衰减，手感接近系统的。",
  "MoonBit compiles this whole app in under a second.",
  "周末一起去爬山吗？天气预报说是晴天 ☀️",
  "Merged. Thanks for the quick fix!",
  "这段文字故意写得比较长，用来测试自动换行：中文可以在任意两个字之间断开，English words should only break at spaces, and mixed 中英文 text should wrap naturally without overflowing the bubble.",
  "👍",
  "Let's ship it after the benchmark looks good on the iPhone simulator.",
  "收到",
  "家人们谁懂啊，这个 bug 只在周五下午出现 😂",
  "Line one\nLine two after a hard break",
]

///|
fn make_messages(n : Int) -> Array[Msg] {
  let out = []
  let mut seed = 12345
  for i in 0..<n {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let a = seed % names.length()
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let p = seed % phrases.length()
    let mins = i / 3
    let hh = 9 + mins / 60 % 12
    let mm = mins % 60
    let time = "\{hh}:\{if mm < 10 { "0" } else { "" }}\{mm}"
    out.push({ author: a, text: phrases[p], time })
  }
  out
}

///|
struct App {
  msgs : Array[Msg]
  initial : Int
  mut tab : Int
  mut sent : Int
  /// what is being written (the composer's field shows it; sending takes it)
  draft : @ui.Field
}

///|
let app : App = { msgs: make_messages(10000), initial: 10000, tab: 0, sent: 0, draft: @ui.Field::new() }

///|
fn message_row(c : @ui.Ctx, i : Int) -> Unit {
  let m = app.msgs[i]
  let mine = m.author == 0
  // messages sent in this session slide in on a spring
  let appear = if i >= app.initial {
    c.spring("appear", 1.0, from=0.0, stiffness=260.0, damping=24.0)
  } else {
    1.0
  }
  c.box(
    dir=Row,
    padx=16.0,
    pady=6.0,
    gap=10.0,
    align=AStart,
    opacity=if appear * 1.4 > 1.0 { 1.0 } else { appear * 1.4 },
    ty=(1.0 - appear) * 24.0,
    fn() {
      c.box(
        w=Px(36.0),
        h=Px(36.0),
        radius=18.0,
        bg=colors[m.author],
        align=ACenter,
        justify=JCenter,
        fn() {
          c.text(
            names[m.author].substring(start=0, end=1),
            size=15.0,
            weight=600,
            color=0xFFFFFFFFL,
            wrap=false,
          )
          |> ignore
        },
      )
      |> ignore
      c.box(
        w=Fill(1.0),
        gap=4.0,
        align=AStart,
        fn() {
          c.row(gap=8.0, fn() {
            c.text(names[m.author], size=13.0, weight=600, wrap=false) |> ignore
            c.text(m.time, size=12.0, color=0x8E8E93FFL, wrap=false) |> ignore
          })
          |> ignore
          c.box(
            padx=12.0,
            pady=8.0,
            radius=14.0,
            bg=if mine { 0x0A84FFFFL } else { 0xFFFFFFFFL },
            shadow=if mine { 0.0 } else { 3.0 },
            fn() {
              c.text(
                m.text,
                size=15.0,
                color=if mine { 0xFFFFFFFFL } else { 0x1D1D1FFFL },
              )
              |> ignore
            },
          )
          |> ignore
        },
      )
      |> ignore
    },
  )
  |> ignore
}

///|
fn send(text : String) -> Unit {
  app.msgs.push({ author: 0, text, time: "现在" })
  app.sent = app.sent + 1
}

///|
fn view(c : @ui.Ctx) -> Unit {
  // the demo keeps iOS's colours (its goldens on every platform are drawn in them)
  c.set_theme(@ui.Theme::ios_light())
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0xF5F5F7FFL, fn() {
    // header
    c.box(
      dir=Row,
      padx=16.0,
      pady=10.0,
      gap=12.0,
      align=ACenter,
      bg=0xFFFFFFFFL,
      fn() {
        c.text("MoonBit UI", size=17.0, weight=700, wrap=false) |> ignore
        let narrow = c.width < 600.0
        app.tab = c.segmented(
          "tabs",
          ["全部", "未读", "@我"],
          app.tab,
          item_w=if narrow { 58.0 } else { 76.0 },
        )
        c.spacer()
        if !narrow {
          c.text(
          "\{app.msgs.length()} 条",
          size=12.0,
          color=0x8E8E93FFL,
          wrap=false,
          )
          |> ignore
        }
      },
    )
    |> ignore
    c.box(h=Px(1.0), bg=0xE5E5EAFFL, fn() {  }) |> ignore
    c.list(
      "messages",
      app.msgs.length(),
      64.0,
      fn(i) { message_row(c, i) },
      stick_end=true,
    )
    |> ignore
    // composer
    c.box(
      dir=Row,
      padx=12.0,
      pady=10.0,
      gap=10.0,
      align=AEnd,
      bg=0xFFFFFFFFL,
      fn() {
        let r = c.editor("composer", placeholder="输入消息，回车发送", field=app.draft)
        match r.submitted {
          Some(t) => send(t)
          None => ()
        }
        if c.button("发送") {
          let st = app.draft.take()
          if st.length() > 0 {
            send(st)
          }
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
fn main {
  @ui.run("MoonBit UI 原型", view)
}
