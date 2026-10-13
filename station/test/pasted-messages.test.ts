import { test } from 'node:test';
import assert from 'node:assert/strict';
import { messageForAgent } from '../src/agents/instructions.ts';
import type { MessageRow } from '../src/store/rows.ts';

test('attachment-only pasted text is explicitly presented to the agent as user input', () => {
  const name = 'pasted-text-12345678-1234-4234-8234-123456789012.txt';
  const message = { text: '', quotes: [], attachments: [{ name, path: `/uploads/${name}`, size: 90000 }] } as unknown as MessageRow;
  const prompt = messageForAgent(message);
  assert.match(prompt, /Read them as part of the user's message/);
  assert.ok(prompt.includes(`/uploads/${name}`));
  const normal = messageForAgent({ ...message, attachments: [{ name: 'notes.txt', path: '/uploads/notes.txt', size: 90 }] });
  assert.doesNotMatch(normal, /The user pasted text/);
});
