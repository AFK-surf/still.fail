// e2e/traces/markdown.trace, made by scripts/trace.py from 01-markdown.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_markdown : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 082947"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792533118}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792532827987.249}
  #|{"in":{"id":1,"ok":null},"w":1792532828110.496}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792532828110.52}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792532828110.529}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792532828112.416}
  #|{"step":"timeout 90000","w":1792532828112.433}
  #|{"step":"answered client.device","w":1792532828112.449}
  #|{"step":"answered client.focus","w":1792532828135.075}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792532828184.672}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792532828184.698}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792532828184.727}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792532828184.743}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DMG689F9J2DDVXT0E8PWF5","name":"Dev","role":"owner","created_at":1792532814,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792532814000,"ago":"刚刚","full":"10/21 05:46:54","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792532828201.34}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792532828201.357}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DMG689F9J2DDVXT0E8PWF5"},"keyed":true},"w":1792532828201.389}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DMG689F9J2DDVXT0E8PWF5","mine":false},"keyed":true},"w":1792532828201.405}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DMG689F9J2DDVXT0E8PWF5"},"keyed":true},"w":1792532828201.528}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DMG689F9J2DDVXT0E8PWF5"},"keyed":true},"w":1792532828201.561}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DMG689F9J2DDVXT0E8PWF5"}},"w":1792532828206.906}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792532828206.916}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DMG689F9J2DDVXT0E8PWF5"},"keyed":true},"w":1792532828206.923}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"5bcc433410c39b695c8e50958e7e4ba119c1b5cc5dd766a2d729d4058ae812e2","code":"P8S-UWT","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792532828220.425}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","id":"4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792532818346,"label":"今天","items":[{"id":"ember:c-ed5ad64e6c","session":"ember:c-ed5ad64e6c","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-ed5ad64e6c","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"08e988a7-dbc8-4f8f-9fce-ebe82fa0c9e7","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792532818274,"endedAt":1792532818348},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-ed5ad64e6c","text":"你好，我是测试用的 agent","createdAt":1792532818346,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792532818346,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792532818346,"station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","stationName":"studio","time":{"lastActiveAt":{"at":1792532818346,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-964b6fc24434e8b42a","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792532828220.458}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DMG689F9J2DDVXT0E8PWF5":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792532828220.48}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792532828220.486}
  #|{"in":{"id":10,"ok":null},"w":1792532828220.489}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792532828220.495}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792532828220.499}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DMG689F9J2DDVXT0E8PWF5"},"keyed":true},"w":1792532828220.528}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792532828223.129}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792532828234.665}
  #|{"in":{"id":14,"ok":null},"w":1792532828234.671}
  #|{"step":"answered notify.permission","w":1792532828234.9}
  #|{"step":"tap 端到端测试","w":1792532828251.492}
  #|{"step":"tap 端到端测试","acted":true,"w":1792532828268.237}
  #|{"out":{"id":15,"subscribe":{"topic":"chat","station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","session":"ember:c-ed5ad64e6c"},"keyed":true},"w":1792532828284.811}
  #|{"out":{"id":16,"call":"draft.get","params":{"key":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7:ember:c-ed5ad64e6c"}},"w":1792532828285.195}
  #|{"step":"answered draft.get","w":1792532828285.329}
  #|{"in":{"id":16,"ok":{"text":"","quotes":[],"files":[],"id":"draft-ef6b8a52495dd26982"}},"w":1792532828301.333}
  #|{"in":{"id":15,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792532818.208000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792532818208,"sessions":[{"thread":1,"session":"ember:c-ed5ad64e6c","connect":"ember","joinedAt":1792532818208}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792532818.346000","authorKind":"agent","author":"ember:c-ed5ad64e6c","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792532818346,"time":{"createdAt":{"at":1792532818346,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792532818208,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-ed5ad64e6c","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"a426a609-ef87-4380-b01e-0ed7dcf30b78","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-ed5ad64e6c/workspace","running":false,"createdAt":1792532818206,"lastActiveAt":1792532818347,"process":"warm","turns":1,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"08e988a7-dbc8-4f8f-9fce-ebe82fa0c9e7","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792532818274,"endedAt":1792532818348},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792532818206,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792532818347,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792532818135,"time":{"checkedAt":{"at":1792532818135,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532818252,"time":{"checkedAt":{"at":1792532818252,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532818252,"time":{"checkedAt":{"at":1792532818252,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532818252,"time":{"checkedAt":{"at":1792532818252,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532818252,"time":{"checkedAt":{"at":1792532818252,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"08e988a7-dbc8-4f8f-9fce-ebe82fa0c9e7","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792532818274,"endedAt":1792532818348}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792532818.208000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792532818208,"sessions":[{"thread":1,"session":"ember:c-ed5ad64e6c","connect":"ember","joinedAt":1792532818208}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792532818.346000","authorKind":"agent","author":"ember:c-ed5ad64e6c","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792532818346,"time":{"createdAt":{"at":1792532818346,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792532818208,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792532818.262000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792532818262,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792532818262,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792532818.346000","authorKind":"agent","author":"ember:c-ed5ad64e6c","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792532818346,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-ed5ad64e6c","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792532818346,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":2,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"connecting"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792532828301.424}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5DMG689F9J2DDVXT0E8PWF5"},"keyed":true},"w":1792532828301.547}
  #|{"out":{"id":18,"subscribe":{"topic":"chatJobs","station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","session":"ember:c-ed5ad64e6c"},"keyed":true},"w":1792532828301.557}
  #|{"out":{"id":19,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792532828301.57}
  #|{"out":{"id":20,"call":"client.focus","params":{"chat":{"station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","session":"ember:c-ed5ad64e6c","thread":1,"end":true}}},"w":1792532828304.224}
  #|{"in":{"id":17,"value":[{"station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","id":"4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792532819,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532818252,"time":{"checkedAt":{"at":1792532818252,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DMG689F9J2DDVXT0E8PWF5","device":"5bcc433410c39b695c8e50958e7e4ba119c1b5cc5dd766a2d729d4058ae812e2"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792532818135,"time":{"checkedAt":{"at":1792532818135,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532818252,"time":{"checkedAt":{"at":1792532818252,"ago":"刚刚","full":"10/21 05:46:58","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","workspace":"Dev","workspaceId":"01M5DMG689F9J2DDVXT0E8PWF5","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":58172698624,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792532815713},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792532815713},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532815713},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532815713},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532815713}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792532819000,"ago":"刚刚","full":"10/21 05:46:59","until":"1 分钟内","past":true}},"joined":false}]},"w":1792532828318.155}
  #|{"in":{"id":18,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792532828318.249}
  #|{"in":{"id":20,"ok":null},"w":1792532828318.256}
  #|{"step":"answered picture","w":1792532828319.073}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5DMG689F9J2DDVXT0E8PWF5"],"set":{"station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","key":"ember:c-ed5ad64e6c"}}]},"w":1792532828484.731}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","chat"],"set":{"station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","key":"ember:c-ed5ad64e6c"}}]},"w":1792532828484.807}
  #|{"in":{"id":19,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792532828501.355}
  #|{"step":"answered client.focus","w":1792532828518.713}
  #|{"step":"wait 300","w":1792532828535.354}
  #|{"step":"now until =studio","w":1792532828836.128}
  #|{"step":"tap 发消息","w":1792532828836.182}
  #|{"step":"tap 发消息","acted":true,"w":1792532828853.016}
  #|{"step":"type 给个表格 082947 md:表格和代码 082947","w":1792532828879.588}
  #|{"step":"type 给个表格 082947 md:表格和代码 082947","acted":true,"w":1792532828879.653}
  #|{"out":{"id":21,"call":"session.warm","params":{"station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","key":"ember:c-ed5ad64e6c"}},"w":1792532828885.111}
  #|{"step":"answered session.warm","w":1792532828892.024}
  #|{"out":{"id":22,"call":"draft.put","params":{"text":"给个表格 082947 md:表格和代码 082947","quotes":[],"files":[],"key":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7:ember:c-ed5ad64e6c"}},"w":1792532829302.216}
  #|{"in":{"id":22,"ok":{"id":"draft-ef6b8a52495dd26982"}},"w":1792532829318.037}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792532830234.74}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792532830234.826}
  #|{"in":{"id":21,"ok":{"ok":true}},"w":1792532831101.325}
  #|{"step":"tap icon:arrow-up","w":1792532831118.76}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792532831134.674}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792532831134.693}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"profile","check","checkedAt"],"set":1792532831020},{"path":["agents",0,"profile","check","time","checkedAt","at"],"set":1792532831020},{"path":["agents",0,"profile","check","time","checkedAt","full"],"set":"10/21 05:47:11"},{"path":["agents",0,"threads",0,"read"],"set":2},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["archiveOffered"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"set":true},{"path":["archiveCheck"],"set":{"text":"所有 agent 都做完了","recommended":true,"failed":false}}]},{"path":["thread","read"],"set":2},{"path":["thread","unread"],"set":0}]},"w":1792532831134.705}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","ember:c-ed5ad64e6c"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792532831134.75}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","unread"],"set":0},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","label"],"remove":true},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","mineTone"],"remove":true},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","tone"],"remove":true}]},"w":1792532831134.766}
  #|{"step":"tap icon:arrow-up","acted":true,"w":1792532831135.32}
  #|{"out":{"id":23,"call":"draft.put","params":{"text":"","quotes":[],"files":[],"key":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7:ember:c-ed5ad64e6c"}},"w":1792532831151.434}
  #|{"out":{"id":24,"call":"chat.send","params":{"station":"01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","text":"给个表格 082947 md:表格和代码 082947","attachments":[],"quotes":[],"thread":1}},"w":1792532831151.453}
  #|{"step":"answered chat.send","w":1792532831152.114}
  #|{"in":{"id":23,"ok":{"id":"draft-a3f33f9e7486ea570d"}},"w":1792532831168.008}
  #|{"in":{"id":24,"ok":{"seq":3}},"w":1792532831184.662}
  #|{"step":"wait 600","w":1792532831201.664}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"session","lastActiveAt"],"set":1792532831181},{"path":["agents",0,"session","lastTurn","endedAt"],"set":1792532831181},{"path":["agents",0,"session","lastTurn","id"],"set":"a362731b-4ffa-474e-b355-7420ad29b7a4"},{"path":["agents",0,"session","lastTurn","startedAt"],"set":1792532831155},{"path":["agents",0,"session","runtimeSessionId"],"set":"b4f5501d-3081-4a3a-b8ab-88d388db8755"},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792532831181},{"path":["agents",0,"session","time","lastActiveAt","full"],"set":"10/21 05:47:11"},{"path":["agents",0,"session","turns"],"set":2},{"path":["agents",0,"threads",0,"last"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792532831179},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","text"],"set":"表格和代码 082947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // only the rows near the screen\n  return visible.length\n}\n```\n\n详见 https://example.com/e2e/082947"},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792532831179},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","full"],"set":"10/21 05:47:11"},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792532831.179000"},{"path":["agents",0,"threads",0,"unread"],"set":1},{"path":["agents",0,"turns"],"append":[{"id":"a362731b-4ffa-474e-b355-7420ad29b7a4","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792532831155,"endedAt":1792532831181}]},{"path":["link","state"],"set":"online"},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"remove":true},{"path":["archiveCheck"],"remove":true}]},{"path":["outbox"],"key":["id"],"put":{"id":"out-a7f7c8975fe9ffef3f","text":"给个表格 082947 md:表格和代码 082947","attachments":[],"quotes":[],"createdAt":1792532831152,"state":"sending","seq":3,"time":{"createdAt":{"at":1792532831152,"ago":"刚刚","full":"10/21 05:47:11","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","last"],"set":4},{"path":["thread","lastMessage","createdAt"],"set":1792532831179},{"path":["thread","lastMessage","seq"],"set":4},{"path":["thread","lastMessage","text"],"set":"表格和代码 082947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // only the rows near the screen\n  return visible.length\n}\n```\n\n详见 https://example.com/e2e/082947"},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792532831179},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/21 05:47:11"},{"path":["thread","lastMessage","ts"],"set":"1792532831.179000"},{"path":["thread","unread"],"set":1},{"path":["archivable"],"remove":true},{"path":["archiveOffered"],"remove":true}]},"w":1792532831218.027}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792532831179},{"path":["items"],"key":["station","id"],"patch":["01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","ember:c-ed5ad64e6c"],"ops":[{"path":["agents",0,"lastTurn","endedAt"],"set":1792532831181},{"path":["agents",0,"lastTurn","id"],"set":"a362731b-4ffa-474e-b355-7420ad29b7a4"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792532831155},{"path":["last","createdAt"],"set":1792532831179},{"path":["last","preview"],"set":"表格和代码 082947 页面 状态 耗时 :-- :-: --: 首页 完成 1.2 s 聊天页的列表和输入框 进行中 3.4 s export function placeRows(rows: Row[], from: number): number { const visible = rows.filter((r) =>"},{"path":["last","seq"],"set":4},{"path":["last","text"],"set":"表格和代码 082947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) =>"},{"path":["last","time","createdAt","at"],"set":1792532831179},{"path":["last","time","createdAt","full"],"set":"10/21 05:47:11"},{"path":["lastActiveAt"],"set":1792532831179},{"path":["time","lastActiveAt","at"],"set":1792532831179},{"path":["time","lastActiveAt","full"],"set":"10/21 05:47:11"},{"path":["tone"],"set":"done"},{"path":["unread"],"set":true},{"path":["archivable"],"remove":true},{"path":["clientKey"],"remove":true},{"path":["settled"],"remove":true},{"path":["stateText"],"remove":true}]}]}]},"w":1792532831218.129}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","label"],"set":"1 个有新消息"},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","mineTone"],"set":"done"},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","tone"],"set":"done"},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","unread"],"set":1}]},"w":1792532831218.166}
  #|{"in":{"id":17,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"overview","disk","freeBytes"],"set":58179960832},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792532831020},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792532831020},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 05:47:11"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792532828574},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792532828574},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792532828574},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792532828574},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792532828574},{"path":[0,"reconnecting"],"set":false}]},"w":1792532831218.179}
  #|{"in":{"id":17,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.37,"cpuBusy":0.22,"uptimeSec":12193,"memory":{"totalBytes":17179869184,"usedBytes":10146791424,"swapUsedBytes":333572997},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":58170900480},"emberRssBytes":139769368,"checkedAt":1792532831167,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 3 小时"],"meters":[{"label":"CPU","short":"CPU","percent":22,"left":78,"level":"ok","value":"22%","remaining":"空闲 78%","big":"78","unit":"%","title":"CPU 空闲","total":"负载 3.7","note":"负载 3.7 · Apple M4"},{"label":"内存","short":"内存","percent":59,"left":41,"level":"ok","value":"9.4 GB / 16.0 GB","remaining":"剩 6.6 G","big":"6.6","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":76,"left":24,"level":"amber","value":"剩余 54.2 GB / 228 GB","remaining":"剩 54.2 G","big":"54.2","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"3 小时"},{"label":"still.fail","value":"进程占用 133 MB"}],"usage":"内存 9.4 GB / 16.0 GB · 磁盘 剩余 54.2 GB / 228 GB","emberText":"still.fail 133 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792532831268.005}
  #|{"in":{"id":15,"delta":[{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":4,"thread":1,"ts":"1792532831.179000","authorKind":"agent","author":"ember:c-ed5ad64e6c","text":"表格和代码 082947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // only the rows near the screen\n  return visible.length\n}\n```\n\n详见 https://example.com/e2e/082947","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792532831179,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-ed5ad64e6c","runtime":"claude","here":true},"waiting":false,"said":true,"time":{"createdAt":{"at":1792532831179,"ago":"刚刚","full":"10/21 05:47:11","until":"1 分钟内","past":true}}},"before":null},{"path":["messages"],"key":["seq","outgoing"],"put":{"outgoing":"out-a7f7c8975fe9ffef3f","seq":3,"thread":1,"ts":"1792532831.154000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"给个表格 082947 md:表格和代码 082947","attachments":[],"quotes":[],"createdAt":1792532831154,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792532831154,"ago":"刚刚","full":"10/21 05:47:11","until":"1 分钟内","past":true}}},"before":[4,null]},{"path":["outbox"],"key":["id"],"drop":"out-a7f7c8975fe9ffef3f"}]},"w":1792532831284.676}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":4},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["archiveOffered"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[4,null],"ops":[{"path":["archive"],"set":true},{"path":["archiveCheck"],"set":{"text":"所有 agent 都做完了","recommended":true,"failed":false}}]},{"path":["thread","read"],"set":4},{"path":["thread","unread"],"set":0}]},"w":1792532831451.342}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DMG689F9J2DDVXT0E8PWF5/4b198cfa6109624ada73e32e7f9c8aa36f368ad28e2fee23d782ae3cb831f4e7","ember:c-ed5ad64e6c"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792532831451.407}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","unread"],"set":0},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","label"],"remove":true},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","mineTone"],"remove":true},{"path":["workspaces","01M5DMG689F9J2DDVXT0E8PWF5","tone"],"remove":true}]},"w":1792532831451.425}
  #|{"step":"now gone 正在发送","w":1792532831801.744}
  #|{"step":"until 聊天页的列表和输入框","w":1792532831801.756}
  #|{"step":"until placeRows","w":1792532831801.765}
  #|{"step":"","w":1792532831801.769}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,63]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11]}}
  #|{"textrec":{"s":[13,500,0,"以下是新消息"],"r":[0,1,12.898832684824903,64,1,1,12.898832684824903,65,2,1,12.898832684824903,66,3,1,12.898832684824903,67,4,1,12.898832684824896,68,5,1,12.898832684824896,69]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,70,1,1,14.883268482490273,71,2,1,14.883268482490273,72,3,1,14.883268482490273,73]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,74,1,1,9.941634241245136,74]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,75,1,1,14.883268482490273,76,2,1,15.087548638132297,77,3,1,14.883268482490273,78,4,1,14.883268482490266,79,5,1,14.88326848249028,80,6,1,14.88326848249028,81,7,1,14.88326848249028,82,8,1,14.88326848249028,83,9,1,3.984375,-1,10,1,8.0419921875,84,11,1,8.90625,85,12,1,8.3349609375,86,13,1,8.51806640625,87,14,1,5.21484375,88]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,89,1,1,15.875486381322958,90,2,1,15.875486381322958,89,3,1,15.875486381322958,91,4,1,15.875486381322958,92,5,1,15.875486381322958,93,6,1,15.875486381322958,94,7,1,15.875486381322958,95,8,1,4.1875,-1,9,1,9.453125,96,10,1,9.140625,97,11,1,8.0234375,98,12,1,5.4609375,99,13,1,4.4375,100,14,1,15.875486381322958,101,15,1,15.875486381322958,102,16,1,16.09338521400778,103,17,1,15.875486381322958,104,18,1,15.875486381322958,105,19,1,15.87548638132293,91,20,1,15.875486381322958,92,21,1,15.875486381322958,106,22,1,15.875486381322958,93,23,1,4.1875,-1,24,1,8.515625,107,25,1,9.4375,108,26,1,8.828125,109,27,1,9.0234375,110,28,1,5.5,99]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,14.076484680175781,62]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,111,1,1,4.330078125,112,2,1,7.001953125,113,3,1,7.37109375,114,4,1,2.96484375,115,5,1,7.08984375,116]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,14.076484680175781,62]}}
  #|{"textrec":{"g":75,"r":[666,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":76,"r":[683,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":77,"r":[700,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":78,"r":[706,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":79,"r":[724,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":80,"r":[741,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":81,"r":[758,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":82,"r":[776,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":83,"r":[792,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":84,"r":[808,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":85,"r":[819,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[830,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":87,"r":[841,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":88,"r":[851,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":89,"r":[859,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":90,"r":[877,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":91,"r":[895,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":92,"r":[913,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":93,"r":[932,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":94,"r":[949,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":95,"r":[967,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":96,"r":[986,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":97,"r":[997,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":98,"r":[1009,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":99,"r":[1020,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":100,"r":[1029,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":101,"r":[1035,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":102,"r":[1053,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":103,"r":[1071,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":104,"r":[1078,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1096,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1114,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":107,"r":[1131,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":108,"r":[1142,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":109,"r":[1154,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":110,"r":[1166,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[1177,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":71,"r":[1195,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[1213,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[1231,0,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,117,1,1,15.875486381322958,118,2,1,15.875486381322958,119]}}
  #|{"textrec":{"g":117,"r":[1248,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":118,"r":[1266,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":119,"r":[1284,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":74,"r":[1302,0,11,11,-1,-9,0]}}
  #|{"textrec":{"g":64,"r":[1314,0,14,15,0,-12,0]}}
  #|{"textrec":{"g":65,"r":[1329,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":66,"r":[1344,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":67,"r":[1359,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":68,"r":[1375,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":69,"r":[1390,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":63,"r":[1406,0,8,8,-1,-7,0]}}
  #|{"textrec":{"g":111,"r":[1415,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":112,"r":[1424,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":113,"r":[1431,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":114,"r":[1441,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":115,"r":[1451,0,5,11,-1,-10,0]}}
  #|{"textrec":{"g":116,"r":[1457,0,9,10,-1,-8,0]}}
  #|{"textrec":{"ib":["2b45ffca62dc37ab",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,400,0,"给个表格 082947 md:表格和代码 082947"],"r":[0,1,15.875486381322958,120,1,1,15.875486381322958,121,2,1,15.875486381322958,122,3,1,15.875486381322958,123,4,1,4.1875,-1,5,1,9.765625,124,6,1,9.90625,125,7,1,9.34375,126,8,1,9.875,127,9,1,9.984375,128,10,1,8.796875,129,11,1,4.1875,-1,12,1,13.609375,130,13,1,9.515625,131,14,1,4.4375,100,15,1,15.875486381322958,122,16,1,15.875486381322958,123,17,1,15.875486381322958,132,18,1,15.875486381322958,133,19,1,15.875486381322958,134,20,1,4.1875,-1,21,1,9.765625,124,22,1,9.90625,125,23,1,9.34375,126,24,1,9.875,127,25,1,9.984375,128,26,1,8.796875,129]}}
  #|{"textrec":{"g":120,"r":[1467,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":121,"r":[1486,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":122,"r":[1505,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":123,"r":[1523,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":124,"r":[1542,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":125,"r":[1554,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":126,"r":[1566,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":127,"r":[1577,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":128,"r":[1589,0,12,14,-1,-13,0]}}
  #|{"textrec":{"g":129,"r":[1602,0,11,14,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1614,0,14,11,0,-10,0]}}
  #|{"textrec":{"g":131,"r":[1629,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":132,"r":[1641,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":133,"r":[1659,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":134,"r":[1677,0,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["9699dbc96b0fdfd9",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.497894287109375,35,12,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.329673767089844,34,11,1,13.973621368408203,135]}}
  #|{"textrec":{"g":135,"r":[1695,0,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"s":[10,400,0,"正在发送"],"r":[0,1,9.941634241245136,136,1,1,9.941634241245136,137,2,1,9.941634241245136,138,3,1,9.941634241245136,139]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.721336364746094,33,10,1,13.973621368408203,135]}}
  #|{"textrec":{"g":136,"r":[1710,0,12,11,-1,-9,0]}}
  #|{"textrec":{"g":137,"r":[1723,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":138,"r":[1736,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":139,"r":[1749,0,12,13,-1,-10,0]}}
  #|{"textrec":{"ib":["d199cb74c5a62786",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["9e48044fa6815e02",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[12,500,0,"页面"],"r":[0,1,11.918287937743191,140,1,1,11.918287937743191,141]}}
  #|{"textrec":{"s":[12,500,0,"页"],"r":[0,1,11.918287937743191,140]}}
  #|{"textrec":{"s":[12,500,0,"面"],"r":[0,1,11.918287937743191,141]}}
  #|{"textrec":{"s":[12,500,0,"状态"],"r":[0,1,11.918287937743191,142,1,1,11.918287937743191,143]}}
  #|{"textrec":{"s":[12,500,0,"状"],"r":[0,1,11.918287937743191,142]}}
  #|{"textrec":{"s":[12,500,0,"态"],"r":[0,1,11.918287937743191,143]}}
  #|{"textrec":{"s":[12,500,0,"耗时"],"r":[0,1,11.918287937743191,144,1,1,11.918287937743191,145]}}
  #|{"textrec":{"s":[12,500,0,"耗"],"r":[0,1,11.918287937743191,144]}}
  #|{"textrec":{"s":[12,500,0,"时"],"r":[0,1,11.918287937743191,145]}}
  #|{"textrec":{"s":[13,400,0,"首页"],"r":[0,1,12.898832684824903,146,1,1,12.898832684824903,147]}}
  #|{"textrec":{"s":[13,400,0,"首"],"r":[0,1,12.898832684824903,146]}}
  #|{"textrec":{"s":[13,400,0,"页"],"r":[0,1,12.898832684824903,147]}}
  #|{"textrec":{"s":[13,400,0,"完成"],"r":[0,1,12.898832684824903,148,1,1,12.898832684824903,149]}}
  #|{"textrec":{"s":[13,400,0,"完"],"r":[0,1,12.898832684824903,148]}}
  #|{"textrec":{"s":[13,400,0,"成"],"r":[0,1,12.898832684824903,149]}}
  #|{"textrec":{"s":[13,400,0,"1.2 s"],"r":[0,1,5.79541015625,150,1,1,3.49755859375,151,2,1,7.642578125,152,3,1,3.580078125,-1,4,1,6.728515625,10]}}
  #|{"textrec":{"s":[13,400,0,"1.2"],"r":[0,1,5.79541015625,150,1,1,3.49755859375,151,2,1,7.642578125,152]}}
  #|{"textrec":{"s":[13,400,0,"s"],"r":[0,1,6.728515625,10]}}
  #|{"textrec":{"s":[13,400,0,"聊天页的列表和输入框"],"r":[0,1,12.898832684824903,153,1,1,12.898832684824903,154,2,1,12.898832684824903,147,3,1,12.898832684824903,5,4,1,12.898832684824896,155,5,1,12.898832684824896,156,6,1,12.898832684824896,157,7,1,12.898832684824896,158,8,1,12.898832684824896,159,9,1,12.898832684824896,160]}}
  #|{"textrec":{"s":[13,400,0,"聊"],"r":[0,1,12.898832684824903,153]}}
  #|{"textrec":{"s":[13,400,0,"天"],"r":[0,1,12.898832684824903,154]}}
  #|{"textrec":{"s":[13,400,0,"的"],"r":[0,1,12.898832684824903,5]}}
  #|{"textrec":{"s":[13,400,0,"列"],"r":[0,1,12.898832684824903,155]}}
  #|{"textrec":{"s":[13,400,0,"表"],"r":[0,1,12.898832684824903,156]}}
  #|{"textrec":{"s":[13,400,0,"和"],"r":[0,1,12.898832684824903,157]}}
  #|{"textrec":{"s":[13,400,0,"输"],"r":[0,1,12.898832684824903,158]}}
  #|{"textrec":{"s":[13,400,0,"入"],"r":[0,1,12.898832684824903,159]}}
  #|{"textrec":{"s":[13,400,0,"框"],"r":[0,1,12.898832684824903,160]}}
  #|{"textrec":{"s":[13,400,0,"进行中"],"r":[0,1,12.898832684824903,161,1,1,12.898832684824903,162,2,1,12.898832684824903,163]}}
  #|{"textrec":{"s":[13,400,0,"进"],"r":[0,1,12.898832684824903,161]}}
  #|{"textrec":{"s":[13,400,0,"行"],"r":[0,1,12.898832684824903,162]}}
  #|{"textrec":{"s":[13,400,0,"中"],"r":[0,1,12.898832684824903,163]}}
  #|{"textrec":{"s":[13,400,0,"3.4 s"],"r":[0,1,7.85205078125,164,1,1,3.37060546875,151,2,1,8.099609375,165,3,1,3.580078125,-1,4,1,6.728515625,10]}}
  #|{"textrec":{"s":[13,400,0,"3.4"],"r":[0,1,7.85205078125,164,1,1,3.37060546875,151,2,1,8.099609375,165]}}
  #|{"textrec":{"s":[15,400,0,"表格和代码 082947"],"r":[0,1,14.883268482490273,166,1,1,14.883268482490273,167,2,1,14.883268482490273,168,3,1,14.883268482490273,169,4,1,14.88326848249028,170,5,1,3.984375,-1,6,1,9.2138671875,171,7,1,9.345703125,172,8,1,8.818359375,173,9,1,9.31640625,174,10,1,9.4189453125,175,11,1,8.3056640625,176]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[12,400,2,"export"],"r":[0,1,7.41796875,177,1,1,7.41796875,178,2,1,7.41796875,179,3,1,7.41796875,180,4,1,7.41796875,181,5,1,7.41796875,182]}}
  #|{"textrec":{"m":[12,400,2],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[12,400,2," "],"r":[0,1,7.41796875,-1]}}
  #|{"textrec":{"s":[12,400,2,"function"],"r":[0,1,7.41796875,183,1,1,7.41796875,184,2,1,7.41796875,185,3,1,7.41796875,186,4,1,7.41796875,182,5,1,7.41796875,187,6,1,7.41796875,180,7,1,7.41796875,185]}}
  #|{"textrec":{"s":[12,400,2,"placeRows"],"r":[0,1,7.41796875,179,1,1,7.41796875,188,2,1,7.41796875,189,3,1,7.41796875,186,4,1,7.41796875,177,5,1,7.41796875,190,6,1,7.41796875,180,7,1,7.41796875,191,8,1,7.41796875,192]}}
  #|{"textrec":{"s":[12,400,2,"("],"r":[0,1,7.41796875,193]}}
  #|{"textrec":{"s":[12,400,2,"rows"],"r":[0,1,7.41796875,181,1,1,7.41796875,180,2,1,7.41796875,191,3,1,7.41796875,192]}}
  #|{"textrec":{"s":[12,400,2,":"],"r":[0,1,7.41796875,194]}}
  #|{"textrec":{"s":[12,400,2,"Row"],"r":[0,1,7.41796875,190,1,1,7.41796875,180,2,1,7.41796875,191]}}
  #|{"textrec":{"s":[12,400,2,"[],"],"r":[0,1,7.41796875,195,1,1,7.41796875,196,2,1,7.41796875,197]}}
  #|{"textrec":{"s":[12,400,2,"from"],"r":[0,1,7.41796875,183,1,1,7.41796875,181,2,1,7.41796875,180,3,1,7.41796875,198]}}
  #|{"textrec":{"s":[12,400,2,"number"],"r":[0,1,7.41796875,185,1,1,7.41796875,184,2,1,7.41796875,198,3,1,7.41796875,199,4,1,7.41796875,177,5,1,7.41796875,181]}}
  #|{"textrec":{"s":[12,400,2,"):"],"r":[0,1,7.41796875,200,1,1,7.41796875,194]}}
  #|{"textrec":{"s":[12,400,2,"{"],"r":[0,1,7.41796875,201]}}
  #|{"textrec":{"s":[12,400,2,"\n  "],"r":[0,1,0,-1,1,1,7.41796875,-1,2,1,7.41796875,-1]}}
  #|{"textrec":{"s":[12,400,2,"const"],"r":[0,1,7.41796875,186,1,1,7.41796875,180,2,1,7.41796875,185,3,1,7.41796875,192,4,1,7.41796875,182]}}
  #|{"textrec":{"s":[12,400,2,"visible"],"r":[0,1,7.41796875,202,1,1,7.41796875,187,2,1,7.41796875,192,3,1,7.41796875,187,4,1,7.41796875,199,5,1,7.41796875,188,6,1,7.41796875,177]}}
  #|{"textrec":{"s":[12,400,2,"="],"r":[0,1,7.41796875,203]}}
  #|{"textrec":{"s":[12,400,2,"."],"r":[0,1,7.41796875,204]}}
  #|{"textrec":{"s":[12,400,2,"filter"],"r":[0,1,7.41796875,183,1,1,7.41796875,187,2,1,7.41796875,188,3,1,7.41796875,182,4,1,7.41796875,177,5,1,7.41796875,181]}}
  #|{"textrec":{"s":[12,400,2,"(("],"r":[0,1,7.41796875,193,1,1,7.41796875,193]}}
  #|{"textrec":{"s":[12,400,2,"r"],"r":[0,1,7.41796875,181]}}
  #|{"textrec":{"s":[12,400,2,")"],"r":[0,1,7.41796875,200]}}
  #|{"textrec":{"s":[12,400,2,"=>"],"r":[0,1,7.41796875,203,1,1,7.41796875,205]}}
  #|{"textrec":{"s":[12,400,2,"top"],"r":[0,1,7.41796875,182,1,1,7.41796875,180,2,1,7.41796875,179]}}
  #|{"textrec":{"s":[12,400,2,">="],"r":[0,1,7.41796875,205,1,1,7.41796875,203]}}
  #|{"textrec":{"s":[12,400,2,"&&"],"r":[0,1,7.41796875,206,1,1,7.41796875,206]}}
  #|{"textrec":{"s":[12,400,2,"<"],"r":[0,1,7.41796875,207]}}
  #|{"textrec":{"s":[12,400,2,"+"],"r":[0,1,7.41796875,208]}}
  #|{"textrec":{"s":[12,400,2,"window"],"r":[0,1,7.41796875,191,1,1,7.41796875,187,2,1,7.41796875,185,3,1,7.41796875,209,4,1,7.41796875,180,5,1,7.41796875,191]}}
  #|{"textrec":{"s":[12,400,2,"innerHeight"],"r":[0,1,7.41796875,187,1,1,7.41796875,185,2,1,7.41796875,185,3,1,7.41796875,177,4,1,7.41796875,181,5,1,7.41796875,210,6,1,7.41796875,177,7,1,7.41796875,187,8,1,7.41796875,211,9,1,7.41796875,212,10,1,7.41796875,182]}}
  #|{"textrec":{"s":[12,400,2,"*"],"r":[0,1,7.41796875,213]}}
  #|{"textrec":{"s":[12,400,2,"2"],"r":[0,1,7.41796875,214]}}
  #|{"textrec":{"s":[12,400,2,"// only the rows near the screen"],"r":[0,1,7.41796875,215,1,1,7.41796875,215,2,1,7.41796875,-1,3,1,7.41796875,180,4,1,7.41796875,185,5,1,7.41796875,188,6,1,7.41796875,216,7,1,7.41796875,-1,8,1,7.41796875,182,9,1,7.41796875,212,10,1,7.41796875,177,11,1,7.41796875,-1,12,1,7.41796875,181,13,1,7.41796875,180,14,1,7.41796875,191,15,1,7.41796875,192,16,1,7.41796875,-1,17,1,7.41796875,185,18,1,7.41796875,177,19,1,7.41796875,189,20,1,7.41796875,181,21,1,7.41796875,-1,22,1,7.41796875,182,23,1,7.41796875,212,24,1,7.41796875,177,25,1,7.41796875,-1,26,1,7.41796875,192,27,1,7.41796875,186,28,1,7.41796875,181,29,1,7.41796875,177,30,1,7.41796875,177,31,1,7.41796875,185]}}
  #|{"textrec":{"s":[12,400,2,"return"],"r":[0,1,7.41796875,181,1,1,7.41796875,177,2,1,7.41796875,182,3,1,7.41796875,184,4,1,7.41796875,181,5,1,7.41796875,185]}}
  #|{"textrec":{"s":[12,400,2,"length"],"r":[0,1,7.41796875,188,1,1,7.41796875,177,2,1,7.41796875,185,3,1,7.41796875,211,4,1,7.41796875,182,5,1,7.41796875,212]}}
  #|{"textrec":{"s":[12,400,2,"\n"],"r":[0,1,0,-1]}}
  #|{"textrec":{"s":[12,400,2,"}"],"r":[0,1,7.41796875,217]}}
  #|{"textrec":{"s":[15,400,0,"详见 "],"r":[0,1,14.883268482490273,218,1,1,14.883268482490273,219,2,1,3.984375,-1]}}
  #|{"textrec":{"s":[15,400,0,"https://example.com/e2e/082947"],"r":[0,1,8.59130859375,220,1,1,5.21484375,88,2,1,5.21484375,88,3,1,8.9208984375,221,4,1,7.6171875,222,5,1,4.21875,223,6,1,4.3359375,224,7,1,4.3359375,224,8,1,8.1884765625,86,9,1,7.4853515625,225,10,1,8.0419921875,84,11,1,12.8173828125,226,12,1,8.9208984375,221,13,1,3.5595703125,227,14,1,8.3349609375,86,15,1,4.072265625,228,16,1,8.0126953125,229,17,1,8.6279296875,230,18,1,12.8173828125,226,19,1,4.3359375,224,20,1,8.3349609375,86,21,1,8.78173828125,173,22,1,8.29833984375,86,23,1,4.3359375,224,24,1,9.2138671875,171,25,1,9.345703125,172,26,1,8.818359375,173,27,1,9.31640625,174,28,1,9.4189453125,175,29,1,8.3056640625,176]}}
  #|{"textrec":{"s":[10,400,0,"ts"],"r":[0,1,3.701171875,231,1,1,5.302734375,232]}}
  #|{"textrec":{"s":[11,400,0,"复制"],"r":[0,1,10.93579766536965,233,1,1,10.93579766536965,234]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"g":166,"r":[1762,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":167,"r":[1779,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":168,"r":[1797,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":169,"r":[1814,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":170,"r":[1831,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":171,"r":[1848,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":172,"r":[1860,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":173,"r":[1872,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":174,"r":[1883,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":175,"r":[1895,0,11,13,-1,-12,0]}}
  #|{"textrec":{"g":176,"r":[1907,0,10,13,-1,-12,0]}}
  #|{"textrec":{"g":140,"r":[1918,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":141,"r":[1933,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":142,"r":[1948,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":143,"r":[1963,0,14,13,-1,-11,0]}}
  #|{"textrec":{"g":144,"r":[1978,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":145,"r":[1993,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":146,"r":[2008,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":147,"r":[2023,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":148,"r":[0,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[16,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[32,20,7,12,-1,-11,0]}}
  #|{"textrec":{"g":151,"r":[40,20,4,5,0,-3,0]}}
  #|{"textrec":{"g":152,"r":[45,20,9,12,-1,-11,0]}}
  #|{"textrec":{"g":10,"r":[55,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":153,"r":[65,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[80,20,15,14,-1,-11,0]}}
  #|{"textrec":{"g":5,"r":[96,20,13,15,0,-12,0]}}
  #|{"textrec":{"g":155,"r":[110,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":156,"r":[125,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":157,"r":[140,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":158,"r":[155,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":159,"r":[171,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":160,"r":[187,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":161,"r":[203,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":162,"r":[219,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":163,"r":[235,20,13,15,0,-12,0]}}
  #|{"textrec":{"g":164,"r":[249,20,10,13,-1,-11,0]}}
  #|{"textrec":{"g":165,"r":[260,20,10,12,-1,-11,0]}}
  #|{"textrec":{"g":231,"r":[271,20,6,10,-1,-8,0]}}
  #|{"textrec":{"g":232,"r":[278,20,7,9,-1,-7,0]}}
  #|{"textrec":{"g":233,"r":[286,20,13,13,-1,-10,0]}}
  #|{"textrec":{"g":234,"r":[300,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":177,"r":[313,20,8,10,0,-8,0]}}
  #|{"textrec":{"g":178,"r":[322,20,9,9,-1,-8,0]}}
  #|{"textrec":{"g":179,"r":[332,20,8,12,0,-8,0]}}
  #|{"textrec":{"g":180,"r":[341,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":181,"r":[351,20,8,9,0,-8,0]}}
  #|{"textrec":{"g":182,"r":[360,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":183,"r":[370,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":184,"r":[379,20,8,10,0,-8,0]}}
  #|{"textrec":{"g":185,"r":[388,20,8,9,0,-8,0]}}
  #|{"textrec":{"g":186,"r":[397,20,8,10,0,-8,0]}}
  #|{"textrec":{"g":187,"r":[406,20,8,12,0,-11,0]}}
  #|{"textrec":{"g":188,"r":[415,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":189,"r":[424,20,8,10,0,-8,0]}}
  #|{"textrec":{"g":190,"r":[433,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":191,"r":[442,20,10,9,-1,-8,0]}}
  #|{"textrec":{"g":192,"r":[453,20,8,10,0,-8,0]}}
  #|{"textrec":{"g":193,"r":[462,20,6,13,1,-11,0]}}
  #|{"textrec":{"g":194,"r":[469,20,5,10,1,-8,0]}}
  #|{"textrec":{"g":195,"r":[475,20,6,13,1,-11,0]}}
  #|{"textrec":{"g":196,"r":[482,20,6,13,1,-11,0]}}
  #|{"textrec":{"g":197,"r":[489,20,5,6,1,-3,0]}}
  #|{"textrec":{"g":198,"r":[495,20,9,9,-1,-8,0]}}
  #|{"textrec":{"g":199,"r":[505,20,8,12,0,-10,0]}}
  #|{"textrec":{"g":200,"r":[514,20,5,13,1,-11,0]}}
  #|{"textrec":{"g":201,"r":[520,20,7,13,0,-11,0]}}
  #|{"textrec":{"g":202,"r":[528,20,9,9,-1,-8,0]}}
  #|{"textrec":{"g":203,"r":[538,20,9,7,-1,-7,0]}}
  #|{"textrec":{"g":204,"r":[548,20,5,6,1,-4,0]}}
  #|{"textrec":{"g":205,"r":[554,20,8,10,0,-9,0]}}
  #|{"textrec":{"g":206,"r":[563,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":207,"r":[574,20,8,10,0,-9,0]}}
  #|{"textrec":{"g":208,"r":[583,20,9,9,-1,-8,0]}}
  #|{"textrec":{"g":209,"r":[593,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":210,"r":[603,20,9,11,-1,-10,0]}}
  #|{"textrec":{"g":211,"r":[613,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":212,"r":[623,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":213,"r":[632,20,9,10,-1,-9,0]}}
  #|{"textrec":{"g":214,"r":[642,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":215,"r":[651,20,8,13,0,-11,0]}}
  #|{"textrec":{"g":216,"r":[660,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":217,"r":[670,20,7,13,0,-11,0]}}
  #|{"textrec":{"g":218,"r":[678,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":219,"r":[695,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":220,"r":[712,20,9,14,0,-13,0]}}
  #|{"textrec":{"g":221,"r":[722,20,10,14,0,-10,0]}}
  #|{"textrec":{"g":222,"r":[733,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":223,"r":[744,20,5,11,0,-9,0]}}
  #|{"textrec":{"g":224,"r":[750,20,7,17,-1,-13,0]}}
  #|{"textrec":{"g":225,"r":[758,20,10,10,-1,-9,0]}}
  #|{"textrec":{"g":226,"r":[769,20,13,11,0,-10,0]}}
  #|{"textrec":{"g":227,"r":[783,20,4,14,0,-13,0]}}
  #|{"textrec":{"g":228,"r":[788,20,5,5,0,-3,0]}}
  #|{"textrec":{"g":229,"r":[794,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":230,"r":[805,20,11,12,-1,-10,0]}}
  #|{"textrec":{"ib":["252b41f603f509d8",656,64],"r":[12,12,12,12]}}
