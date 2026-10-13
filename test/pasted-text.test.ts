import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makePastedFile, pastedInfo, PASTE_RESTORE_LIMIT } from '../web/src/pastedText.ts';

test('paste attachments preserve exact UTF-8 text, line endings and whitespace', async () => {
  const text = '\r\n 原文😀\t\r\n'.repeat(1000);
  const file = makePastedFile(text);
  assert.equal(await file.text(), text);
  assert.equal(file.size, Buffer.byteLength(text));
  assert.equal(file.type, 'text/plain;charset=utf-8');
  assert.notEqual(makePastedFile(text).name, file.name);
});
test('restore is available up to 25,000 characters, larger pastes retain bounded previews only', () => {
  assert.equal(pastedInfo('a'.repeat(PASTE_RESTORE_LIMIT)).text?.length, PASTE_RESTORE_LIMIT);
  const info = pastedInfo('b'.repeat(PASTE_RESTORE_LIMIT + 1));
  assert.equal(info.text, undefined);
  assert.equal(info.characters, PASTE_RESTORE_LIMIT + 1);
  assert.equal(info.preview.length, 200);
});
