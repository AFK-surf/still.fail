---
name: stillfail-show
description: Showing work whose result is seen — a UI change, a page, a design, an animation, a chart, a generated image or video — so people can judge it in the chat: which way to show it (images, video, an inline HTML page, a web service) and how to make the evidence. Use whenever a task has a visible result to be looked at or signed off, instead of describing it in words.
---

# Showing visible work

When what you did is seen rather than read, people judge it by looking. Show it; do not describe it ("the button is now
centred") and do not ask them to check it themselves. Words go around the evidence: what changed, where it was taken,
what to look at.

## Which way

| What they need to judge | Show | Why |
|---|---|---|
| How something looks (layout, spacing, colour, a state) | images | quickest to look at, works on a phone and in any client, compared at a glance |
| How it moves or behaves over time (animation, transition, a flow of steps) | a video | a still cannot show motion; a strip of frames if they must study it frame by frame |
| Something to try: click, type, resize, go through pages | a web service (stillfail-jobs skill) | they use the real thing, at the sizes they choose, and can mark it up |
| Data, a comparison, a choice between options, a diagram | an inline HTML page (stillfail-viz skill) | drawn in the message in still.fail's look, interactive, can hand their choice back |

Often two together: images in the message for the verdict at a glance, and the web service for those who want to try
it. In a Slack thread files are uploaded below the text (not placed in it); say there in words what the evidence
shows.

## Images

- Attach with `chat_post(files=[…])` and place each where it belongs: `![](after.png)` on a line of its own. Several on
  one line (`![](light.png) ![](dark.png)`) show side by side, one height; that is the way to put before and after,
  or options, next to each other.
- In the chat an image shows at most 360×300 and opens full size on a click. So crop to what changed (a whole 1440 px
  page shrinks to illegible), and add a full view only if the context matters. Use a device scale of 2 for sharpness.
- Name files for what they show and keep names distinct in a post (`before.png`, `after.png`, `option-a.png`): files of
  the same name overwrite each other.
- PNG for UI and text; JPEG only for photos or when size matters. Up to 10 files, 50 MB each, per post.

## Video

- Placed like an image (`![](demo.webm)` on a line of its own), it shows as a still with ▶ and plays in still.fail's viewer.
  Use mp4 (H.264) or webm (VP8/VP9); other codecs may not play in every browser.
- Keep it short (a few seconds to show one thing) and cropped to the part that moves. Say what to watch for.
- Screen recording of a browser (Playwright `recordVideo`, CDP screencast) drops frames on a slow or virtual machine
  and can capture blank frames if you take screenshots in the same page at the same time: record and screenshot in
  separate runs. For motion that must be exact, do not trust a live recording: pause the page's animations
  (`document.getAnimations()`), step `currentTime` by 1000/60 ms, screenshot each step, and join the frames into a
  video (or a contact sheet image). Motion that waits on real time can instead be slowed down
  (CDP `Animation.setPlaybackRate`) and recorded live.

## Web service

- Start it with `job_start` and a port (the stillfail-jobs skill), check it answers, then post its link with what to try.
- The preview beside the chat can lay the page out at a phone, tablet, laptop or desktop size, zoomed and turned, so
  one link serves every size. People can also mark places on the page and comment on each; the marks reach you as
  quotes with a screenshot, numbered. Tell them they can.
- The page must work at its own root, with no live reload or streaming (WebSockets do not get through).
- Keep the service on the version you showed while they look. To compare with the old version, start a second service
  from another checkout, not by changing the one they have open. Stop services nobody needs any more.

## Inline HTML

- For charts, tables, comparisons and choices: the stillfail-viz skill says how. A widget with option buttons that hand
  the choice back (`ember.sendFollowUpMessage`) makes picking between designs one click.
- It is not the way to show a real UI: it runs in a sandbox in still.fail's stylesheet, not your app's. Screenshot or serve
  the app itself.
- A page made to fill a screen (a promo, a player, a slideshow) is not a figure either: attach it unplaced, as a file
  to open full screen, or serve it; with it, send a screenshot or a video so it can be seen in the chat.

## Making the evidence

- Show the real thing: the actual build or page, with realistic data, at the sizes and in the themes (light and dark)
  it will be used in. A mock-up is a proposal, not evidence; say so if that is what it is.
- Before and after, side by side, taken the same way (same size, data, scroll position). For a choice, several options
  that differ in structure, not just in a few pixels.
- Look at every image or frame yourself before sending it: that it shows your change (a stale build, a cached style,
  another session's server on the same port all happen), and that nothing else broke. Check motion frame by frame,
  not by a few measured values.
- Say where it came from: which environment, branch or commit, and what is not shown (only visible after release,
  needs a device you do not have) and how it can be checked then.
- After each round of changes, send new evidence; do not ask them to reuse the old one.
