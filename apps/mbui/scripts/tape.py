# tape.py LOG NAME MODE [FRAME] : a dev build's tape (its run's MBUI_DRAW_LOG and MBUI_TEXT_RECORD lines: DRAWHASH,
# INPUT, MSG, ENV, NATIVESAID, VIEWSCRIPT, TEXTREC; android/apk.json's debug build keeps one each start) made a Tester's
# test of the app over the fixture MODE (what MBUI_FIXTURE it ran with: src/sffix), src/sfapp/tape_NAME_wbtest.mbt
# (git ignores it): the run's frames drawn again over its text, each frame's hash the run's or the first that is not
# said (TAPE lines). FRAME: given again up to that frame and no further (the frame a bug is at). Used by scripts/tape.sh
import re, sys
if sys.argv[1] == '--fields':
    f = sys.argv[2].split(); print(dict(frame=f[1], time=f[2], w=f[3], h=f[4], scale=f[5], hash=f[6], stable=f[7] if len(f) > 7 else '0')); sys.exit(0)
kinds = ('DRAWHASH', 'INPUT', 'MSG', 'NATIVESAID', 'VIEWSCRIPT', 'ENV', 'TEXTREC')
# (a line as logcat says it, the app's tag before its message: "… I mbui    : MESSAGE"; the app's own file has the
# message alone)
logcat = re.compile(r'^.*?\s[VDIWEF]\s+mbui\s*: ')

def body(line):
    m = logcat.match(line)
    return line[m.end():] if m else line

def tape_lines(text, upto=None):
    """The tape's text answers (TEXTREC) and its run (ENV, DRAWHASH, INPUT, MSG, …) in their order; with `upto`, the
    run up to that frame's DRAWHASH and nothing after it (what came after is the next frames'). Text answers kept
    whole: they are what the host said of its text, asked again at any frame. A record is what a message begins with
    (its kind, a space): the same words inside another's (a message's JSON) are its words, not a record."""
    rec, run, done = [], [], False
    for line in text.replace('\r\n', '\n').split('\n'):
        b = body(line)
        k = b.split(' ', 1)[0]
        if k not in kinds or ' ' not in b:
            continue
        if k == 'TEXTREC':
            rec.append(b[len('TEXTREC '):]); continue
        if done:
            continue
        run.append(b)
        if upto is not None and k == 'DRAWHASH' and int(b.split()[1]) >= upto:
            done = True
    return rec, run

if sys.argv[1] == '--selftest':
    # (a run made up: its frames 1 to 3 as logcat says them, the input and the message before frames 2 and 3, a text
    # answer after frame 3; words that look like records inside a message and an input; a line of the app's file)
    log = '\n'.join(['11-06 08:43:30.1  1  2 I mbui    : ENV {"dark":0}',
                     '11-06 08:43:30.2  1  2 I mbui    : DRAWHASH 1 10 350 800 3 111 0',
                     '11-06 08:43:30.3  1  2 I mbui    : INPUT {"k":"text","s":"DRAWHASH hello TEXTREC x"}',
                     '11-06 08:43:30.4  1  2 I mbui    : TEXTREC {"t":1}',
                     'DRAWHASH 2 26 350 800 3 222 0',
                     '11-06 08:43:30.5  1  2 I mbui    : MSG {"c":"core","j":"{\\"w\\":\\"INPUT DRAWHASH 9\\"}"}',
                     '11-06 08:43:30.6  1  2 I other   : DRAWHASH 7 1 1 1 1 1 0',
                     '11-06 08:43:30.7  1  2 I mbui    : DRAWHASH 3 43 350 800 3 333 0',
                     '11-06 08:43:30.8  1  2 I mbui    : INPUT {"k":"key"}',
                     '11-06 08:43:30.9  1  2 I mbui    : TEXTREC {"t":2}'])
    rec, run = tape_lines(log, 2)
    assert run == ['ENV {"dark":0}', 'DRAWHASH 1 10 350 800 3 111 0', 'INPUT {"k":"text","s":"DRAWHASH hello TEXTREC x"}',
                   'DRAWHASH 2 26 350 800 3 222 0'], run
    assert rec == ['{"t":1}', '{"t":2}'], rec
    rec, run = tape_lines(log)
    assert [r.split()[0] for r in run] == ['ENV', 'DRAWHASH', 'INPUT', 'DRAWHASH', 'MSG', 'DRAWHASH', 'INPUT'], run
    rec, run = tape_lines(log, 1)
    assert run[-1].startswith('DRAWHASH 1 '), run
    print('tape: selftest passed'); sys.exit(0)
