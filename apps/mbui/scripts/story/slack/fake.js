// Film 5's Slack, over the desktop client's own page (build.mjs): the made-up workspace Acme, its #support channel and
// the thread Ana starts there by @-ing still.fail, in the client's own markup and styles. Every word is the film's:
// the page's own (its people, channels, messages) all replaced, its interface's words in English. window.at(t, marks)
// shows the thread as it stands `t` seconds into the film: its messages come in at their marks.
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  // a person's or an app's picture: a square of colour with initials, as SVG
  const pic = (who, bg, fg = '#fff') => 'data:image/svg+xml;utf8,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96"><rect width="96" height="96" fill="${bg}"/>` +
    `<text x="48" y="61" text-anchor="middle" font-family="Lato,Helvetica,Arial" font-weight="800" font-size="${who.length > 1 ? 38 : 46}" fill="${fg}">${who}</text></svg>`);
  // (people: Slack's own default pictures, as for anyone who set none; the app: still.fail's mark)
  const ava = (n) => `https://a.slack-edge.com/80588/img/avatars/ava_${n}-72.png`;
  const ANA = ava('0015'), BEN = ava('0001'), LIN = ava('0022'), APP = pic('S.', '#5b45e0'), ACME = pic('A', '#e8562a');
  const setImg = (img, src) => { if (!img) return; img.removeAttribute('srcset'); img.src = src; };

  // ---- the interface's words, in English ----
  const words = {
    '主页': 'Home', '私信': 'DMs', '活动': 'Activity', '文件': 'Files', '待办事项': 'Later', '代理与工具': 'Agents',
    '频道': 'Channels', '消息列': 'Thread', '消息': 'Messages', '添加画板': 'Add canvas', '文件与链接': 'Files', '钉选': 'Pins',
    '应用': 'APP', '描述你想要查找的信息': 'Search Acme', '回复消息列...': 'Reply…', '同时发送至': 'Also send to\u00a0',
    '在分屏中打开': 'Open in split view', '抱团': 'Huddles', '草稿和已发送': 'Drafts & sent', '已保存': 'Saved', '目录': 'Directories',
    '外部连接': 'External connections', '查找对话...': 'Find conversations…', '建立分区': 'Create section', '小窍门': 'Tip', '昨天': 'Yesterday', '今天': 'Today', '新': 'New', '已加星标': 'Starred',
  };
  const walk = (root) => {
    const it = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let n; (n = it.nextNode());) {
      const k = n.nodeValue.trim();
      if (words[k]) n.nodeValue = n.nodeValue.replace(k, words[k]);
    }
  };

  // ---- the workspace: Acme, its channels and people ----
  $$('.p-ia4_home_header_menu__team_name, [data-qa="team-name"]').forEach((e) => (e.textContent = 'Acme'));
  for (const e of $$('*')) if (e.children.length === 0 && e.textContent.trim() === 'AFK AI') e.textContent = 'Acme';
  // (the note over the sidebar about channels not visited: gone)
  for (const e of $$('button, div')) if (e.textContent.trim() === '整理') { e.closest('[class*="banner"], [class*="Banner"], [class*="nudge"], [class*="Nudge"]')?.remove(); }
  for (const team of $$('[data-qa="team-icon"]')) {
    const img = document.createElement('img');
    img.src = ACME;
    img.style.cssText = 'width:100%;height:100%;border-radius:inherit;display:block';
    team.style.background = 'none';
    team.replaceChildren(img);
  }
  // the sidebar: its channels and its direct messages, the film's (rows of the client's own, laid out anew)
  const sideBox = $('.p-channel_sidebar__static_list .c-virtual_list__scroll_container');
  const rows = $$(':scope > .c-virtual_list__item', sideBox);
  const tHead = rows.find((r) => $('[data-qa-channel-sidebar-section-heading="channels"]', r));
  const tDmHead = rows.find((r) => $('[data-qa-channel-sidebar-section-heading="direct_messages"]', r)) || tHead;
  const tChan = rows.find((r) => $('[data-qa-channel-sidebar-channel-type="channel"]', r) && !r.classList.contains('p-channel_sidebar__static_list__item--selected'));
  const tSel = rows.find((r) => r.classList.contains('p-channel_sidebar__static_list__item--selected'));
  const tDm = rows.find((r) => $('[data-qa-channel-sidebar-channel-type="im"]', r));
  const row = (tpl, name, img) => {
    const r = tpl.cloneNode(true);
    r.removeAttribute('id');
    const n = $('.p-channel_sidebar__name', r);
    if (n) n.innerHTML = `<span>${name}</span>`;
    if (img) {
      setImg($('img', r), img);
      // (no mask of a presence of the person it was, nor its dot)
      $$('[data-mask]', r).forEach((e) => e.removeAttribute('data-mask'));
      $$('.c-avatar__presence, .c-avatar > svg', r).forEach((e) => e.remove());
    }
    $$('[hidden], .p-channel_sidebar__channel_suffix > *, .c-emoji, [data-qa*="status"]', r).forEach((e) => e.remove());
    return r;
  };
  const head = (tpl, label) => {
    const r = tpl.cloneNode(true);
    r.removeAttribute('id');
    const l = $('.overflowEllipsis__HJDrl, [class*="overflowEllipsis"]', r);
    if (l) l.textContent = label;
    return r;
  };
  const side = [head(tHead, 'Channels')];
  for (const c of ['announcements', 'design', 'engineering', 'general', 'marketing', 'payments', 'random', 'releases']) side.push(row(tChan, c));
  side.push(row(tSel, 'support'));
  side.push(row(tChan, 'web'));
  side.push(head(tDmHead, 'Direct messages'));
  for (const [who, n] of [['Ana Costa', '0015'], ['Ben Okafor', '0001'], ['Chen Wei', '0010'], ['Dana Kim', '0004'],
    ['Felix Wagner', '0007'], ['Lin (you)', '0022']]) side.push(row(tDm, who, ava(n)));
  sideBox.replaceChildren(...side);
  { let y = 0; for (const r of side) { r.style.top = y + 'px'; y += r.getBoundingClientRect().height || 28; } sideBox.style.height = y + 'px'; }
  // every other picture of a real person: one of the made-up people's
  $$('img').forEach((img) => {
    if (!/ca\.slack-edge\.com|avatars-slack-edge/.test(img.src)) return;
    const r = img.getBoundingClientRect();
    setImg(img, r.left < 60 && r.top > 500 ? LIN : r.left < 60 ? img.src : pic('', '#d6d6d6'));
  });

  // ---- the channel: #support ----
  const views = $$('.c-message_list, [role="list"]').map((l) => l.closest('.c-virtual_list')).filter(Boolean);
  const mainList = views.find((v) => !v.closest('.p-threads_flexpane') && v.querySelector('[data-qa="message_container"]'));
  const threadList = views.find((v) => v.closest('.p-threads_flexpane'));
  const mainBox = $('.c-virtual_list__scroll_container', mainList);
  const threadBox = $('.c-virtual_list__scroll_container', threadList);
  const mainItems = $$(':scope > .c-virtual_list__item', mainBox);
  const threadItems = $$(':scope > .c-virtual_list__item', threadBox);
  const tRoot = mainItems.find((i) => $('[data-qa="reply_bar"]', i) && $('.c-message_kit__avatar', i));
  const tDivider = $('[data-qa="day-divider-label"]', mainList).closest('.c-virtual_list__item');
  // (the pills the list kept over it as it scrolled: gone with what they were over)
  $$('.c-virtual_list__sticky_container', mainList).forEach((e) => e.replaceChildren());
  const tThreadRoot = threadItems.find((i) => $('.c-message_kit__thread_message--root', i));
  const tSeparator = threadItems.find((i) => $('.p-threads_flexpane__separator', i));
  const tApp = threadItems.find((i) => $('[data-qa="message_sender_app_badge"]', i));
  const sectionHtml = (html) => `<div class="p-rich_text_block" dir="auto"><div class="p-rich_text_section">${html}</div></div>`;
  const mention = (label) => `<span role="presentation"><a class="c-link c-member_slug c-member_slug--light c-member_slug--link">${label}</a></span>`;
  // a message from a template, its sender, time, picture and words its own
  const message = (tpl, { who, at, img, html, app = false, replies = null, after = '' }) => {
    const item = tpl.cloneNode(true);
    item.removeAttribute('id');
    item.style.position = 'absolute';
    const sender = $('[data-qa="message_sender_name"]', item);
    if (sender) sender.textContent = who;
    const badge = $('[data-qa="message_sender_app_badge"]', item);
    if (badge && !app) badge.closest('.margin_left_25')?.remove();
    if (badge && app) badge.textContent = 'APP';
    const ts = $('[data-qa="timestamp_label"]', item);
    if (ts) ts.textContent = at;
    setImg($('.c-message_kit__avatar img', item), img);
    const blocks = $('.c-message__message_blocks', item);
    if (blocks) blocks.innerHTML = `<div class="p-block_kit_renderer">${$$('.p-block_kit_renderer__block_wrapper', blocks).length || true ? '' : ''}<div class="p-block_kit_renderer__block_wrapper p-block_kit_renderer__block_wrapper--first">${sectionHtml(html)}</div>${after}</div>`;
    $$('.c-message_kit__reaction_bar, .c-message_kit__attachments, .c-files_container, [data-qa="message_attachment"], .c-message__edited_label', item).forEach((e) => e.remove());
    $$('.c-message_kit__thread_message--root', item).forEach((e) => { if (!replies) e.classList.remove('c-message_kit__thread_message--root'); });
    const bar = $('[data-qa="reply_bar"]', item);
    if (bar) {
      if (replies) {
        const avs = $$('.c-message__reply_bar_avatar', bar);
        avs.forEach((a, k) => (k === 0 ? setImg($('img', a), APP) : a.remove()));
        $('[data-qa="reply_bar_count"]', bar).textContent = replies;
        const d = $('.c-message__reply_bar_view_thread', bar);
        if (d) d.textContent = 'Last reply today at 9:33 AM';
      } else bar.remove();
    }
    $$('[hidden]', item).forEach((e) => e.remove());
    return item;
  };
  // a day's divider: its pill on a line across the list, as the client draws the two
  const divider = (label) => {
    const d = tDivider.cloneNode(true);
    d.removeAttribute('id');
    d.classList.remove('c-virtual_list__item--sticky', 'c-virtual_list__item--sticky-animated');
    d.style.position = 'absolute';
    d.style.zIndex = '1';
    d.style.height = '44px';
    d.style.display = 'flex';
    d.style.alignItems = 'center';
    d.style.justifyContent = 'center';
    d.style.background = 'linear-gradient(transparent calc(50% - .5px), rgba(29,28,29,.13) calc(50% - .5px), rgba(29,28,29,.13) calc(50% + .5px), transparent calc(50% + .5px))';
    const pill = $('.c-message_list__day_divider__label__pill', d);
    if (pill) pill.firstChild.nodeValue = label;
    return d;
  };
  const button = (label) => `<div class="p-block_kit_renderer__block_wrapper"><div class="p-actions_block"><div class="p-actions_block_elements">` +
    `<button class="c-button c-button--outline c-button--small p-block_kit_button_element" type="button">${label}</button></div></div></div>`;
  const context = (text) => `<div class="p-block_kit_renderer__block_wrapper"><div class="p-context_block"><span class="p-context_block__text" style="opacity:.7;font-size:12px">${text}</span></div></div>`;

  // what the channel shows: an earlier message, then Ana's, its replies counted under it
  const ANA_TEXT = `${mention('@still.fail')} checkout is failing for some customers in the EU, they get a 500 after entering their card. Can you look?`;
  const main = [
    divider('Yesterday'),
    message(tRoot, { who: 'Chen Wei', at: '4:52 PM', img: ava('0010'), html: 'Refund for order #48213 went through, the customer confirmed by email 👍' }),
    message(tRoot, { who: 'Dana Kim', at: '5:30 PM', img: ava('0004'), html: 'Heads up: the help center search is slow tonight, the vendor is on it.' }),
    divider('Today'),
    message(tRoot, { who: 'Ben Okafor', at: '9:12 AM', img: BEN, html: 'Spring sale banner goes live at noon, ping me here if a customer can\'t see the discount 🎉' }),
    message(tRoot, { who: 'Ana Costa', at: '9:29 AM', img: ANA, html: ANA_TEXT, replies: '1 reply' }),
  ];
  mainBox.replaceChildren(...main);
  // the thread beside it: the agent's question to Lin as still.fail's card in Slack (station/src/slack/cards.ts: its words,
  // then the options as radio buttons, the recommended last and chosen already, each its detail under it, and OK),
  // answered from the phone: then its words and who answered what (answeredBlocks)
  const FOUND = `Found it: cards that need 3-D Secure are sent back to a return page without the locale, so the bank's redirect lands on a 500. The fix is one line in the payment flow, but it touches payments. ${mention('@Lin')}, ship it?`;
  const FIXED = `Fixed and live: EU cards go through 3-D Secure again, and all 14 payment tests pass. ${mention('@Ana Costa')} can you try once more?`;
  const radio = (label, detail, on) =>
    `<label style="display:flex;gap:9px;align-items:flex-start;padding:4px 0;cursor:default">` +
    `<span style="flex:none;width:16px;height:16px;margin-top:2px;border-radius:50%;box-sizing:border-box;` +
    (on ? 'border:5px solid #1d9bd1;background:#fff' : 'border:1px solid rgba(232,232,232,.5)') + `"></span>` +
    `<span><span style="display:block;font-size:15px;line-height:22px">${label}</span>` +
    `<span style="display:block;font-size:13px;line-height:18px;opacity:.7">${detail}</span></span></label>`;
  const card = `<div class="p-block_kit_renderer__block_wrapper" data-card="ask"><div style="padding:4px 0 2px">` +
    radio('Not yet', 'Leave it for review', false) + radio('Fix and deploy', 'Patch it, run the payment tests, deploy', true) +
    `</div><button class="c-button c-button--primary c-button--small" type="button" style="margin-top:6px">OK</button></div>`;
  const answered = `<div class="p-block_kit_renderer__block_wrapper" data-card="answered"><div class="p-context_block">` +
    `<span class="p-context_block__text" style="opacity:.7;font-size:13px">✓ Lin answered: Fix and deploy</span></div></div>`;
  const sep = tSeparator.cloneNode(true);
  sep.style.position = 'absolute';
  const sepCount = $('.p-threads_flexpane__separator_count', sep);
  const ask = message(tApp, { who: 'still.fail', at: '9:33 AM', img: APP, app: true, html: FOUND, after: card + answered });
  const thread = [
    message(tThreadRoot, { who: 'Ana Costa', at: '9:29 AM', img: ANA, html: ANA_TEXT, replies: null }),
    sep,
    ask,
    message(tApp, { who: 'still.fail', at: '9:41 AM', img: APP, app: true, html: FIXED }),
    message(tApp, { who: 'Ana Costa', at: '9:43 AM', img: ANA, html: 'Just paid with my French card, it works. Thanks! 🙌' }),
  ];
  // what the agent does now, as Slack shows an app's status under its thread (assistant.threads.setStatus:
  // station/src/slack/status.ts), over the reply box
  const status = document.createElement('div');
  status.style.cssText = 'position:absolute;left:0;right:0;padding:6px 20px 8px;font-size:13px;display:flex;align-items:center;gap:8px';
  status.innerHTML = `<img src="${APP}" style="width:18px;height:18px;border-radius:4px"><span style="opacity:.75"><b style="font-weight:700">still.fail</b> <i></i></span>`;
  thread.push(status);
  const input = threadItems.find((i) => $('[data-qa="reply_container"]', i));
  threadBox.replaceChildren(...thread, ...(input ? [input] : []));
  walk(document.body);
  $$('input[placeholder]').forEach((i) => { if (words[i.placeholder]) i.placeholder = words[i.placeholder]; });
  $$('.ql-placeholder span').forEach((s) => { s.textContent = s.closest('.p-threads_flexpane') ? 'Reply…' : 'Message #support'; });
  $$('*').forEach((e) => { if (e.children.length === 0 && /^support（频道）|^频道 support/.test(e.textContent)) e.textContent = '# support'; });
  document.title = '# support - Acme - Slack';
  // the Mac's window over it: its three buttons at the top bar's left, as the desktop app leaves room for them
  const lights = document.createElement('div');
  lights.style.cssText = 'position:fixed;left:13px;top:0;height:40px;display:flex;align-items:center;gap:8px;z-index:99999';
  for (const [c, b] of [['#ff5f57', '#e0443e'], ['#febc2e', '#dea123'], ['#28c840', '#1aab29']]) {
    const d = document.createElement('span');
    d.style.cssText = `width:12px;height:12px;border-radius:50%;background:${c};box-shadow:inset 0 0 0 .5px ${b}`;
    lights.append(d);
  }
  document.body.append(lights);

  // the list laid out from the top (its items one under another, as the virtual list places them) and shown from its end
  const lay = (box, list, bottom = false) => {
    let y = 0;
    for (const it of box.children) {
      if (it.style.display === 'none') continue;
      it.style.top = y + 'px';
      it.style.width = '100%';
      y += it.getBoundingClientRect().height;
    }
    // (the channel's few messages at its foot, over the composer, as the client keeps a list that does not fill it)
    const room = list.getBoundingClientRect().height;
    if (bottom && y < room) {
      for (const it of box.children) it.style.top = (parseFloat(it.style.top) + room - y - 22) + 'px';
      y = room - 22;
    }
    box.style.height = y + 'px';
    const scroller = $('.c-scrollbar__hider', list);
    if (scroller) scroller.scrollTop = scroller.scrollHeight;
  };
  // in at its mark: what is not yet is not shown
  // marks: ana (her question), working (the agent at it: its status), found (its card), deploy (answered from the
  // phone: the agent at it again), fixed, thanks
  window.at = (t, m = {}) => {
    const on = (at) => at === undefined || t >= at;
    const show = (el, at) => { el.style.display = on(at) ? '' : 'none'; };
    show(main[main.length - 1], m.ana);
    show(thread[0], m.ana);
    show(sep, m.found);
    show(ask, m.found);
    $('[data-card="ask"]', ask).style.display = on(m.deploy) ? 'none' : '';
    $('[data-card="answered"]', ask).style.display = on(m.deploy) ? '' : 'none';
    show(thread[3], m.fixed);
    show(thread[4], m.thanks);
    // (its status while it works: reading before its card, fixing after the answer, none once it said how it went)
    const words = on(m.fixed) ? '' : on(m.deploy) ? 'is fixing the 3-D Secure return URL…' : on(m.found) ? '' : on(m.working) ? 'is reading the checkout logs…' : '';
    status.style.display = words ? 'flex' : 'none';
    $('i', status).textContent = words;
    $('i', status).style.fontStyle = 'normal';
    const n = [m.found, m.fixed, m.thanks].filter((x) => on(x)).length;
    if (sepCount) sepCount.textContent = n === 1 ? '1 reply' : `${n} replies`;
    const rc = $('[data-qa="reply_bar_count"]', main[main.length - 1]);
    if (rc) rc.textContent = n === 1 ? '1 reply' : `${n} replies`;
    const bar = $('[data-qa="reply_bar"]', main[main.length - 1]);
    if (bar) bar.style.visibility = n ? '' : 'hidden';
    lay(mainBox, mainList, true);
    lay(threadBox, threadList);
  };
  window.at(1e9);
})();
