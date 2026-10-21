// e2e/traces/station-files.trace, made by scripts/trace.py from 02-station_files.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_station_files : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792531773}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792531480375.628}
  #|{"in":{"id":1,"ok":null},"w":1792531480465.342}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792531480465.366}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792531480465.376}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792531480466.821}
  #|{"step":"timeout 90000","w":1792531480466.827}
  #|{"step":"answered client.device","w":1792531480466.829}
  #|{"step":"answered client.focus","w":1792531480493.114}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792531480559.48}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792531480559.502}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792531480559.527}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792531480559.538}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DK74HJYQXG9W9K5TENX0NB","name":"Dev","role":"owner","created_at":1792531468,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792531468000,"ago":"刚刚","full":"10/21 05:24:28","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792531480578.131}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792531480578.146}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DK74HJYQXG9W9K5TENX0NB"},"keyed":true},"w":1792531480578.173}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DK74HJYQXG9W9K5TENX0NB","mine":false},"keyed":true},"w":1792531480578.188}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DK74HJYQXG9W9K5TENX0NB"},"keyed":true},"w":1792531480578.317}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DK74HJYQXG9W9K5TENX0NB"},"keyed":true},"w":1792531480578.348}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DK74HJYQXG9W9K5TENX0NB"}},"w":1792531480583.717}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792531480583.728}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DK74HJYQXG9W9K5TENX0NB"},"keyed":true},"w":1792531480583.735}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"39a4700faaefe1a05f4aad81d6001d744bafee739b4e397051d563eaace55a17","code":"CPW-ENM","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792531480592.817}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","id":"49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792531473040,"label":"今天","items":[{"id":"ember:c-f4302226a3","session":"ember:c-f4302226a3","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-f4302226a3","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"9f666caa-9d63-4c6d-8ef7-a230f232aa32","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792531472965,"endedAt":1792531473042},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-f4302226a3","text":"你好，我是测试用的 agent","createdAt":1792531473040,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792531473040,"ago":"刚刚","full":"10/21 05:24:33","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792531473040,"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","stationName":"studio","time":{"lastActiveAt":{"at":1792531473040,"ago":"刚刚","full":"10/21 05:24:33","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-656be3f62673961902","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792531480592.843}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DK74HJYQXG9W9K5TENX0NB":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792531480592.866}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792531480592.873}
  #|{"in":{"id":10,"ok":null},"w":1792531480592.876}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792531480592.881}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792531480592.885}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DK74HJYQXG9W9K5TENX0NB"},"keyed":true},"w":1792531480592.91}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792531480595.406}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792531480609.477}
  #|{"in":{"id":14,"ok":null},"w":1792531480609.482}
  #|{"step":"answered notify.permission","w":1792531480609.69}
  #|{"step":"tap 端到端测试","w":1792531480626.287}
  #|{"step":"tap 端到端测试","acted":true,"w":1792531480659.69}
  #|{"out":{"id":15,"subscribe":{"topic":"chat","station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","session":"ember:c-f4302226a3"},"keyed":true},"w":1792531480676.218}
  #|{"out":{"id":16,"call":"draft.get","params":{"key":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed:ember:c-f4302226a3"}},"w":1792531480676.601}
  #|{"step":"answered draft.get","w":1792531480676.726}
  #|{"in":{"id":16,"ok":{"text":"","quotes":[],"files":[],"id":"draft-5ad3fa69685cc61bc8"}},"w":1792531480692.805}
  #|{"in":{"id":15,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792531472.916000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792531472916,"sessions":[{"thread":1,"session":"ember:c-f4302226a3","connect":"ember","joinedAt":1792531472916}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792531473.040000","authorKind":"agent","author":"ember:c-f4302226a3","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792531473040,"time":{"createdAt":{"at":1792531473040,"ago":"刚刚","full":"10/21 05:24:33","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792531472916,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-f4302226a3","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"18b6a6b9-f489-4239-994d-441bcd080f79","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-f4302226a3/workspace","running":false,"createdAt":1792531472915,"lastActiveAt":1792531473042,"process":"warm","turns":1,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"9f666caa-9d63-4c6d-8ef7-a230f232aa32","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792531472965,"endedAt":1792531473042},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792531472915,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792531473042,"ago":"刚刚","full":"10/21 05:24:33","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792531472846,"time":{"checkedAt":{"at":1792531472846,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792531472945,"time":{"checkedAt":{"at":1792531472945,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792531472945,"time":{"checkedAt":{"at":1792531472945,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792531472945,"time":{"checkedAt":{"at":1792531472945,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792531472945,"time":{"checkedAt":{"at":1792531472945,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"9f666caa-9d63-4c6d-8ef7-a230f232aa32","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792531472965,"endedAt":1792531473042}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792531472.916000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792531472916,"sessions":[{"thread":1,"session":"ember:c-f4302226a3","connect":"ember","joinedAt":1792531472916}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792531473.040000","authorKind":"agent","author":"ember:c-f4302226a3","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792531473040,"time":{"createdAt":{"at":1792531473040,"ago":"刚刚","full":"10/21 05:24:33","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792531472916,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792531472.953000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792531472953,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792531472953,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792531473.040000","authorKind":"agent","author":"ember:c-f4302226a3","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792531473040,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-f4302226a3","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792531473040,"ago":"刚刚","full":"10/21 05:24:33","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":2,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792531480692.907}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5DK74HJYQXG9W9K5TENX0NB"},"keyed":true},"w":1792531480693.029}
  #|{"out":{"id":18,"subscribe":{"topic":"chatJobs","station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","session":"ember:c-f4302226a3"},"keyed":true},"w":1792531480693.039}
  #|{"out":{"id":19,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792531480693.051}
  #|{"out":{"id":20,"call":"client.focus","params":{"chat":{"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","session":"ember:c-f4302226a3","thread":1,"end":true}}},"w":1792531480695.832}
  #|{"in":{"id":17,"value":[{"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","id":"49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792531472,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792531472945,"time":{"checkedAt":{"at":1792531472945,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DK74HJYQXG9W9K5TENX0NB","device":"39a4700faaefe1a05f4aad81d6001d744bafee739b4e397051d563eaace55a17"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792531472846,"time":{"checkedAt":{"at":1792531472846,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792531472945,"time":{"checkedAt":{"at":1792531472945,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","workspace":"Dev","workspaceId":"01M5DK74HJYQXG9W9K5TENX0NB","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":57219559424,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792531470410},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792531470410},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792531470410},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792531470410},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792531470410}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[{"path":"/tmp/mbe2e-C/home/e2e-084051","name":"e2e-084051","state":"ok"}],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.01,"cpuBusy":0.32,"uptimeSec":10838,"memory":{"totalBytes":17179869184,"usedBytes":9435512832,"swapUsedBytes":341961605},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":57220231168},"emberRssBytes":160168888,"checkedAt":1792531476886,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 3 小时"],"meters":[{"label":"CPU","short":"CPU","percent":32,"left":68,"level":"ok","value":"32%","remaining":"空闲 68%","big":"68","unit":"%","title":"CPU 空闲","total":"负载 10.1","note":"负载 10.1 · Apple M4"},{"label":"内存","short":"内存","percent":55,"left":45,"level":"ok","value":"8.8 GB / 16.0 GB","remaining":"剩 7.2 G","big":"7.2","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":77,"left":23,"level":"amber","value":"剩余 53.3 GB / 228 GB","remaining":"剩 53.3 G","big":"53.3","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"3 小时"},{"label":"still.fail","value":"进程占用 153 MB"}],"usage":"内存 8.8 GB / 16.0 GB · 磁盘 剩余 53.3 GB / 228 GB","emberText":"still.fail 153 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792531472000,"ago":"刚刚","full":"10/21 05:24:32","until":"1 分钟内","past":true}},"joined":false}]},"w":1792531480709.615}
  #|{"in":{"id":18,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792531480709.728}
  #|{"in":{"id":20,"ok":null},"w":1792531480709.733}
  #|{"step":"answered picture","w":1792531480710.598}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5DK74HJYQXG9W9K5TENX0NB"],"set":{"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","key":"ember:c-f4302226a3"}}]},"w":1792531480742.803}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DK74HJYQXG9W9K5TENX0NB","chat"],"set":{"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","key":"ember:c-f4302226a3"}}]},"w":1792531480742.817}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":57219563520}]},"w":1792531480742.823}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":2},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["archiveOffered"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"set":true},{"path":["archiveCheck"],"set":{"text":"所有 agent 都做完了","recommended":true,"failed":false}}]},{"path":["thread","read"],"set":2},{"path":["thread","unread"],"set":0}]},"w":1792531480759.476}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","ember:c-f4302226a3"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792531480759.512}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DK74HJYQXG9W9K5TENX0NB","unread"],"set":0},{"path":["workspaces","01M5DK74HJYQXG9W9K5TENX0NB","label"],"remove":true},{"path":["workspaces","01M5DK74HJYQXG9W9K5TENX0NB","mineTone"],"remove":true},{"path":["workspaces","01M5DK74HJYQXG9W9K5TENX0NB","tone"],"remove":true}]},"w":1792531480759.529}
  #|{"in":{"id":19,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792531480892.848}
  #|{"step":"answered client.focus","w":1792531480911.256}
  #|{"step":"wait 300","w":1792531480928.19}
  #|{"step":"now until =studio","w":1792531481244.127}
  #|{"step":"tap icon:plus","w":1792531481244.18}
  #|{"step":"tap icon:plus","acted":true,"w":1792531481260.889}
  #|{"step":"rest","w":1792531481289.032}
  #|{"step":"now tap Station 文件","w":1792531482693.112}
  #|{"step":"now tap Station 文件","acted":true,"w":1792531482709.817}
  #|{"step":"rest","w":1792531482734.158}
  #|{"step":"now until 所有位置","w":1792531484210.905}
  #|{"step":"tap =e2e-084051","w":1792531484210.944}
  #|{"step":"tap =e2e-084051","acted":true,"w":1792531484244.552}
  #|{"step":"until 整个文件夹","w":1792531484260.99}
  #|{"out":{"id":21,"subscribe":{"topic":"drive","station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","root":"/tmp/mbe2e-C/home/e2e-084051","path":""},"keyed":true},"w":1792531484276.566}
  #|{"step":"tap 说明.txt","w":1792531484287.904}
  #|{"in":{"id":21,"value":{"path":"","entries":[{"name":"子文件夹","dir":true,"size":0,"mtime":1792531473741,"type":"","kind":"folder","sizeText":"","timeText":"05:24"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792531473767,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"05:24"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792531473741,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"05:24"}],"truncated":false,"folders":1,"files":2,"countText":"1 个文件夹 · 2 个文件"}},"w":1792531484292.843}
  #|{"step":"tap 说明.txt","acted":true,"w":1792531484310.855}
  #|{"step":"tap 添加 1 个","w":1792531484328.262}
  #|{"step":"tap 添加 1 个","acted":true,"w":1792531484361.228}
  #|{"step":"rest","w":1792531484377.855}
  #|{"step":"now gone 所有位置","w":1792531485877.5}
  #|{"step":"until studio · 路径","w":1792531485877.538}
  #|{"step":"tap 发消息","w":1792531485877.557}
  #|{"step":"tap 发消息","acted":true,"w":1792531485894.396}
  #|{"step":"type 看看这个文件 084051","w":1792531485920.402}
  #|{"step":"type 看看这个文件 084051","acted":true,"w":1792531485920.46}
  #|{"out":{"id":22,"call":"session.warm","params":{"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","key":"ember:c-f4302226a3"}},"w":1792531485926.411}
  #|{"step":"answered session.warm","w":1792531485930.386}
  #|{"in":{"id":22,"ok":{"ok":true}},"w":1792531485942.815}
  #|{"step":"tap icon:arrow-up","w":1792531485960.885}
  #|{"step":"tap icon:arrow-up","acted":true,"w":1792531485977.541}
  #|{"out":{"id":23,"call":"chat.send","params":{"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","text":"看看这个文件 084051\nstudio 上的文件：/tmp/mbe2e-C/home/e2e-084051/说明.txt","attachments":[],"quotes":[],"thread":1}},"w":1792531485993.18}
  #|{"step":"answered chat.send","w":1792531485998.892}
  #|{"in":{"id":23,"ok":{"seq":3}},"w":1792531486045.655}
  #|{"step":"wait 600","w":1792531486059.652}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"badge"],"set":"failed"},{"path":["agents",0,"session","badgeText"],"set":"失败，需要处理"},{"path":["agents",0,"session","lastActiveAt"],"set":1792531486017},{"path":["agents",0,"session","lastTurn","endedAt"],"set":1792531486018},{"path":["agents",0,"session","lastTurn","id"],"set":"16b0458a-fb54-453b-b65a-05449bc8cda2"},{"path":["agents",0,"session","lastTurn","kind"],"set":"nudge"},{"path":["agents",0,"session","lastTurn","startedAt"],"set":1792531486015},{"path":["agents",0,"session","lastTurn","declared"],"remove":true},{"path":["agents",0,"session","lastTurn","ending"],"remove":true},{"path":["agents",0,"session","lastTurn","need"],"remove":true},{"path":["agents",0,"session","mark"],"set":"failed"},{"path":["agents",0,"session","statusText"],"set":"出错：意外停止"},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792531486017},{"path":["agents",0,"session","time","lastActiveAt","full"],"set":"10/21 05:24:46"},{"path":["agents",0,"session","tone"],"set":"red"},{"path":["agents",0,"session","turns"],"set":4},{"path":["agents",0,"status"],"set":"unexpected"},{"path":["agents",0,"threads",0,"last"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","author"],"set":"ember"},{"path":["agents",0,"threads",0,"lastMessage","authorKind"],"set":"ember"},{"path":["agents",0,"threads",0,"lastMessage","authorName"],"set":"still.fail"},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792531486019},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","text"],"set":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work."},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792531486019},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","full"],"set":"10/21 05:24:46"},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792531486.019000"},{"path":["agents",0,"threads",0,"lastMessage","declared"],"remove":true},{"path":["agents",0,"threads",0,"lastMessage","ending"],"remove":true},{"path":["agents",0,"threads",0,"unread"],"set":1},{"path":["agents",0,"turns"],"append":[{"id":"ba5be777-066b-4845-b09b-f0f7918a35be","kind":"input","startedAt":1792531486004},{"id":"d62df379-d5c1-4004-8565-314924ebe470","kind":"nudge","startedAt":1792531486011},{"id":"16b0458a-fb54-453b-b65a-05449bc8cda2","kind":"nudge","outcome":"completed","startedAt":1792531486015,"endedAt":1792531486018}]},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"remove":true},{"path":["archiveCheck"],"remove":true}]},{"path":["outbox"],"key":["id"],"put":{"id":"out-372423ec1683b658ea","text":"看看这个文件 084051\nstudio 上的文件：/tmp/mbe2e-C/home/e2e-084051/说明.txt","attachments":[],"quotes":[],"createdAt":1792531485994,"state":"sending","seq":3,"time":{"createdAt":{"at":1792531485994,"ago":"刚刚","full":"10/21 05:24:45","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","last"],"set":4},{"path":["thread","lastMessage","author"],"set":"ember"},{"path":["thread","lastMessage","authorKind"],"set":"ember"},{"path":["thread","lastMessage","authorName"],"set":"still.fail"},{"path":["thread","lastMessage","createdAt"],"set":1792531486019},{"path":["thread","lastMessage","seq"],"set":4},{"path":["thread","lastMessage","text"],"set":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work."},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792531486019},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/21 05:24:46"},{"path":["thread","lastMessage","ts"],"set":"1792531486.019000"},{"path":["thread","lastMessage","declared"],"remove":true},{"path":["thread","lastMessage","ending"],"remove":true},{"path":["thread","unread"],"set":1},{"path":["archivable"],"remove":true},{"path":["archiveOffered"],"remove":true}]},"w":1792531486076.161}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DK74HJYQXG9W9K5TENX0NB":{"alert":1,"unread":0,"tone":"alert","label":"1 个出错","chat":{"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","key":"ember:c-f4302226a3"},"badge":1,"items":[{"kind":"alert","workspace":"01M5DK74HJYQXG9W9K5TENX0NB","workspaceName":"Dev","station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","stationName":"studio","session":"ember:c-f4302226a3","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"出错：意外停止","seen":false,"at":1792531486019}],"mineTone":"alert"}},"badge":1,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792531486076.301}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"put":{"daysAgo":0,"at":1792531486019,"label":"今天","items":[{"id":"ember:c-f4302226a3","session":"ember:c-f4302226a3","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-f4302226a3","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"16b0458a-fb54-453b-b65a-05449bc8cda2","kind":"nudge","outcome":"completed","startedAt":1792531486015,"endedAt":1792531486018},"agentText":"默认模型","mark":"failed","statusText":"出错：意外停止","badgeText":"失败，需要处理"}],"last":{"seq":4,"authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","createdAt":1792531486019,"by":{"kind":"ember","name":"still.fail","mine":false,"label":"still.fail"},"preview":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","time":{"createdAt":{"at":1792531486019,"ago":"刚刚","full":"10/21 05:24:46","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792531486019,"station":"01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","stationName":"studio","state":"failed","time":{"lastActiveAt":{"at":1792531486019,"ago":"刚刚","full":"10/21 05:24:46","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-656be3f62673961902","pinned":false,"stateText":"出错：意外停止","tone":"alert"}]}}]},"w":1792531486076.331}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":57553956864}]},"w":1792531486076.355}
  #|{"in":{"id":15,"delta":[{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":4,"thread":1,"ts":"1792531486.019000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792531486019,"mine":false,"system":true,"reportable":true,"by":{"name":"still.fail"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792531486019,"ago":"刚刚","full":"10/21 05:24:46","until":"1 分钟内","past":true}}},"before":null},{"path":["messages"],"key":["seq","outgoing"],"put":{"outgoing":"out-372423ec1683b658ea","seq":3,"thread":1,"ts":"1792531486.000000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"看看这个文件 084051\nstudio 上的文件：/tmp/mbe2e-C/home/e2e-084051/说明.txt","attachments":[],"quotes":[],"createdAt":1792531486000,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792531486000,"ago":"刚刚","full":"10/21 05:24:46","until":"1 分钟内","past":true}}},"before":[4,null]},{"path":["outbox"],"key":["id"],"drop":"out-372423ec1683b658ea"}]},"w":1792531486226.144}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":57553825792}]},"w":1792531486226.196}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":4},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["thread","read"],"set":4},{"path":["thread","unread"],"set":0}]},"w":1792531486442.825}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DK74HJYQXG9W9K5TENX0NB/49b3c6fc7b8682796ca8102a0ae5d593f1c724e99ce57e811167eb0b150e99ed","ember:c-f4302226a3"],"ops":[{"path":["unread"],"set":false}]}]}]},"w":1792531486442.931}
  #|{"in":{"id":8,"delta":[{"path":["badge"],"set":0},{"path":["workspaces","01M5DK74HJYQXG9W9K5TENX0NB","badge"],"set":0},{"path":["workspaces","01M5DK74HJYQXG9W9K5TENX0NB","items",0,"seen"],"set":true}]},"w":1792531486442.973}
  #|{"step":"now until 看看这个文件 084051","w":1792531486660.722}
  #|{"step":"gone 正在发送","w":1792531486660.792}
  #|{"step":"rest","w":1792531486660.823}
  #|{"step":"","w":1792531486693.829}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
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
  #|{"textrec":{"s":[12,500,0,"归档"],"r":[0,1,11.918287937743191,120,1,1,11.918287937743191,121]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[14,400,0,"answered the question that was asked"],"r":[0,1,7.57421875,57,1,1,8.0185546875,60,2,1,7.0751953125,122,3,1,10.4521484375,123,4,1,7.7109375,59,5,1,5.0791015625,124,6,1,7.7451171875,59,7,1,8.44921875,125,8,1,3.787109375,-1,9,1,4.935546875,61,10,1,8.0869140625,126,11,1,7.84765625,59,12,1,3.787109375,-1,13,1,8.380859375,127,14,1,8.0185546875,128,15,1,7.84765625,59,16,1,7.1435546875,122,17,1,4.9013671875,61,18,1,3.30859375,129,19,1,8.12109375,130,20,1,8.0185546875,60,21,1,3.787109375,-1,22,1,4.935546875,61,23,1,8.0869140625,126,24,1,7.57421875,57,25,1,4.935546875,61,26,1,3.787109375,-1,27,1,10.5888671875,123,28,1,7.4716796875,57,29,1,7.177734375,122,30,1,3.787109375,-1,31,1,7.57421875,57,32,1,7.177734375,122,33,1,7.2802734375,131,34,1,7.6767578125,59,35,1,8.44921875,125]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,132]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试…"],"r":[0,1,15.875486381322958,89,1,1,15.875486381322958,90,2,1,15.875486381322958,89,3,1,15.875486381322958,91,4,1,15.875486381322958,92,5,1,15.875486381322958,93,6,1,15.875486381322958,94,7,1,15.875486381322958,95,8,1,4.1875,-1,9,1,9.453125,96,10,1,9.140625,97,11,1,8.0234375,98,12,1,5.4609375,99,13,1,4.4375,100,14,1,15.875486381322958,101,15,1,15.875486381322958,102,16,1,16.09338521400778,103,17,1,15.875486381322958,104,18,1,15.875486381322958,105,19,1,15.87548638132293,91,20,1,15.875486381322958,92,21,1,12.5625,132]}}
  #|{"textrec":{"g":132,"r":[1302,0,13,5,0,-3,0]}}
  #|{"textrec":{"g":122,"r":[1316,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":123,"r":[1326,0,13,10,-1,-9,0]}}
  #|{"textrec":{"g":124,"r":[1340,0,6,10,0,-9,0]}}
  #|{"textrec":{"g":125,"r":[1347,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":126,"r":[1358,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[1368,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":128,"r":[1379,0,9,11,0,-9,0]}}
  #|{"textrec":{"g":129,"r":[1389,0,5,13,-1,-12,0]}}
  #|{"textrec":{"g":130,"r":[1395,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":131,"r":[1406,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":74,"r":[1416,0,11,11,-1,-9,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,14.076484680175781,62]}}
  #|{"textrec":{"g":64,"r":[1428,0,14,15,0,-12,0]}}
  #|{"textrec":{"g":65,"r":[1443,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":66,"r":[1458,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":67,"r":[1473,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":68,"r":[1489,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":69,"r":[1504,0,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.497894287109375,35,12,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.329673767089844,34,11,1,13.973621368408203,133]}}
  #|{"textrec":{"g":133,"r":[1520,0,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"g":63,"r":[1535,0,8,8,-1,-7,0]}}
  #|{"textrec":{"g":111,"r":[1544,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":112,"r":[1553,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":113,"r":[1560,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":114,"r":[1570,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":115,"r":[1580,0,5,11,-1,-10,0]}}
  #|{"textrec":{"g":116,"r":[1586,0,9,10,-1,-8,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.721336364746094,33,10,1,13.973621368408203,133]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["2b45ffca62dc37ab",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[12,400,0,"显示最近照片"],"r":[0,1,11.918287937743191,134,1,1,11.918287937743191,135,2,1,11.918287937743195,136,3,1,11.918287937743187,137,4,1,11.918287937743187,138,5,1,11.918287937743187,139]}}
  #|{"textrec":{"s":[13,400,0,"照片"],"r":[0,1,12.898832684824903,140,1,1,12.898832684824903,141]}}
  #|{"textrec":{"s":[13,400,0,"文件"],"r":[0,1,12.898832684824903,142,1,1,12.898832684824903,143]}}
  #|{"textrec":{"s":[13,400,0,"Station 文件"],"r":[0,1,8.20751953125,144,1,1,4.646484375,145,2,1,7.0966796875,12,3,1,4.646484375,145,4,1,3.1357421875,146,5,1,7.6044921875,7,6,1,7.50927734375,147,7,1,3.580078125,-1,8,1,12.898832684824903,142,9,1,12.898832684824903,143]}}
  #|{"textrec":{"g":134,"r":[1596,0,13,13,-1,-11,0]}}
  #|{"textrec":{"g":135,"r":[1610,0,13,13,-1,-10,0]}}
  #|{"textrec":{"g":136,"r":[1624,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":137,"r":[1639,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":138,"r":[1654,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":139,"r":[1669,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":140,"r":[1683,0,15,14,-1,-11,0]}}
  #|{"textrec":{"g":141,"r":[1699,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":142,"r":[1714,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":143,"r":[1730,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":144,"r":[1746,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":145,"r":[1757,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":12,"r":[1765,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":146,"r":[1775,0,5,12,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[1781,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":147,"r":[1791,0,8,9,0,-8,0]}}
  #|{"textrec":{"ib":["f9f0734c1a48af9b",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["23c7a61557c7b0d0",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["3a4647b496156c8f",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["b0778cffbc49e979",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["f68dbe6aa56805aa",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"s":[17,700,0,"Station 文件"],"r":[0,1,11.044189453125,148,1,1,6.58251953125,149,2,1,9.591552734375,150,3,1,6.58251953125,149,4,1,4.44921875,151,5,1,10.10205078125,152,6,1,10.230712890625,153,7,1,3.951171875,-1,8,1,16.851167315175104,154,9,1,16.851167315175104,155]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[14,600,0,"所有位置"],"r":[0,1,13.891050583657588,156,1,1,13.891050583657588,157,2,1,13.891050583657588,158,3,1,13.891050583657588,159]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,160,1,1,13.891050583657588,161]}}
  #|{"textrec":{"s":[14,600,0,"添加"],"r":[0,1,13.891050583657588,162,1,1,13.891050583657588,163]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,164,1,1,5.658300518989563,165,2,1,8.93320620059967,166,3,1,9.332013130187988,167,4,1,3.8520312309265137,168,5,1,8.901597261428833,169]}}
  #|{"textrec":{"s":[15,400,0,"主目录"],"r":[0,1,14.883268482490273,170,1,1,14.883268482490273,171,2,1,14.883268482490273,172]}}
  #|{"textrec":{"s":[12,400,0,"/tmp/mbe2e-C/home"],"r":[0,1,3.65625,173,1,1,4.359375,112,2,1,10.44140625,174,3,1,7.32421875,175,4,1,3.65625,173,5,1,10.44140625,174,6,1,7.37109375,176,7,1,6.85546875,177,8,1,7.212890625,178,9,1,6.826171875,177,10,1,5.66015625,179,11,1,8.58984375,180,12,1,3.65625,173,13,1,7.060546875,181,14,1,7.08984375,116,15,1,10.44140625,174,16,1,6.85546875,177]}}
  #|{"textrec":{"s":[15,400,0,"e2e-084051"],"r":[0,1,8.3349609375,86,1,1,8.78173828125,182,2,1,8.29833984375,86,3,1,6.8408203125,183,4,1,9.2138671875,184,5,1,9.345703125,185,6,1,9.4189453125,186,7,1,9.2138671875,184,8,1,9.0380859375,187,9,1,6.7236328125,188]}}
  #|{"textrec":{"s":[12,400,0,"/tmp/mbe2e-C/home/e2e-084051"],"r":[0,1,3.65625,173,1,1,4.359375,112,2,1,10.44140625,174,3,1,7.32421875,175,4,1,3.65625,173,5,1,10.44140625,174,6,1,7.37109375,176,7,1,6.85546875,177,8,1,7.212890625,178,9,1,6.826171875,177,10,1,5.66015625,179,11,1,8.58984375,180,12,1,3.65625,173,13,1,7.060546875,181,14,1,7.08984375,116,15,1,10.44140625,174,16,1,6.85546875,177,17,1,3.65625,173,18,1,6.85546875,177,19,1,7.212890625,178,20,1,6.826171875,177,21,1,5.66015625,179,22,1,7.55859375,189,23,1,7.6640625,190,24,1,7.72265625,191,25,1,7.55859375,189,26,1,7.41796875,192,27,1,5.56640625,193]}}
  #|{"textrec":{"g":148,"r":[1800,0,13,16,-1,-14,0]}}
  #|{"textrec":{"g":149,"r":[1814,0,9,15,-1,-13,0]}}
  #|{"textrec":{"g":150,"r":[1824,0,11,13,-1,-11,0]}}
  #|{"textrec":{"g":151,"r":[1836,0,5,16,0,-15,0]}}
  #|{"textrec":{"g":152,"r":[1842,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":153,"r":[1855,0,11,12,0,-11,0]}}
  #|{"textrec":{"g":154,"r":[1867,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":155,"r":[1887,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":156,"r":[1906,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[1923,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[1939,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[1956,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":164,"r":[1972,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":165,"r":[1983,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":166,"r":[1992,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":167,"r":[2003,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":168,"r":[2015,0,6,14,-1,-13,0]}}
  #|{"textrec":{"g":169,"r":[2022,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":170,"r":[0,20,16,15,-1,-13,0]}}
  #|{"textrec":{"g":171,"r":[17,20,13,16,1,-13,0]}}
  #|{"textrec":{"g":172,"r":[31,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":173,"r":[48,20,6,14,-1,-10,0]}}
  #|{"textrec":{"g":174,"r":[55,20,12,9,-1,-8,0]}}
  #|{"textrec":{"g":175,"r":[68,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":176,"r":[78,20,8,12,0,-10,0]}}
  #|{"textrec":{"g":177,"r":[87,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":178,"r":[97,20,9,11,-1,-10,0]}}
  #|{"textrec":{"g":179,"r":[107,20,7,4,-1,-5,0]}}
  #|{"textrec":{"g":180,"r":[115,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":181,"r":[126,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":182,"r":[135,20,10,13,0,-12,0]}}
  #|{"textrec":{"g":183,"r":[146,20,7,4,0,-6,0]}}
  #|{"textrec":{"g":184,"r":[154,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":185,"r":[166,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":186,"r":[178,20,11,13,-1,-12,0]}}
  #|{"textrec":{"g":187,"r":[190,20,10,14,0,-12,0]}}
  #|{"textrec":{"g":188,"r":[201,20,8,13,-1,-12,0]}}
  #|{"textrec":{"g":189,"r":[210,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":190,"r":[220,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":191,"r":[230,20,10,11,-1,-10,0]}}
  #|{"textrec":{"g":192,"r":[241,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":193,"r":[251,20,7,11,-1,-10,0]}}
  #|{"textrec":{"g":160,"r":[259,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":161,"r":[276,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":162,"r":[292,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":163,"r":[309,20,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["44c3a16b8dbfdba1",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["4de709dc80063c11",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[14,400,0,"所有位置"],"r":[0,1,13.891050583657588,194,1,1,13.891050583657588,195,2,1,13.891050583657588,196,3,1,13.891050583657588,197]}}
  #|{"textrec":{"s":[14,600,0,"studio · e2e-084051"],"r":[0,1,7.5353477001190186,198,1,1,5.349439859390259,199,2,1,8.406018495559692,200,3,1,8.778238296508789,201,4,1,3.663588523864746,202,5,1,8.376516819000244,203,6,1,3.5793075561523438,-1,7,1,6.707664066085357,204,8,1,3.5793075561523438,-1,9,1,8.109573125839233,205,10,1,8.626137018203735,206,11,1,8.086216449737549,205,12,1,6.5656843185424805,207,13,1,9.152839660644531,208,14,1,9.280215740203857,209,15,1,9.24467420578003,210,16,1,9.152839660644531,208,17,1,8.86106562614441,211,18,1,6.724720001220703,212]}}
  #|{"textrec":{"s":[15,400,0,"整个文件夹"],"r":[0,1,14.883268482490273,213,1,1,14.883268482490273,214,2,1,14.883268482490273,215,3,1,14.883268482490273,216,4,1,14.88326848249028,217]}}
  #|{"textrec":{"g":194,"r":[325,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":195,"r":[342,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":196,"r":[358,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":197,"r":[375,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":198,"r":[391,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":199,"r":[402,20,7,13,-1,-11,0]}}
  #|{"textrec":{"g":200,"r":[410,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":201,"r":[421,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":202,"r":[432,20,5,13,-1,-12,0]}}
  #|{"textrec":{"g":203,"r":[438,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":204,"r":[449,20,5,6,1,-8,0]}}
  #|{"textrec":{"g":205,"r":[455,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":206,"r":[466,20,10,13,-1,-12,0]}}
  #|{"textrec":{"g":207,"r":[477,20,7,4,0,-6,0]}}
  #|{"textrec":{"g":208,"r":[485,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":209,"r":[497,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[509,20,11,12,-1,-11,0]}}
  #|{"textrec":{"g":211,"r":[521,20,10,13,0,-11,0]}}
  #|{"textrec":{"g":212,"r":[532,20,8,12,-1,-11,0]}}
  #|{"textrec":{"g":213,"r":[541,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":214,"r":[558,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":215,"r":[576,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":216,"r":[594,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":217,"r":[611,20,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["c63576325cefdb0c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[15,400,0,"子文件夹"],"r":[0,1,14.883268482490273,218,1,1,14.883268482490273,215,2,1,14.883268482490273,216,3,1,14.883268482490273,217]}}
  #|{"textrec":{"s":[12,400,0,"05:24"],"r":[0,1,7.55859375,189,1,1,7.41796875,192,2,1,3.591796875,219,3,1,7.18359375,178,4,1,7.634765625,191]}}
  #|{"textrec":{"s":[15,400,0,"小说-e2e.txt"],"r":[0,1,14.883268482490273,220,1,1,14.883268482490273,221,2,1,6.8408203125,183,3,1,8.3349609375,86,4,1,8.78173828125,182,5,1,8.29833984375,86,6,1,4.072265625,222,7,1,5.068359375,88,8,1,7.6318359375,223,9,1,5.21484375,88]}}
  #|{"textrec":{"s":[12,400,0,"36 KB · 05:24"],"r":[0,1,7.5234375,224,1,1,7.640625,225,2,1,3.375,-1,3,1,7.904296875,226,4,1,7.88671875,227,5,1,3.375,-1,6,1,5.754933455713626,228,7,1,3.375,-1,8,1,7.55859375,189,9,1,7.41796875,192,10,1,3.591796875,219,11,1,7.18359375,178,12,1,7.634765625,191]}}
  #|{"textrec":{"s":[15,400,0,"说明.txt"],"r":[0,1,14.883268482490273,221,1,1,14.883268482490273,229,2,1,4.072265625,222,3,1,5.068359375,88,4,1,7.6318359375,223,5,1,5.21484375,88]}}
  #|{"textrec":{"s":[12,400,0,"43 B · 05:24"],"r":[0,1,7.72265625,191,1,1,7.5234375,224,2,1,3.375,-1,3,1,7.88671875,227,4,1,3.375,-1,5,1,5.754933455713626,228,6,1,3.375,-1,7,1,7.55859375,189,8,1,7.41796875,192,9,1,3.591796875,219,10,1,7.18359375,178,11,1,7.634765625,191]}}
  #|{"textrec":{"g":218,"r":[628,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":219,"r":[645,20,4,9,0,-7,0]}}
  #|{"textrec":{"g":220,"r":[650,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":221,"r":[668,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":222,"r":[686,20,5,5,0,-3,0]}}
  #|{"textrec":{"g":223,"r":[692,20,10,10,-1,-9,0]}}
  #|{"textrec":{"g":224,"r":[703,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":225,"r":[713,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":226,"r":[723,20,9,11,0,-10,0]}}
  #|{"textrec":{"g":227,"r":[733,20,9,11,0,-10,0]}}
  #|{"textrec":{"g":228,"r":[743,20,5,5,0,-7,0]}}
  #|{"textrec":{"g":229,"r":[749,20,15,16,0,-13,0]}}
  #|{"textrec":{"ib":["94631d87c55eb536",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[14,600,0,"添加 1 个"],"r":[0,1,13.891050583657588,162,1,1,13.891050583657588,163,2,1,3.5793075561523438,-1,3,1,6.768012046813965,212,4,1,3.5793075561523438,-1,5,1,13.891050583657588,230]}}
  #|{"textrec":{"g":230,"r":[765,20,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["e13e77444a4987cd",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[11,400,0,"studio · 路径"],"r":[0,1,5.79541015625,231,1,1,4.03369140625,232,2,1,6.48291015625,233,3,1,6.8212890625,234,4,1,2.7822265625,235,5,1,6.5634765625,236,6,1,3.158203125,-1,7,1,5.2804038549793475,237,8,1,3.158203125,-1,9,1,10.935797665369648,238,10,1,10.935797665369655,239]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"g":231,"r":[782,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":232,"r":[791,20,6,11,-1,-9,0]}}
  #|{"textrec":{"g":233,"r":[798,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":234,"r":[807,20,8,12,-1,-10,0]}}
  #|{"textrec":{"g":235,"r":[816,20,5,11,-1,-10,0]}}
  #|{"textrec":{"g":236,"r":[822,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":237,"r":[831,20,5,4,0,-6,0]}}
  #|{"textrec":{"g":238,"r":[837,20,13,13,-1,-10,0]}}
  #|{"textrec":{"g":239,"r":[851,20,13,13,-1,-10,0]}}
  #|{"textrec":{"ib":["0e8b868650fac0a8",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["50f6cd6f265f8a8c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["9699dbc96b0fdfd9",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,400,0,"看看这个文件 084051"],"r":[0,1,15.875486381322958,240,1,1,15.875486381322958,240,2,1,15.875486381322958,241,3,1,15.875486381322958,242,4,1,15.875486381322958,243,5,1,15.875486381322958,244,6,1,4.1875,-1,7,1,9.765625,245,8,1,9.90625,246,9,1,9.984375,247,10,1,9.765625,245,11,1,9.578125,248,12,1,7.109375,249]}}
  #|{"textrec":{"g":240,"r":[865,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":241,"r":[883,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":242,"r":[901,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":243,"r":[920,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":244,"r":[938,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":245,"r":[956,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":246,"r":[968,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":247,"r":[980,20,12,14,-1,-13,0]}}
  #|{"textrec":{"g":248,"r":[993,20,10,15,0,-13,0]}}
  #|{"textrec":{"g":249,"r":[1004,20,7,14,0,-13,0]}}
  #|{"textrec":{"s":[16,400,0,"看看这个文件 084051\nstudio 上的文件：/tmp/mbe2e-C/home/e2e-084051/说明.txt"],"r":[0,1,15.875486381322958,240,1,1,15.875486381322958,240,2,1,15.875486381322958,241,3,1,15.875486381322958,242,4,1,15.875486381322958,243,5,1,15.875486381322958,244,6,1,4.1875,-1,7,1,9.765625,245,8,1,9.90625,246,9,1,9.984375,247,10,1,9.765625,245,11,1,9.578125,248,12,1,7.109375,249,13,1,0,-1,14,1,8.0234375,98,15,1,5.4609375,99,16,1,9.0234375,250,17,1,9.515625,251,18,1,3.640625,252,19,1,9.140625,97,20,1,4.1875,-1,21,1,15.875486381322958,253,22,1,15.875486381322958,93,23,1,15.875486381322958,243,24,1,15.875486381322958,244,25,1,16.093385214007753,254,26,1,4.5625,255,27,1,5.5,99,28,1,13.609375,256,29,1,9.453125,96,30,1,4.5625,255,31,1,13.609375,256,32,1,9.515625,257,33,1,8.828125,109,34,1,9.3046875,258,35,1,8.7890625,109,36,1,7.234375,259,37,1,11.140625,260,38,1,4.5625,255,39,1,9.1015625,261,40,1,9.140625,97,41,1,13.609375,256,42,1,8.828125,109,43,1,4.5625,255,44,1,8.828125,109,45,1,9.3046875,258,46,1,8.7890625,109,47,1,7.234375,259,48,1,9.765625,245,49,1,9.90625,246,50,1,9.984375,247,51,1,9.765625,245,52,1,9.578125,248,53,1,7.109375,249,54,1,6.5625,255,55,1,15.875486381322958,262,56,1,15.875486381322958,263,57,1,4.28125,264,58,1,5.34375,99,59,1,8.078125,265,60,1,5.5,99]}}
  #|{"textrec":{"g":250,"r":[1012,20,10,12,0,-10,0]}}
  #|{"textrec":{"g":251,"r":[1023,20,11,15,-1,-13,0]}}
  #|{"textrec":{"g":252,"r":[1035,20,4,14,0,-13,0]}}
  #|{"textrec":{"g":253,"r":[1040,20,17,16,-1,-14,0]}}
  #|{"textrec":{"g":254,"r":[1058,20,5,11,1,-11,0]}}
  #|{"textrec":{"g":255,"r":[1064,20,7,17,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[1072,20,14,11,0,-10,0]}}
  #|{"textrec":{"g":257,"r":[1087,20,10,15,0,-13,0]}}
  #|{"textrec":{"g":258,"r":[1098,20,10,14,0,-13,0]}}
  #|{"textrec":{"g":259,"r":[1109,20,8,5,0,-7,0]}}
  #|{"textrec":{"g":260,"r":[1118,20,12,15,0,-13,0]}}
  #|{"textrec":{"g":261,"r":[1131,20,10,14,0,-13,0]}}
  #|{"textrec":{"s":[10,400,0,"正在发送"],"r":[0,1,9.941634241245136,266,1,1,9.941634241245136,267,2,1,9.941634241245136,268,3,1,9.941634241245136,269]}}
  #|{"textrec":{"g":262,"r":[1142,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":263,"r":[1161,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":264,"r":[1178,20,5,5,0,-3,0]}}
  #|{"textrec":{"g":265,"r":[1184,20,10,11,-1,-10,0]}}
  #|{"textrec":{"g":266,"r":[1195,20,12,11,-1,-9,0]}}
  #|{"textrec":{"g":267,"r":[1208,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":268,"r":[1221,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":269,"r":[1234,20,12,13,-1,-10,0]}}
  #|{"textrec":{"ib":["abd519d291ad649c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["550a89fdd3627b9e",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["8a3f7c664f10bd54",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["bc56d3e0d751880c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["8702d89573d5efdf",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续："],"r":[0,1,14.883268482490273,270,1,1,14.883268482490273,271,2,1,3.984375,-1,3,1,8.0419921875,84,4,1,8.90625,85,5,1,8.3349609375,86,6,1,8.51806640625,87,7,1,5.21484375,88,8,1,3.984375,-1,9,1,14.883268482490266,272,10,1,14.88326848249028,273,11,1,14.88326848249028,274,12,1,14.88326848249028,275,13,1,14.88326848249028,276,14,1,14.88326848249028,277,15,1,14.88326848249028,278,16,1,15.08754863813229,77,17,1,14.88326848249028,279,18,1,14.88326848249028,280,19,1,14.88326848249028,79,20,1,14.88326848249028,281,21,1,14.88326848249028,282,22,1,14.88326848249028,283,23,1,14.88326848249028,284,24,1,14.88326848249028,285,25,1,14.88326848249028,83,26,1,14.88326848249028,215,27,1,14.88326848249028,286,28,1,15.087548638132319,77,29,1,14.88326848249028,287,30,1,3.984375,-1,31,1,7.58056640625,288,32,1,5.17822265625,88,33,1,8.0419921875,84,34,1,5.21484375,88,35,1,3.4716796875,289,36,1,8.6279296875,290,37,1,8.51806640625,87,38,1,3.984375,-1,39,1,14.88326848249028,291,40,1,14.88326848249028,292,41,1,14.88326848249028,293,42,1,22.38326848249028,294,43,1,4.698443579766547,295,44,1,14.88326848249028,296,45,1,14.88326848249028,297,46,1,14.88326848249028,281,47,1,14.88326848249028,294,48,1,14.88326848249028,298,49,1,14.88326848249028,83,50,1,14.88326848249028,299,51,1,14.88326848249028,300,52,1,6.296206225680976,301,53,1,15.087548638132262,302,54,1,14.88326848249028,277,55,1,14.88326848249028,278,56,1,14.88326848249028,303,57,1,14.88326848249028,304,58,1,14.88326848249028,305,59,1,14.88326848249028,306,60,1,7.587548638132262,307]}}
  #|{"textrec":{"s":[15,400,0,"…"],"r":[0,1,11.8359375,308]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后输出…"],"r":[0,1,14.883268482490273,270,1,1,14.883268482490273,271,2,1,3.984375,-1,3,1,8.0419921875,84,4,1,8.90625,85,5,1,8.3349609375,86,6,1,8.51806640625,87,7,1,5.21484375,88,8,1,3.984375,-1,9,1,14.883268482490266,272,10,1,14.88326848249028,273,11,1,14.88326848249028,274,12,1,14.88326848249028,275,13,1,14.88326848249028,276,14,1,14.88326848249028,277,15,1,14.88326848249028,278,16,1,15.08754863813229,77,17,1,14.88326848249028,279,18,1,14.88326848249028,280,19,1,14.88326848249028,79,20,1,14.88326848249028,281,21,1,14.88326848249028,282,22,1,14.88326848249028,283,23,1,14.88326848249028,284,24,1,14.88326848249028,285,25,1,11.8359375,308]}}
  #|{"textrec":{"g":270,"r":[1247,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":271,"r":[1265,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":272,"r":[1283,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":273,"r":[1300,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":274,"r":[1317,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":275,"r":[1334,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[1352,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":277,"r":[1368,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":278,"r":[1384,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":279,"r":[1401,20,16,16,0,-13,0]}}
  #|{"textrec":{"g":280,"r":[1418,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":281,"r":[1435,20,15,17,0,-14,0]}}
  #|{"textrec":{"g":282,"r":[1451,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":283,"r":[1468,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":284,"r":[1485,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":285,"r":[1503,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":308,"r":[1519,20,12,5,0,-3,0]}}
