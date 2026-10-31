# Styles

What a box or a line of words looks like is a value, named, made of the theme's tokens, and given to the call that
builds it:

```moonbit
let card : @ui.Style = @ui.css("w=Full p=S5 radius=Xl3 bg=Card pressed{bg=Over(Card, A(Fg, O5))}")
c.box(style=card, id=c.id("row"), fn() { … })
c.text(title, style=@sf.title)
c.rich(runs, style=@sf.body)
```

`src/ui/style_tokens.mbt` has the tokens, `src/ui/style.mbt` the values, `src/kit/styles.mbt` kit's recipes.

A named style is said in one of two ways, and which is not a choice:

- all tokens and numbers: its text, `@ui.css("…")` (`src/ui/style_css.mbt`). The same items as `style(…)`'s, `row`,
  `clip` and `dashed` alone for `=true`, a state's block in braces; a `.then(…)` of named styles adds its literal part the
  same way (`base.then(@ui.css("bg=AccentBg"))`). Longer than a line, its text goes on `#|` lines.
- naming a variable (`w=@sf.grow`, `Fixed(side_w)`, `shadow=@sf.floating.cast()`) or worked out: `@ui.style(…)`;
  inside a function always `@ui.style(…)` (made as the frame is built, no constant).

```moonbit
let card : @ui.Style = @ui.css("w=Full p=S5 radius=Xl3 bg=Card pressed{bg=Over(Card, A(Fg, O5))}")
let card_on : @ui.Style = card.then(@ui.css("bg=Selected"))
let side : @ui.Style = @ui.style(w=@sf.grow, px=S2) // names the library's length
```

