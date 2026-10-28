// Film 5's desktop Slack: the client grab.mjs kept (slack/desk: its page as it showed, its styles), made a page of its
// own (desk/desk.html: no scripts, its styles in it) with fake.js over it, which puts the film's made-up workspace,
// channel and thread in it and shows them as the film goes (window.at). Its words are all the film's own.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
let h = readFileSync(join(here, 'desk/slack.raw.html'), 'utf8');
const css = readFileSync(join(here, 'desk/slack.css'), 'utf8');
h = h.replace(/<script\b[\s\S]*?<\/script>/g, '').replace(/<link\b[^>]*rel="stylesheet"[^>]*>/g, '')
  .replace(/<style\b[\s\S]*?<\/style>/g, '').replace(/<noscript\b[\s\S]*?<\/noscript>/g, '');
// (its policy against scripts of the page's own gone: the film's is one)
h = h.replace(/<meta[^>]*http-equiv="Content-Security-Policy"[^>]*>/gi, '');
const fake = readFileSync(join(here, 'fake.js'), 'utf8');
h = h.replace('<head>', () => `<head><base href="https://app.slack.com/"><style>${css}</style>`);
h = h.replace('</body>', () => `<script>${fake}</script></body>`);
writeFileSync(join(here, 'desk/desk.html'), h);
console.log('desk.html', h.length);
