import { test } from 'node:test';
import assert from 'node:assert/strict';
import { messageForAgent } from '../src/agents/instructions.ts';
import type { MessageRow } from '../src/store/rows.ts';

test('an image of an earlier message quoted names where that image is, not attached again', () => {
  const shot = { name: 'shot.png', path: '/w/uploads/2026-10-23T01-00-00-shot.png', size: 120, width: 40, height: 30 };
  const message = {
    text: '这里的按钮歪了',
    quotes: [{ author: 'Claude', role: 'agent', ts: '1.000001', text: 'shot.png', comment: '左上角', file: 'shot.png' }],
    attachments: [shot],
  } as unknown as MessageRow;
  const prompt = messageForAgent(message);
  assert.ok(prompt.startsWith(`[Quote] From your own earlier message 1.000001 in this conversation, its file ${shot.path} (sent with that message, not again):\n> shot.png\nTheir comment on it: 左上角\n\n这里的按钮歪了`), prompt);
  assert.ok(!prompt.includes('Attached files'), prompt);
  // Beside a file attached anew: only that one attached.
  const fresh = { name: 'b.mp4', path: '/w/uploads/b.mp4', size: 9 };
  const both = messageForAgent({ ...message, attachments: [shot, fresh] } as MessageRow);
  assert.ok(both.endsWith(`Attached files:\n- ${fresh.path} (b.mp4, 9 bytes)`), both);
  // A quote naming a file the message does not carry says only whose it is.
  const without = messageForAgent({ ...message, attachments: [] } as MessageRow);
  assert.ok(without.startsWith('[Quote] From your own earlier message 1.000001 in this conversation:\n'), without);
});
