#!/usr/bin/env python3
"""apps/mbui/scripts/shots.sh made from mbui's scripts/shots.sh (scripts/import.py): its still.fail screens only, run
here (this module's apps, its goldens, mbui's web-shot.mjs and imgdiff.mjs; the demo's kit and glass are sfkit's).
    python3 apps/mbui/scripts/shots.py MBUI_SHOTS_SH OUT"""
import os
import re
import sys


def drop_arm(text, name):
    i = text.index('\n    %s)' % name)
    j = text.index(';;', i) + 2
    return text[:i] + text[j:]


# ---- still.fail's copy: its screens only
s = open(sys.argv[1]).read()
head_end = s.index('D="$(cd "$(dirname "$0")" && pwd)"')
body = s[head_end:]
header = '''#!/bin/bash
# Screenshots of still.fail's screens in mbui on macOS and in a browser, compared with apps/mbui/goldens/ (what mbui's
# own scripts/shots.sh did for them before they moved here; its demo's are still its).
#   apps/mbui/scripts/shots.sh [kit home chat composer drive decide glass newchat preview settings web-kit web-home …]
#   UPDATE=1 accepts them as goldens
# Writes out/shots/<name>.png and, where a golden exists, out/shots/<name>-review.png (golden | new | differences).
# `kit` (macOS) and `web-kit` are the kit (APP=sfkit, a phone's window: rich text, Markdown, pages): kit gives mac-kit
# (its first page) and mac-kit-swipe (the next page pushed, then swiped halfway back from the left edge). `home` (macOS)
# and `web-home` are still.fail's Home over made-up chats (APP=sffix, src/sfapp/fixture.mbt) in a phone's window: home
# gives mac-home (the list), mac-home-sheet (the workspaces' sheet) and mac-home-swipe (a chat pushed, swiped halfway
# back). `chat` and `web-chat` are a made-up chat open over it (MBUI_FIXTURE=chat, src/sfapp/chat_fixture.mbt): chat
# gives mac-chat (at its end), mac-chat-up (scrolled up: the way to the newest over it) and mac-chat-loading (being
# read), its dark look (mac-chat-dark), a picture under the bar's glass (mac-chat-glass) and its glass drawn solid
# (mac-chat-solid). `composer` and `web-composer` are its composer's states (MBUI_FIXTURE=chat-compose|attach|quote|
# sending|failed). `drive` and `web-drive` the drive's pages over a made-up drive (src/sfapp/drive_fixture.mbt);
# `decide` and `web-decide` src/sfapp/decide_fixture.mbt's modes; `settings` and `web-settings` the settings' pages
# (src/sfapp/settings/fixture.mbt); `glass` and `web-glass` frosted and liquid glass over bands of colour (APP=sfkit
# MBUI_SCREEN=glass), light and dark; `newchat` and `web-newchat` a new chat, its sheets, the bottom bar's panel and a
# place (src/sfapp/newchat_fixture.mbt); `preview` and `web-preview` a file of a chat open in the preview.
'''
body = body.replace('''D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
''', '''D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
''')
body = re.sub(r'PLATFORMS=\$\{\*:-[^}]*\}', 'PLATFORMS=${*:-kit home chat composer drive decide glass newchat preview settings web-kit web-home web-chat web-composer web-drive web-decide web-glass web-newchat web-preview web-settings}', body)


def drop_arm(text, name):
    i = text.index('\n    %s)' % name)
    j = text.index(';;', i) + 2
    return text[:i] + text[j:]


for arm in ['mac', 'windows', 'web', 'ios', 'android']:
    body = drop_arm(body, arm)
body = body.replace('./_build/native/release/build/demo/demo.exe', './_build/native/release/build/stillfail/sfkit/sfkit.exe')
body = body.replace('./_build/native/release/build/sffix/sffix.exe', './_build/native/release/build/stillfail/sffix/sffix.exe')
# the kit's and the glass's builds: sfkit's
body = body.replace('''    kit)
      MODE=release bash scripts/mac.sh build''', '''    kit)
      APP=sfkit MODE=release bash scripts/mac.sh build''')
body = body.replace('''    glass)
      MODE=release bash scripts/mac.sh build''', '''    glass)
      APP=sfkit MODE=release bash scripts/mac.sh build''')
body = body.replace('''    web-kit)
      bash scripts/web.sh build''', '''    web-kit)
      APP=sfkit bash scripts/web.sh build''')
body = body.replace('''    web-glass)
      bash scripts/web.sh build''', '''    web-glass)
      APP=sfkit bash scripts/web.sh build''')
body = body.replace('node scripts/web-shot.mjs', 'node "$MBUI_DIR/scripts/web-shot.mjs"')
body = body.replace('node scripts/imgdiff.mjs', 'node "$MBUI_DIR/scripts/imgdiff.mjs"')
assert 'demo' not in re.sub(r'#.*', '', body.replace('demo.js', '')), [l for l in body.split('\n') if 'demo' in l and not l.strip().startswith('#')]
open(sys.argv[2], 'w').write(header + body)
os.chmod(sys.argv[2], os.stat(sys.argv[1]).st_mode & 0o777)