log, name, mode = sys.argv[1], sys.argv[2], sys.argv[3]
upto = int(sys.argv[4]) if len(sys.argv) > 4 else None
assert re.fullmatch(r'[a-z0-9_]+', name), 'NAME: lowercase letters, digits, _'
text, frames = tape_lines(open(log, encoding='utf-8', errors='replace').read(), upto)
n = sum(1 for l in frames if l.startswith('DRAWHASH '))
first = next((l for l in frames if l.startswith('DRAWHASH ')), None)
if not first: sys.exit(f'tape: no DRAWHASH line in {log} (was it a dev build, MBUI_DRAW_LOG=1?)')
# (DRAWHASH frame time width height scale hash stable: app.mbt's line)
f = first.split()
assert f[0] == 'DRAWHASH' and len(f) >= 7, f'tape: not a DRAWHASH line: {first}'
t0, w, h, scale = f[2], f[3], f[4], f[5]
stable = 'true' if len(f) > 7 and f[7] == '1' else 'false'
def lit(lines): return '\n'.join('  #|' + l for l in lines) or '  #|'
body = f'''// A dev build's tape ({log}) given again over the fixture "{mode}"{f" up to frame {upto}" if upto is not None else ""}: made by
// scripts/tape.sh (scripts/tape.py), not kept (git ignores tape_*_wbtest.mbt).

///|
let tape_{name}_text : String =
{lit(text)}

///|
let tape_{name}_run : String =
{lit(frames)}

///|
test "tape {name}: the run drawn again, frame for frame" {{
  new_run()
  // (as src/sffix's main begins a run: the platform said by MBUI_PLATFORM=android, its core's pure calls kept)
  @ui.set_platform(Some(2))
  @sf.kept_call.val = Some(@sfkept.answer)
  @sfdesk.set_this_machine("")
  let src = @sffixture.fixture("{mode}")
  open_fixture_over("{mode}", src)
  let both = tape_{name}_text + "\\n" + tape_{name}_run
  let t = @ui.Tester::new(fn(c) {{ view(c, src) }}, tree=app_tree(src), w={w}, h={h}, text=both, run=both, scale={scale}, time={t0} - 16.0, stable={stable}, platform=2, env=[("MBUI_FIXTURE", "{mode}"), ("MBUI_PLATFORM", "android")])
  // (the faces the app carries, given to the host as its main gives them: src/sffix)
  @sf.give_faces()
  let frames = t.replay_frames(tape_{name}_run)
  let apart = frames.filter(fn(f) {{ f.1 != f.2 }})
  println("TAPE frames \\{{frames.length()}}, apart \\{{apart.length()}}, text missing \\{{t.text_missing()}}")
  if apart.length() > 0 {{
    println("TAPE first apart: frame \\{{apart[0].0}}: the run's \\{{apart[0].1}}, here \\{{apart[0].2}}")
  }}
  assert_true(frames.length() > 0)
  assert_eq(apart.length(), 0)
}}
'''
open(f'src/sfapp/tape_{name}_wbtest.mbt', 'w').write(body)
print(f'tape: src/sfapp/tape_{name}_wbtest.mbt: {n} frames, {len(text)} text lines, {len(frames)} lines of the run')
