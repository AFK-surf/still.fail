---
name: stillfail-show
description: Show evidence of visible work such as a UI, animation or generated image. Use when people need to judge appearance or interaction.
---

# Show visible work

Show the result, not just a description or a request that the user check it themselves. Say what changed, where
the evidence came from and what to look at.

| To judge | Show |
|---|---|
| Layout, spacing, colours, a state | Images, compared at a glance |
| Animation, transitions, a sequence | Short video; a frame strip for detailed study |
| `still.fail` UI changes or UI proposals | Real `mbui` fixture/code rendered via `apps/mbui/scripts/media.sh` (or `media-job.sh` on a build station) |
| Web app / service to click, type in or resize | Web service via `stillfail-jobs` |
| Data, charts, comparisons or interactive choices | Native `.mbui` widget via `stillfail-viz` |

Images plus a service or `.mbui` widget often work together: quick visual review and an interactive version to try.

## Images

- In still.fail, attach with `chat_post(files=[…])` and place with `![](after.png)`. Images on one line appear
  side by side at the same height: `![](before.png) ![](after.png)`.
- Images display at most 360×300, opening full size on click. Include the full window/screen so layout context is clear.
  Use device scale 2 for sharpness.
- Use distinct filenames per post. PNG for UI/text; JPEG for photos or size constraints. Limit: 10 files, 50 MB each.
- Slack uploads below the text; omit Markdown image syntax and describe what the evidence shows.

## Video

- Place like an image: `![](demo.webm)` shows a still with a play button. Use mp4 (H.264) or webm (VP8/VP9).
  Keep it short and say what to watch; watch the video end to end before posting.
- Browser recordings (Playwright/CDP) can drop frames on slow machines. Record and screenshot in separate runs
  to avoid blank frames. For exact motion, pause `document.getAnimations()`, step `currentTime` by 1000/60 ms,
  capture each step and assemble a video or contact sheet. Real-time-dependent motion can instead be slowed with
  CDP `Animation.setPlaybackRate` and recorded live.

## `still.fail` UI proposals & Native `.mbui` widgets

- When proposing or verifying `still.fail` client UI (`apps/mbui`), never mock it up in HTML/CSS. Write or edit the
  `mbui` view/fixture in `apps/mbui` and render real full-window screenshots or recordings via
  `apps/mbui/scripts/media.sh` (`apps/mbui/scripts/media-job.sh` on the build station).
- Use `stillfail-viz` (`.mbui` declarative widgets) for inline charts, metrics, comparisons and interactive option
  widgets (`follow_up` puts a choice in the user's composer).
- Use `stillfail-jobs` to start, verify, share and keep a web service available when reviewing a web project.

## A person on the station's screen

When a person has to act on this machine's display or a browser tab of the station (log in, solve a captcha,
approve a prompt, judge something live), the `screen` tool gives the link that opens it in their still.fail app,
where they see and drive it. Post the link with `chat_post kind=need_human` saying what to do there, and end the
turn; `screen` later says whether someone is viewing or controlling it. Not for evidence: show that as above.
The `computer` tool lets you see and operate a screen yourself (screenshots, clicks, keys); for web pages prefer the
browser's DevTools (stillfail-browser), and when you are stuck hand the screen to a person with its link.

## Evidence

- Capture the actual build/page with realistic data, intended sizes and light/dark themes. Label mock-ups as proposals.
- Compare before/after at the same size, data and scroll position. Design alternatives should differ in structure,
  not just a few pixels.
- Inspect images and motion frames yourself: check the change is visible, the build/cache is current, the server
  belongs to you, and nothing else broke. Measured values alone do not demonstrate motion.
- Name the environment and branch/commit. State anything not shown, why, and how it can be checked later.
- Send fresh evidence after each revision.
