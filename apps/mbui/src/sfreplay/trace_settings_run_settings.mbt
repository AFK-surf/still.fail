// e2e/traces/settings-run-settings.trace, made by scripts/trace.py from 10-settings_run_settings.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_run_settings : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 032949"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792524897}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792524910403.777}
  #|{"in":{"id":1,"ok":null},"w":1792524910541.32}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792524910541.344}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792524910541.354}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792524910543.983}
  #|{"step":"timeout 90000","w":1792524910543.999}
  #|{"step":"answered client.device","w":1792524910544.004}
  #|{"step":"answered client.focus","w":1792524910561.827}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792524910617.304}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792524910617.329}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792524910617.358}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792524910617.37}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DCN9EHV11TX62FVBT8G02C","name":"Dev","role":"owner","created_at":1792524592,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792524592000,"ago":"5 分钟前","full":"10/21 03:29:52","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":false,"beta":true}]},"w":1792524910627.834}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524910627.858}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524910627.893}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DCN9EHV11TX62FVBT8G02C","mine":false},"keyed":true},"w":1792524910627.905}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524910628.025}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524910628.056}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DCN9EHV11TX62FVBT8G02C"}},"w":1792524910633.559}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792524910633.571}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524910633.578}
  #|{"in":{"id":4,"delta":[{"path":[0,"loaded"],"set":true}]},"w":1792524910644.49}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"7508068c0838052834dcdd24dd864d54a9300b8708e8b2f2324424a37bc525fe","code":"2CS-XCW","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792524910644.507}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792524597114,"label":"今天","items":[{"id":"ember:c-680584e540","session":"ember:c-680584e540","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-680584e540","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"bcf24f08-9b85-4698-bf0d-c70c9355816b","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524597028,"endedAt":1792524597117},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-680584e540","text":"你好，我是测试用的 agent","createdAt":1792524597114,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792524597114,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792524597114,"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","stationName":"studio","time":{"lastActiveAt":{"at":1792524597114,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-a35a0a154db00eb361","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792524910644.535}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DCN9EHV11TX62FVBT8G02C":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792524910644.56}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524910644.565}
  #|{"in":{"id":10,"ok":null},"w":1792524910644.567}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524910644.573}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524910644.577}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524910644.612}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792524910647.446}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792524910663.058}
  #|{"in":{"id":14,"ok":null},"w":1792524910663.068}
  #|{"step":"answered notify.permission","w":1792524910663.433}
  #|{"step":"tap 端到端测试","w":1792524910678.082}
  #|{"step":"tap 端到端测试","acted":true,"w":1792524910694.774}
  #|{"out":{"id":15,"subscribe":{"topic":"chat","station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","session":"ember:c-680584e540"},"keyed":true},"w":1792524910711.501}
  #|{"out":{"id":16,"call":"draft.get","params":{"key":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244:ember:c-680584e540"}},"w":1792524910713.262}
  #|{"step":"answered draft.get","w":1792524910713.453}
  #|{"in":{"id":15,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792524596.969000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792524596969,"sessions":[{"thread":1,"session":"ember:c-680584e540","connect":"ember","joinedAt":1792524596969}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792524597.114000","authorKind":"agent","author":"ember:c-680584e540","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524597114,"time":{"createdAt":{"at":1792524597114,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792524596969,"ago":"5 分钟前","full":"10/21 03:29:56","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-680584e540","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"8dd838d1-54bd-4001-af50-0774b84550a3","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-680584e540/workspace","running":false,"createdAt":1792524596969,"lastActiveAt":1792524597116,"process":"warm","turns":1,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"bcf24f08-9b85-4698-bf0d-c70c9355816b","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524597028,"endedAt":1792524597117},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792524596969,"ago":"5 分钟前","full":"10/21 03:29:56","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792524597116,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524596815,"time":{"checkedAt":{"at":1792524596815,"ago":"5 分钟前","full":"10/21 03:29:56","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524597005,"time":{"checkedAt":{"at":1792524597005,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524597005,"time":{"checkedAt":{"at":1792524597005,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524597005,"time":{"checkedAt":{"at":1792524597005,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524597005,"time":{"checkedAt":{"at":1792524597005,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"bcf24f08-9b85-4698-bf0d-c70c9355816b","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792524597028,"endedAt":1792524597117}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792524596.969000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792524596969,"sessions":[{"thread":1,"session":"ember:c-680584e540","connect":"ember","joinedAt":1792524596969}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792524597.114000","authorKind":"agent","author":"ember:c-680584e540","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524597114,"time":{"createdAt":{"at":1792524597114,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792524596969,"ago":"5 分钟前","full":"10/21 03:29:56","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792524597.011000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792524597012,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792524597012,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792524597.114000","authorKind":"agent","author":"ember:c-680584e540","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524597114,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-680584e540","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792524597114,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":2,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"connecting"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792524910727.883}
  #|{"in":{"id":16,"ok":{"text":"","quotes":[],"files":[],"id":"draft-61fe9117fbd4bd1507"}},"w":1792524910727.941}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524910728.244}
  #|{"out":{"id":18,"subscribe":{"topic":"chatJobs","station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","session":"ember:c-680584e540"},"keyed":true},"w":1792524910728.258}
  #|{"out":{"id":19,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792524910728.272}
  #|{"out":{"id":20,"call":"client.focus","params":{"chat":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","session":"ember:c-680584e540","thread":1,"end":true}}},"w":1792524910731.068}
  #|{"in":{"id":17,"value":[{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792524598,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524597005,"time":{"checkedAt":{"at":1792524597005,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DCN9EHV11TX62FVBT8G02C","device":"7508068c0838052834dcdd24dd864d54a9300b8708e8b2f2324424a37bc525fe"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524596815,"time":{"checkedAt":{"at":1792524596815,"ago":"5 分钟前","full":"10/21 03:29:56","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524597005,"time":{"checkedAt":{"at":1792524597005,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","workspace":"Dev","workspaceId":"01M5DCN9EHV11TX62FVBT8G02C","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":67701837824,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792524594499},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792524594499},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524594499},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524594499},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524594499}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792524598000,"ago":"5 分钟前","full":"10/21 03:29:58","until":"1 分钟内","past":true}},"joined":false}]},"w":1792524910744.572}
  #|{"in":{"id":18,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792524910744.647}
  #|{"in":{"id":20,"ok":null},"w":1792524910744.653}
  #|{"step":"answered picture","w":1792524910745.45}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5DCN9EHV11TX62FVBT8G02C"],"set":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","key":"ember:c-680584e540"}}]},"w":1792524910894.501}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DCN9EHV11TX62FVBT8G02C","chat"],"set":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","key":"ember:c-680584e540"}}]},"w":1792524910894.548}
  #|{"in":{"id":19,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792524910927.855}
  #|{"step":"answered client.focus","w":1792524910945.52}
  #|{"step":"rest","w":1792524910962.804}
  #|{"step":"now until =studio","w":1792524911478.934}
  #|{"step":"tap icon:more","w":1792524911478.97}
  #|{"step":"tap icon:more","acted":true,"w":1792524911495.629}
  #|{"step":"rest","w":1792524911532.015}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio ×2 · 2 秒 · 共 4 项","items":[{"state":"slow","text":"正在连接 studio ×2","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524912811.192}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio ×2 · 2 秒 · 共 4 项","items":[{"state":"slow","text":"正在连接 studio ×2","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524912811.251}
  #|{"step":"now tap icon:chevron-right","w":1792524912962.484}
  #|{"step":"now tap icon:chevron-right","acted":true,"w":1792524912979.265}
  #|{"step":"tap =历史","w":1792524912995.826}
  #|{"out":{"id":21,"subscribe":{"topic":"agentCard","station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","key":"ember:c-680584e540"},"keyed":true},"w":1792524913012.232}
  #|{"in":{"id":5,"delta":[{"path":["items"],"set":[{"state":"slow","text":"正在连接 studio ×2","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"},{"state":"slow","text":"studio 提交修改","detail":"已等待 2 秒，尚未收到数据"}]}]},"w":1792524913027.854}
  #|{"in":{"id":9,"delta":[{"path":["items"],"set":[{"state":"slow","text":"正在连接 studio ×2","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"},{"state":"slow","text":"studio 提交修改","detail":"已等待 2 秒，尚未收到数据"}]}]},"w":1792524913027.903}
  #|{"in":{"id":21,"value":{"work":"1 轮","latest":[],"attention":[]}},"w":1792524913027.925}
  #|{"step":"tap =历史","acted":true,"w":1792524913412.313}
  #|{"out":{"id":22,"subscribe":{"topic":"history","station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","key":"ember:c-680584e540"},"keyed":true},"w":1792524913430.171}
  #|{"step":"rest","w":1792524913433.629}
  #|{"in":{"id":22,"value":{"items":[],"live":[],"edge":"station 离线，此设备上暂无该会话的执行历史","empty":true,"loaded":true,"more":false}},"w":1792524913444.502}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 · 2 秒 · 48 B/s","items":[{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524913594.499}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 · 2 秒 · 48 B/s","items":[{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524913594.52}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":2},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["archiveOffered"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"set":true},{"path":["archiveCheck"],"set":{"text":"所有 agent 都做完了","recommended":true,"failed":false}}]},{"path":["thread","read"],"set":2},{"path":["thread","unread"],"set":0}]},"w":1792524913594.53}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","ember:c-680584e540"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792524913594.56}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DCN9EHV11TX62FVBT8G02C","unread"],"set":0},{"path":["workspaces","01M5DCN9EHV11TX62FVBT8G02C","label"],"remove":true},{"path":["workspaces","01M5DCN9EHV11TX62FVBT8G02C","mineTone"],"remove":true},{"path":["workspaces","01M5DCN9EHV11TX62FVBT8G02C","tone"],"remove":true}]},"w":1792524913594.575}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"account","quota","checkedAt"],"set":1792524913584},{"path":["agents",0,"account","quota","time","checkedAt","ago"],"set":"刚刚"},{"path":["agents",0,"account","quota","time","checkedAt","at"],"set":1792524913584},{"path":["agents",0,"account","quota","time","checkedAt","full"],"set":"10/21 03:35:13"},{"path":["agents",0,"choices",0,"accounts","claude",0,"quota","checkedAt"],"set":1792524913584},{"path":["agents",0,"choices",0,"accounts","claude",0,"quota","time","checkedAt","ago"],"set":"刚刚"},{"path":["agents",0,"choices",0,"accounts","claude",0,"quota","time","checkedAt","at"],"set":1792524913584},{"path":["agents",0,"choices",0,"accounts","claude",0,"quota","time","checkedAt","full"],"set":"10/21 03:35:13"},{"path":["agents",0,"profile","check","checkedAt"],"set":1792524913442},{"path":["agents",0,"profile","check","time","checkedAt","ago"],"set":"刚刚"},{"path":["agents",0,"profile","check","time","checkedAt","at"],"set":1792524913442},{"path":["agents",0,"profile","check","time","checkedAt","full"],"set":"10/21 03:35:13"},{"path":["agents",0,"profile","quota","checkedAt"],"set":1792524913584},{"path":["agents",0,"profile","quota","time","checkedAt","ago"],"set":"刚刚"},{"path":["agents",0,"profile","quota","time","checkedAt","at"],"set":1792524913584},{"path":["agents",0,"profile","quota","time","checkedAt","full"],"set":"10/21 03:35:13"},{"path":["agents",0,"profiles",0,"quota","checkedAt"],"set":1792524913584},{"path":["agents",0,"profiles",0,"quota","time","checkedAt","ago"],"set":"刚刚"},{"path":["agents",0,"profiles",0,"quota","time","checkedAt","at"],"set":1792524913584},{"path":["agents",0,"profiles",0,"quota","time","checkedAt","full"],"set":"10/21 03:35:13"}]},"w":1792524913644.514}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524913644.578}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524913644.583}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","ember:c-680584e540"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792524913644.589}
  #|{"in":{"id":17,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"models",0,"accounts","claude",0,"quota","checkedAt"],"set":1792524913584},{"path":[0,"models",0,"accounts","claude",0,"quota","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"models",0,"accounts","claude",0,"quota","time","checkedAt","at"],"set":1792524913584},{"path":[0,"models",0,"accounts","claude",0,"quota","time","checkedAt","full"],"set":"10/21 03:35:13"},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":66004291584},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792524913442},{"path":[0,"overview","profiles",0,"check","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792524913442},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 03:35:13"},{"path":[0,"overview","profiles",0,"quota","checkedAt"],"set":1792524913584},{"path":[0,"overview","profiles",0,"quota","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"overview","profiles",0,"quota","time","checkedAt","at"],"set":1792524913584},{"path":[0,"overview","profiles",0,"quota","time","checkedAt","full"],"set":"10/21 03:35:13"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792524911135},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792524911135},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792524911135},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792524911135},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792524911135},{"path":[0,"overview","updates",4,"latest"],"set":"1.0.62"},{"path":[0,"reconnecting"],"set":false}]},"w":1792524913644.609}
  #|{"in":{"id":22,"delta":[{"path":["edge"],"set":"找不到运行时记录，可能已归档"}]},"w":1792524913644.658}
  #|{"in":{"id":15,"delta":[{"path":["link","state"],"set":"online"}]},"w":1792524913794.495}
  #|{"in":{"id":17,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.06,"cpuBusy":0.23,"uptimeSec":4275,"memory":{"totalBytes":17179869184,"usedBytes":8440266752,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":66003165184},"emberRssBytes":140588568,"checkedAt":1792524913624,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":23,"left":77,"level":"ok","value":"23%","remaining":"空闲 77%","big":"77","unit":"%","title":"CPU 空闲","total":"负载 10.6","note":"负载 10.6 · Apple M4"},{"label":"内存","short":"内存","percent":49,"left":51,"level":"ok","value":"7.9 GB / 16.0 GB","remaining":"剩 8.1 G","big":"8.1","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":73,"left":27,"level":"ok","value":"剩余 61.5 GB / 228 GB","remaining":"剩 61.5 G","big":"61.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 134 MB"}],"usage":"内存 7.9 GB / 16.0 GB · 磁盘 剩余 61.5 GB / 228 GB","emberText":"still.fail 134 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792524913794.526}
  #|{"step":"now tap =详情","w":1792524914844.687}
  #|{"step":"now tap =详情","acted":true,"w":1792524914861.353}
  #|{"out":{"id":23,"subscribe":{"topic":"host","station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244"},"keyed":true},"w":1792524914877.871}
  #|{"step":"tap icon:chevron-down","w":1792524914880.474}
  #|{"in":{"id":23,"value":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.06,"cpuBusy":0.23,"uptimeSec":4275,"memory":{"totalBytes":17179869184,"usedBytes":8440266752,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":66003165184},"emberRssBytes":140588568,"checkedAt":1792524913624,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":23,"left":77,"level":"ok","value":"23%","remaining":"空闲 77%","big":"77","unit":"%","title":"CPU 空闲","total":"负载 10.6","note":"负载 10.6 · Apple M4"},{"label":"内存","short":"内存","percent":49,"left":51,"level":"ok","value":"7.9 GB / 16.0 GB","remaining":"剩 8.1 G","big":"8.1","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":73,"left":27,"level":"ok","value":"剩余 61.5 GB / 228 GB","remaining":"剩 61.5 G","big":"61.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 134 MB"}],"usage":"内存 7.9 GB / 16.0 GB · 磁盘 剩余 61.5 GB / 228 GB","emberText":"still.fail 134 MB"}},"w":1792524914894.49}
  #|{"step":"tap icon:chevron-down","acted":true,"w":1792524914895.591}
  #|{"out":{"id":24,"subscribe":{"topic":"pick","station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","of":"session:ember:c-680584e540"},"keyed":true},"w":1792524914911.299}
  #|{"out":{"id":25,"call":"pick.set","params":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","of":"session:ember:c-680584e540","open":true}},"w":1792524914911.32}
  #|{"step":"answered pick.set","w":1792524914911.943}
  #|{"in":{"id":25,"ok":null},"w":1792524914927.809}
  #|{"in":{"id":17,"delta":[{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792524914927.829}
  #|{"in":{"id":24,"value":{"fastAvailable":false,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524913584,"time":{"checkedAt":{"at":1792524913584,"ago":"刚刚","full":"10/21 03:35:13","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"}],"runtimeFixed":true,"value":{"runtime":"claude"},"account":{"text":"自动 · cc","auto":true,"profile":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524913584,"time":{"checkedAt":{"at":1792524913584,"ago":"刚刚","full":"10/21 03:35:13","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}},"draft":{"runtime":"claude"},"runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[],"who":"账号","autoNote":"当前：cc","changed":false,"was":["默认模型","默认深度","自动 · cc"],"becomes":["默认模型","默认深度","自动分配"],"modelText":"选择模型","accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更"}},"w":1792524914927.863}
  #|{"out":{"id":26,"subscribe":{"topic":"doing"},"keyed":true},"w":1792524914927.95}
  #|{"in":{"id":26,"value":{"doing":[]}},"w":1792524914944.476}
  #|{"step":"rest","w":1792524914944.766}
  #|{"step":"now until 思考深度","w":1792524915244.591}
  #|{"step":"tap =high","w":1792524915244.602}
  #|{"step":"tap =high","acted":true,"w":1792524915261.279}
  #|{"out":{"id":27,"call":"pick.set","params":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","of":"session:ember:c-680584e540","effort":"high"}},"w":1792524915277.888}
  #|{"step":"tap =选择模型","w":1792524915278.009}
  #|{"in":{"id":27,"ok":null},"w":1792524915294.473}
  #|{"step":"tap =选择模型","acted":true,"w":1792524915294.685}
  #|{"step":"tap Sonnet","w":1792524915311.301}
  #|{"step":"tap Sonnet","acted":true,"w":1792524915344.621}
  #|{"out":{"id":28,"call":"pick.set","params":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","of":"session:ember:c-680584e540","model":"claude-sonnet-5-5"}},"w":1792524915361.224}
  #|{"step":"until 改成","w":1792524915361.332}
  #|{"in":{"id":28,"ok":null},"w":1792524915377.811}
  #|{"in":{"id":24,"delta":[{"path":["accounts"],"append":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524913584,"time":{"checkedAt":{"at":1792524913584,"ago":"刚刚","full":"10/21 03:35:13","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},{"path":["becomes",0],"set":"Sonnet 5.5"},{"path":["becomes",1],"set":"high"},{"path":["becomes",2],"set":"自动 · cc"},{"path":["changed"],"set":true},{"path":["draft","effort"],"set":"high"},{"path":["draft","model"],"set":"claude-sonnet-5-5"},{"path":["maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["modelText"],"set":"Sonnet 5.5"},{"path":["option"],"set":"claude-sonnet-5-5"},{"path":["saveText"],"set":"改成 Sonnet 5.5 · high · 自动分配"}]},"w":1792524915377.846}
  #|{"step":"tap 改成","w":1792524915379.482}
  #|{"step":"tap 改成","acted":true,"w":1792524915394.713}
  #|{"out":{"id":29,"call":"pick.save","params":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","of":"session:ember:c-680584e540"}},"w":1792524915411.2}
  #|{"step":"until 已更改，下一轮起生效","w":1792524915411.502}
  #|{"in":{"id":29,"ok":{"saved":true}},"w":1792524915444.488}
  #|{"step":"wait 2600","w":1792524915445.402}
  #|{"in":{"id":24,"delta":[{"path":["changed"],"set":false},{"path":["saveText"],"set":"无变更"},{"path":["value","effort"],"set":"high"},{"path":["value","model"],"set":"claude-sonnet-5-5"},{"path":["valueOption"],"set":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524913584,"time":{"checkedAt":{"at":1792524913584,"ago":"刚刚","full":"10/21 03:35:13","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"}},{"path":["was",0],"set":"Sonnet 5.5"},{"path":["was",1],"set":"high"}]},"w":1792524915527.843}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"session","agentText"],"set":"Sonnet 5.5 · high"},{"path":["agents",0,"session","effort"],"set":"high"},{"path":["agents",0,"session","maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["agents",0,"session","model"],"set":"claude-sonnet-5-5"},{"path":["agents",0,"session","modelName"],"set":"Sonnet 5.5"},{"path":["agents",0,"session","process"],"set":"cold"},{"path":["agents",0,"session","processText"],"set":"已释放"},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["by","maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["by","name"],"set":"Sonnet 5.5 · high"}]}]},"w":1792524915527.883}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","ember:c-680584e540"],"ops":[{"path":["agents",0,"agentText"],"set":"Sonnet 5.5 · high"},{"path":["agents",0,"effort"],"set":"high"},{"path":["agents",0,"maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["agents",0,"model"],"set":"claude-sonnet-5-5"},{"path":["last","by","label"],"set":"Sonnet 5.5"},{"path":["last","by","maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["last","by","model"],"set":"claude-sonnet-5-5"},{"path":["last","by","name"],"set":"Sonnet 5.5"}]}]}]},"w":1792524915527.914}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":66003918848}]},"w":1792524915527.934}
  #|{"step":"now rest","w":1792524918061.792}
  #|{"step":"","w":1792524918178.438}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,63]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11]}}
  #|{"textrec":{"s":[13,500,0,"以下是新消息"],"r":[0,1,12.898832684824903,64,1,1,12.898832684824903,65,2,1,12.898832684824903,66,3,1,12.898832684824903,67,4,1,12.898832684824896,68,5,1,12.898832684824896,69]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,70,1,1,14.883268482490273,71,2,1,14.883268482490273,72,3,1,14.883268482490273,73]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[10,400,0,"5 分钟前"],"r":[0,1,6.298828125,74,1,1,2.9296875,-1,2,1,9.941634241245136,75,3,1,9.941634241245136,76,4,1,9.941634241245133,77]}}
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
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
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
  #|{"textrec":{"g":74,"r":[1302,0,8,11,-1,-9,0]}}
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
  #|{"textrec":{"s":[18,700,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,17.842412451361866,123,1,1,17.842412451361866,124,2,1,17.842412451361866,123,3,1,17.842412451361866,125,4,1,17.842412451361866,126,5,1,17.842412451361866,127,6,1,17.842412451361866,128,7,1,17.842412451361866,129,8,1,4.152015030384064,-1,9,1,11.16209328174591,130,10,1,10.675500869750977,131,11,1,9.692523032426834,132,12,1,6.919372379779816,133,13,1,5.73083621263504,134,14,1,17.842412451361866,135,15,1,17.842412451361866,136,16,1,18.08754863813229,137,17,1,17.842412451361866,138,18,1,17.842412451361838,139,19,1,17.842412451361838,125,20,1,17.842412451361838,126,21,1,17.842412451361838,140,22,1,17.842412451361838,127,23,1,4.152015030384064,-1,24,1,10.138570368289948,141,25,1,11.132530510425568,142,26,1,10.337921261787415,143,27,1,10.808134496212006,144,28,1,6.940345913171768,133]}}
  #|{"textrec":{"m":[18,700,0],"r":[17.40234375,3.796875,26]}}
  #|{"textrec":{"s":[13,400,0,"你 5 分钟前发起 · 最新 5 分钟前"],"r":[0,1,12.898832684824903,4,1,1,3.580078125,-1,2,1,7.9599609375,145,3,1,3.580078125,-1,4,1,12.898832684824903,146,5,1,12.898832684824903,147,6,1,12.898832684824903,148,7,1,12.898832684824896,149,8,1,12.898832684824896,150,9,1,3.580078125,-1,10,1,6.228545204222115,151,11,1,3.580078125,-1,12,1,12.898832684824896,152,13,1,12.898832684824896,153,14,1,3.580078125,-1,15,1,7.9599609375,145,16,1,3.580078125,-1,17,1,12.898832684824896,146,18,1,12.898832684824896,147,19,1,12.898832684824896,148]}}
  #|{"textrec":{"s":[15,600,0,"默认模型"],"r":[0,1,14.883268482490273,154,1,1,14.883268482490273,155,2,1,14.883268482490273,156,3,1,14.883268482490273,157]}}
  #|{"textrec":{"s":[12,400,0,"已完成：answered the question that was asked · 5 分钟前"],"r":[0,1,11.918287937743191,158,1,1,11.918287937743191,159,2,1,11.918287937743195,160,3,1,12.081712062256813,161,4,1,6.62109375,162,5,1,7.001953125,163,6,1,6.193359375,114,7,1,9.087890625,164,8,1,6.73828125,165,9,1,4.482421875,166,10,1,6.767578125,165,11,1,7.37109375,117,12,1,3.375,-1,13,1,4.359375,115,14,1,7.060546875,167,15,1,6.85546875,165,16,1,3.375,-1,17,1,7.312500000000014,168,18,1,7.001953125,116,19,1,6.85546875,165,20,1,6.251953125,114,21,1,4.330078125,115,22,1,2.96484375,118,23,1,7.08984375,119,24,1,7.001953125,163,25,1,3.375,-1,26,1,4.359375,115,27,1,7.060546875,167,28,1,6.62109375,162,29,1,4.359375,115,30,1,3.375,-1,31,1,9.205078125,164,32,1,6.533203125,162,33,1,6.28125,114,34,1,3.375,-1,35,1,6.62109375,162,36,1,6.28125,114,37,1,6.369140625,169,38,1,6.708984375,165,39,1,7.37109375,117,40,1,3.375,-1,41,1,5.754933455713626,170,42,1,3.375,-1,43,1,7.41796875,171,44,1,3.375,-1,45,1,11.918287937743173,172,46,1,11.918287937743173,173,47,1,11.918287937743173,174]}}
  #|{"textrec":{"s":[14,400,0,"固定到列表顶部"],"r":[0,1,13.891050583657588,175,1,1,13.891050583657588,176,2,1,13.891050583657588,177,3,1,13.891050583657588,178,4,1,13.891050583657588,179,5,1,13.891050583657588,180,6,1,13.891050583657588,181]}}
  #|{"textrec":{"s":[14,400,0,"复制会话链接"],"r":[0,1,13.891050583657588,182,1,1,13.891050583657588,183,2,1,13.891050583657588,184,3,1,13.891050583657588,185,4,1,13.891050583657588,186,5,1,13.891050583657588,187]}}
  #|{"textrec":{"s":[14,400,0,"归档对话"],"r":[0,1,13.891050583657588,188,1,1,13.891050583657588,189,2,1,13.891050583657588,190,3,1,13.891050583657588,185]}}
  #|{"textrec":{"s":[12,400,0,"…"],"r":[0,1,9.65625,191]}}
  #|{"textrec":{"s":[12,400,0,"已完成：answered the question that was ask…"],"r":[0,1,11.918287937743191,158,1,1,11.918287937743191,159,2,1,11.918287937743195,160,3,1,12.081712062256813,161,4,1,6.62109375,162,5,1,7.001953125,163,6,1,6.193359375,114,7,1,9.087890625,164,8,1,6.73828125,165,9,1,4.482421875,166,10,1,6.767578125,165,11,1,7.37109375,117,12,1,3.375,-1,13,1,4.359375,115,14,1,7.060546875,167,15,1,6.85546875,165,16,1,3.375,-1,17,1,7.312500000000014,168,18,1,7.001953125,116,19,1,6.85546875,165,20,1,6.251953125,114,21,1,4.330078125,115,22,1,2.96484375,118,23,1,7.08984375,119,24,1,7.001953125,163,25,1,3.375,-1,26,1,4.359375,115,27,1,7.060546875,167,28,1,6.62109375,162,29,1,4.359375,115,30,1,3.375,-1,31,1,9.205078125,164,32,1,6.533203125,162,33,1,6.28125,114,34,1,3.375,-1,35,1,6.62109375,162,36,1,6.28125,114,37,1,6.515625,169,38,1,9.65625,191]}}
  #|{"textrec":{"g":123,"r":[1502,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":124,"r":[1522,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":125,"r":[1542,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":126,"r":[1562,0,20,19,-1,-16,0]}}
  #|{"textrec":{"g":127,"r":[1583,0,18,19,0,-16,0]}}
  #|{"textrec":{"g":128,"r":[1602,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":129,"r":[1622,0,20,19,-1,-16,0]}}
  #|{"textrec":{"g":130,"r":[1643,0,12,16,0,-11,0]}}
  #|{"textrec":{"g":131,"r":[1656,0,13,13,-1,-11,0]}}
  #|{"textrec":{"g":132,"r":[1670,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":133,"r":[1683,0,9,15,-1,-13,0]}}
  #|{"textrec":{"g":134,"r":[1693,0,6,13,0,-11,0]}}
  #|{"textrec":{"g":135,"r":[1700,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":136,"r":[1720,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":137,"r":[1740,0,7,9,0,-4,0]}}
  #|{"textrec":{"g":138,"r":[1748,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":139,"r":[1768,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":140,"r":[1788,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":141,"r":[1807,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":142,"r":[1820,0,13,16,-1,-11,0]}}
  #|{"textrec":{"g":143,"r":[1834,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":144,"r":[1847,0,12,12,0,-11,0]}}
  #|{"textrec":{"g":4,"r":[1860,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":145,"r":[1875,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":146,"r":[1886,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":147,"r":[1902,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":148,"r":[1917,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[1933,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[1948,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":151,"r":[1964,0,4,5,1,-7,0]}}
  #|{"textrec":{"g":152,"r":[1969,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":153,"r":[1984,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[2000,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":155,"r":[2018,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":156,"r":[0,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[18,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[35,20,13,12,0,-10,0]}}
  #|{"textrec":{"g":159,"r":[49,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":160,"r":[64,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":161,"r":[79,20,4,9,1,-9,0]}}
  #|{"textrec":{"g":162,"r":[84,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":163,"r":[93,20,9,9,-1,-8,0]}}
  #|{"textrec":{"g":164,"r":[103,20,11,9,-1,-8,0]}}
  #|{"textrec":{"g":165,"r":[115,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":166,"r":[125,20,7,9,-1,-8,0]}}
  #|{"textrec":{"g":167,"r":[133,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":168,"r":[142,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":169,"r":[152,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":191,"r":[161,20,10,5,0,-3,0]}}
  #|{"textrec":{"g":175,"r":[172,20,14,15,0,-12,0]}}
  #|{"textrec":{"g":176,"r":[187,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":177,"r":[203,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":178,"r":[219,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":179,"r":[235,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":180,"r":[251,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":181,"r":[268,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":182,"r":[284,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":183,"r":[300,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":184,"r":[316,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":185,"r":[333,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":186,"r":[350,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":187,"r":[367,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":188,"r":[383,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":189,"r":[399,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":190,"r":[415,20,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["92022e9e11aef691",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["f1276e6323a9ca06",1853,64],"r":[21,21,21,21]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["030aece180ce0f3c",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["b9bedad57f2a5f13",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["97cc1349f5996766",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[17,700,0,"默认模型"],"r":[0,1,16.851167315175097,192,1,1,16.851167315175097,193,2,1,16.851167315175097,194,3,1,16.851167315175097,195]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[13,400,0,"已完成：answered the question that was asked"],"r":[0,1,12.898832684824903,196,1,1,12.898832684824903,197,2,1,12.898832684824903,198,3,1,13.075875486381321,199,4,1,7.0966796875,12,5,1,7.509277343749993,200,6,1,6.63330078125,10,7,1,9.76904296875,6,8,1,7.2236328125,14,9,1,4.77978515625,8,10,1,7.25537109375,14,11,1,7.9091796875,201,12,1,3.580078125,-1,13,1,4.646484375,202,14,1,7.57275390625,203,15,1,7.3505859375,14,16,1,3.580078125,-1,17,1,7.845703125,204,18,1,7.50927734375,205,19,1,7.3505859375,14,20,1,6.69677734375,10,21,1,4.61474609375,202,22,1,3.1357421875,206,23,1,7.6044921875,7,24,1,7.50927734375,200,25,1,3.580078125,-1,26,1,4.646484375,202,27,1,7.57275390625,203,28,1,7.0966796875,12,29,1,4.646484375,202,30,1,3.580078125,-1,31,1,9.89599609375,6,32,1,7.00146484375,12,33,1,6.728515625,10,34,1,3.580078125,-1,35,1,7.0966796875,12,36,1,6.728515625000028,10,37,1,6.82373046875,9,38,1,7.19189453125,14,39,1,7.9091796875,201]}}
  #|{"textrec":{"s":[13,400,0," · 5 分钟前"],"r":[0,1,3.580078125,-1,1,1,6.228545204222119,151,2,1,3.580078125,-1,3,1,7.9599609375,145,4,1,3.580078125,-1,5,1,12.898832684824907,146,6,1,12.898832684824903,147,7,1,12.898832684824903,148]}}
  #|{"textrec":{"s":[14,400,0,"Station"],"r":[0,1,8.7705078125,207,1,1,4.935546875,61,2,1,7.57421875,57,3,1,4.935546875,61,4,1,3.30859375,208,5,1,8.12109375,209,6,1,8.0185546875,60]}}
  #|{"textrec":{"s":[14,400,0,"studio"],"r":[0,1,7.1435546875,210,1,1,4.9013671875,61,2,1,8.0185546875,211,3,1,8.44921875,212,4,1,3.30859375,208,5,1,8.12109375,209]}}
  #|{"textrec":{"s":[14,400,0,"账号"],"r":[0,1,13.891050583657588,213,1,1,13.891050583657588,214]}}
  #|{"textrec":{"s":[14,400,0,"cc · 自动"],"r":[0,1,7.68359375,215,1,1,7.68359375,215,2,1,3.787109375,-1,3,1,6.707664066085361,216,4,1,3.787109375,-1,5,1,13.891050583657584,217,6,1,13.891050583657588,218]}}
  #|{"textrec":{"s":[14,400,0,"历史"],"r":[0,1,13.891050583657588,219,1,1,13.891050583657588,220]}}
  #|{"textrec":{"s":[14,400,0,"尚未运行"],"r":[0,1,13.891050583657588,221,1,1,13.891050583657588,222,2,1,13.891050583657588,223,3,1,13.891050583657588,224]}}
  #|{"textrec":{"g":192,"r":[431,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":193,"r":[451,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":194,"r":[471,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":195,"r":[490,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":196,"r":[509,20,13,13,0,-11,0]}}
  #|{"textrec":{"g":197,"r":[523,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":198,"r":[539,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":199,"r":[555,20,4,9,1,-9,0]}}
  #|{"textrec":{"g":12,"r":[560,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":200,"r":[570,20,8,9,0,-8,0]}}
  #|{"textrec":{"g":10,"r":[579,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":6,"r":[589,20,12,9,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[602,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":8,"r":[612,20,6,9,0,-8,0]}}
  #|{"textrec":{"g":201,"r":[619,20,9,13,-1,-11,0]}}
  #|{"textrec":{"g":202,"r":[629,20,7,12,-1,-10,0]}}
  #|{"textrec":{"g":203,"r":[637,20,8,12,0,-11,0]}}
  #|{"textrec":{"g":204,"r":[646,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":205,"r":[656,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":206,"r":[666,20,5,12,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[672,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":9,"r":[682,20,8,12,0,-11,0]}}
  #|{"textrec":{"g":207,"r":[691,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":208,"r":[703,20,5,13,-1,-12,0]}}
  #|{"textrec":{"g":209,"r":[709,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":210,"r":[720,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":211,"r":[730,20,9,11,0,-9,0]}}
  #|{"textrec":{"g":212,"r":[740,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":213,"r":[751,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":214,"r":[768,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":215,"r":[784,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":216,"r":[795,20,5,4,1,-7,0]}}
  #|{"textrec":{"g":217,"r":[801,20,12,16,1,-13,0]}}
  #|{"textrec":{"g":218,"r":[814,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":219,"r":[830,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[846,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":221,"r":[862,20,14,16,0,-13,0]}}
  #|{"textrec":{"g":222,"r":[877,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":223,"r":[893,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":224,"r":[910,20,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["0e6dfc8705c682a0",2207,64],"r":[23,23,23,23]}}
  #|{"textrec":{"s":[14,400,0,"1 轮"],"r":[0,1,6.34375,225,1,1,3.787109375,-1,2,1,13.891050583657588,226]}}
  #|{"textrec":{"g":225,"r":[926,20,7,12,-1,-11,0]}}
  #|{"textrec":{"g":226,"r":[934,20,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"执行历史"],"r":[0,1,15.875486381322958,227,1,1,15.875486381322958,228,2,1,15.875486381322958,229,3,1,15.875486381322958,230]}}
  #|{"textrec":{"s":[13,400,0,"步骤"],"r":[0,1,12.898832684824903,231,1,1,12.898832684824903,232]}}
  #|{"textrec":{"s":[13,400,0,"详情"],"r":[0,1,12.898832684824903,233,1,1,12.898832684824903,234]}}
  #|{"textrec":{"s":[16,700,0,"默认模型"],"r":[0,1,15.875486381322958,235,1,1,15.875486381322958,236,2,1,15.875486381322958,237,3,1,15.875486381322958,238]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[17,400,0,"返回"],"r":[0,1,16.851167315175097,239,1,1,16.851167315175097,240]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[12,400,0,"station 离线，此设备上暂无该会话的执行历史"],"r":[0,1,6.251953125,114,1,1,4.330078125,115,2,1,6.62109375,162,3,1,4.359375,115,4,1,2.96484375,118,5,1,7.08984375,119,6,1,7.001953125,163,7,1,3.375,-1,8,1,11.918287937743187,241,9,1,11.918287937743187,242,10,1,12.081712062256813,243,11,1,11.918287937743187,244,12,1,11.918287937743187,245,13,1,11.918287937743187,246,14,1,11.918287937743187,247,15,1,11.918287937743187,248,16,1,11.918287937743202,249,17,1,11.918287937743202,250,18,1,11.918287937743202,251,19,1,11.918287937743202,252,20,1,11.918287937743202,253,21,1,11.918287937743202,254,22,1,11.918287937743202,255,23,1,11.918287937743202,256,24,1,11.918287937743202,257]}}
  #|{"textrec":{"g":241,"r":[951,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":242,"r":[965,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":243,"r":[980,20,5,6,0,-3,0]}}
  #|{"textrec":{"g":244,"r":[986,20,14,13,-1,-11,0]}}
  #|{"textrec":{"g":245,"r":[1001,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":246,"r":[1016,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":247,"r":[1031,20,14,13,-1,-11,0]}}
  #|{"textrec":{"g":248,"r":[1046,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":249,"r":[1061,20,14,13,-1,-10,0]}}
  #|{"textrec":{"g":250,"r":[1076,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":251,"r":[1091,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":252,"r":[1106,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":253,"r":[1121,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":254,"r":[1135,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":255,"r":[1150,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":256,"r":[1165,20,13,13,-1,-10,0]}}
  #|{"textrec":{"g":257,"r":[1179,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":239,"r":[1194,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":240,"r":[1213,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":235,"r":[1230,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":236,"r":[1249,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":237,"r":[1268,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":238,"r":[1286,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":227,"r":[1304,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":228,"r":[1323,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":229,"r":[1341,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":230,"r":[1359,20,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["5e7fcd0c8367a3ab",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":231,"r":[1377,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":232,"r":[1392,20,15,14,-1,-11,0]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,14.076484680175781,62]}}
  #|{"textrec":{"g":233,"r":[1408,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":234,"r":[1424,20,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.497894287109375,35,12,1,14.076484680175781,62]}}
  #|{"textrec":{"ib":["ee44219918426000",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[12,400,0,"找不到运行时记录，可能已归档"],"r":[0,1,11.918287937743191,258,1,1,11.918287937743191,259,2,1,11.918287937743195,260,3,1,11.918287937743187,261,4,1,11.918287937743187,255,5,1,11.918287937743187,262,6,1,11.918287937743187,263,7,1,11.918287937743187,264,8,1,12.081712062256813,243,9,1,11.918287937743187,265,10,1,11.918287937743187,266,11,1,11.918287937743202,158,12,1,11.918287937743202,267,13,1,11.918287937743202,268]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.329673767089844,34,11,1,13.973621368408203,269]}}
  #|{"textrec":{"g":258,"r":[1440,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":259,"r":[1455,20,14,13,-1,-10,0]}}
  #|{"textrec":{"g":260,"r":[1470,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":261,"r":[1484,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":262,"r":[1499,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":263,"r":[1514,20,14,13,-1,-11,0]}}
  #|{"textrec":{"g":264,"r":[1529,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":265,"r":[1543,20,14,13,-1,-10,0]}}
  #|{"textrec":{"g":266,"r":[1558,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":267,"r":[1573,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":268,"r":[1587,20,14,14,-1,-11,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.721336364746094,33,10,1,13.973621368408203,269]}}
  #|{"textrec":{"s":[14,400,0,"选择模型"],"r":[0,1,13.891050583657588,270,1,1,13.891050583657588,271,2,1,13.891050583657588,272,3,1,13.891050583657588,273]}}
  #|{"textrec":{"s":[14,400,0," · 默认深度 · 自动 · cc"],"r":[0,1,3.787109375,-1,1,1,6.707664066085361,216,2,1,3.787109375,-1,3,1,13.891050583657588,274,4,1,13.891050583657584,275,5,1,13.891050583657588,276,6,1,13.891050583657588,277,7,1,3.787109375,-1,8,1,6.707664066085357,216,9,1,3.787109375,-1,10,1,13.891050583657588,217,11,1,13.891050583657588,218,12,1,3.787109375,-1,13,1,6.707664066085357,216,14,1,3.787109375,-1,15,1,7.68359375,215,16,1,7.68359375,215]}}
  #|{"textrec":{"s":[14,400,0,"运行时"],"r":[0,1,13.891050583657588,223,1,1,13.891050583657588,224,2,1,13.891050583657588,278]}}
  #|{"textrec":{"s":[14,400,0,"Claude Code"],"r":[0,1,9.87109375,279,1,1,3.390625,280,2,1,7.57421875,57,3,1,8.0185546875,211,4,1,8.44921875,212,5,1,7.84765625,59,6,1,3.787109375,-1,7,1,9.87109375,279,8,1,8.12109375,209,9,1,8.44921875,212,10,1,7.84765625,59]}}
  #|{"textrec":{"s":[14,400,0,"进程"],"r":[0,1,13.891050583657588,281,1,1,13.891050583657588,282]}}
  #|{"textrec":{"s":[14,400,0,"保温中"],"r":[0,1,13.891050583657588,283,1,1,13.891050583657588,284,2,1,13.891050583657588,285]}}
  #|{"textrec":{"s":[14,400,0,"轮次"],"r":[0,1,13.891050583657588,226,1,1,13.891050583657588,286]}}
  #|{"textrec":{"s":[13,400,0,"Station"],"r":[0,1,8.20751953125,287,1,1,4.646484375,202,2,1,7.0966796875,12,3,1,4.646484375,202,4,1,3.1357421875,206,5,1,7.6044921875,7,6,1,7.50927734375,200]}}
  #|{"textrec":{"s":[14,400,0,"名称"],"r":[0,1,13.891050583657588,288,1,1,13.891050583657588,289]}}
  #|{"textrec":{"g":270,"r":[1602,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":271,"r":[1619,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":272,"r":[1636,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":273,"r":[1653,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":274,"r":[1669,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":275,"r":[1686,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[1703,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":277,"r":[1720,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":278,"r":[1737,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":279,"r":[1753,20,12,14,-1,-12,0]}}
  #|{"textrec":{"g":280,"r":[1766,20,4,13,0,-12,0]}}
  #|{"textrec":{"g":281,"r":[1771,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":282,"r":[1788,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":283,"r":[1804,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":284,"r":[1821,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":285,"r":[1838,20,14,16,0,-13,0]}}
  #|{"textrec":{"g":286,"r":[1853,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":287,"r":[1870,20,10,13,-1,-11,0]}}
  #|{"textrec":{"g":288,"r":[1881,20,14,16,-1,-13,0]}}
  #|{"textrec":{"g":289,"r":[1896,20,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["54f6f25c61b411ff",983,64],"r":[15,15,15,15]}}
  #|{"textrec":{"ib":["e733bc7eab8087ba",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[14,400,0,"机器"],"r":[0,1,13.891050583657588,290,1,1,13.891050583657588,291]}}
  #|{"textrec":{"s":[14,400,0,"Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,9.283203125,292,1,1,8.39453125,293,2,1,8.39453125,293,3,1,3.390625,280,4,1,7.84765625,59,5,1,3.787109375,-1,6,1,12.0859375,294,7,1,8.859375,295,8,1,3.787109375,-1,9,1,6.707664066085357,216,10,1,3.787109375,-1,11,1,6.34375,225,12,1,8.763671875,296,13,1,3.787109375,-1,14,1,10.3017578125,297,15,1,9.05078125,298,16,1,3.787109375,-1,17,1,6.707664066085357,216,18,1,3.787109375,-1,19,1,12.03125,299,20,1,7.57421875,57,21,1,7.68359375,215,22,1,10.650390625,300,23,1,8.7705078125,207,24,1,3.787109375,-1,25,1,8.298828125,301,26,1,7.068359375,302,27,1,2.98046875,303,28,1,8.12109375,304,29,1,3.52734375,303,30,1,6.138671875,225]}}
  #|{"textrec":{"g":290,"r":[1913,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":291,"r":[1930,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":292,"r":[1947,20,11,12,-1,-11,0]}}
  #|{"textrec":{"g":293,"r":[1959,20,9,13,0,-9,0]}}
  #|{"textrec":{"g":294,"r":[1969,20,12,12,0,-11,0]}}
  #|{"textrec":{"g":295,"r":[1982,20,11,12,-1,-11,0]}}
  #|{"textrec":{"g":296,"r":[1994,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":297,"r":[2006,20,12,14,-1,-12,0]}}
  #|{"textrec":{"g":298,"r":[2019,20,10,12,0,-11,0]}}
  #|{"textrec":{"g":299,"r":[2030,20,13,10,0,-9,0]}}
  #|{"textrec":{"g":300,"r":[0,39,12,14,-1,-12,0]}}
  #|{"textrec":{"g":301,"r":[13,39,9,13,0,-12,0]}}
  #|{"textrec":{"g":302,"r":[23,39,10,12,-1,-11,0]}}
  #|{"textrec":{"g":303,"r":[34,39,4,5,0,-3,0]}}
  #|{"textrec":{"g":304,"r":[39,39,10,14,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"更换模型"],"r":[0,1,15.875486381322958,305,1,1,15.875486381322958,306,2,1,15.875486381322958,307,3,1,15.875486381322958,308]}}
  #|{"textrec":{"s":[15,600,0,"无变更"],"r":[0,1,14.883268482490273,309,1,1,14.883268482490273,310,2,1,14.883268482490273,311]}}
  #|{"textrec":{"s":[14,400,0,"默认模型"],"r":[0,1,13.891050583657588,274,1,1,13.891050583657588,275,2,1,13.891050583657588,272,3,1,13.891050583657588,273]}}
  #|{"textrec":{"s":[13,400,0,"模型"],"r":[0,1,12.898832684824903,312,1,1,12.898832684824903,313]}}
  #|{"textrec":{"s":[14,400,0,"默认深度"],"r":[0,1,13.891050583657588,274,1,1,13.891050583657588,275,2,1,13.891050583657588,276,3,1,13.891050583657588,277]}}
  #|{"textrec":{"s":[13,400,0,"深度"],"r":[0,1,12.898832684824903,314,1,1,12.898832684824903,315]}}
  #|{"textrec":{"s":[14,400,0,"自动 · cc"],"r":[0,1,13.891050583657588,217,1,1,13.891050583657588,218,2,1,3.787109375,-1,3,1,6.707664066085357,216,4,1,3.787109375,-1,5,1,7.68359375,215,6,1,7.68359375,215]}}
  #|{"textrec":{"s":[13,400,0,"账号"],"r":[0,1,12.898832684824903,316,1,1,12.898832684824903,317]}}
  #|{"textrec":{"s":[14,600,0,"自动分配"],"r":[0,1,13.891050583657588,318,1,1,13.891050583657588,319,2,1,13.891050583657588,320,3,1,13.891050583657588,321]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[12,400,0,"更改将从下一轮开始生效。"],"r":[0,1,11.918287937743191,322,1,1,11.918287937743191,323,2,1,11.918287937743195,324,3,1,11.918287937743187,325,4,1,11.918287937743187,326,5,1,11.918287937743187,327,6,1,11.918287937743187,328,7,1,11.918287937743187,329,8,1,11.918287937743187,330,9,1,11.918287937743187,331,10,1,11.918287937743187,332,11,1,6.081712062256798,333]}}
  #|{"textrec":{"s":[15,400,0,"选择模型"],"r":[0,1,14.883268482490273,334,1,1,14.883268482490273,335,2,1,14.883268482490273,336,3,1,14.883268482490273,337]}}
  #|{"textrec":{"s":[13,400,0,"思考深度"],"r":[0,1,12.898832684824903,338,1,1,12.898832684824903,339,2,1,12.898832684824903,314,3,1,12.898832684824903,315]}}
  #|{"textrec":{"s":[12,400,0,"深度越高，速度越慢，消耗的额度也越多。"],"r":[0,1,11.918287937743191,340,1,1,11.918287937743191,341,2,1,11.918287937743195,342,3,1,11.918287937743187,343,4,1,12.081712062256813,243,5,1,11.918287937743187,344,6,1,11.918287937743187,341,7,1,11.918287937743187,342,8,1,11.918287937743187,345,9,1,12.081712062256813,243,10,1,11.918287937743187,346,11,1,11.918287937743202,347,12,1,11.918287937743202,253,13,1,11.918287937743202,348,14,1,11.918287937743202,341,15,1,11.918287937743202,349,16,1,11.918287937743202,342,17,1,11.918287937743202,350,18,1,6.081712062256798,333]}}
  #|{"textrec":{"s":[14,400,0,"low"],"r":[0,1,3.390625,280,1,1,7.984375,209,2,1,10.5546875,351]}}
  #|{"textrec":{"s":[14,400,0,"medium"],"r":[0,1,12.03125,299,1,1,7.84765625,59,2,1,8.44921875,212,3,1,3.30859375,208,4,1,8.0185546875,211,5,1,12.03125,299]}}
  #|{"textrec":{"s":[14,400,0,"high"],"r":[0,1,8.0869140625,352,1,1,3.30859375,208,2,1,8.380859375,58,3,1,8.0869140625,352]}}
  #|{"textrec":{"s":[14,400,0,"xhigh"],"r":[0,1,7.19140625,353,1,1,8.0869140625,352,2,1,3.30859375,208,3,1,8.380859375,58,4,1,8.0869140625,352]}}
  #|{"textrec":{"s":[14,400,0,"max"],"r":[0,1,12.03125,299,1,1,7.57421875,57,2,1,7.19140625,353]}}
  #|{"textrec":{"s":[14,400,0,"…"],"r":[0,1,11.115234375,354]}}
  #|{"textrec":{"s":[14,400,0,"默认…"],"r":[0,1,13.891050583657588,274,1,1,13.891050583657588,275,2,1,11.115234375,354]}}
  #|{"textrec":{"s":[14,400,0,"me…"],"r":[0,1,12.03125,299,1,1,7.84765625,59,2,1,11.115234375,354]}}
  #|{"textrec":{"s":[14,400,0,"x…"],"r":[0,1,7.19140625,353,1,1,11.115234375,354]}}
  #|{"textrec":{"s":[15,400,0,"自动分配"],"r":[0,1,14.883268482490273,355,1,1,14.883268482490273,356,2,1,14.883268482490273,357,3,1,14.883268482490273,358]}}
  #|{"textrec":{"s":[12,400,0,"额度用完或登录失效时自动切换"],"r":[0,1,11.918287937743191,348,1,1,11.918287937743191,341,2,1,11.918287937743195,359,3,1,11.918287937743187,159,4,1,11.918287937743187,360,5,1,11.918287937743187,361,6,1,11.918287937743187,264,7,1,11.918287937743187,362,8,1,11.918287937743187,332,9,1,11.918287937743187,262,10,1,11.918287937743187,363,11,1,11.918287937743202,364,12,1,11.918287937743202,365,13,1,11.918287937743202,366]}}
  #|{"textrec":{"g":312,"r":[50,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":313,"r":[66,39,14,14,-1,-12,0]}}
  #|{"textrec":{"g":314,"r":[81,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":315,"r":[97,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":316,"r":[113,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":317,"r":[129,39,15,14,-1,-11,0]}}
  #|{"textrec":{"g":322,"r":[145,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":323,"r":[160,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":324,"r":[175,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":325,"r":[190,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":326,"r":[205,39,14,13,-1,-10,0]}}
  #|{"textrec":{"g":327,"r":[220,39,14,4,-1,-6,0]}}
  #|{"textrec":{"g":328,"r":[235,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":329,"r":[250,39,14,13,-1,-10,0]}}
  #|{"textrec":{"g":330,"r":[265,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":331,"r":[280,39,14,13,-1,-11,0]}}
  #|{"textrec":{"g":332,"r":[295,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":333,"r":[310,39,6,6,0,-3,0]}}
  #|{"textrec":{"g":338,"r":[317,39,15,14,-1,-11,0]}}
  #|{"textrec":{"g":339,"r":[333,39,14,15,-1,-12,0]}}
  #|{"textrec":{"g":340,"r":[348,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":341,"r":[363,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":342,"r":[378,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":343,"r":[393,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":344,"r":[407,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":345,"r":[422,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":346,"r":[437,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":347,"r":[451,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":348,"r":[466,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":349,"r":[481,39,14,13,-1,-11,0]}}
  #|{"textrec":{"g":350,"r":[496,39,12,14,0,-11,0]}}
  #|{"textrec":{"g":354,"r":[509,39,12,5,0,-3,0]}}
  #|{"textrec":{"g":355,"r":[522,39,13,16,1,-13,0]}}
  #|{"textrec":{"g":356,"r":[536,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":357,"r":[553,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":358,"r":[570,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":359,"r":[587,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":360,"r":[601,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":361,"r":[616,39,14,13,-1,-11,0]}}
  #|{"textrec":{"g":362,"r":[631,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":363,"r":[646,39,11,14,0,-11,0]}}
  #|{"textrec":{"g":364,"r":[658,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":365,"r":[672,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":366,"r":[686,39,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["7e9322e1e57d8f14",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":334,"r":[701,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":335,"r":[718,39,17,16,-1,-13,0]}}
  #|{"textrec":{"g":336,"r":[736,39,17,16,-1,-13,0]}}
  #|{"textrec":{"g":337,"r":[754,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":305,"r":[771,39,18,17,-1,-14,0]}}
  #|{"textrec":{"g":306,"r":[790,39,18,17,-1,-14,0]}}
  #|{"textrec":{"g":307,"r":[809,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":308,"r":[827,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":318,"r":[845,39,12,16,1,-13,0]}}
  #|{"textrec":{"g":319,"r":[858,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":320,"r":[874,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":321,"r":[891,39,16,15,-1,-12,0]}}
  #|{"textrec":{"g":309,"r":[908,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":310,"r":[925,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":311,"r":[943,39,17,16,-1,-13,0]}}
  #|{"textrec":{"ib":["fcc12d57cc8a9841",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":353,"r":[961,39,9,10,-1,-9,0]}}
  #|{"textrec":{"s":[17,400,0,"更换模型"],"r":[0,1,16.851167315175097,367,1,1,16.851167315175097,368,2,1,16.851167315175097,369,3,1,16.851167315175097,370]}}
  #|{"textrec":{"s":[17,600,0,"选择模型"],"r":[0,1,16.851167315175097,371,1,1,16.851167315175097,372,2,1,16.851167315175097,373,3,1,16.851167315175097,374]}}
  #|{"textrec":{"m":[17,600,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"Sonnet 5.5"],"r":[0,1,9.32373046875,375,1,1,8.6279296875,376,2,1,8.51806640625,90,3,1,8.51806640625,90,4,1,8.3349609375,89,5,1,5.21484375,91,6,1,3.984375,-1,7,1,8.78173828125,377,8,1,3.724365234375,378,9,1,8.800048828125,377]}}
  #|{"textrec":{"g":367,"r":[971,39,18,17,-1,-14,0]}}
  #|{"textrec":{"g":368,"r":[990,39,19,18,-1,-15,0]}}
  #|{"textrec":{"g":369,"r":[1010,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":370,"r":[1029,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":371,"r":[1048,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":372,"r":[1067,39,19,18,-1,-15,0]}}
  #|{"textrec":{"g":373,"r":[1087,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":374,"r":[1106,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":375,"r":[1125,39,11,14,-1,-12,0]}}
  #|{"textrec":{"g":376,"r":[1137,39,11,12,-1,-10,0]}}
  #|{"textrec":{"g":377,"r":[1149,39,10,14,0,-12,0]}}
  #|{"textrec":{"g":378,"r":[1160,39,5,5,0,-3,0]}}
  #|{"textrec":{"s":[15,600,0,"改成 Sonnet 5.5 · high · 自动分配"],"r":[0,1,14.883268482490273,379,1,1,14.883268482490273,380,2,1,3.761730194091797,-1,3,1,9.68320906162262,381,4,1,8.901597261428833,382,5,1,8.93320620059967,383,6,1,8.93320620059967,383,7,1,8.615586161613464,384,8,1,5.683325529098511,385,9,1,3.761730194091797,-1,10,1,9.187601208686829,386,11,1,4.189368188381195,387,12,1,9.23490196466446,386,13,1,3.761730194091797,-1,14,1,7.186782927948599,388,15,1,3.761730194091797,-1,16,1,9.006448388099656,389,17,1,3.8520312309265137,390,18,1,9.247174859046936,391,19,1,9.00644838809967,389,20,1,3.761730194091797,-1,21,1,7.186782927948599,388,22,1,3.761730194091797,-1,23,1,14.88326848249028,392,24,1,14.88326848249028,393,25,1,14.88326848249028,394,26,1,14.88326848249028,395]}}
  #|{"textrec":{"s":[14,600,0,"Sonnet 5.5"],"r":[0,1,9.106021165847778,396,1,1,8.376516819000244,397,2,1,8.406018495559692,398,3,1,8.406018495559692,398,4,1,8.109573125839233,399,5,1,5.372796535491943,400,6,1,3.5793075561523438,-1,7,1,8.64345383644104,401,8,1,3.9784363508224487,402,9,1,8.687601208686829,401]}}
  #|{"textrec":{"s":[14,600,0,"high"],"r":[0,1,8.474377870559692,403,1,1,3.663588523864746,404,2,1,8.699055910110474,405,3,1,8.474377870559692,403]}}
  #|{"textrec":{"g":396,"r":[1166,39,11,14,-1,-12,0]}}
  #|{"textrec":{"g":397,"r":[1178,39,10,11,-1,-9,0]}}
  #|{"textrec":{"g":398,"r":[1189,39,9,10,0,-9,0]}}
  #|{"textrec":{"g":399,"r":[1199,39,10,11,-1,-9,0]}}
  #|{"textrec":{"g":400,"r":[1210,39,7,13,-1,-11,0]}}
  #|{"textrec":{"g":401,"r":[1218,39,10,13,0,-11,0]}}
  #|{"textrec":{"g":402,"r":[1229,39,5,6,0,-4,0]}}
  #|{"textrec":{"g":403,"r":[1235,39,9,13,0,-12,0]}}
  #|{"textrec":{"g":404,"r":[1245,39,5,13,-1,-12,0]}}
  #|{"textrec":{"g":405,"r":[1251,39,10,13,-1,-9,0]}}
  #|{"textrec":{"g":379,"r":[1262,39,17,16,-1,-13,0]}}
  #|{"textrec":{"g":380,"r":[1280,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":381,"r":[1298,39,12,14,-1,-12,0]}}
  #|{"textrec":{"g":382,"r":[1311,39,11,12,-1,-10,0]}}
  #|{"textrec":{"g":383,"r":[1323,39,10,11,0,-10,0]}}
  #|{"textrec":{"g":384,"r":[1334,39,11,12,-1,-10,0]}}
  #|{"textrec":{"g":385,"r":[1346,39,8,13,-1,-11,0]}}
  #|{"textrec":{"g":386,"r":[1355,39,10,14,0,-12,0]}}
  #|{"textrec":{"g":387,"r":[1366,39,5,6,0,-4,0]}}
  #|{"textrec":{"g":388,"r":[1372,39,5,5,1,-8,0]}}
  #|{"textrec":{"g":389,"r":[1378,39,10,14,0,-13,0]}}
  #|{"textrec":{"g":390,"r":[1389,39,6,14,-1,-13,0]}}
  #|{"textrec":{"g":391,"r":[1396,39,11,14,-1,-10,0]}}
  #|{"textrec":{"g":392,"r":[1408,39,13,17,1,-14,0]}}
  #|{"textrec":{"g":393,"r":[1422,39,16,17,-1,-14,0]}}
  #|{"textrec":{"g":394,"r":[1439,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":395,"r":[1456,39,17,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"已更改，下一轮起生效"],"r":[0,1,13.891050583657588,406,1,1,13.891050583657588,407,2,1,13.891050583657588,408,3,1,14.081712062256813,50,4,1,13.891050583657588,409,5,1,13.891050583657588,410,6,1,13.891050583657588,226,7,1,13.891050583657588,411,8,1,13.891050583657588,412,9,1,13.891050583657588,413]}}
  #|{"textrec":{"g":406,"r":[1474,39,14,14,0,-12,0]}}
  #|{"textrec":{"g":407,"r":[1489,39,16,15,-1,-12,0]}}
  #|{"textrec":{"g":408,"r":[1506,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":409,"r":[1523,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":410,"r":[1539,39,15,4,-1,-7,0]}}
  #|{"textrec":{"g":411,"r":[1555,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":412,"r":[1572,39,15,15,-1,-13,0]}}
  #|{"textrec":{"g":413,"r":[1588,39,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,700,0,"Sonnet 5.5 · high"],"r":[0,1,10.48828125,414,1,1,9.6015625,415,2,1,9.72265625,416,3,1,9.72265625,416,4,1,9.30078125,417,5,1,6.2890625,418,6,1,3.8125,-1,7,1,9.98828125,419,8,1,4.693359375,420,9,1,10.056640625,419,10,1,3.8125,-1,11,1,7.665901789811841,421,12,1,3.8125,-1,13,1,9.80078125,422,14,1,4.28125,423,15,1,10.01171875,424,16,1,9.80078125,422]}}
  #|{"textrec":{"s":[14,400,0,"Sonnet 5.5"],"r":[0,1,8.7705078125,207,1,1,8.12109375,209,2,1,8.0185546875,60,3,1,8.0185546875,60,4,1,7.84765625,59,5,1,4.935546875,61,6,1,3.787109375,-1,7,1,8.2646484375,425,8,1,3.54443359375,303,9,1,8.28173828125,425]}}
  #|{"textrec":{"s":[14,400,0," · high · 自动 · cc"],"r":[0,1,3.787109375,-1,1,1,6.707664066085361,216,2,1,3.787109375,-1,3,1,8.0869140625,352,4,1,3.30859375,208,5,1,8.380859374999996,58,6,1,8.0869140625,352,7,1,3.787109375,-1,8,1,6.707664066085357,216,9,1,3.787109375,-1,10,1,13.891050583657588,217,11,1,13.891050583657588,218,12,1,3.787109375,-1,13,1,6.707664066085357,216,14,1,3.787109375,-1,15,1,7.68359375,215,16,1,7.68359375,215]}}
  #|{"textrec":{"s":[14,400,0,"已释放"],"r":[0,1,13.891050583657588,406,1,1,13.891050583657588,426,2,1,13.891050583657588,427]}}
  #|{"textrec":{"g":414,"r":[1605,39,12,15,-1,-13,0]}}
  #|{"textrec":{"g":415,"r":[1618,39,12,12,-1,-10,0]}}
  #|{"textrec":{"g":416,"r":[1631,39,10,11,0,-10,0]}}
  #|{"textrec":{"g":417,"r":[1642,39,11,12,-1,-10,0]}}
  #|{"textrec":{"g":418,"r":[1654,39,8,14,-1,-12,0]}}
  #|{"textrec":{"g":419,"r":[1663,39,11,15,0,-13,0]}}
  #|{"textrec":{"g":420,"r":[1675,39,6,6,0,-4,0]}}
  #|{"textrec":{"g":421,"r":[1682,39,5,5,1,-8,0]}}
  #|{"textrec":{"g":422,"r":[1688,39,11,14,0,-13,0]}}
  #|{"textrec":{"g":423,"r":[1700,39,5,15,0,-14,0]}}
  #|{"textrec":{"g":424,"r":[1706,39,12,15,-1,-10,0]}}
  #|{"textrec":{"g":352,"r":[1719,39,9,13,0,-12,0]}}
  #|{"textrec":{"g":426,"r":[1729,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":427,"r":[1746,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":425,"r":[1763,39,9,13,0,-11,0]}}