Why text: a constant is made in the program's start, and moonc made each `style(…)` constant ~5-10 KB of C there (an
assignment and a release for each of its ~38 optional parameters), ~1400 of them ~11.8 MB of one function built again
on every build (2026-10-24: 38 s of Windows' MSVC). Said as text it is a string, read once as the app starts into
the same Style. A word it does not know aborts, naming the text, so a mistyped one fails every test at once.
detlint's `style-text` holds it (forbidden: none left), and prints the text to write in its place.

## Tokens

A style says names, not numbers. The numbers are in the theme (`Theme`, set with `Ctx::set_theme`), looked up as the
node is built, so one style is a constant and right in light and dark, wide and narrow.

| token | names | values |
|---|---|---|
| `Space` (padding, gaps) | `S0` `SPx` `S0_5` `S1` `S1_25` `S1_5` … `S4` `S4_5` `S5` … `S12` `S14` `S16` `S20` … `S96` | Tailwind v3.4's: a step 4 px; v4's quarter steps where still.fail says them (5, 18) |
| `Len` (sizes) | `Hug` (what it holds), `Cut` (what it holds, cut short where its row has less), `Full`, `Grow(k)`, `Pct(p)` (a share of the parent's room, CSS's `50%`), `Fixed(v)`, `Within(v)` (a least across only, `min_w`: `v` where the parent has the room, all of it where it has less, CSS's `min(100%, 320px)`), and every `Space` name | |
| `Radius` | `Sharp` `Sm` `Base` `Md` `Lg` `Xl` `Xl1_5` `Xl2` `Xl3` `Xl4` `Full` (a pill) `Inner` | `Theme.radii` (Tailwind's by default; `Xl1_5` 14, `Xl4` 32) |
| `TextSize` (size and line) | `Xs3` `Xs2` `Xs` `Sm` `Base` `Lg` `Xl` `Xl2` `Xl3` `Xl4` | `Theme.text` (Tailwind's by default; `Xs2` 11 on 16, `Xs3` 10 on 14) |
| `Leading` (a line's height said apart from the size's) | `L3` `L4` `L4_75` `L5` … `L10`, `Font` (the font's own) | `Theme.leading` (Tailwind's leading-3 … leading-10 by default: 12, 16 … 40 px; `L4_75` 19) |
| `Weight` | `Normal` `Medium` `Semibold` `Bold` | 400 … 700 |
| `Tracking` (letter spacing) | `Tighter` `Tight` `Normal` `Wide` `Wider` `Widest` | Tailwind's, in ems of the words' size; `Exact(px)` in pixels |
| `Color` | `Bg` `Surface` `Raised` `Card` `Fg` `Muted` `Subtle` `Faint` `Line` `Border` `Accent` `AccentText` `AccentBg` `OnAccent` `Primary` `OnPrimary` `Positive` `Danger` `DangerBg` `OnDanger` `Neutral` `Hover` `Selected` `Focus` `Scrim` `Link` `ShadowC` `Warn` `Tint` `TintStrong` `Floating` `Veil` `VeilDeep` `OnVeil` `Lifted` `Theater` `Wash` `Sidebar` `FieldHover` `Clear`; `A(c, o)` at an opacity, `Over(under, top)` | the theme's fields (`Tint` the words' colour at 6%, `TintStrong` at 8%, `Floating` Raised at 72% over Bg, `Veil` black at 62%, `VeilDeep` at 92%, `OnVeil` white, `Lifted` a segmented choice's thumb, `Theater` black, `Wash` a quiet wash under what comes onto it: #322D24 at 6.5%, white at 5% in the dark; `Sidebar` a sidebar's ground beside the page, `FieldHover` a field's edge pointed at or written in) |
| `Opacity` | `O0` `O5` … `O95` `O100` | |
| `Stroke` (an edge) | `B0` `B0_5` (a hairline) `B1` `B2` `B4` `B8` | |
| `Shadow` | `NoShadow` `Sm` `Base` `Md` `Lg` `Xl` | Tailwind's first layer, in `Theme.shadow` |

`Exact(…)` is a value off the scale. It belongs in an app's token file (detlint's `style.tokens`), named:
`pub let code_size : @ui.TextSize = Exact(13.0, 0.0)`. Out of the scale's bounds (below 0, an opacity past 1) it
stops the frame, saying what it was.

Outside a style: `c.space(S11)`, `c.color(Fg)`, `c.text_size(Sm)`.

## The theme, wide and narrow

`c.set_theme(wide, narrow=…, narrow_below=700.0)` once, as the app starts and when the person picks light or dark.
Each frame, before it builds, the window's width picks the one in force (`Ctx::narrow`). `c.with_theme(t, body)` puts
another under part of a view.

## Properties

A box: `row`, `w` `h` `min_w` `max_w` `min_h` `max_h`, `p` `px` `py` `pl` `pr` `pt` `pb`, `m` `mx` `my` `ml` `mr` `mt` `mb`
(margins, as CSS's), `gap`, `align`, `justify`,
`bg`, `radius`, `border`, `border_color`, `dashed` (the border as CSS's `dashed`: dashes three of its widths and gaps
two, spread to come round evenly), `shadow`, `clip`, `opacity`. Words: `size` (with its line), `weight`, `color`,
`leading` (the line's height in place of the size's own; `line=` in the call over it), `w`, `center`, `wrap` (false: one
line, cut with an ellipsis), `tracking`, `max_lines` (wrapped words cut after that
many lines, the last ending in an ellipsis: what follows of its paragraph up to what fits with it, as Android's
`maxLines`; a count, so no style-literal). Letter spacing is Android's: each cluster's advance has it, its piece drawn
half of it in; words with it are shaped with no ligatures (`@hostapi.style_no_ligatures`), each cluster spaced on its own.
`tabular` (CSS's `font-variant-numeric: tabular-nums`): digits all one width, the font's tabular figures
(`@hostapi.style_tabular`), so a number keeps its width as it changes (a percentage, a time running, a count) and what
is beside it stays put. Where words say nothing of it the theme's `tabular` decides, for the app's own words (`Ctx::text`,
a `Ctx::rich` not `words`): an app whose numbers move sets it once there, as a web page sets it on its root, rather than
on each number. What people wrote (`words`), a face shown in itself and a book's pages keep the font's own figures. Words
with no digit are shaped as they are either way.
Rich text (`Ctx::rich`) has both: letter spacing in every run, and `max_lines` (the ellipsis in the style of the run it
follows). Behaviour is not a style (`id`, `glass`, `notch_*`,
`aspect`, `tx`/`ty`, a place in the parent: `left` `top` `right` `bottom`, `moves`).

A box's corner is the one it has standing alone. Where the layout puts it in the corners of a rounded container that
shows (the nearest round it with a ground, an edge, glass or a cut: `Tester::corner_faults`'s), filling it (in all four
of its corners, as far from each edge), its corner is worked out after layout, concentric with the container's
(smooth.mbt `concentric`: corners.mbt `corners_in_corners`). In only some of its corners it keeps its own, all four
alike: concentric there alone it would have corners unlike each other, which mbui never makes by the way (only a
design says them, below); `corner_faults` says where it is not concentric, and the page gives it the corner, or the
place, that is. Not a capsule or a circle (its corner half its shorter
side): its shape is its height's, and where it stands is what makes it concentric (the container's corner its distance
and its half), which the page lays out and `corner_faults` checks; nor one too small for the corner it would have there,
nor one at different distances from the two edges: each keeps its own and `corner_faults` says so.

`radius=Inner`: the corner of the container the corner rule measures against, as above, for a box near only one pair
of its edges too (a row across a card, near its sides), drawn square where it cannot be (in no rounded container, near
none of its edges, nearer one edge than another) and said so by `corner_faults`: a test fails, a person's screen does not
stop. `InnerOr(own)`: the same, its own corner where it stands alone, or where following would leave its corners
unlike. `Around`: the other way, the container's corner round what lies in its corner.

Each corner is its own (`Corners(tl, tr, br, bl)`, CSS's border-radius of four; every renderer draws a box's corner by
the quarter it is in), and the rule works corner by corner. Corners unlike each other are a design's, said
(`Corners`, `LinkedEach`: a panel whose corners at the window's edge follow the window's and whose others stand alone),
each looked at and kept by a person (an app's detlint `corners-each`); what mbui works out is unlike only as the
container's corners are, where it fills it (an `Inner` one, with none of its own, follows the container's matching
corner in all four). A box whose own corner is rounder than any it could have concentric in a corner it stands in (a
card's 26 in a window's 16) keeps it, alone. `Tester::mixed_corners` lists every box drawn with corners unlike, and how.

A theme may say its corner ladder (`Theme::corner_ladder`, outermost first): the corners nested things are round by,
each the next in at one inset. `corner_faults` then holds a rounded container with something in its corner, and a
smooth box there, to its steps (a capsule or a circle round by its shape; a control's own parts hugging its edge and
what is in the last step only concentric). Under such a theme the Tester holds every frame a test draws with nothing
moving to the rule: a fault fails the test there, with what and where (`Tester::new(corners_held=false)` for one that
draws a fault on purpose, to find it). So every state a test walks through keeps to it, not only the screens a test of
corners looks at.

Not the rule's: what scrolls in the container (a list, a box kept to a height, a strip scrolled sideways: where it is
from the container's corner is not fixed; `Inner` in one is near only the edges it does not scroll past), and what is
in a picture (said to be one: Role `Image`, a drawing of another system's screen, whose corners are what it draws).

## Short of room

A box has the room its parent gives it. When that is less than what it holds, these rules decide what happens, and
nothing else gives way:

- A box sized by what it holds (in a row, with no width of its own) is never laid narrower than what it holds needs at
  least (CSS's `min-width: auto`): words on one line, icons, boxes of a fixed size, side by side; the widest of what is
  under each other. Worked out as it is laid out (Node's `least`), it is what its row may squeeze it to. A box sized by
  its room (`Fill`, `Pct`) takes what it is given, and what it holds is squeezed in it where that is too little: a
  fault, which `Tester::squeeze_faults` says (two things drawn over each other, something cut off by what clips it or
  by the window, words cut down to nothing, words wrapped narrower than a word of them or four characters, a field's
  placeholder cut down to nothing).
- Words on one line (`wrap=false`, Ctx::text's and Ctx::rich's alike) are one line whatever they hold: their line
  breaks are spaces (CSS's white-space: nowrap), unless `breaks` keeps them (code shown as written, in what scrolls
  sideways: CSS's pre).
- Words on one line, and what is said to be cut short (`w=Cut`), are never laid wider than a column they are in,
  whatever its alignment: cut with an ellipsis there. A `max_w` said as well is that where the column has the room and
  the column's where it has less (CSS's `min(100%, 560px)`). In a row they are as wide as they are, unless they say
  otherwise.
- Words beside something else in a row (a value, a button, a switch, a chevron) are words of a length known (a title,
  a label, a button's words, a short number) that fit there whole in the narrowest window, in every language; words of
  no length known (what is under way, why something failed, a note, a line of facts, a path) stand on a line of their
  own, what their row has at its end on its first line beside its title (a round control, a switch, a radio, across
  the row's middle: on its first line it would stand in the row's corner, not concentric with it; its title and its
  note beside it are words of a length known, a line there or a paragraph of lines, never a line but for a word or
  two it pushes onto a second). A name cut short beside a time or a count says so (`w=Cut`). What stands before words in their row (a mark, a face, a box to tick, a table's labels) is the
  row's own column, not beside them; so is another share of a row the words' box is a share of (tiles side by side). `Tester::squeeze_faults` says words broken onto lines or cut short only for what
  is after them in their row (in its room as well they would be one line, whole), unless they are said to be cut
  short.
- What may give way says so, and how:
  - words cut short with an ellipsis: `w=Cut` (as wide as they are, cut where the row has less), `w=Fill` (what the
    row leaves, cut where that is less), `min_w` the least of them kept; in a row that leaves parts out (`drop`
    below), four of their size are kept before a part leaves, all of them with Ctx::text's `keep` (cut only once all
    that may leave has left: a way's last folder);
  - a box that takes what its row leaves, but never less than what it holds needs: `w=Fill` with `keep` (words cut
    short in it counted at what they keep, four of their size: what is beside it gives way first);
  - a box as wide as it is said (`w=Px`) where its row has the room, less down to a least said below it (`min_w`)
    where it has not (CSS's width with its min-width in a flex row): a field 320 wide, 160 at least;
  - a part left out of its row: `Ctx::box drop=k`, there whole (as wide as what it holds) or not at all, the lowest k
    first, of the same k the last in the row first; left out, laid out nowhere, drawn and pressed nowhere; `more` is the row's ⋯, there only while something of it is left out, and
    `Ctx::left_out(id)` says what a row left out, for its ⋯ to offer instead (read back: the frame is built again
    when it changes as it is laid out). The library's `@sf.tools_row` is a row of tools whose ⋯ does that. Such rows,
    each as wide as what it keeps, in a row that has not the room for all it holds, leave out their parts as though
    they were one row's (the lowest k across them first, of the same the last in the row first) until the row has the
    room, what else is in it given way as their own row would have it (each down to the least it needs, words cut short
    to four of their size); then they are not squeezed further: what is beside them gives way no more than that, and
    none of their room is left empty (a new chat's station and model: the model's runtime and how hard it thinks
    leave, k 3 and 4, before the station's name, 5);
  - words on one line said a shorter way where they have less room: Ctx::text's `shorter`, and a field's
    placeholder's (Ctx::editor `shorter`: 搜索全部内容, then 搜索), each shorter than the one before. The longest of
    them all that fits is shown whole (SwiftUI's ViewThatFits), and in a row they need no more than the shortest at
    least; where none fits, the shortest is cut with an ellipsis. A placeholder is words on one line as any others:
    never cut by its field's edge, cut with an ellipsis where it has no shorter way that fits (one an agent wrote has
    none);
  - a row of ways of saying one thing, each shorter than the one before, of which it shows only the first that fits
    its room whole, the last where none does: `Ctx::box one_of` (SwiftUI's ViewThatFits for what is more than words:
    an allowance's chips all in words, then in figures, then by their marks, one way for all of them); it needs at
    least what its last way needs, and the ways it does not show are laid out, drawn, pressed and read out nowhere;
  - what is cut or scrolled by its own box: `clip`, `sideways` (not a box's corners: what draws inside them keeps to
    them itself, as a press's ripple does).
- A row that has not the room for every least even so (a page that said not how something gives, words longer than
  anyone thought) does not run past its room: as a last resort (flex's `soft_min`, `last_resort`) words on one line in
  it that say not how they give, and what holds them, come down, the widest first, all to one width where that is
  enough, cut with an ellipsis; what never gives way (an icon, a box of a said width, a control: what is pressed, a
  button, a chip) stays as it is. None is cut in vain: where that would not make the row fit, they stay whole. The worst a row
  shows is words cut short, never one thing over another. So words a row holds as wide as they are stay whole while
  there is room and are cut only when nothing else can give, the longest first (a station's name after a chat's title
  cut short): what is to give first says so (`w=Cut`, `drop`). What still is a fault: words cut to nothing, what never
  gives way running past its room.

## Corners linked

A corner says where its radius comes from (`CornerOf`, ui/corner_of.mbt), not a number worked out where it is used:

- the roots: `Window`, the window's corner as the system draws it now (`@hostapi.window_corner`: 0 square, maximized,
  filling the screen), and `Own(r)`, a number of its own (a theme's ladder);
- every other corner `Follow(from, inset, alone)`: `from` followed `inset` in from its edges, concentric with it where
  the theme's ranges let a corner be so round and stand so far in (`Theme::corner_fit`), else `alone`, as round as it
  is standing alone.

A box takes one as its radius (`Radius::Linked`, each corner its own with `Radius::LinkedEach`); its radius is read
each frame, so the window's corner changing (maximized, another system) changes the whole chain. Where a linked box
lies in its container's corner, the corner rule (corners.mbt `corner_faults`) holds it to its link: as far in from the
container's edges as its link's inset, and the container's corner there the one it follows. So a panel and what is
drawn in it can not drift apart: still.fail's tape panels and closed bar follow the window, the rail's grounds follow
the bar or the panel they stand in (src/sf/tokens.mbt `window_follow`, `tape_corners`, `closed_bar_of`,
`rail_ground_radius`).

## The four rules

1. In one `style(…)` each property is said once. Padding from the finer to the coarser: `pl` `pr` `pt` `pb` over
   `px` `py` over `p`.
2. `a.then(b)`: what `b` says over `a`; `b`'s coarser padding takes `a`'s finer with it (`b`'s `px` drops `a`'s `pl`
   and `pr`); their state blocks merge the same way. A recipe is base, then its variants, then their compounds; what
   the call says loosely (`pad=`, `bg=`, `size=`) last.
3. A node's states are laid on in one order, the later winning: `narrow`, `dark`, `selected`, `hovered`, `focused`,
   `pressed`, `disabled`. `pressed`, `hovered`, `focused` come from the box's `id` (`Ctx::pressed`, `lit`,
   `focus_shown`: the inputs the last frame took); `selected`, `disabled` are said in the call; `dark` is the theme's,
   `narrow` the width's. Words have `dark` and `narrow` alone.
4. What answers the hand is a tint laid over what is there, never a ground in its place: the ground `hovered` and
   `pressed` say goes over the ground under it (the box's own, its `selected` one: `Over(under, top)`), as the kit's
   `tinted` does, so `hovered{bg=Hover}` is a step more on any ground, pressed a step more again. A box pointed at
   is pointed at while the pointer is on what is drawn in it (`Ctx::hovered`, as CSS's `:hover`): a tab and its ×,
   the × pointed at, are both lit, the × a step more than the tab (still.fail's docs/ui-panels.md 悬停).

Nothing cascades: no selectors, words do not inherit from the boxes round them. Nothing in a style moves by itself
(no transition): a state changed is the other value from the frame that sees it. An animation is motion's.

## kit's recipes

`card(tone)`, `list_card()`, `list_row(density)`, `section_header(indent)`, `button_style(size, tone)` with
`button_text`, `field(size)`, `badge(tone)` with `badge_text`, `panel()`; words `row_title`, `row_sub`, `row_value`,
`section_title`. Tokens alone: an app's theme is their look. What does not fit goes in the app's own styles.

## The lint

detlint (docs/detlint.md) counts, file by file, only going down:

- `style-literal`: a number in a box's or words' look (`c.box(pad=12.0)`, `c.text(size=13.0)`), in `@ui.style(…)`
  and its kin (a `@ui.css("…")` text's numbers too), or an `Exact(…)` outside the token files;
- `box-loose`: a call that says its look loosely (`pad=`, `bg=`, `size=`…) rather than by `style=`;
- `style-exact`: every `Exact(…)`, the token files' too (and a style's text's).
- `style-text`: a named style (a top-level `let`, a `.then(…)` of one) said as `@ui.style(…)` with nothing but
  tokens and numbers in it: forbidden; its message is the `@ui.css("…")` to write instead.

What draws a look that is not the theme's is outside them all (detlint.json `style.outside`): a program of its own
drawing to units of its own, every size a share of the window's width (still.fail's keyboard, laid out as WeChat's
in its units, 1080 across), has no place on the theme's scale, and its numbers are its design's data, as a
layout table's are. A page, a part of the library, anything of the app's own look is never put there.

`Tester::census()` gives the values the last frame used, by kind (sizes of words, weights, paddings, corners,
colours): an app counts how many each kind has across its screens, which should go down.

## Seen

What is drawn to be seen with nothing in it (a gauge's empty cell, a track, a line, each bar and shape of a page's
bones (`Ctx::bones`), a sheet's grip: a box holding no words, picture or icon, nor under any drawn after it) stands at least `contrast_mark_least`
(1.25, WCAG 2's ratio) off what it lies on, by its ground or by its edge: `Tester::contrast_faults` says where it does
not, measured on the frame as drawn (the colour under it worked out from what was drawn before it there; loops at their
start). A ground under words carries none of this: its words carry it. So that one colour is seen on whatever it lies
on (the page, a card, a menu), the theme's `line` and `neutral` are the ink at an opacity, not an opaque grey: an opaque
grey stands a step off the one ground it was chosen on and none off another.

Words and icons are held to WCAG's AA by the same check: words 4.5:1 (3:1 at 24 and up, or 18.66 and up bold:
`contrast_words_least`), measured at their faintest letter; an icon (Ctx::shapes, 48 across at most) 3:1
(`contrast_icon_least`), at its strongest piece; a larger shape is a drawing or an outline, held as a line. Not asked:
what is in a widget said disabled (`Ctx::semantics` `disabled`: a button that cannot be pressed says so, it is not only
faded), what lies on a picture, what is said to be a picture (Role Image), and what draws in its own colours
(`Ctx::own_colours`: a maker's mark, an illustration). The theme gives an ink for each colour words come in: `accent_text`
for the accent's (the accent itself a fill's and a mark's), `warn_ink` (`WarnInk`) for warn's; `@ui.ink_on` picks the
ink that reads on a colour a person chose.
