// e2e/traces/history.trace, made by scripts/trace.py from 06-history.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_history : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 083209"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792524496}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792524445899.654}
  #|{"in":{"id":1,"ok":null},"w":1792524446034.316}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792524446034.353}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792524446034.37}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792524446037.402}
  #|{"step":"timeout 90000","w":1792524446037.414}
  #|{"step":"answered client.device","w":1792524446037.416}
  #|{"step":"answered client.focus","w":1792524446060.116}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792524446109.645}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792524446109.669}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792524446109.695}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792524446109.708}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DC9315VBKXJ81H711B9NEX","name":"Dev","role":"owner","created_at":1792524192,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792524192000,"ago":"4 分钟前","full":"10/21 03:23:12","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792524446126.314}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524446126.333}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524446126.366}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DC9315VBKXJ81H711B9NEX","mine":false},"keyed":true},"w":1792524446126.38}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524446126.503}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524446126.536}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DC9315VBKXJ81H711B9NEX"}},"w":1792524446132.058}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792524446132.067}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524446132.073}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"88982d3a718cefa1251315a5600b94e2cbb579962951f5e86379f41281b25a1a","code":"9LD-4LL","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792524446145.042}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","id":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792524196935,"label":"今天","items":[{"id":"ember:c-d046dea6e6","session":"ember:c-d046dea6e6","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-d046dea6e6","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"3fa63eff-5564-4abf-8b36-e15f985356da","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524196845,"endedAt":1792524196938},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-d046dea6e6","text":"你好，我是测试用的 agent","createdAt":1792524196935,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792524196935,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792524196935,"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","stationName":"studio","time":{"lastActiveAt":{"at":1792524196935,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-9ac2ad15b3d7c1c8fb","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792524446145.083}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DC9315VBKXJ81H711B9NEX":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792524446145.109}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524446145.114}
  #|{"in":{"id":10,"ok":null},"w":1792524446145.122}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524446145.129}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524446145.135}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524446145.176}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792524446148.109}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792524446159.633}
  #|{"in":{"id":14,"ok":null},"w":1792524446159.642}
  #|{"step":"answered notify.permission","w":1792524446159.968}
  #|{"step":"tap 端到端测试","w":1792524446176.489}
  #|{"step":"tap 端到端测试","acted":true,"w":1792524446193.135}
  #|{"out":{"id":15,"subscribe":{"topic":"chat","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","session":"ember:c-d046dea6e6"},"keyed":true},"w":1792524446209.695}
  #|{"out":{"id":16,"call":"draft.get","params":{"key":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643:ember:c-d046dea6e6"}},"w":1792524446210.021}
  #|{"step":"answered draft.get","w":1792524446210.121}
  #|{"in":{"id":16,"ok":{"text":"","quotes":[],"files":[],"id":"draft-b9b45575524b2862dd"}},"w":1792524446226.302}
  #|{"in":{"id":15,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792524196.665000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792524196665,"sessions":[{"thread":1,"session":"ember:c-d046dea6e6","connect":"ember","joinedAt":1792524196680}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792524196.935000","authorKind":"agent","author":"ember:c-d046dea6e6","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524196935,"time":{"createdAt":{"at":1792524196935,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792524196665,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-d046dea6e6","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"d7c286c5-7770-484a-ae04-9dd685576775","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-d046dea6e6/workspace","running":false,"createdAt":1792524196639,"lastActiveAt":1792524196938,"process":"warm","turns":1,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"3fa63eff-5564-4abf-8b36-e15f985356da","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524196845,"endedAt":1792524196938},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792524196639,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792524196938,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524196560,"time":{"checkedAt":{"at":1792524196560,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"3fa63eff-5564-4abf-8b36-e15f985356da","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792524196845,"endedAt":1792524196938}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792524196.665000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792524196665,"sessions":[{"thread":1,"session":"ember:c-d046dea6e6","connect":"ember","joinedAt":1792524196680}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792524196.935000","authorKind":"agent","author":"ember:c-d046dea6e6","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524196935,"time":{"createdAt":{"at":1792524196935,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792524196665,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792524196.821000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792524196821,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792524196821,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792524196.935000","authorKind":"agent","author":"ember:c-d046dea6e6","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524196935,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-d046dea6e6","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792524196935,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":2,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"connecting"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792524446226.391}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524446226.514}
  #|{"out":{"id":18,"subscribe":{"topic":"chatJobs","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","session":"ember:c-d046dea6e6"},"keyed":true},"w":1792524446226.528}
  #|{"out":{"id":19,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792524446226.549}
  #|{"out":{"id":20,"call":"client.focus","params":{"chat":{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","session":"ember:c-d046dea6e6","thread":1,"end":true}}},"w":1792524446229.747}
  #|{"in":{"id":17,"value":[{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","id":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792524199,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DC9315VBKXJ81H711B9NEX","device":"88982d3a718cefa1251315a5600b94e2cbb579962951f5e86379f41281b25a1a"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524196560,"time":{"checkedAt":{"at":1792524196560,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","workspace":"Dev","workspaceId":"01M5DC9315VBKXJ81H711B9NEX","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":69091438592,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792524194158},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792524194158},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524194158},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524194158},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524194158}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792524199000,"ago":"4 分钟前","full":"10/21 03:23:19","until":"1 分钟内","past":true}},"joined":false}]},"w":1792524446243.066}
  #|{"in":{"id":18,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792524446243.151}
  #|{"in":{"id":20,"ok":null},"w":1792524446243.161}
  #|{"step":"answered picture","w":1792524446244.08}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5DC9315VBKXJ81H711B9NEX"],"set":{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","key":"ember:c-d046dea6e6"}}]},"w":1792524446342.976}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","chat"],"set":{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","key":"ember:c-d046dea6e6"}}]},"w":1792524446342.996}
  #|{"in":{"id":19,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792524446426.312}
  #|{"step":"answered client.focus","w":1792524446443.433}
  #|{"step":"wait 300","w":1792524446460.166}
  #|{"step":"now until =studio","w":1792524446776.61}
  #|{"step":"tap 发消息","w":1792524446776.623}
  #|{"step":"tap 发消息","acted":true,"w":1792524446793.274}
  #|{"step":"type 看看文档 083209 steps:文档目录看过了 083209","w":1792524446812.503}
  #|{"step":"type 看看文档 083209 steps:文档目录看过了 083209","acted":true,"w":1792524446812.515}
  #|{"out":{"id":21,"call":"session.warm","params":{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","key":"ember:c-d046dea6e6"}},"w":1792524446826.38}
  #|{"step":"answered session.warm","w":1792524446828.41}
  #|{"out":{"id":22,"call":"draft.put","params":{"text":"看看文档 083209 steps:文档目录看过了 083209","quotes":[],"files":[],"key":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643:ember:c-d046dea6e6"}},"w":1792524447243.154}
  #|{"in":{"id":22,"ok":{"id":"draft-b9b45575524b2862dd"}},"w":1792524447259.641}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio ×2 · 2 秒 · 共 4 项","items":[{"state":"slow","text":"正在连接 studio ×2","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524448276.321}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio ×2 · 2 秒 · 共 4 项","items":[{"state":"slow","text":"正在连接 studio ×2","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524448276.343}
  #|{"in":{"id":21,"ok":{"ok":true}},"w":1792524449042.988}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524449059.666}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524449059.691}
  #|{"step":"tap icon:arrow-up","w":1792524449060.346}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":2},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["archiveOffered"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"set":true},{"path":["archiveCheck"],"set":{"text":"所有 agent 都做完了","recommended":true,"failed":false}}]},{"path":["thread","read"],"set":2},{"path":["thread","unread"],"set":0}]},"w":1792524449076.346}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","ember:c-d046dea6e6"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792524449076.389}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","unread"],"set":0},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","label"],"remove":true},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","mineTone"],"remove":true},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","tone"],"remove":true}]},"w":1792524449076.406}
  #|{"step":"tap icon:arrow-up","acted":true,"w":1792524449077.117}
  #|{"out":{"id":23,"call":"draft.put","params":{"text":"","quotes":[],"files":[],"key":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643:ember:c-d046dea6e6"}},"w":1792524449093.089}
  #|{"out":{"id":24,"call":"chat.send","params":{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","text":"看看文档 083209 steps:文档目录看过了 083209","attachments":[],"quotes":[],"thread":1}},"w":1792524449093.108}
  #|{"step":"answered chat.send","w":1792524449093.844}
  #|{"in":{"id":23,"ok":{"id":"draft-5b7b5d361c1e062c75"}},"w":1792524449109.652}
  #|{"in":{"id":24,"ok":{"seq":3}},"w":1792524449109.676}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"badge"],"set":"run"},{"path":["agents",0,"profile","check","checkedAt"],"set":1792524448932},{"path":["agents",0,"profile","check","time","checkedAt","ago"],"set":"刚刚"},{"path":["agents",0,"profile","check","time","checkedAt","at"],"set":1792524448932},{"path":["agents",0,"profile","check","time","checkedAt","full"],"set":"10/21 03:27:28"},{"path":["agents",0,"session","badgeText"],"set":"工作中"},{"path":["agents",0,"session","lastActiveAt"],"set":1792524449097},{"path":["agents",0,"session","lastTurn","id"],"set":"af1865d1-5b0e-44f0-8bbd-aeb27415d209"},{"path":["agents",0,"session","lastTurn","startedAt"],"set":1792524449097},{"path":["agents",0,"session","lastTurn","declared"],"remove":true},{"path":["agents",0,"session","lastTurn","endedAt"],"remove":true},{"path":["agents",0,"session","lastTurn","ending"],"remove":true},{"path":["agents",0,"session","lastTurn","need"],"remove":true},{"path":["agents",0,"session","lastTurn","outcome"],"remove":true},{"path":["agents",0,"session","mark"],"set":"run"},{"path":["agents",0,"session","process"],"set":"running"},{"path":["agents",0,"session","processText"],"set":"运行中"},{"path":["agents",0,"session","running"],"set":true},{"path":["agents",0,"session","runtimeSessionId"],"set":"2a1d135f-d50a-471d-99c2-b217e076b185"},{"path":["agents",0,"session","statusText"],"set":"进行中"},{"path":["agents",0,"session","time","lastActiveAt","ago"],"set":"刚刚"},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792524449097},{"path":["agents",0,"session","time","lastActiveAt","full"],"set":"10/21 03:27:29"},{"path":["agents",0,"session","tone"],"set":"accent"},{"path":["agents",0,"session","turns"],"set":2},{"path":["agents",0,"since"],"set":1792524449097},{"path":["agents",0,"started"],"set":true},{"path":["agents",0,"status"],"set":"running"},{"path":["agents",0,"threads",0,"last"],"set":3},{"path":["agents",0,"threads",0,"lastMessage","author"],"set":"alice@example.test"},{"path":["agents",0,"threads",0,"lastMessage","authorKind"],"set":"person"},{"path":["agents",0,"threads",0,"lastMessage","authorName"],"set":"Name of alice"},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792524449095},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":3},{"path":["agents",0,"threads",0,"lastMessage","text"],"set":"看看文档 083209 steps:文档目录看过了 083209"},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","ago"],"set":"刚刚"},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792524449095},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","full"],"set":"10/21 03:27:29"},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792524449.095000"},{"path":["agents",0,"threads",0,"lastMessage","declared"],"remove":true},{"path":["agents",0,"threads",0,"lastMessage","ending"],"remove":true},{"path":["agents",0,"turns"],"append":[{"id":"af1865d1-5b0e-44f0-8bbd-aeb27415d209","kind":"input","startedAt":1792524449097}]},{"path":["link","state"],"set":"online"},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"remove":true},{"path":["archiveCheck"],"remove":true}]},{"path":["outbox"],"key":["id"],"put":{"id":"out-02aa047d9421cbdbcf","text":"看看文档 083209 steps:文档目录看过了 083209","attachments":[],"quotes":[],"createdAt":1792524449094,"state":"sending","seq":3,"time":{"createdAt":{"at":1792524449094,"ago":"刚刚","full":"10/21 03:27:29","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","last"],"set":3},{"path":["thread","lastMessage","author"],"set":"alice@example.test"},{"path":["thread","lastMessage","authorKind"],"set":"person"},{"path":["thread","lastMessage","authorName"],"set":"Name of alice"},{"path":["thread","lastMessage","createdAt"],"set":1792524449095},{"path":["thread","lastMessage","seq"],"set":3},{"path":["thread","lastMessage","text"],"set":"看看文档 083209 steps:文档目录看过了 083209"},{"path":["thread","lastMessage","time","createdAt","ago"],"set":"刚刚"},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792524449095},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/21 03:27:29"},{"path":["thread","lastMessage","ts"],"set":"1792524449.095000"},{"path":["thread","lastMessage","declared"],"remove":true},{"path":["thread","lastMessage","ending"],"remove":true},{"path":["archivable"],"remove":true},{"path":["archiveOffered"],"remove":true}]},"w":1792524449126.417}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"put":{"daysAgo":0,"at":1792524449095,"label":"今天","items":[{"id":"ember:c-d046dea6e6","session":"ember:c-d046dea6e6","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-d046dea6e6","runtime":"claude","process":"running","pending":0,"lastTurn":{"id":"af1865d1-5b0e-44f0-8bbd-aeb27415d209","kind":"input","startedAt":1792524449097},"agentText":"默认模型","mark":"run","statusText":"进行中","badgeText":"工作中"}],"last":{"seq":3,"authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"看看文档 083209 steps:文档目录看过了 083209","createdAt":1792524449095,"by":{"kind":"person","name":"你","mine":true,"id":"alice@example.test","picture":"https://example.test/p.png","label":"你"},"preview":"看看文档 083209 steps:文档目录看过了 083209","time":{"createdAt":{"at":1792524449095,"ago":"刚刚","full":"10/21 03:27:29","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792524449095,"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","stationName":"studio","state":"run","time":{"lastActiveAt":{"at":1792524449095,"ago":"刚刚","full":"10/21 03:27:29","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","pinned":false,"tone":"busy"}]}},{"path":["glyph","label"],"set":"1 台 station，1 台在线，1 台运行中"},{"path":["glyph","summary"],"set":"studio · 运行中"},{"path":["glyph","working"],"set":1}]},"w":1792524449126.736}
  #|{"in":{"id":17,"delta":[{"path":[0,"face"],"set":"working"},{"path":[0,"link","state"],"set":"online"},{"path":[0,"overview","counts","running"],"set":1},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":68227457024},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792524448932},{"path":[0,"overview","profiles",0,"check","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792524448932},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 03:27:28"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792524446518},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792524446518},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792524446518},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792524446518},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792524446518},{"path":[0,"reconnecting"],"set":false}]},"w":1792524449126.82}
  #|{"out":{"id":25,"subscribe":{"topic":"live","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","key":"ember:c-d046dea6e6"},"keyed":true},"w":1792524449127.245}
  #|{"step":"wait 600","w":1792524449130.145}
  #|{"in":{"id":17,"delta":[{"path":[0,"face"],"set":"idle"},{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.86,"cpuBusy":0.19,"uptimeSec":3811,"memory":{"totalBytes":17179869184,"usedBytes":8960196608,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":68227452928},"emberRssBytes":140801512,"checkedAt":1792524449101,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":19,"left":81,"level":"ok","value":"19%","remaining":"空闲 81%","big":"81","unit":"%","title":"CPU 空闲","total":"负载 18.6","note":"负载 18.6 · Apple M4"},{"label":"内存","short":"内存","percent":52,"left":48,"level":"ok","value":"8.3 GB / 16.0 GB","remaining":"剩 7.7 G","big":"7.7","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":72,"left":28,"level":"ok","value":"剩余 63.5 GB / 228 GB","remaining":"剩 63.5 G","big":"63.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 134 MB"}],"usage":"内存 8.3 GB / 16.0 GB · 磁盘 剩余 63.5 GB / 228 GB","emberText":"still.fail 134 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"overview","counts","running"],"set":0},{"path":[0,"overview","counts","warm"],"set":1},{"path":[0,"overview","disk","freeBytes"],"set":68227338240},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792524449159.672}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"session","lastActiveAt"],"set":1792524449124},{"path":["agents",0,"session","lastTurn","declared"],"set":"final"},{"path":["agents",0,"session","lastTurn","endedAt"],"set":1792524449124},{"path":["agents",0,"session","lastTurn","ending"],"set":"all_done"},{"path":["agents",0,"session","lastTurn","need"],"set":"answered the question that was asked"},{"path":["agents",0,"session","lastTurn","outcome"],"set":"completed"},{"path":["agents",0,"session","process"],"set":"warm"},{"path":["agents",0,"session","processText"],"set":"保温中"},{"path":["agents",0,"session","running"],"set":false},{"path":["agents",0,"session","statusText"],"set":"已完成：answered the question that was asked"},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792524449124},{"path":["agents",0,"session","tone"],"set":"green"},{"path":["agents",0,"session","badgeText"],"remove":true},{"path":["agents",0,"session","mark"],"remove":true},{"path":["agents",0,"status"],"set":"final"},{"path":["agents",0,"threads",0,"last"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","author"],"set":"ember:c-d046dea6e6"},{"path":["agents",0,"threads",0,"lastMessage","authorKind"],"set":"agent"},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792524449121},{"path":["agents",0,"threads",0,"lastMessage","declared"],"set":"final"},{"path":["agents",0,"threads",0,"lastMessage","ending"],"set":"all_done"},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","text"],"set":"文档目录看过了 083209"},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792524449121},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792524449.121000"},{"path":["agents",0,"threads",0,"lastMessage","authorName"],"remove":true},{"path":["agents",0,"threads",0,"unread"],"set":1},{"path":["agents",0,"turns",1,"declared"],"set":"final"},{"path":["agents",0,"turns",1,"endedAt"],"set":1792524449124},{"path":["agents",0,"turns",1,"ending"],"set":"all_done"},{"path":["agents",0,"turns",1,"outcome"],"set":"completed"},{"path":["agents",0,"badge"],"remove":true},{"path":["agents",0,"since"],"remove":true},{"path":["agents",0,"started"],"remove":true},{"path":["messages"],"key":["seq","outgoing"],"put":{"outgoing":"out-02aa047d9421cbdbcf","seq":3,"thread":1,"ts":"1792524449.095000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"看看文档 083209 steps:文档目录看过了 083209","attachments":[],"quotes":[],"createdAt":1792524449095,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792524449095,"ago":"刚刚","full":"10/21 03:27:29","until":"1 分钟内","past":true}}},"before":null},{"path":["outbox"],"key":["id"],"drop":"out-02aa047d9421cbdbcf"},{"path":["thread","last"],"set":4},{"path":["thread","lastMessage","author"],"set":"ember:c-d046dea6e6"},{"path":["thread","lastMessage","authorKind"],"set":"agent"},{"path":["thread","lastMessage","createdAt"],"set":1792524449121},{"path":["thread","lastMessage","declared"],"set":"final"},{"path":["thread","lastMessage","ending"],"set":"all_done"},{"path":["thread","lastMessage","seq"],"set":4},{"path":["thread","lastMessage","text"],"set":"文档目录看过了 083209"},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792524449121},{"path":["thread","lastMessage","ts"],"set":"1792524449.121000"},{"path":["thread","lastMessage","authorName"],"remove":true},{"path":["thread","unread"],"set":1}]},"w":1792524449159.744}
  #|{"in":{"id":25,"value":{"loaded":true,"first":0,"timeline":[{"at":"2026-10-20T19:27:29.098Z","kind":"user","text":"Your earlier conversation could not be restored. Read the relevant threads with chat_history to catch up before answering.\n\n<message via=\"web\" connect=\"ember\" thread=\"EMBER/1792524196.665000\" from=\"alice@example.test (alice@example.test)\" client=\"desktop\" ts=\"1792524449.095000\">\n看看文档 083209 steps:文档目录看过了 083209\n</message>"},{"at":"2026-10-20T19:27:29.099Z","kind":"tool_call","text":"{\n  \"command\": \"ls docs\",\n  \"description\": \"列出 docs 目录\"\n}","tool":"Bash","callId":"toolu_e2e_1"},{"at":"2026-10-20T19:27:29.099Z","kind":"tool_result","text":"stillfail-port.md\nstillfail-android-map.md","ok":true,"callId":"toolu_e2e_1"},{"at":"2026-10-20T19:27:29.099Z","kind":"tool_call","text":"{\n  \"file_path\": \"/tmp/e2e/notes.md\",\n  \"old_string\": \"旧的一行\",\n  \"new_string\": \"新的一行\"\n}","tool":"Edit","callId":"toolu_e2e_2"},{"at":"2026-10-20T19:27:29.100Z","kind":"tool_result","text":"The file /tmp/e2e/notes.md has been updated.","ok":true,"callId":"toolu_e2e_2"},{"at":"2026-10-20T19:27:29.100Z","kind":"assistant","text":"看过了，改好了。"}],"usage":{"modelCalls":0,"inputTokens":0,"cachedTokens":0,"outputTokens":0,"contextTokens":0},"steps":[],"rate":0,"activity":{"now":{"key":"busy","text":"处理中"}}}},"w":1792524449159.869}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792524449121},{"path":["items"],"key":["station","id"],"patch":["01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","ember:c-d046dea6e6"],"ops":[{"path":["agents",0,"lastTurn","declared"],"set":"final"},{"path":["agents",0,"lastTurn","endedAt"],"set":1792524449124},{"path":["agents",0,"lastTurn","ending"],"set":"all_done"},{"path":["agents",0,"lastTurn","need"],"set":"answered the question that was asked"},{"path":["agents",0,"lastTurn","outcome"],"set":"completed"},{"path":["agents",0,"process"],"set":"warm"},{"path":["agents",0,"statusText"],"set":"已完成：answered the question that was asked"},{"path":["agents",0,"badgeText"],"remove":true},{"path":["agents",0,"mark"],"remove":true},{"path":["last","author"],"set":"ember:c-d046dea6e6"},{"path":["last","authorKind"],"set":"agent"},{"path":["last","by","kind"],"set":"agent"},{"path":["last","by","label"],"set":"agent"},{"path":["last","by","mine"],"set":false},{"path":["last","by","name"],"set":"agent"},{"path":["last","by","runtime"],"set":"claude"},{"path":["last","by","id"],"remove":true},{"path":["last","by","picture"],"remove":true},{"path":["last","createdAt"],"set":1792524449121},{"path":["last","preview"],"set":"文档目录看过了 083209"},{"path":["last","seq"],"set":4},{"path":["last","text"],"set":"文档目录看过了 083209"},{"path":["last","time","createdAt","at"],"set":1792524449121},{"path":["last","authorName"],"remove":true},{"path":["lastActiveAt"],"set":1792524449121},{"path":["time","lastActiveAt","at"],"set":1792524449121},{"path":["tone"],"set":"done"},{"path":["unread"],"set":true},{"path":["state"],"remove":true}]}]},{"path":["glyph","label"],"set":"1 台 station，1 台在线"},{"path":["glyph","summary"],"set":"studio"},{"path":["glyph","working"],"set":0}]},"w":1792524449159.894}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","label"],"set":"1 个有新消息"},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","mineTone"],"set":"done"},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","tone"],"set":"done"},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","unread"],"set":1}]},"w":1792524449159.94}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":3},{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":4,"thread":1,"ts":"1792524449.121000","authorKind":"agent","author":"ember:c-d046dea6e6","text":"文档目录看过了 083209","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524449121,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-d046dea6e6","runtime":"claude","here":true},"waiting":false,"said":true,"time":{"createdAt":{"at":1792524449121,"ago":"刚刚","full":"10/21 03:27:29","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","read"],"set":3}]},"w":1792524449176.327}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":4},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["archiveOffered"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[4,null],"ops":[{"path":["archive"],"set":true},{"path":["archiveCheck"],"set":{"text":"所有 agent 都做完了","recommended":true,"failed":false}}]},{"path":["thread","read"],"set":4},{"path":["thread","unread"],"set":0}]},"w":1792524449326.329}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","ember:c-d046dea6e6"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792524449326.368}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","unread"],"set":0},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","label"],"remove":true},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","mineTone"],"remove":true},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","tone"],"remove":true}]},"w":1792524449326.384}
  #|{"step":"now gone 正在发送","w":1792524449743.401}
  #|{"step":"untiln 2 文档目录看过了 083209","w":1792524449743.413}
  #|{"step":"tap icon:more","w":1792524449793.997}
  #|{"step":"tap icon:more","acted":true,"w":1792524449810.052}
  #|{"step":"rest","w":1792524449836.939}
  #|{"in":{"id":17,"delta":[{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792524450459.641}
  #|{"step":"now until 复制会话链接","w":1792524451326.593}
  #|{"step":"tap icon:chevron-right","w":1792524451326.604}
  #|{"step":"tap icon:chevron-right","acted":true,"w":1792524451343.308}
  #|{"step":"rest","w":1792524451359.875}
  #|{"out":{"id":26,"subscribe":{"topic":"agentCard","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","key":"ember:c-d046dea6e6"},"keyed":true},"w":1792524451376.364}
  #|{"in":{"id":26,"value":{"work":"2 轮","latest":[{"key":"1","text":"列出 docs 目录"},{"key":"3","text":"编辑 notes.md"},{"key":"5","text":"看过了，改好了。"}],"attention":[]}},"w":1792524451392.977}
  #|{"step":"now until =历史","w":1792524452711.391}
  #|{"step":"tap =历史","w":1792524452711.444}
  #|{"step":"tap =历史","acted":true,"w":1792524452744.916}
  #|{"out":{"id":27,"subscribe":{"topic":"history","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","key":"ember:c-d046dea6e6"},"keyed":true},"w":1792524452761.369}
  #|{"step":"wait 300","w":1792524452765.734}
  #|{"in":{"id":27,"value":{"items":[{"key":"e0","entries":[0,0],"body":{"kind":"received","content":{"note":"Your earlier conversation could not be restored. Read the relevant threads with chat_history to catch up before answering.","tasks":[],"messages":[{"key":"1792524449.095000","from":{"name":"Name of alice","bound":false},"text":"看看文档 083209 steps:文档目录看过了 083209","place":{"name":"端到端测试的对话 post:你好，我是测试用的 agent","surface":"ember","session":"ember:c-d046dea6e6"}}]}},"turn":{"at":1792524449098,"time":"03:27","text":"2 步 · 未发消息"}},{"key":"e1","entries":[1,4],"body":{"kind":"group","content":{"summary":"编辑 notes.md · 共 2 项","title":"运行 1 条命令、编辑 1 个文件","failures":0,"pending":0,"rows":[{"kind":"step","content":{"said":"列出 docs 目录","name":"Bash","hint":"ls docs","meta":"0ms","failed":false,"call":"{\n  \"command\": \"ls docs\",\n  \"description\": \"列出 docs 目录\"\n}","result":"stillfail-port.md\nstillfail-android-map.md","entries":[1,2],"brief":false}},{"kind":"step","content":{"name":"Edit","hint":"/tmp/e2e/notes.md","meta":"1ms","failed":false,"call":"{\n  \"file_path\": \"/tmp/e2e/notes.md\",\n  \"old_string\": \"旧的一行\",\n  \"new_string\": \"新的一行\"\n}","result":"The file /tmp/e2e/notes.md has been updated.","entries":[3,4],"brief":false}}]}}},{"key":"e5","entries":[5,5],"body":{"kind":"text","content":{"text":"看过了，改好了。","md":[["p",["看过了，改好了。"]]],"subagent":false}}}],"live":[],"usage":[{"label":"模型调用","value":"0 次"},{"label":"输入","value":"0"},{"label":"其中缓存","value":"0"},{"label":"输出","value":"0"},{"label":"缓存命中率","value":"未报告"}],"usageLine":"调用 0 次 · 输入 0 · 输出 0","edge":"已到会话开头","empty":false,"loaded":true,"more":false}},"w":1792524452776.419}
  #|{"step":"now rest","w":1792524453077.278}
  #|{"step":"now until 执行历史","w":1792524454193.884}
  #|{"step":"until 文档目录看过了 083209","w":1792524454193.943}
  #|{"step":"tap icon:chevron-right","w":1792524454193.964}
  #|{"step":"tap icon:chevron-right","acted":true,"w":1792524454210.544}
  #|{"step":"until 列出 docs 目录","w":1792524454241.553}
  #|{"step":"tap 列出 docs 目录","w":1792524454241.59}
  #|{"step":"tap 列出 docs 目录","acted":true,"w":1792524454252.659}
  #|{"step":"wait 300","w":1792524454262.995}
  #|{"step":"now until stillfail-port.md","w":1792524454594.406}
  #|{"step":"rest","w":1792524454594.451}
  #|{"step":"","w":1792524454627.339}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,20,3,1,14.883268482490273,21,4,1,14.88326848249028,22,5,1,14.88326848249028,23]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,25]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,3.95001220703125,-1,24,1,8.899068832397461,44,25,1,9.801153182983398,45,26,1,9.127458572387695,46,27,1,9.466253280639648,47,28,1,5.999713897705078,36]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,48,1,1,13.891050583657588,49,2,1,14.081712062256813,50,3,1,13.891050583657588,51,4,1,13.891050583657588,52,5,1,13.891050583657588,53,6,1,13.891050583657588,54,7,1,13.891050583657588,55,8,1,13.891050583657588,56,9,1,3.787109375000014,-1,10,1,7.57421875,57,11,1,8.380859375,58,12,1,7.84765625,59,13,1,8.0185546875,60,14,1,4.935546875,61]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,14.076484680175781,62]}}
  #|{"textrec":{"g":18,"r":[51,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":19,"r":[69,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":20,"r":[86,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":21,"r":[104,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":22,"r":[121,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":23,"r":[137,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":24,"r":[154,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":25,"r":[172,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":26,"r":[190,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":27,"r":[208,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":28,"r":[226,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":29,"r":[244,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":30,"r":[263,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":31,"r":[280,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":32,"r":[298,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":33,"r":[317,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":34,"r":[329,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":35,"r":[341,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":36,"r":[353,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":37,"r":[362,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":38,"r":[368,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":39,"r":[386,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":40,"r":[404,0,6,8,0,-4,0]}}
  #|{"textrec":{"g":41,"r":[411,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":42,"r":[430,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[448,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":62,"r":[465,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":48,"r":[480,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":49,"r":[496,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":50,"r":[513,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":51,"r":[519,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":52,"r":[536,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":53,"r":[552,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[568,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":55,"r":[585,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":56,"r":[601,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":57,"r":[616,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":58,"r":[626,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":59,"r":[637,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":60,"r":[648,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":61,"r":[658,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,63]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11]}}
  #|{"textrec":{"s":[13,500,0,"以下是新消息"],"r":[0,1,12.898832684824903,64,1,1,12.898832684824903,65,2,1,12.898832684824903,66,3,1,12.898832684824903,67,4,1,12.898832684824896,68,5,1,12.898832684824896,69]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,70,1,1,14.883268482490273,71,2,1,14.883268482490273,72,3,1,14.883268482490273,73]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[10,400,0,"4 分钟前"],"r":[0,1,6.552734375,74,1,1,2.9296875,-1,2,1,9.941634241245136,75,3,1,9.941634241245136,76,4,1,9.941634241245133,77]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,78,1,1,14.883268482490273,79,2,1,15.087548638132297,80,3,1,14.883268482490273,81,4,1,14.883268482490266,82,5,1,14.88326848249028,83,6,1,14.88326848249028,84,7,1,14.88326848249028,85,8,1,14.88326848249028,86,9,1,3.984375,-1,10,1,8.0419921875,87,11,1,8.90625,88,12,1,8.3349609375,89,13,1,8.51806640625,90,14,1,5.21484375,91]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,92,1,1,15.875486381322958,93,2,1,15.875486381322958,92,3,1,15.875486381322958,94,4,1,15.875486381322958,95,5,1,15.875486381322958,96,6,1,15.875486381322958,97,7,1,15.875486381322958,98,8,1,4.1875,-1,9,1,9.453125,99,10,1,9.140625,100,11,1,8.0234375,101,12,1,5.4609375,102,13,1,4.4375,103,14,1,15.875486381322958,104,15,1,15.875486381322958,105,16,1,16.09338521400778,106,17,1,15.875486381322958,107,18,1,15.875486381322958,108,19,1,15.87548638132293,94,20,1,15.875486381322958,95,21,1,15.875486381322958,109,22,1,15.875486381322958,96,23,1,4.1875,-1,24,1,8.515625,110,25,1,9.4375,111,26,1,8.828125,112,27,1,9.0234375,113,28,1,5.5,102]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,14.076484680175781,62]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,114,1,1,4.330078125,115,2,1,7.001953125,116,3,1,7.37109375,117,4,1,2.96484375,118,5,1,7.08984375,119]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,14.076484680175781,62]}}
  #|{"textrec":{"g":78,"r":[666,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":79,"r":[683,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":80,"r":[700,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":81,"r":[706,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":82,"r":[724,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":83,"r":[741,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":84,"r":[758,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":85,"r":[776,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":86,"r":[792,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":87,"r":[808,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":88,"r":[819,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":89,"r":[830,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":90,"r":[841,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":91,"r":[851,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":92,"r":[859,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":93,"r":[877,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":94,"r":[895,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":95,"r":[913,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":96,"r":[932,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":97,"r":[949,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":98,"r":[967,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":99,"r":[986,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":100,"r":[997,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":101,"r":[1009,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":102,"r":[1020,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":103,"r":[1029,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":104,"r":[1035,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1053,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1071,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":107,"r":[1078,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":108,"r":[1096,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":109,"r":[1114,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":110,"r":[1131,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":111,"r":[1142,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":112,"r":[1154,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":113,"r":[1166,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[1177,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":71,"r":[1195,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[1213,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[1231,0,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,120,1,1,15.875486381322958,121,2,1,15.875486381322958,122]}}
  #|{"textrec":{"g":120,"r":[1248,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":121,"r":[1266,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":122,"r":[1284,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":74,"r":[1302,0,8,10,-1,-9,0]}}
  #|{"textrec":{"g":75,"r":[1311,0,12,12,-1,-9,0]}}
  #|{"textrec":{"g":76,"r":[1324,0,11,12,-1,-9,0]}}
  #|{"textrec":{"g":77,"r":[1336,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":64,"r":[1349,0,14,15,0,-12,0]}}
  #|{"textrec":{"g":65,"r":[1364,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":66,"r":[1379,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":67,"r":[1394,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":68,"r":[1410,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":69,"r":[1425,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":63,"r":[1441,0,8,8,-1,-7,0]}}
  #|{"textrec":{"g":114,"r":[1450,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":115,"r":[1459,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":116,"r":[1466,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":117,"r":[1476,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":118,"r":[1486,0,5,11,-1,-10,0]}}
  #|{"textrec":{"g":119,"r":[1492,0,9,10,-1,-8,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["2b45ffca62dc37ab",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,400,0,"看看文档 083209 steps:文档目录看过了 083209"],"r":[0,1,15.875486381322958,123,1,1,15.875486381322958,123,2,1,15.875486381322958,124,3,1,15.875486381322958,125,4,1,4.1875,-1,5,1,9.765625,126,6,1,9.90625,127,7,1,9.71875,128,8,1,9.34375,129,9,1,9.765625,126,10,1,9.875,130,11,1,4.1875,-1,12,1,8.0234375,101,13,1,5.40234375,102,14,1,8.76953125,112,15,1,9.453125,99,16,1,8.0625,101,17,1,4.4375,103,18,1,15.875486381322958,124,19,1,15.875486381322958,125,20,1,15.875486381322958,131,21,1,15.875486381322958,132,22,1,15.875486381322958,123,23,1,15.875486381322958,133,24,1,15.875486381322958,134,25,1,4.1875,-1,26,1,9.765625,126,27,1,9.90625,127,28,1,9.71875,128,29,1,9.34375,129,30,1,9.765625,126,31,1,9.875,130]}}
  #|{"textrec":{"g":123,"r":[1502,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":124,"r":[1520,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":125,"r":[1538,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":126,"r":[1556,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":127,"r":[1568,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":128,"r":[1580,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":129,"r":[1592,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":130,"r":[1603,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":131,"r":[1615,0,14,16,1,-13,0]}}
  #|{"textrec":{"g":132,"r":[1630,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":133,"r":[1648,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":134,"r":[1666,0,15,16,0,-13,0]}}
  #|{"textrec":{"ib":["9699dbc96b0fdfd9",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.497894287109375,35,12,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[15,400,0,"处理中"],"r":[0,1,14.883268482490273,135,1,1,14.883268482490273,136,2,1,14.883268482490273,137]}}
  #|{"textrec":{"s":[15,400,0,"0s"],"r":[0,1,9.2138671875,138,1,1,7.6171875,139]}}
  #|{"textrec":{"s":[10,400,0,"正在发送"],"r":[0,1,9.941634241245136,140,1,1,9.941634241245136,141,2,1,9.941634241245136,142,3,1,9.941634241245136,143]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.329673767089844,34,11,1,13.973621368408203,144]}}
  #|{"textrec":{"g":140,"r":[1682,0,12,11,-1,-9,0]}}
  #|{"textrec":{"g":141,"r":[1695,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":142,"r":[1708,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":143,"r":[1721,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":135,"r":[1734,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":136,"r":[1752,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":137,"r":[1770,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":138,"r":[1786,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":139,"r":[1798,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":144,"r":[1809,0,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"ib":["21d27b298626ff58",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["f5b690f675ff566e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["4bc090bb9b23f00c",332,64],"r":[8,8,8,8]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,145,1,1,9.941634241245136,145]}}
  #|{"textrec":{"g":145,"r":[1824,0,11,11,-1,-9,0]}}
  #|{"textrec":{"ib":["23be9de733505de0",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[15,400,0,"…"],"r":[0,1,11.8359375,146]}}
  #|{"textrec":{"s":[15,400,0,"处…"],"r":[0,1,14.883268482490273,135,1,1,11.8359375,146]}}
  #|{"textrec":{"g":146,"r":[1836,0,12,5,0,-3,0]}}
  #|{"textrec":{"ib":["c0c6472547170db1",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["805e20b342e99c1d",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.721336364746094,33,10,1,13.973621368408203,144]}}
  #|{"textrec":{"ib":["81585702d274dcb9",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["757f0d8a38f50a63",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c128550ca18c58cd",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e92142d386538128",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["92e22e14c647c922",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[15,400,0,"文档目录看过了 083209"],"r":[0,1,14.883268482490273,147,1,1,14.883268482490273,148,2,1,14.883268482490273,149,3,1,14.883268482490273,150,4,1,14.88326848249028,151,5,1,14.88326848249028,152,6,1,14.88326848249028,153,7,1,3.984375,-1,8,1,9.2138671875,138,9,1,9.345703125,154,10,1,9.169921875,155,11,1,8.818359375,156,12,1,9.2138671875,138,13,1,9.31640625,157]}}
  #|{"textrec":{"g":147,"r":[1849,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":148,"r":[1867,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":149,"r":[1884,0,13,16,1,-13,0]}}
  #|{"textrec":{"g":150,"r":[1898,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":151,"r":[1915,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":152,"r":[1932,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":153,"r":[1950,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":154,"r":[1965,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[1977,0,10,14,0,-12,0]}}
  #|{"textrec":{"g":156,"r":[1988,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":157,"r":[1999,0,11,14,-1,-12,0]}}
  #|{"textrec":{"s":[18,700,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,17.842412451361866,158,1,1,17.842412451361866,159,2,1,17.842412451361866,158,3,1,17.842412451361866,160,4,1,17.842412451361866,161,5,1,17.842412451361866,162,6,1,17.842412451361866,163,7,1,17.842412451361866,164,8,1,4.152015030384064,-1,9,1,11.16209328174591,165,10,1,10.675500869750977,166,11,1,9.692523032426834,167,12,1,6.919372379779816,168,13,1,5.73083621263504,169,14,1,17.842412451361866,170,15,1,17.842412451361866,171,16,1,18.08754863813229,172,17,1,17.842412451361866,173,18,1,17.842412451361838,174,19,1,17.842412451361838,160,20,1,17.842412451361838,161,21,1,17.842412451361838,175,22,1,17.842412451361838,162,23,1,4.152015030384064,-1,24,1,10.138570368289948,176,25,1,11.132530510425568,177,26,1,10.337921261787415,178,27,1,10.808134496212006,179,28,1,6.940345913171768,168]}}
  #|{"textrec":{"m":[18,700,0],"r":[17.40234375,3.796875,26]}}
  #|{"textrec":{"s":[13,400,0,"你 4 分钟前发起 · 最新 刚刚"],"r":[0,1,12.898832684824903,4,1,1,3.580078125,-1,2,1,8.2900390625,180,3,1,3.580078125,-1,4,1,12.898832684824903,181,5,1,12.898832684824903,182,6,1,12.898832684824903,183,7,1,12.898832684824896,184,8,1,12.898832684824896,185,9,1,3.580078125,-1,10,1,6.228545204222115,186,11,1,3.580078125,-1,12,1,12.898832684824896,187,13,1,12.898832684824896,188,14,1,3.580078125,-1,15,1,12.898832684824896,189,16,1,12.898832684824896,189]}}
  #|{"textrec":{"s":[15,600,0,"默认模型"],"r":[0,1,14.883268482490273,190,1,1,14.883268482490273,191,2,1,14.883268482490273,192,3,1,14.883268482490273,193]}}
  #|{"textrec":{"s":[12,400,0,"已完成：answered the question that was asked · 刚刚"],"r":[0,1,11.918287937743191,194,1,1,11.918287937743191,195,2,1,11.918287937743195,196,3,1,12.081712062256813,197,4,1,6.62109375,198,5,1,7.001953125,199,6,1,6.193359375,114,7,1,9.087890625,200,8,1,6.73828125,201,9,1,4.482421875,202,10,1,6.767578125,201,11,1,7.37109375,117,12,1,3.375,-1,13,1,4.359375,115,14,1,7.060546875,203,15,1,6.85546875,201,16,1,3.375,-1,17,1,7.312500000000014,204,18,1,7.001953125,116,19,1,6.85546875,201,20,1,6.251953125,114,21,1,4.330078125,115,22,1,2.96484375,118,23,1,7.08984375,119,24,1,7.001953125,199,25,1,3.375,-1,26,1,4.359375,115,27,1,7.060546875,203,28,1,6.62109375,198,29,1,4.359375,115,30,1,3.375,-1,31,1,9.205078125,200,32,1,6.533203125,198,33,1,6.28125,114,34,1,3.375,-1,35,1,6.62109375,198,36,1,6.28125,114,37,1,6.369140625,205,38,1,6.708984375,201,39,1,7.37109375,117,40,1,3.375,-1,41,1,5.754933455713626,206,42,1,3.375,-1,43,1,11.918287937743173,207,44,1,11.918287937743173,207]}}
  #|{"textrec":{"s":[14,400,0,"固定到列表顶部"],"r":[0,1,13.891050583657588,208,1,1,13.891050583657588,209,2,1,13.891050583657588,210,3,1,13.891050583657588,211,4,1,13.891050583657588,212,5,1,13.891050583657588,213,6,1,13.891050583657588,214]}}
  #|{"textrec":{"s":[14,400,0,"复制会话链接"],"r":[0,1,13.891050583657588,215,1,1,13.891050583657588,216,2,1,13.891050583657588,217,3,1,13.891050583657588,218,4,1,13.891050583657588,219,5,1,13.891050583657588,220]}}
  #|{"textrec":{"s":[14,400,0,"归档对话"],"r":[0,1,13.891050583657588,221,1,1,13.891050583657588,222,2,1,13.891050583657588,223,3,1,13.891050583657588,218]}}
  #|{"textrec":{"s":[12,400,0,"…"],"r":[0,1,9.65625,224]}}
  #|{"textrec":{"s":[12,400,0,"已完成：answered the question that was ask…"],"r":[0,1,11.918287937743191,194,1,1,11.918287937743191,195,2,1,11.918287937743195,196,3,1,12.081712062256813,197,4,1,6.62109375,198,5,1,7.001953125,199,6,1,6.193359375,114,7,1,9.087890625,200,8,1,6.73828125,201,9,1,4.482421875,202,10,1,6.767578125,201,11,1,7.37109375,117,12,1,3.375,-1,13,1,4.359375,115,14,1,7.060546875,203,15,1,6.85546875,201,16,1,3.375,-1,17,1,7.312500000000014,204,18,1,7.001953125,116,19,1,6.85546875,201,20,1,6.251953125,114,21,1,4.330078125,115,22,1,2.96484375,118,23,1,7.08984375,119,24,1,7.001953125,199,25,1,3.375,-1,26,1,4.359375,115,27,1,7.060546875,203,28,1,6.62109375,198,29,1,4.359375,115,30,1,3.375,-1,31,1,9.205078125,200,32,1,6.533203125,198,33,1,6.28125,114,34,1,3.375,-1,35,1,6.62109375,198,36,1,6.28125,114,37,1,6.515625,205,38,1,9.65625,224]}}
  #|{"textrec":{"g":158,"r":[2011,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":159,"r":[0,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":160,"r":[20,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":161,"r":[40,20,20,19,-1,-16,0]}}
  #|{"textrec":{"g":162,"r":[61,20,18,19,0,-16,0]}}
  #|{"textrec":{"g":163,"r":[80,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":164,"r":[100,20,20,19,-1,-16,0]}}
  #|{"textrec":{"g":165,"r":[121,20,12,16,0,-11,0]}}
  #|{"textrec":{"g":166,"r":[134,20,13,13,-1,-11,0]}}
  #|{"textrec":{"g":167,"r":[148,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":168,"r":[161,20,9,15,-1,-13,0]}}
  #|{"textrec":{"g":169,"r":[171,20,6,13,0,-11,0]}}
  #|{"textrec":{"g":170,"r":[178,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":171,"r":[198,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":172,"r":[218,20,7,9,0,-4,0]}}
  #|{"textrec":{"g":173,"r":[226,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":174,"r":[246,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":175,"r":[266,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":176,"r":[285,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":177,"r":[298,20,13,16,-1,-11,0]}}
  #|{"textrec":{"g":178,"r":[312,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":179,"r":[325,20,12,12,0,-11,0]}}
  #|{"textrec":{"g":4,"r":[338,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":180,"r":[353,20,10,12,-1,-11,0]}}
  #|{"textrec":{"g":181,"r":[364,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":182,"r":[380,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":183,"r":[395,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":184,"r":[411,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":185,"r":[426,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":186,"r":[442,20,4,5,1,-7,0]}}
  #|{"textrec":{"g":187,"r":[447,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":188,"r":[462,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":189,"r":[478,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":190,"r":[493,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":191,"r":[511,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":192,"r":[529,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":193,"r":[547,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":194,"r":[564,20,13,12,0,-10,0]}}
  #|{"textrec":{"g":195,"r":[578,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":196,"r":[593,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":197,"r":[608,20,4,9,1,-9,0]}}
  #|{"textrec":{"g":198,"r":[613,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":199,"r":[622,20,9,9,-1,-8,0]}}
  #|{"textrec":{"g":200,"r":[632,20,11,9,-1,-8,0]}}
  #|{"textrec":{"g":201,"r":[644,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":202,"r":[654,20,7,9,-1,-8,0]}}
  #|{"textrec":{"g":203,"r":[662,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":204,"r":[671,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":205,"r":[681,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":224,"r":[690,20,10,5,0,-3,0]}}
  #|{"textrec":{"g":208,"r":[701,20,14,15,0,-12,0]}}
  #|{"textrec":{"g":209,"r":[716,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":210,"r":[732,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":211,"r":[748,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":212,"r":[764,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":213,"r":[780,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":214,"r":[797,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":215,"r":[813,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":216,"r":[829,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":217,"r":[845,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":218,"r":[862,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":219,"r":[879,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":220,"r":[896,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":221,"r":[912,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":222,"r":[928,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":223,"r":[944,20,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["9c06d7ecdaa044c6",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["92022e9e11aef691",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["f1276e6323a9ca06",1853,64],"r":[21,21,21,21]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["030aece180ce0f3c",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["b9bedad57f2a5f13",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["97cc1349f5996766",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["ec36c6e8ac21838c",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["aeda78da8b5e3b41",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["a4d1a98b8e0d1a16",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[15,400,0,"1s"],"r":[0,1,6.7236328125,225,1,1,7.6171875,139]}}
  #|{"textrec":{"g":225,"r":[960,20,8,13,-1,-12,0]}}
  #|{"textrec":{"ib":["f01fcb189f45d55f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["9f0662fe9e17eae7",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["a986d7bcdb21f400",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["4503e9e4577fb13f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["d70c57d0da6e9617",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["614ee45c85d9b372",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[15,400,0,"处理…"],"r":[0,1,14.883268482490273,135,1,1,14.883268482490273,136,2,1,11.8359375,146]}}
  #|{"textrec":{"ib":["c4fa0db25ea05b0c",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c2e47748355a73f3",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c87083340379cf22",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["cf97bef1151b216c",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["ee2a42e952bf870f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[15,400,0,"2s"],"r":[0,1,8.818359375,156,1,1,7.6171875,139]}}
  #|{"textrec":{"s":[17,700,0,"默认模型"],"r":[0,1,16.851167315175097,226,1,1,16.851167315175097,227,2,1,16.851167315175097,228,3,1,16.851167315175097,229]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[13,400,0,"已完成：answered the question that was asked"],"r":[0,1,12.898832684824903,230,1,1,12.898832684824903,231,2,1,12.898832684824903,232,3,1,13.075875486381321,233,4,1,7.0966796875,12,5,1,7.509277343749993,234,6,1,6.63330078125,10,7,1,9.76904296875,6,8,1,7.2236328125,14,9,1,4.77978515625,8,10,1,7.25537109375,14,11,1,7.9091796875,235,12,1,3.580078125,-1,13,1,4.646484375,236,14,1,7.57275390625,237,15,1,7.3505859375,14,16,1,3.580078125,-1,17,1,7.845703125,238,18,1,7.50927734375,239,19,1,7.3505859375,14,20,1,6.69677734375,10,21,1,4.61474609375,236,22,1,3.1357421875,240,23,1,7.6044921875,7,24,1,7.50927734375,234,25,1,3.580078125,-1,26,1,4.646484375,236,27,1,7.57275390625,237,28,1,7.0966796875,12,29,1,4.646484375,236,30,1,3.580078125,-1,31,1,9.89599609375,6,32,1,7.00146484375,12,33,1,6.728515625,10,34,1,3.580078125,-1,35,1,7.0966796875,12,36,1,6.728515625000028,10,37,1,6.82373046875,9,38,1,7.19189453125,14,39,1,7.9091796875,235]}}
  #|{"textrec":{"s":[13,400,0," · 刚刚"],"r":[0,1,3.580078125,-1,1,1,6.228545204222119,186,2,1,3.580078125,-1,3,1,12.898832684824903,189,4,1,12.8988326848249,189]}}
  #|{"textrec":{"s":[14,400,0,"Station"],"r":[0,1,8.7705078125,241,1,1,4.935546875,61,2,1,7.57421875,57,3,1,4.935546875,61,4,1,3.30859375,242,5,1,8.12109375,243,6,1,8.0185546875,60]}}
  #|{"textrec":{"s":[14,400,0,"studio"],"r":[0,1,7.1435546875,244,1,1,4.9013671875,61,2,1,8.0185546875,245,3,1,8.44921875,246,4,1,3.30859375,242,5,1,8.12109375,243]}}
  #|{"textrec":{"s":[14,400,0,"账号"],"r":[0,1,13.891050583657588,247,1,1,13.891050583657588,248]}}
  #|{"textrec":{"s":[14,400,0,"cc · 自动"],"r":[0,1,7.68359375,249,1,1,7.68359375,249,2,1,3.787109375,-1,3,1,6.707664066085361,250,4,1,3.787109375,-1,5,1,13.891050583657584,251,6,1,13.891050583657588,252]}}
  #|{"textrec":{"s":[14,400,0,"历史"],"r":[0,1,13.891050583657588,253,1,1,13.891050583657588,254]}}
  #|{"textrec":{"s":[14,400,0,"尚未运行"],"r":[0,1,13.891050583657588,255,1,1,13.891050583657588,256,2,1,13.891050583657588,257,3,1,13.891050583657588,258]}}
  #|{"textrec":{"g":226,"r":[969,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":227,"r":[989,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":228,"r":[1009,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":229,"r":[1028,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":230,"r":[1047,20,13,13,0,-11,0]}}
  #|{"textrec":{"g":231,"r":[1061,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":232,"r":[1077,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":233,"r":[1093,20,4,9,1,-9,0]}}
  #|{"textrec":{"g":12,"r":[1098,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":234,"r":[1108,20,8,9,0,-8,0]}}
  #|{"textrec":{"g":10,"r":[1117,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":6,"r":[1127,20,12,9,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[1140,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":8,"r":[1150,20,6,9,0,-8,0]}}
  #|{"textrec":{"g":235,"r":[1157,20,9,13,-1,-11,0]}}
  #|{"textrec":{"g":236,"r":[1167,20,7,12,-1,-10,0]}}
  #|{"textrec":{"g":237,"r":[1175,20,8,12,0,-11,0]}}
  #|{"textrec":{"g":238,"r":[1184,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":239,"r":[1194,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":240,"r":[1204,20,5,12,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[1210,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":9,"r":[1220,20,8,12,0,-11,0]}}
  #|{"textrec":{"g":241,"r":[1229,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":242,"r":[1241,20,5,13,-1,-12,0]}}
  #|{"textrec":{"g":243,"r":[1247,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":244,"r":[1258,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":245,"r":[1268,20,9,11,0,-9,0]}}
  #|{"textrec":{"g":246,"r":[1278,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":247,"r":[1289,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":248,"r":[1306,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":249,"r":[1322,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":250,"r":[1333,20,5,4,1,-7,0]}}
  #|{"textrec":{"g":251,"r":[1339,20,12,16,1,-13,0]}}
  #|{"textrec":{"g":252,"r":[1352,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":253,"r":[1368,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":254,"r":[1384,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[1400,20,14,16,0,-13,0]}}
  #|{"textrec":{"g":256,"r":[1415,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[1431,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":258,"r":[1448,20,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["0e6dfc8705c682a0",2207,64],"r":[23,23,23,23]}}
  #|{"textrec":{"s":[13,400,0,"列出 docs 目录"],"r":[0,1,12.898832684824903,259,1,1,12.898832684824903,260,2,1,3.580078125,-1,3,1,7.9091796875,235,4,1,7.6044921875,7,5,1,7.1982421875,13,6,1,6.728515625,10,7,1,3.580078125,-1,8,1,12.89883268482491,261,9,1,12.898832684824896,262]}}
  #|{"textrec":{"s":[13,400,0,"编辑 notes.md"],"r":[0,1,12.898832684824903,263,1,1,12.898832684824903,264,2,1,3.580078125,-1,3,1,7.50927734375,234,4,1,7.6044921875,7,5,1,4.598876953125,236,6,1,7.302978515625,14,7,1,6.728515625,10,8,1,3.783203125,265,9,1,11.2353515625,266,10,1,7.9091796875,235]}}
  #|{"textrec":{"s":[13,400,0,"看过了，改好了。"],"r":[0,1,12.898832684824903,267,1,1,12.898832684824903,268,2,1,12.898832684824903,269,3,1,13.075875486381321,270,4,1,12.898832684824903,271,5,1,12.89883268482491,272,6,1,12.898832684824896,269,7,1,6.575875486381321,273]}}
  #|{"textrec":{"s":[14,400,0,"2 轮"],"r":[0,1,8.298828125,274,1,1,3.787109375,-1,2,1,13.891050583657588,275]}}
  #|{"textrec":{"g":259,"r":[1464,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":260,"r":[1479,20,13,15,0,-12,0]}}
  #|{"textrec":{"g":13,"r":[1493,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":261,"r":[1503,20,11,14,1,-11,0]}}
  #|{"textrec":{"g":262,"r":[1515,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":263,"r":[1530,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":264,"r":[1545,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":265,"r":[1561,20,4,5,0,-3,0]}}
  #|{"textrec":{"g":266,"r":[1566,20,12,9,0,-8,0]}}
  #|{"textrec":{"g":267,"r":[1579,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":268,"r":[1594,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":269,"r":[1610,20,13,14,0,-11,0]}}
  #|{"textrec":{"g":270,"r":[1624,20,5,7,0,-3,0]}}
  #|{"textrec":{"g":271,"r":[1630,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":272,"r":[1646,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":273,"r":[1662,20,6,6,0,-3,0]}}
  #|{"textrec":{"g":274,"r":[1669,20,9,13,0,-12,0]}}
  #|{"textrec":{"g":275,"r":[1679,20,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"执行历史"],"r":[0,1,15.875486381322958,276,1,1,15.875486381322958,277,2,1,15.875486381322958,278,3,1,15.875486381322958,279]}}
  #|{"textrec":{"s":[13,400,0,"步骤"],"r":[0,1,12.898832684824903,280,1,1,12.898832684824903,281]}}
  #|{"textrec":{"s":[13,400,0,"详情"],"r":[0,1,12.898832684824903,282,1,1,12.898832684824903,283]}}
  #|{"textrec":{"s":[16,700,0,"默认模型"],"r":[0,1,15.875486381322958,284,1,1,15.875486381322958,285,2,1,15.875486381322958,286,3,1,15.875486381322958,287]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[17,400,0,"返回"],"r":[0,1,16.851167315175097,288,1,1,16.851167315175097,289]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[14,400,0,"看过了，改好了。"],"r":[0,1,13.891050583657588,290,1,1,13.891050583657588,291,2,1,13.891050583657588,292,3,1,14.081712062256813,50,4,1,13.891050583657588,293,5,1,13.891050583657588,49,6,1,13.891050583657588,292,7,1,7.081712062256813,294]}}
  #|{"textrec":{"s":[14,400,0,"编辑 notes.md · 共 2 项"],"r":[0,1,13.891050583657588,295,1,1,13.891050583657588,296,2,1,3.787109375,-1,3,1,8.0185546875,60,4,1,8.12109375,243,5,1,4.88427734375,61,6,1,7.79638671875,59,7,1,7.177734375,244,8,1,4.005859375,297,9,1,12.03125,298,10,1,8.44921875,246,11,1,3.787109375,-1,12,1,6.707664066085357,250,13,1,3.787109375,-1,14,1,13.891050583657588,299,15,1,3.787109375,-1,16,1,8.298828125000014,274,17,1,3.787109375,-1,18,1,13.891050583657602,300]}}
  #|{"textrec":{"s":[13,400,0,"收到来自 "],"r":[0,1,12.898832684824903,301,1,1,12.898832684824903,302,2,1,12.898832684824903,303,3,1,12.898832684824903,304,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,600,0,"still.fail"],"r":[0,1,7.060585141181946,305,1,1,5.030813574790955,306,2,1,3.4653801918029785,307,3,1,3.5576319694519043,308,4,1,3.5576319694519043,308,5,1,3.9606012105941772,309,6,1,4.6613849401474,310,7,1,7.302963018417358,311,8,1,3.4653801918029785,307,9,1,3.5576319694519043,308]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[13,400,0," 的提醒"],"r":[0,1,3.580078125,-1,1,1,12.898832684824903,5,2,1,12.898832684824903,312,3,1,12.898832684824903,313]}}
  #|{"textrec":{"s":[14,400,0,"Your earlier conversation could not be restored. Read the relevant threads with chat_history to catch up before answering."],"r":[0,1,8.4423828125,314,1,1,7.5400390625,243,2,1,8.0185546875,245,3,1,5.181640625,315,4,1,3.787109375,-1,5,1,7.84765625,59,6,1,7.57421875,57,7,1,5.181640625,315,8,1,3.390625,316,9,1,3.30859375,242,10,1,7.84765625,59,11,1,5.181640625,315,12,1,3.787109375,-1,13,1,7.68359375,249,14,1,8.12109375,243,15,1,7.8818359375,60,16,1,7.1640625,317,17,1,7.7109375,59,18,1,5.11328125,315,19,1,7.109375,244,20,1,7.57421875,57,21,1,4.935546875,61,22,1,3.30859375,242,23,1,8.12109375,243,24,1,8.0185546875,60,25,1,3.787109375,-1,26,1,7.68359375,249,27,1,8.12109375,243,28,1,8.0185546875,245,29,1,3.390625,316,30,1,8.44921875,246,31,1,3.787109375,-1,32,1,8.0185546875,60,33,1,8.12109375,243,34,1,4.935546875,61,35,1,3.787109375,-1,36,1,8.44921875,318,37,1,7.84765625,59,38,1,3.787109375,-1,39,1,5.0791015625,315,40,1,7.7451171875,59,41,1,7.1435546875,244,42,1,4.85009765625,61,43,1,8.06982421875,243,44,1,5.0791015625,315,45,1,7.7451171875,59,46,1,8.44921875,246,47,1,4.005859375,297,48,1,3.787109375,-1,49,1,8.8935546875,319,50,1,7.7451171875,59,51,1,7.57421875,57,52,1,8.44921875,246,53,1,3.787109375,-1,54,1,4.935546875,61,55,1,8.0869140625,320,56,1,7.84765625,59,57,1,3.787109375,-1,58,1,5.0791015625,315,59,1,7.7451171875,59,60,1,3.390625,316,61,1,7.779296875,59,62,1,7.232421875,317,63,1,7.4375,57,64,1,8.0185546875,60,65,1,4.935546875,61,66,1,3.787109375,-1,67,1,4.935546875,61,68,1,8.0869140625,320,69,1,5.0791015625,315,70,1,7.7451171875,59,71,1,7.57421875,57,72,1,8.44921875,246,73,1,7.177734375,244,74,1,3.787109375,-1,75,1,10.69140625,321,76,1,3.30859375,242,77,1,4.935546875,61,78,1,8.0869140625,320,79,1,3.787109375,-1,80,1,7.68359375,249,81,1,8.0869140625,320,82,1,7.57421875,57,83,1,4.935546875,61,84,1,8.0185546875,322,85,1,8.0869140625,320,86,1,3.30859375,242,87,1,7.1435546875,244,88,1,4.85009765625,61,89,1,8.06982421875,243,90,1,5.2158203125,315,91,1,7.4853515625,323,92,1,3.787109375,-1,93,1,4.88427734375,61,94,1,8.06982421875,243,95,1,3.787109375,-1,96,1,7.68359375,249,97,1,7.57421875,57,98,1,4.88427734375,61,99,1,7.63232421875,249,100,1,8.0869140625,320,101,1,3.787109375,-1,102,1,8.0185546875,245,103,1,8.39453125,324,104,1,3.787109375,-1,105,1,8.44921875,318,106,1,7.84765625,59,107,1,4.76123046875,325,108,1,7.96728515625,243,109,1,5.0791015625,315,110,1,7.7451171875,59,111,1,3.787109375,-1,112,1,7.57421875,57,113,1,8.0185546875,60,114,1,7.0751953125,244,115,1,10.4521484375,321,116,1,7.7109375,59,117,1,5.181640625,315,118,1,3.30859375,242,119,1,8.0185546875,60,120,1,8.380859375,58,121,1,4.005859375,297]}}
  #|{"textrec":{"s":[13,600,0,"Name of alice"],"r":[0,1,9.785324335098267,326,1,1,7.408227801322937,311,2,1,11.745888471603394,327,3,1,7.593794465065002,328,4,1,3.3871192932128906,-1,5,1,7.841670751571655,329,6,1,5.007329106330872,310,7,1,3.3871192932128906,-1,8,1,7.408227801322937,311,9,1,3.5576319694519043,308,10,1,3.4653801918029785,307,11,1,7.427380800247192,330,12,1,7.593794465065002,328]}}
  #|{"textrec":{"s":[13,400,0," 的消息"],"r":[0,1,3.580078125,-1,1,1,12.898832684824903,5,2,1,12.898832684824903,331,3,1,12.898832684824903,332]}}
  #|{"textrec":{"s":[13,400,0," · "],"r":[0,1,3.580078125,-1,1,1,6.228545204222119,186,2,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,12.898832684824903,333,1,1,12.898832684824903,334,2,1,12.898832684824903,333,3,1,12.898832684824903,335,4,1,12.898832684824896,336,5,1,12.898832684824896,337,6,1,12.898832684824896,338,7,1,12.898832684824896,339,8,1,3.3871192932128906,-1,9,1,8.159896612167358,340,10,1,7.841670751571655,329,11,1,7.060585141181946,305,12,1,5.030813574790955,306,13,1,4.20128059387207,341,14,1,12.898832684824896,342,15,1,12.898832684824896,343,16,1,13.075875486381335,344,17,1,12.898832684824896,345,18,1,12.898832684824896,346,19,1,12.898832684824896,335,20,1,12.898832684824896,336,21,1,12.898832684824896,347,22,1,12.898832684824896,337,23,1,3.387119293212919,-1,24,1,7.408227801322937,311,25,1,8.141171336174011,348,26,1,7.593794465065002,328,27,1,7.869065165519714,349,28,1,5.052501916885376,306]}}
  #|{"textrec":{"s":[14,400,0,"看看文档 083209 steps:文档目录看过了 083209"],"r":[0,1,13.891050583657588,290,1,1,13.891050583657588,290,2,1,13.891050583657588,350,3,1,13.891050583657588,222,4,1,3.787109375,-1,5,1,8.66796875,351,6,1,8.791015625,352,7,1,8.626953125,353,8,1,8.298828125,274,9,1,8.66796875,351,10,1,8.763671875,354,11,1,3.787109375,-1,12,1,7.1435546875,244,13,1,4.85009765625,61,14,1,7.79638671875,59,15,1,8.39453125,324,16,1,7.177734375,244,17,1,4.005859375,355,18,1,13.891050583657602,350,19,1,13.891050583657602,222,20,1,13.891050583657602,356,21,1,13.891050583657602,357,22,1,13.891050583657602,290,23,1,13.891050583657602,291,24,1,13.891050583657602,292,25,1,3.787109375,-1,26,1,8.66796875,351,27,1,8.791015625,352,28,1,8.626953125,353,29,1,8.298828125,274,30,1,8.66796875,351,31,1,8.763671875,354]}}
  #|{"textrec":{"s":[12,400,0,"已到会话开头"],"r":[0,1,11.918287937743191,194,1,1,11.918287937743191,358,2,1,11.918287937743195,359,3,1,11.918287937743187,360,4,1,11.918287937743187,361,5,1,11.918287937743187,362]}}
  #|{"textrec":{"g":288,"r":[1696,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":289,"r":[1715,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":358,"r":[1732,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":359,"r":[1746,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":360,"r":[1761,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":361,"r":[1776,20,14,13,-1,-10,0]}}
  #|{"textrec":{"g":362,"r":[1791,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":314,"r":[1805,20,11,12,-1,-11,0]}}
  #|{"textrec":{"g":315,"r":[1817,20,6,10,0,-9,0]}}
  #|{"textrec":{"g":316,"r":[1824,20,4,13,0,-12,0]}}
  #|{"textrec":{"g":317,"r":[1829,20,10,10,-1,-9,0]}}
  #|{"textrec":{"g":318,"r":[1840,20,9,14,0,-12,0]}}
  #|{"textrec":{"g":297,"r":[1850,20,4,5,0,-3,0]}}
  #|{"textrec":{"g":319,"r":[1855,20,10,12,0,-11,0]}}
  #|{"textrec":{"g":320,"r":[1866,20,9,13,0,-12,0]}}
  #|{"textrec":{"g":321,"r":[1876,20,13,10,-1,-9,0]}}
  #|{"textrec":{"g":322,"r":[1890,20,11,4,-1,-1,0]}}
  #|{"textrec":{"g":323,"r":[1902,20,10,13,-1,-9,0]}}
  #|{"textrec":{"g":324,"r":[1913,20,9,13,0,-9,0]}}
  #|{"textrec":{"g":325,"r":[1923,20,7,13,-1,-12,0]}}
  #|{"textrec":{"g":290,"r":[1931,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":350,"r":[1947,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":351,"r":[1964,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":352,"r":[1975,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":353,"r":[1987,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":354,"r":[1998,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":355,"r":[2010,20,4,10,0,-8,0]}}
  #|{"textrec":{"g":356,"r":[2015,20,12,15,1,-12,0]}}
  #|{"textrec":{"g":357,"r":[2028,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":291,"r":[0,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":292,"r":[17,40,13,15,0,-12,0]}}
  #|{"textrec":{"g":293,"r":[31,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":294,"r":[48,40,6,6,0,-3,0]}}
  #|{"textrec":{"ib":["b7bb1080b4377070",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["82c2071e3017b0de",757,64],"r":[13,13,13,13]}}
  #|{"textrec":{"g":284,"r":[55,40,18,17,-1,-14,0]}}
  #|{"textrec":{"g":285,"r":[74,40,18,17,-1,-14,0]}}
  #|{"textrec":{"g":286,"r":[93,40,17,17,-1,-14,0]}}
  #|{"textrec":{"g":287,"r":[111,40,17,17,-1,-14,0]}}
  #|{"textrec":{"g":301,"r":[129,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":302,"r":[145,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[160,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[176,40,11,15,1,-12,0]}}
  #|{"textrec":{"g":305,"r":[188,40,9,11,-1,-9,0]}}
  #|{"textrec":{"g":306,"r":[198,40,7,12,-1,-10,0]}}
  #|{"textrec":{"g":307,"r":[206,40,5,12,-1,-11,0]}}
  #|{"textrec":{"g":308,"r":[212,40,4,12,0,-11,0]}}
  #|{"textrec":{"g":309,"r":[217,40,5,5,0,-3,0]}}
  #|{"textrec":{"g":310,"r":[223,40,7,12,-1,-11,0]}}
  #|{"textrec":{"g":311,"r":[231,40,9,11,-1,-9,0]}}
  #|{"textrec":{"g":5,"r":[241,40,13,15,0,-12,0]}}
  #|{"textrec":{"g":312,"r":[255,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":313,"r":[271,40,15,14,-1,-11,0]}}
  #|{"textrec":{"g":326,"r":[287,40,10,12,0,-11,0]}}
  #|{"textrec":{"g":327,"r":[298,40,13,10,-1,-9,0]}}
  #|{"textrec":{"g":328,"r":[312,40,10,11,-1,-9,0]}}
  #|{"textrec":{"g":329,"r":[323,40,10,11,-1,-9,0]}}
  #|{"textrec":{"g":330,"r":[334,40,9,11,-1,-9,0]}}
  #|{"textrec":{"g":331,"r":[344,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":332,"r":[359,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":333,"r":[375,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":334,"r":[391,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":335,"r":[406,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":336,"r":[421,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":337,"r":[437,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":338,"r":[452,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":339,"r":[468,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":340,"r":[484,40,10,13,-1,-9,0]}}
  #|{"textrec":{"g":341,"r":[495,40,5,10,0,-8,0]}}
  #|{"textrec":{"g":342,"r":[501,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":343,"r":[517,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":344,"r":[533,40,5,7,0,-3,0]}}
  #|{"textrec":{"g":345,"r":[539,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":346,"r":[555,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":347,"r":[570,40,14,14,-1,-11,0]}}
  #|{"textrec":{"g":348,"r":[585,40,10,13,-1,-9,0]}}
  #|{"textrec":{"g":349,"r":[596,40,10,10,-1,-9,0]}}
  #|{"textrec":{"g":295,"r":[607,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":296,"r":[623,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":298,"r":[640,40,13,10,0,-9,0]}}
  #|{"textrec":{"g":299,"r":[654,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":300,"r":[670,40,16,15,-1,-12,0]}}
  #|{"textrec":{"g":276,"r":[687,40,18,17,-1,-14,0]}}
  #|{"textrec":{"g":277,"r":[706,40,17,17,-1,-14,0]}}
  #|{"textrec":{"g":278,"r":[724,40,17,17,-1,-14,0]}}
  #|{"textrec":{"g":279,"r":[742,40,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["5e7fcd0c8367a3ab",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":280,"r":[760,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":281,"r":[775,40,15,14,-1,-11,0]}}
  #|{"textrec":{"g":282,"r":[791,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":283,"r":[807,40,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["ee44219918426000",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[11,400,0,"0ms"],"r":[0,1,6.9931640625,363,1,1,9.6357421875,364,2,1,5.822265625,365]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"s":[13,500,0,"Edit"],"r":[0,1,7.792499661445618,366,1,1,8.08608341217041,367,2,1,3.3266119956970215,368,3,1,4.881580114364624,369]}}
  #|{"textrec":{"s":[11,400,0,"1ms"],"r":[0,1,5.1669921875,370,1,1,9.6357421875,364,2,1,5.822265625,365]}}
  #|{"textrec":{"s":[12,400,2,"/tmp/e2e/notes.md"],"r":[0,1,7.41796875,371,1,1,7.41796875,372,2,1,7.41796875,373,3,1,7.41796875,374,4,1,7.41796875,371,5,1,7.41796875,375,6,1,7.41796875,376,7,1,7.41796875,375,8,1,7.41796875,371,9,1,7.41796875,377,10,1,7.41796875,378,11,1,7.41796875,372,12,1,7.41796875,375,13,1,7.41796875,379,14,1,7.41796875,380,15,1,7.41796875,373,16,1,7.41796875,381]}}
  #|{"textrec":{"m":[12,400,2],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"g":363,"r":[823,40,9,11,-1,-9,0]}}
  #|{"textrec":{"g":364,"r":[833,40,11,8,-1,-7,0]}}
  #|{"textrec":{"g":365,"r":[845,40,8,9,-1,-7,0]}}
  #|{"textrec":{"g":366,"r":[854,40,8,12,0,-11,0]}}
  #|{"textrec":{"g":367,"r":[863,40,10,13,-1,-11,0]}}
  #|{"textrec":{"g":368,"r":[874,40,5,12,-1,-11,0]}}
  #|{"textrec":{"g":369,"r":[880,40,7,12,-1,-10,0]}}
  #|{"textrec":{"g":371,"r":[888,40,8,13,0,-11,0]}}
  #|{"textrec":{"g":372,"r":[897,40,9,12,-1,-10,0]}}
  #|{"textrec":{"g":373,"r":[907,40,9,9,-1,-8,0]}}
  #|{"textrec":{"g":374,"r":[917,40,8,12,0,-8,0]}}
  #|{"textrec":{"g":375,"r":[926,40,8,10,0,-8,0]}}
  #|{"textrec":{"g":376,"r":[935,40,8,11,0,-10,0]}}
  #|{"textrec":{"g":377,"r":[944,40,8,9,0,-8,0]}}
  #|{"textrec":{"g":378,"r":[953,40,9,10,-1,-8,0]}}
  #|{"textrec":{"g":379,"r":[963,40,8,10,0,-8,0]}}
  #|{"textrec":{"g":380,"r":[972,40,5,6,1,-4,0]}}
  #|{"textrec":{"g":381,"r":[978,40,9,12,-1,-10,0]}}
  #|{"textrec":{"g":370,"r":[988,40,6,10,-1,-9,0]}}
  #|{"textrec":{"ib":["ba295b08fbfa6d3a",757,64],"r":[13,13,13,13]}}
  #|{"textrec":{"s":[12,400,2,"ls"],"r":[0,1,7.41796875,382,1,1,7.41796875,379]}}
  #|{"textrec":{"s":[12,400,2," "],"r":[0,1,7.41796875,-1]}}
  #|{"textrec":{"s":[12,400,2,"docs"],"r":[0,1,7.41796875,381,1,1,7.41796875,378,2,1,7.41796875,383,3,1,7.41796875,379]}}
  #|{"textrec":{"s":[12,400,2,"stillfail-port.md\nstillfail-android-map.md"],"r":[0,1,7.41796875,379,1,1,7.41796875,372,2,1,7.41796875,384,3,1,7.41796875,382,4,1,7.41796875,382,5,1,7.41796875,385,6,1,7.41796875,386,7,1,7.41796875,384,8,1,7.41796875,382,9,1,7.41796875,387,10,1,7.41796875,374,11,1,7.41796875,378,12,1,7.41796875,388,13,1,7.41796875,372,14,1,7.41796875,380,15,1,7.41796875,373,16,1,7.41796875,381,17,1,0,-1,18,1,7.41796875,379,19,1,7.41796875,372,20,1,7.41796875,384,21,1,7.41796875,382,22,1,7.41796875,382,23,1,7.41796875,385,24,1,7.41796875,386,25,1,7.41796875,384,26,1,7.41796875,382,27,1,7.41796875,387,28,1,7.41796875,386,29,1,7.41796875,377,30,1,7.41796875,381,31,1,7.41796875,388,32,1,7.41796875,378,33,1,7.41796875,384,34,1,7.41796875,381,35,1,7.41796875,387,36,1,7.41796875,373,37,1,7.41796875,386,38,1,7.41796875,374,39,1,7.41796875,380,40,1,7.41796875,373,41,1,7.41796875,381]}}
  #|{"textrec":{"g":382,"r":[995,40,8,11,0,-10,0]}}
  #|{"textrec":{"g":383,"r":[1004,40,8,10,0,-8,0]}}
  #|{"textrec":{"g":384,"r":[1013,40,8,12,0,-11,0]}}
  #|{"textrec":{"g":385,"r":[1022,40,8,11,0,-10,0]}}
  #|{"textrec":{"g":386,"r":[1031,40,8,10,0,-8,0]}}
  #|{"textrec":{"g":387,"r":[1040,40,9,4,-1,-6,0]}}
  #|{"textrec":{"g":388,"r":[1050,40,8,9,0,-8,0]}}
