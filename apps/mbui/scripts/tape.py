# tape.py LOG NAME MODE [FRAME] : a dev build's tape (its run's MBUI_DRAW_LOG and MBUI_TEXT_RECORD lines: DRAWHASH,
# INPUT, MSG, ENV, NATIVESAID, VIEWSCRIPT, TEXTREC; android/apk.json's debug build keeps one each start) made a Tester's
# test of the app over the fixture MODE (what MBUI_FIXTURE it ran with: src/sffix), src/sfapp/tape_NAME_wbtest.mbt
# (git ignores it): the run's frames drawn again over its text, each frame's hash the run's or the first that is not
# said (TAPE lines). FRAME: given again up to that frame and no further (the frame a bug is at). Used by scripts/tape.sh
import re, sys
if sys.argv[1] == '--fields':
    f = sys.argv[2].split(); print(dict(frame=f[1], time=f[2], w=f[3], h=f[4], scale=f[5], hash=f[6], stable=f[7] if len(f) > 7 else '0')); sys.exit(0)
kinds = ('DRAWHASH ', 'INPUT ', 'MSG ', 'NATIVESAID ', 'VIEWSCRIPT ')

def tape_lines(text, upto=None):
    """The tape's text answers (TEXTREC) and its run (ENV, DRAWHASH, INPUT, MSG, …) in their order; with `upto`, the
    run up to that frame's DRAWHASH and nothing after it (what came after is the next frames'). Text answers kept
    whole: they are what the host said of its text, asked again at any frame."""
    rec, run, done = [], [], False
    for line in text.replace('\r\n', '\n').split('\n'):
        if 'TEXTREC ' in line:
            rec.append(line[line.index('TEXTREC ') + 8:]); continue
        if done:
            continue
        m = re.search(r'(^|[\s:])(ENV \{.*)', line)
        k = next((k for k in kinds if k in line), None)
        if m:
            run.append(m.group(2))
        elif k:
            run.append(line[line.index(k):])
        else:
            continue
        if upto is not None and k == 'DRAWHASH ' and int(run[-1].split()[1]) >= upto:
            done = True
    return rec, run

if sys.argv[1] == '--selftest':
    # (a run made up: its frames 1 to 3, the input and the message before frame 2 and 3, a text answer after frame 3)
    log = '\n'.join(['x I mbui: ENV {"dark":0}', 'x I mbui: DRAWHASH 1 10 350 800 3 111 0', 'x I mbui: INPUT {"k":"pointer"}',
                     'x I mbui: TEXTREC {"t":1}', 'x I mbui: DRAWHASH 2 26 350 800 3 222 0', 'x I mbui: MSG {"c":"core"}',
                     'x I mbui: DRAWHASH 3 43 350 800 3 333 0', 'x I mbui: INPUT {"k":"key"}', 'x I mbui: TEXTREC {"t":2}'])
    rec, run = tape_lines(log, 2)
    assert run == ['ENV {"dark":0}', 'DRAWHASH 1 10 350 800 3 111 0', 'INPUT {"k":"pointer"}', 'DRAWHASH 2 26 350 800 3 222 0'], run
    assert rec == ['{"t":1}', '{"t":2}'], rec
    rec, run = tape_lines(log)
    assert len(run) == 7 and run[-1] == 'INPUT {"k":"key"}', run
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
