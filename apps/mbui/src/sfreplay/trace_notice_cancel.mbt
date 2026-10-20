// e2e/traces/notice-cancel.trace, made by scripts/trace.py from 07-notice_cancel.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_notice_cancel : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 083209"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792524496}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792524458472.315}
  #|{"in":{"id":1,"ok":null},"w":1792524458596.506}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792524458596.533}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792524458596.544}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792524458598.038}
  #|{"step":"timeout 90000","w":1792524458598.046}
  #|{"step":"answered client.device","w":1792524458598.048}
  #|{"step":"until 端到端测试","w":1792524458610.277}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792524458659.657}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792524458659.675}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792524458659.698}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792524458659.712}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DC9315VBKXJ81H711B9NEX","name":"Dev","role":"owner","created_at":1792524192,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792524192000,"ago":"4 分钟前","full":"10/21 03:23:12","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":false,"beta":true}]},"w":1792524458676.357}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524458676.381}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524458676.424}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DC9315VBKXJ81H711B9NEX","mine":false},"keyed":true},"w":1792524458676.439}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524458676.572}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524458676.604}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DC9315VBKXJ81H711B9NEX"}},"w":1792524458682.003}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792524458682.013}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524458682.02}
  #|{"in":{"id":4,"delta":[{"path":[0,"loaded"],"set":true}]},"w":1792524458692.989}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"88982d3a718cefa1251315a5600b94e2cbb579962951f5e86379f41281b25a1a","code":"9LD-4LL","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792524458692.999}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","id":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792524196935,"label":"今天","items":[{"id":"ember:c-d046dea6e6","session":"ember:c-d046dea6e6","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-d046dea6e6","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"3fa63eff-5564-4abf-8b36-e15f985356da","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524196845,"endedAt":1792524196938},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-d046dea6e6","text":"你好，我是测试用的 agent","createdAt":1792524196935,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792524196935,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792524196935,"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","stationName":"studio","time":{"lastActiveAt":{"at":1792524196935,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-9ac2ad15b3d7c1c8fb","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792524458693.024}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DC9315VBKXJ81H711B9NEX":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792524458693.042}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524458693.047}
  #|{"in":{"id":10,"ok":null},"w":1792524458693.049}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524458693.057}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524458693.061}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524458693.087}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792524458695.676}
  #|{"step":"log do: peer send 打开就消失 083209 card:看一眼就行 083209|好 083209|不好 083209","w":1792524458698.613}
  #|{"step":"peer send 打开就消失 083209 card:看一眼就行 083209|好 083209|不好 083209"}
  #|{"step":"done 1-peer","w":1792524458698.618}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792524458712.066}
  #|{"in":{"id":14,"ok":null},"w":1792524458712.075}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524460809.741}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524460809.831}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 · 3 秒","items":[{"state":"slow","text":"studio 打开实时更新","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792524461626.353}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 · 3 秒","items":[{"state":"slow","text":"studio 打开实时更新","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792524461626.404}
  #|{"step":"noticed 看一眼就行 083209","w":1792524461660.095}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524461693.035}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524461693.07}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792524461666},{"path":["items"],"key":["station","id"],"patch":["01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","ember:c-d046dea6e6"],"ops":[{"path":["agents",0,"badgeText"],"set":"agent 已暂停，等待处理"},{"path":["agents",0,"lastTurn","about"],"set":{"thread":1,"seq":4,"ts":"1792524461.666000"}},{"path":["agents",0,"lastTurn","declared"],"set":"block"},{"path":["agents",0,"lastTurn","endedAt"],"set":1792524461668},{"path":["agents",0,"lastTurn","ending"],"set":"need_help"},{"path":["agents",0,"lastTurn","id"],"set":"e4306081-d09c-4789-8cdd-0b31a9d81d6b"},{"path":["agents",0,"lastTurn","need"],"set":"看一眼就行 083209"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792524461625},{"path":["agents",0,"mark"],"set":"block"},{"path":["agents",0,"statusText"],"set":"需要你处理：看一眼就行 083209"},{"path":["decision"],"set":{"seq":4,"options":[{"label":"好 083209"},{"label":"不好 083209"}],"card":{"type":"options","options":[{"label":"好 083209"},{"label":"不好 083209"}]},"text":"奏 · 看一眼就行 083209"}},{"path":["last","by","label"],"set":"agent（agent 已暂停，等待处理）"},{"path":["last","by","state"],"set":"block"},{"path":["last","createdAt"],"set":1792524461666},{"path":["last","preview"],"set":"看一眼就行 083209"},{"path":["last","seq"],"set":4},{"path":["last","text"],"set":"看一眼就行 083209"},{"path":["last","time","createdAt","ago"],"set":"刚刚"},{"path":["last","time","createdAt","at"],"set":1792524461666},{"path":["last","time","createdAt","full"],"set":"10/21 03:27:41"},{"path":["lastActiveAt"],"set":1792524461666},{"path":["state"],"set":"block"},{"path":["stateText"],"set":"需要你处理：看一眼就行 083209"},{"path":["time","lastActiveAt","ago"],"set":"刚刚"},{"path":["time","lastActiveAt","at"],"set":1792524461666},{"path":["time","lastActiveAt","full"],"set":"10/21 03:27:41"},{"path":["tone"],"set":"wait"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792524461693.1}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DC9315VBKXJ81H711B9NEX":{"alert":0,"unread":0,"wait":1,"decisions":1,"tone":"wait","label":"1 个待你处理","badge":1,"items":[{"kind":"wait","workspace":"01M5DC9315VBKXJ81H711B9NEX","workspaceName":"Dev","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","stationName":"studio","session":"ember:c-d046dea6e6","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"需要你处理：看一眼就行 083209","seq":4,"seen":false,"at":1792524461666}],"elsewhere":1,"mineTone":"wait"}},"badge":1,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792524461693.18}
  #|{"in":{"id":11,"delta":[{"path":["show"],"append":[{"id":"n-12f25082d3aa7e671e","kind":"wait","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","workspace":"01M5DC9315VBKXJ81H711B9NEX","stationId":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","session":"ember:c-d046dea6e6","thread":1,"seq":4,"title":"端到端测试的对话 post:你好，我是测试用的 agent","body":"待你决定 · 看一眼就行 083209","tag":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643/ember:c-d046dea6e6","url":"/o/01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643/ember%3Ac-d046dea6e6?message=4","at":1792524461689}]}]},"w":1792524461693.195}
  #|{"in":{"id":12,"delta":[{"path":["show"],"append":[{"id":"n-12f25082d3aa7e671e","kind":"wait","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","workspace":"01M5DC9315VBKXJ81H711B9NEX","stationId":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","session":"ember:c-d046dea6e6","thread":1,"seq":4,"title":"端到端测试的对话 post:你好，我是测试用的 agent","body":"待你决定 · 看一眼就行 083209","tag":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643/ember:c-d046dea6e6","url":"/o/01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643/ember%3Ac-d046dea6e6?message=4","at":1792524461689}]}]},"w":1792524461693.204}
  #|{"out":{"id":15,"call":"notice.claim","params":{"id":"n-12f25082d3aa7e671e"}},"w":1792524461693.679}
  #|{"in":{"id":15,"ok":{"show":true}},"w":1792524461709.675}
  #|{"step":"tap 端到端测试","w":1792524461726.511}
  #|{"step":"tap 端到端测试","acted":true,"w":1792524461743.153}
  #|{"out":{"id":16,"subscribe":{"topic":"chat","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","session":"ember:c-d046dea6e6"},"keyed":true},"w":1792524461759.745}
  #|{"out":{"id":17,"call":"draft.get","params":{"key":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643:ember:c-d046dea6e6"}},"w":1792524461760.169}
  #|{"step":"answered client.focus","w":1792524461760.277}
  #|{"in":{"id":17,"ok":{"text":"","quotes":[],"files":[],"id":"draft-8256d00392aca0a8fe"}},"w":1792524461776.346}
  #|{"in":{"id":11,"delta":[{"path":["show"],"set":[]}]},"w":1792524461776.373}
  #|{"in":{"id":12,"delta":[{"path":["show"],"set":[]}]},"w":1792524461776.383}
  #|{"in":{"id":16,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792524196.665000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792524196665,"sessions":[{"thread":1,"session":"ember:c-d046dea6e6","connect":"ember","joinedAt":1792524196680}],"last":4,"lastMessage":{"seq":4,"thread":1,"ts":"1792524461.666000","authorKind":"agent","author":"ember:c-d046dea6e6","text":"看一眼就行 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792524461666,"time":{"createdAt":{"at":1792524461666,"ago":"刚刚","full":"10/21 03:27:41","until":"1 分钟内","past":true}}},"read":0,"unread":2,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792524196665,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-d046dea6e6","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"a8f28830-3244-4b17-a623-58cbf06fb25e","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-d046dea6e6/workspace","running":false,"createdAt":1792524196639,"lastActiveAt":1792524461668,"process":"warm","turns":2,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"e4306081-d09c-4789-8cdd-0b31a9d81d6b","kind":"input","outcome":"completed","declared":"block","ending":"need_help","need":"看一眼就行 083209","about":{"thread":1,"seq":4,"ts":"1792524461.666000"},"startedAt":1792524461625,"endedAt":1792524461668},"statusText":"需要你处理：看一眼就行 083209","tone":"blue","mark":"block","badgeText":"agent 已暂停，等待处理","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792524196639,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792524461668,"ago":"刚刚","full":"10/21 03:27:41","until":"1 分钟内","past":true}}},"status":"block","badge":"block","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524461505,"time":{"checkedAt":{"at":1792524461505,"ago":"刚刚","full":"10/21 03:27:41","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"3fa63eff-5564-4abf-8b36-e15f985356da","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792524196845,"endedAt":1792524196938},{"id":"e4306081-d09c-4789-8cdd-0b31a9d81d6b","kind":"input","outcome":"completed","declared":"block","ending":"need_help","startedAt":1792524461625,"endedAt":1792524461668}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792524196.665000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792524196665,"sessions":[{"thread":1,"session":"ember:c-d046dea6e6","connect":"ember","joinedAt":1792524196680}],"last":4,"lastMessage":{"seq":4,"thread":1,"ts":"1792524461.666000","authorKind":"agent","author":"ember:c-d046dea6e6","text":"看一眼就行 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792524461666,"time":{"createdAt":{"at":1792524461666,"ago":"刚刚","full":"10/21 03:27:41","until":"1 分钟内","past":true}}},"read":0,"unread":2,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792524196665,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792524196.821000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792524196821,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792524196821,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792524196.935000","authorKind":"agent","author":"ember:c-d046dea6e6","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524196935,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-d046dea6e6","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792524196935,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},{"seq":3,"thread":1,"ts":"1792524461.591000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"打开就消失 083209 card:看一眼就行 083209|好 083209|不好 083209","attachments":[],"quotes":[],"createdAt":1792524461591,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792524461591,"ago":"刚刚","full":"10/21 03:27:41","until":"1 分钟内","past":true}}},{"seq":4,"thread":1,"ts":"1792524461.666000","authorKind":"agent","author":"ember:c-d046dea6e6","text":"看一眼就行 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792524461666,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-d046dea6e6","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792524461666,"ago":"刚刚","full":"10/21 03:27:41","until":"1 分钟内","past":true}},"options":[{"label":"好 083209"},{"label":"不好 083209"}],"card":{"assigneeText":"待你决策","type":"options","options":[{"label":"好 083209"},{"label":"不好 083209"}]},"decision":{"resolved":false},"asked":true}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":4,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"decision":{"seq":4,"options":[{"label":"好 083209"},{"label":"不好 083209"}],"card":{"type":"options","options":[{"label":"好 083209"},{"label":"不好 083209"}]},"text":"奏 · 看一眼就行 083209"},"asks":[{"seq":4,"card":true,"mine":true,"text":"看一眼就行 083209"}],"publish":{"may":true,"links":[]}}},"w":1792524461776.503}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5DC9315VBKXJ81H711B9NEX"},"keyed":true},"w":1792524461776.727}
  #|{"out":{"id":19,"subscribe":{"topic":"chatJobs","station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","session":"ember:c-d046dea6e6"},"keyed":true},"w":1792524461776.739}
  #|{"out":{"id":20,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792524461776.754}
  #|{"out":{"id":21,"call":"client.focus","params":{"chat":{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","session":"ember:c-d046dea6e6","thread":1,"end":true}}},"w":1792524461782.581}
  #|{"step":"answered notify.permission","w":1792524461783.128}
  #|{"in":{"id":18,"value":[{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","id":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792524199,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DC9315VBKXJ81H711B9NEX","device":"88982d3a718cefa1251315a5600b94e2cbb579962951f5e86379f41281b25a1a"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524461505,"time":{"checkedAt":{"at":1792524461505,"ago":"刚刚","full":"10/21 03:27:41","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524196838,"time":{"checkedAt":{"at":1792524196838,"ago":"4 分钟前","full":"10/21 03:23:16","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","workspace":"Dev","workspaceId":"01M5DC9315VBKXJ81H711B9NEX","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":68227092480,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792524459073},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792524459073},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524459073},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524459073},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524459073}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792524199000,"ago":"4 分钟前","full":"10/21 03:23:19","until":"1 分钟内","past":true}},"joined":false}]},"w":1792524461793.101}
  #|{"in":{"id":19,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792524461793.186}
  #|{"in":{"id":21,"ok":null},"w":1792524461793.191}
  #|{"step":"answered notice.claim","w":1792524461794.083}
  #|{"step":"answered draft.get","w":1792524461811.444}
  #|{"step":"answered picture","w":1792524461828.804}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5DC9315VBKXJ81H711B9NEX"],"set":{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","key":"ember:c-d046dea6e6"}}]},"w":1792524461843.023}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","chat"],"set":{"station":"01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","key":"ember:c-d046dea6e6"}}]},"w":1792524461843.052}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":68226945024}]},"w":1792524461843.067}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.52,"cpuBusy":0.09,"uptimeSec":3823,"memory":{"totalBytes":17179869184,"usedBytes":8495366144,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":68226940928},"emberRssBytes":153646664,"checkedAt":1792524461823,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":9,"left":91,"level":"ok","value":"9%","remaining":"空闲 91%","big":"91","unit":"%","title":"CPU 空闲","total":"负载 15.2","note":"负载 15.2 · Apple M4"},{"label":"内存","short":"内存","percent":49,"left":51,"level":"ok","value":"7.9 GB / 16.0 GB","remaining":"剩 8.1 G","big":"8.1","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":72,"left":28,"level":"ok","value":"剩余 63.5 GB / 228 GB","remaining":"剩 63.5 G","big":"63.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 147 MB"}],"usage":"内存 7.9 GB / 16.0 GB · 磁盘 剩余 63.5 GB / 228 GB","emberText":"still.fail 147 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792524461843.099}
  #|{"in":{"id":16,"delta":[{"path":["agents",0,"threads",0,"read"],"set":4},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["thread","read"],"set":4},{"path":["thread","unread"],"set":0}]},"w":1792524461926.337}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DC9315VBKXJ81H711B9NEX/a4cd177ad3c6c7e3d982590f0fa60772a1ae605bfd8dfd1fa16aa59d52884643","ember:c-d046dea6e6"],"ops":[{"path":["unread"],"set":false}]}]}]},"w":1792524461926.364}
  #|{"in":{"id":8,"delta":[{"path":["badge"],"set":0},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","badge"],"set":0},{"path":["workspaces","01M5DC9315VBKXJ81H711B9NEX","items",0,"seen"],"set":true}]},"w":1792524461926.382}
  #|{"in":{"id":20,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792524461993.06}
  #|{"step":"answered client.focus","w":1792524462010.291}
  #|{"step":"wait 300","w":1792524462027.88}
  #|{"step":"now untiln 2 看一眼就行 083209","w":1792524462344.131}
  #|{"step":"nonotice 看一眼就行 083209","w":1792524462344.194}
  #|{"step":"rest","w":1792524462361.02}
  #|{"step":"now rest","w":1792524462527.763}
  #|{"step":"","w":1792524462544.434}
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
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[14,400,0,"看一眼就行 083209"],"r":[0,1,13.891050583657588,63,1,1,13.891050583657588,64,2,1,13.891050583657588,65,3,1,13.891050583657588,66,4,1,13.891050583657588,67,5,1,3.787109375,-1,6,1,8.66796875,68,7,1,8.791015625,69,8,1,8.626953125,70,9,1,8.298828125,71,10,1,8.66796875,68,11,1,8.763671875,72]}}
  #|{"textrec":{"g":63,"r":[666,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":64,"r":[682,0,15,4,-1,-7,0]}}
  #|{"textrec":{"g":65,"r":[698,0,15,15,0,-12,0]}}
  #|{"textrec":{"g":66,"r":[714,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":67,"r":[731,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":68,"r":[747,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":69,"r":[758,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":70,"r":[770,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":71,"r":[781,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":72,"r":[791,0,11,14,-1,-12,0]}}
  #|{"textrec":{"ib":["5945e93431220f31",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,73]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11]}}
  #|{"textrec":{"s":[13,500,0,"以下是新消息"],"r":[0,1,12.898832684824903,74,1,1,12.898832684824903,75,2,1,12.898832684824903,76,3,1,12.898832684824903,77,4,1,12.898832684824896,78,5,1,12.898832684824896,79]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,80,1,1,14.883268482490273,81,2,1,14.883268482490273,82,3,1,14.883268482490273,83]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[10,400,0,"4 分钟前"],"r":[0,1,6.552734375,84,1,1,2.9296875,-1,2,1,9.941634241245136,85,3,1,9.941634241245136,86,4,1,9.941634241245133,87]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,88,1,1,14.883268482490273,89,2,1,15.087548638132297,90,3,1,14.883268482490273,91,4,1,14.883268482490266,92,5,1,14.88326848249028,93,6,1,14.88326848249028,94,7,1,14.88326848249028,95,8,1,14.88326848249028,96,9,1,3.984375,-1,10,1,8.0419921875,97,11,1,8.90625,98,12,1,8.3349609375,99,13,1,8.51806640625,100,14,1,5.21484375,101]}}
  #|{"textrec":{"s":[16,400,0,"打开就消失 083209 card:看一眼就行 083209|好 083209|不好 083209"],"r":[0,1,15.875486381322958,102,1,1,15.875486381322958,103,2,1,15.875486381322958,104,3,1,15.875486381322958,105,4,1,15.875486381322958,106,5,1,4.1875,-1,6,1,9.765625,107,7,1,9.90625,108,8,1,9.71875,109,9,1,9.34375,110,10,1,9.765625,107,11,1,9.875,111,12,1,4.1875,-1,13,1,8.640625,112,14,1,8.515625,113,15,1,5.6640625,114,16,1,9.3984375,115,17,1,4.4375,116,18,1,15.875486381322958,117,19,1,15.875486381322958,118,20,1,15.875486381322958,119,21,1,15.875486381322958,104,22,1,15.875486381322958,120,23,1,4.1875,-1,24,1,9.765625,107,25,1,9.90625,108,26,1,9.71875,109,27,1,9.34375,110,28,1,9.765625,107,29,1,9.875,111,30,1,5.828125,121,31,1,15.875486381322958,122,32,1,4.1875,-1,33,1,9.765625,107,34,1,9.90625,108,35,1,9.71875,109,36,1,9.34375,110,37,1,9.765625,107,38,1,9.875,111,39,1,5.828125,121,40,1,15.875486381322958,123,41,1,15.875486381322958,122,42,1,4.1875,-1,43,1,9.765625,107,44,1,9.90625,108,45,1,9.71875,109,46,1,9.34375,110,47,1,9.765625,107,48,1,9.875,111]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,124,1,1,9.941634241245136,124]}}
  #|{"textrec":{"s":[15,400,0,"看一眼就行 083209"],"r":[0,1,14.883268482490273,125,1,1,14.883268482490273,126,2,1,14.883268482490273,127,3,1,14.883268482490273,128,4,1,14.88326848249028,129,5,1,3.984375,-1,6,1,9.2138671875,130,7,1,9.345703125,131,8,1,9.169921875,132,9,1,8.818359375,133,10,1,9.2138671875,130,11,1,9.31640625,134]}}
  #|{"textrec":{"s":[13,400,0,"待你决策"],"r":[0,1,12.898832684824903,135,1,1,12.898832684824903,4,2,1,12.898832684824903,136,3,1,12.898832684824903,137]}}
  #|{"textrec":{"s":[15,500,0,"好 083209"],"r":[0,1,14.883268482490273,138,1,1,3.855457305908203,-1,2,1,9.51467514038086,139,3,1,9.649196863174438,140,4,1,9.400899410247803,141,5,1,9.035907983779907,142,6,1,9.514675140380866,139,7,1,9.574241638183594,143]}}
  #|{"textrec":{"m":[15,500,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[15,500,0,"不好 083209"],"r":[0,1,14.883268482490273,144,1,1,14.883268482490273,138,2,1,3.855457305908203,-1,3,1,9.51467514038086,139,4,1,9.649196863174438,140,5,1,9.400899410247803,141,6,1,9.035907983779907,142,7,1,9.51467514038086,139,8,1,9.574241638183594,143]}}
  #|{"textrec":{"s":[12,400,0,"忽略"],"r":[0,1,11.918287937743191,145,1,1,11.918287937743191,146]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,147,1,1,15.875486381322958,148,2,1,15.875486381322958,147,3,1,15.875486381322958,149,4,1,15.875486381322958,150,5,1,15.875486381322958,151,6,1,15.875486381322958,152,7,1,15.875486381322958,153,8,1,4.1875,-1,9,1,9.453125,154,10,1,9.140625,155,11,1,8.0234375,156,12,1,5.4609375,157,13,1,4.4375,116,14,1,15.875486381322958,158,15,1,15.875486381322958,122,16,1,16.09338521400778,159,17,1,15.875486381322958,160,18,1,15.875486381322958,161,19,1,15.87548638132293,149,20,1,15.875486381322958,150,21,1,15.875486381322958,162,22,1,15.875486381322958,151,23,1,4.1875,-1,24,1,8.515625,113,25,1,9.4375,163,26,1,8.828125,164,27,1,9.0234375,165,28,1,5.5,157]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,14.076484680175781,62]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,166,1,1,4.330078125,167,2,1,7.001953125,168,3,1,7.37109375,169,4,1,2.96484375,170,5,1,7.08984375,171]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,14.076484680175781,62]}}
  #|{"textrec":{"g":88,"r":[803,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":89,"r":[820,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":90,"r":[837,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":91,"r":[843,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":92,"r":[861,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":93,"r":[878,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":94,"r":[895,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":95,"r":[913,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":96,"r":[929,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":97,"r":[945,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":98,"r":[956,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":99,"r":[967,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":100,"r":[978,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":101,"r":[988,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":125,"r":[996,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1013,0,16,4,-1,-7,0]}}
  #|{"textrec":{"g":127,"r":[1030,0,16,16,0,-13,0]}}
  #|{"textrec":{"g":128,"r":[1047,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":129,"r":[1064,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1081,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":131,"r":[1093,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":132,"r":[1105,0,10,14,0,-12,0]}}
  #|{"textrec":{"g":133,"r":[1116,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":134,"r":[1127,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":135,"r":[1139,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":4,"r":[1155,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":136,"r":[1170,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":137,"r":[1186,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":145,"r":[1202,0,14,13,-1,-11,0]}}
  #|{"textrec":{"g":146,"r":[1217,0,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["bd8d9582330c77a7",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["7c9b8ed8dd95a6c4",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":147,"r":[1232,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":148,"r":[1250,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":149,"r":[1268,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":150,"r":[1286,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":151,"r":[1305,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":152,"r":[1322,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":153,"r":[1340,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":154,"r":[1359,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":155,"r":[1370,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":156,"r":[1382,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":157,"r":[1393,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":116,"r":[1402,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":158,"r":[1408,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":122,"r":[1426,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":159,"r":[1444,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":160,"r":[1451,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":161,"r":[1469,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":162,"r":[1487,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":113,"r":[1504,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":163,"r":[1515,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":164,"r":[1527,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":165,"r":[1539,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":80,"r":[1550,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":81,"r":[1568,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":82,"r":[1586,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":83,"r":[1604,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":138,"r":[1621,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":139,"r":[1639,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":140,"r":[1651,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[1663,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":142,"r":[1675,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":143,"r":[1686,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":144,"r":[1698,0,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,172,1,1,15.875486381322958,105,2,1,15.875486381322958,173]}}
  #|{"textrec":{"g":172,"r":[1715,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1733,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":173,"r":[1751,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":84,"r":[1769,0,8,10,-1,-9,0]}}
  #|{"textrec":{"g":85,"r":[1778,0,12,12,-1,-9,0]}}
  #|{"textrec":{"g":86,"r":[1791,0,11,12,-1,-9,0]}}
  #|{"textrec":{"g":87,"r":[1803,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":102,"r":[1816,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":103,"r":[1834,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":104,"r":[1852,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1870,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":107,"r":[1888,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":108,"r":[1900,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":109,"r":[1912,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":110,"r":[1924,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":111,"r":[1935,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":112,"r":[1947,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":114,"r":[1959,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":115,"r":[1967,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":117,"r":[1979,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":118,"r":[1997,0,17,4,-1,-8,0]}}
  #|{"textrec":{"g":119,"r":[2015,0,17,17,0,-14,0]}}
  #|{"textrec":{"g":120,"r":[0,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":121,"r":[18,20,4,17,0,-13,0]}}
  #|{"textrec":{"g":123,"r":[23,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":124,"r":[41,20,11,11,-1,-9,0]}}
  #|{"textrec":{"g":74,"r":[53,20,14,15,0,-12,0]}}
  #|{"textrec":{"g":75,"r":[68,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":76,"r":[83,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":77,"r":[98,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":78,"r":[114,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":79,"r":[129,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":73,"r":[145,20,8,8,-1,-7,0]}}
  #|{"textrec":{"g":166,"r":[154,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":167,"r":[163,20,6,11,-1,-9,0]}}
  #|{"textrec":{"g":168,"r":[170,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":169,"r":[180,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":170,"r":[190,20,5,11,-1,-10,0]}}
  #|{"textrec":{"g":171,"r":[196,20,9,10,-1,-8,0]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,174]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,147,1,1,15.875486381322958,148,2,1,15.875486381322958,147,3,1,15.875486381322958,149,4,1,15.875486381322958,150,5,1,15.875486381322958,151,6,1,15.875486381322958,152,7,1,15.875486381322958,153,8,1,4.1875,-1,9,1,9.453125,154,10,1,9.140625,155,11,1,8.0234375,156,12,1,5.4609375,157,13,1,4.4375,116,14,1,15.875486381322958,158,15,1,15.875486381322958,122,16,1,16.09338521400778,159,17,1,15.875486381322958,160,18,1,15.875486381322958,161,19,1,15.87548638132293,149,20,1,15.875486381322958,150,21,1,15.875486381322958,162,22,1,15.875486381322958,151,23,1,12.5625,174]}}
  #|{"textrec":{"g":174,"r":[206,20,13,5,0,-3,0]}}
  #|{"textrec":{"ib":["2b45ffca62dc37ab",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
