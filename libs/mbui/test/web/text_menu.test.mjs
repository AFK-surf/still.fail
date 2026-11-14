// The web's floating text menu over words a finger picked (@hostapi.text_menu): the system's items it offers, then the
// app's own ones (@hostapi.text_menu_own) in their order, each chosen as its key (60 + its place), the menu then gone.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/host.js', import.meta.url), 'utf8');

function browser() {
  const element = () => ({
    style: {}, listeners: new Map(), children: [], textContent: '',
    addEventListener(name, f) { this.listeners.set(name, [...(this.listeners.get(name) || []), f]); },
    dispatch(name, e) { for (const f of this.listeners.get(name) || []) f(e); },
    append(...kids) { this.children.push(...kids); },
    replaceChildren(...kids) { this.children = [...kids]; },
    remove() { body.children = body.children.filter((k) => k !== this); },
    getContext: () => ({}),
  });
  const body = element();
  const gl = new Proxy({}, { get: (_, name) => {
    if (name === 'getShaderParameter' || name === 'getProgramParameter') return () => true;
    return () => ({});
  } });
  const canvas = { ...element(), width: 0, height: 0, getContext: () => gl,
    getBoundingClientRect: () => ({ width: 800, height: 600, left: 0, top: 0 }) };
  const ime = element();
  const document = { body, createElement: () => element(),
    getElementById: (id) => id === 'c' ? canvas : ime,
    addEventListener() {} };
  const win = { ...element(), document, navigator: { platform: 'Linux', language: 'zh-CN' }, location: { search: '' },
    URLSearchParams, Intl, queueMicrotask, devicePixelRatio: 1, performance: { now: () => 0 }, requestAnimationFrame() {} };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const keys = [];
  win.__mbhost.run('test', () => {}, () => {}, () => {}, (code, mods) => keys.push([code, mods]), () => {});
  return {
    host: win.__mbhost, keys,
    menu() { return body.children[0]; },
    labels() { return (body.children[0]?.children || []).map((b) => b.textContent); },
  };
}

test("the app's own items after the system's, in their order; the k-th chosen is the key 60 + k, the menu gone", () => {
  const b = browser();
  b.host.textMenuOwn('引用\n分享这一轮\n复制链接');
  b.host.textMenu(1, 10, 100, 50, 20, 2 | 8 | 64);
  assert.deepEqual(b.labels(), ['复制', '全选', '引用', '分享这一轮', '复制链接']);
  const third = b.menu().children[4];
  third.dispatch('click', { stopPropagation() {} });
  assert.deepEqual(b.keys, [[62, 0]]);
  assert.equal(b.menu(), undefined);
});

test("where `can` says none of the app's own, or it said none, only the system's", () => {
  const b = browser();
  b.host.textMenuOwn('引用');
  b.host.textMenu(1, 10, 100, 50, 20, 2 | 8);
  assert.deepEqual(b.labels(), ['复制', '全选']);
  b.host.textMenu(0, 0, 0, 0, 0, 0);
  b.host.textMenuOwn('');
  b.host.textMenu(1, 10, 100, 50, 20, 2 | 64);
  assert.deepEqual(b.labels(), ['复制']);
});
