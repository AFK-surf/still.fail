// e2e/traces/mark-read.trace, made by scripts/trace.py from 05-mark_read.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_mark_read : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 082947"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792526000}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792525903035.976}
  #|{"in":{"id":1,"ok":null},"w":1792525903157.038}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792525903157.064}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792525903157.073}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792525903158.578}
  #|{"step":"timeout 90000","w":1792525903158.585}
  #|{"step":"answered client.device","w":1792525903158.587}
  #|{"step":"answered client.focus","w":1792525903177.949}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792525903227.539}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792525903227.565}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792525903227.592}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792525903227.607}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DDPX9NNTYBJH47RQA861VH","name":"Dev","role":"owner","created_at":1792525694,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792525694000,"ago":"3 分钟前","full":"10/21 03:48:14","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792525903244.21}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792525903244.229}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DDPX9NNTYBJH47RQA861VH"},"keyed":true},"w":1792525903244.264}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DDPX9NNTYBJH47RQA861VH","mine":false},"keyed":true},"w":1792525903244.28}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DDPX9NNTYBJH47RQA861VH"},"keyed":true},"w":1792525903244.409}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DDPX9NNTYBJH47RQA861VH"},"keyed":true},"w":1792525903244.438}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DDPX9NNTYBJH47RQA861VH"}},"w":1792525903249.9}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792525903249.91}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DDPX9NNTYBJH47RQA861VH"},"keyed":true},"w":1792525903249.917}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"40b04173637ffc1fbad6bc73275216e9552fe09d3beb2e05718e65965bdddc58","code":"VK5-9GT","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792525903262.431}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","id":"6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792525699947,"label":"今天","items":[{"id":"ember:c-bd6c494983","session":"ember:c-bd6c494983","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-bd6c494983","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"b160c4bd-11d8-4ac5-9e1e-e3b6a15c28b2","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792525699843,"endedAt":1792525699952},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-bd6c494983","text":"你好，我是测试用的 agent","createdAt":1792525699947,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792525699947,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792525699947,"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","stationName":"studio","time":{"lastActiveAt":{"at":1792525699947,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-469cfdf3c99c30c0d2","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792525903262.459}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DDPX9NNTYBJH47RQA861VH":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792525903262.479}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792525903262.484}
  #|{"in":{"id":10,"ok":null},"w":1792525903262.486}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792525903262.492}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792525903262.496}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DDPX9NNTYBJH47RQA861VH"},"keyed":true},"w":1792525903262.522}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792525903265.21}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792525903277.542}
  #|{"in":{"id":14,"ok":null},"w":1792525903277.548}
  #|{"step":"answered notify.permission","w":1792525903277.765}
  #|{"step":"until 端到端测试","w":1792525903294.374}
  #|{"step":"log do: peer send 再问一次 post:这一条应当显示为未读 082947","w":1792525903294.398}
  #|{"step":"peer send 再问一次 post:这一条应当显示为未读 082947"}
  #|{"step":"done 1-peer","w":1792525903294.402}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792525905544.288}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792525905544.374}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 · 3 秒","items":[{"state":"slow","text":"studio 打开实时更新","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792525906210.888}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 · 3 秒","items":[{"state":"slow","text":"studio 打开实时更新","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792525906210.91}
  #|{"step":"until =这一条应当显示为未读 082947","w":1792525906227.873}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792525906260.888}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792525906260.906}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"put":{"daysAgo":0,"at":1792525906159,"label":"今天","items":[{"id":"ember:c-bd6c494983","session":"ember:c-bd6c494983","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-bd6c494983","runtime":"claude","process":"running","pending":0,"lastTurn":{"id":"dec09ef4-ae61-4801-b54e-9603b69fc80d","kind":"input","startedAt":1792525906193},"agentText":"默认模型","mark":"run","statusText":"进行中","badgeText":"工作中"}],"last":{"seq":3,"authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"再问一次 post:这一条应当显示为未读 082947","createdAt":1792525906159,"by":{"kind":"person","name":"你","mine":true,"id":"alice@example.test","picture":"https://example.test/p.png","label":"你"},"preview":"再问一次 post:这一条应当显示为未读 082947","time":{"createdAt":{"at":1792525906159,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792525906159,"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","stationName":"studio","state":"run","time":{"lastActiveAt":{"at":1792525906159,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","pinned":false,"tone":"busy"}]}},{"path":["glyph","label"],"set":"1 台 station，1 台在线，1 台运行中"},{"path":["glyph","summary"],"set":"studio · 运行中"},{"path":["glyph","working"],"set":1}]},"w":1792525906260.927}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DDPX9NNTYBJH47RQA861VH":{"alert":0,"unread":0,"badge":0,"items":[]}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792525906260.958}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792525906254},{"path":["items"],"key":["station","id"],"patch":["01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","ember:c-bd6c494983"],"ops":[{"path":["agents",0,"lastTurn","declared"],"set":"final"},{"path":["agents",0,"lastTurn","endedAt"],"set":1792525906256},{"path":["agents",0,"lastTurn","ending"],"set":"all_done"},{"path":["agents",0,"lastTurn","need"],"set":"answered the question that was asked"},{"path":["agents",0,"lastTurn","outcome"],"set":"completed"},{"path":["agents",0,"process"],"set":"warm"},{"path":["agents",0,"statusText"],"set":"已完成：answered the question that was asked"},{"path":["agents",0,"badgeText"],"remove":true},{"path":["agents",0,"mark"],"remove":true},{"path":["last","author"],"set":"ember:c-bd6c494983"},{"path":["last","authorKind"],"set":"agent"},{"path":["last","by","kind"],"set":"agent"},{"path":["last","by","label"],"set":"agent"},{"path":["last","by","mine"],"set":false},{"path":["last","by","name"],"set":"agent"},{"path":["last","by","runtime"],"set":"claude"},{"path":["last","by","id"],"remove":true},{"path":["last","by","picture"],"remove":true},{"path":["last","createdAt"],"set":1792525906254},{"path":["last","preview"],"set":"这一条应当显示为未读 082947"},{"path":["last","seq"],"set":4},{"path":["last","text"],"set":"这一条应当显示为未读 082947"},{"path":["last","time","createdAt","at"],"set":1792525906254},{"path":["last","authorName"],"remove":true},{"path":["lastActiveAt"],"set":1792525906254},{"path":["time","lastActiveAt","at"],"set":1792525906254},{"path":["tone"],"set":"done"},{"path":["state"],"remove":true}]}]},{"path":["glyph","label"],"set":"1 台 station，1 台在线"},{"path":["glyph","summary"],"set":"studio"},{"path":["glyph","working"],"set":0}]},"w":1792525906377.584}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DDPX9NNTYBJH47RQA861VH":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792525906377.682}
  #|{"step":"tap =这一条应当显示为未读 082947","w":1792525906378.259}
  #|{"step":"tap =这一条应当显示为未读 082947","acted":true,"w":1792525906394.486}
  #|{"out":{"id":15,"subscribe":{"topic":"chat","station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","session":"ember:c-bd6c494983"},"keyed":true},"w":1792525906411.008}
  #|{"out":{"id":16,"call":"draft.get","params":{"key":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9:ember:c-bd6c494983"}},"w":1792525906411.588}
  #|{"step":"answered draft.get","w":1792525906411.764}
  #|{"in":{"id":16,"ok":{"text":"","quotes":[],"files":[],"id":"draft-f15cabd313ab94ca41"}},"w":1792525906427.558}
  #|{"in":{"id":15,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792525699.584000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792525699584,"sessions":[{"thread":1,"session":"ember:c-bd6c494983","connect":"ember","joinedAt":1792525699584}],"last":4,"lastMessage":{"seq":4,"thread":1,"ts":"1792525906.254000","authorKind":"agent","author":"ember:c-bd6c494983","text":"这一条应当显示为未读 082947","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792525906254,"time":{"createdAt":{"at":1792525906254,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}}},"read":0,"unread":2,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792525699584,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-bd6c494983","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"9b9a1bb0-36f2-430c-9861-09a425331911","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-bd6c494983/workspace","running":false,"createdAt":1792525699583,"lastActiveAt":1792525906256,"process":"warm","turns":2,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"dec09ef4-ae61-4801-b54e-9603b69fc80d","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792525906193,"endedAt":1792525906256},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792525699583,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792525906256,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792525906072,"time":{"checkedAt":{"at":1792525906072,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792525699832,"time":{"checkedAt":{"at":1792525699832,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792525699832,"time":{"checkedAt":{"at":1792525699832,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792525699832,"time":{"checkedAt":{"at":1792525699832,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792525699832,"time":{"checkedAt":{"at":1792525699832,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"b160c4bd-11d8-4ac5-9e1e-e3b6a15c28b2","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792525699843,"endedAt":1792525699952},{"id":"dec09ef4-ae61-4801-b54e-9603b69fc80d","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792525906193,"endedAt":1792525906256}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792525699.584000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792525699584,"sessions":[{"thread":1,"session":"ember:c-bd6c494983","connect":"ember","joinedAt":1792525699584}],"last":4,"lastMessage":{"seq":4,"thread":1,"ts":"1792525906.254000","authorKind":"agent","author":"ember:c-bd6c494983","text":"这一条应当显示为未读 082947","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792525906254,"time":{"createdAt":{"at":1792525906254,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}}},"read":0,"unread":2,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792525699584,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792525699.826000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792525699826,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792525699826,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792525699.947000","authorKind":"agent","author":"ember:c-bd6c494983","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792525699947,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-bd6c494983","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792525699947,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},{"seq":3,"thread":1,"ts":"1792525906.159000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"再问一次 post:这一条应当显示为未读 082947","attachments":[],"quotes":[],"createdAt":1792525906159,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792525906159,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}}},{"seq":4,"thread":1,"ts":"1792525906.254000","authorKind":"agent","author":"ember:c-bd6c494983","text":"这一条应当显示为未读 082947","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792525906254,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-bd6c494983","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792525906254,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":4,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792525906427.734}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5DDPX9NNTYBJH47RQA861VH"},"keyed":true},"w":1792525906427.954}
  #|{"out":{"id":18,"subscribe":{"topic":"chatJobs","station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","session":"ember:c-bd6c494983"},"keyed":true},"w":1792525906427.971}
  #|{"out":{"id":19,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792525906427.989}
  #|{"out":{"id":20,"call":"client.focus","params":{"chat":{"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","session":"ember:c-bd6c494983","thread":1,"end":true}}},"w":1792525906433.174}
  #|{"in":{"id":17,"value":[{"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","id":"6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792525701,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792525699832,"time":{"checkedAt":{"at":1792525699832,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DDPX9NNTYBJH47RQA861VH","device":"40b04173637ffc1fbad6bc73275216e9552fe09d3beb2e05718e65965bdddc58"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792525906072,"time":{"checkedAt":{"at":1792525906072,"ago":"刚刚","full":"10/21 03:51:46","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792525699832,"time":{"checkedAt":{"at":1792525699832,"ago":"3 分钟前","full":"10/21 03:48:19","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","workspace":"Dev","workspaceId":"01M5DDPX9NNTYBJH47RQA861VH","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":65368670208,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792525903635},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792525903635},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792525903635},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792525903635},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792525903635}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792525701000,"ago":"3 分钟前","full":"10/21 03:48:21","until":"1 分钟内","past":true}},"joined":false}]},"w":1792525906444.356}
  #|{"in":{"id":18,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792525906444.473}
  #|{"in":{"id":20,"ok":null},"w":1792525906444.482}
  #|{"step":"answered picture","w":1792525906445.772}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5DDPX9NNTYBJH47RQA861VH"],"set":{"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","key":"ember:c-bd6c494983"}}]},"w":1792525906494.243}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DDPX9NNTYBJH47RQA861VH","chat"],"set":{"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","key":"ember:c-bd6c494983"}}]},"w":1792525906494.275}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":65368522752}]},"w":1792525906494.284}
  #|{"in":{"id":17,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.73,"cpuBusy":0.09,"uptimeSec":5268,"memory":{"totalBytes":17179869184,"usedBytes":7735541760,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":65368522752},"emberRssBytes":153155120,"checkedAt":1792525906481,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":9,"left":91,"level":"ok","value":"9%","remaining":"空闲 91%","big":"91","unit":"%","title":"CPU 空闲","total":"负载 7.3","note":"负载 7.3 · Apple M4"},{"label":"内存","short":"内存","percent":45,"left":55,"level":"ok","value":"7.2 GB / 16.0 GB","remaining":"剩 8.8 G","big":"8.8","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":73,"left":27,"level":"ok","value":"剩余 60.9 GB / 228 GB","remaining":"剩 60.9 G","big":"60.9","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 146 MB"}],"usage":"内存 7.2 GB / 16.0 GB · 磁盘 剩余 60.9 GB / 228 GB","emberText":"still.fail 146 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792525906494.308}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":4},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["archiveOffered"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[4,null],"ops":[{"path":["archive"],"set":true},{"path":["archiveCheck"],"set":{"text":"所有 agent 都做完了","recommended":true,"failed":false}}]},{"path":["thread","read"],"set":4},{"path":["thread","unread"],"set":0}]},"w":1792525906627.59}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","ember:c-bd6c494983"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792525906627.654}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DDPX9NNTYBJH47RQA861VH","unread"],"set":0},{"path":["workspaces","01M5DDPX9NNTYBJH47RQA861VH","label"],"remove":true},{"path":["workspaces","01M5DDPX9NNTYBJH47RQA861VH","mineTone"],"remove":true},{"path":["workspaces","01M5DDPX9NNTYBJH47RQA861VH","tone"],"remove":true}]},"w":1792525906627.681}
  #|{"in":{"id":19,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792525906627.701}
  #|{"step":"answered client.focus","w":1792525906645.18}
  #|{"step":"wait 300","w":1792525906661.764}
  #|{"step":"now untiln 2 这一条应当显示为未读 082947","w":1792525906962.066}
  #|{"step":"tap icon:chevron-left","w":1792525906962.152}
  #|{"step":"tap icon:chevron-left","acted":true,"w":1792525906978.938}
  #|{"step":"wait 300","w":1792525906997.246}
  #|{"out":{"id":21,"call":"client.focus","params":{"left":{"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","session":"ember:c-bd6c494983","thread":1}}},"w":1792525907311.902}
  #|{"out":{"id":22,"call":"chat.place","params":{"station":"01M5DDPX9NNTYBJH47RQA861VH/6216a0f065102facf4db89768ab94d5aa0e286e4e54bfab977c08dc83419a8a9","thread":1}},"w":1792525907311.959}
  #|{"out":{"id":15,"unsubscribe":true},"w":1792525907311.993}
  #|{"step":"now answered client.focus","w":1792525907312.709}
  #|{"in":{"id":21,"ok":null},"w":1792525907327.581}
  #|{"in":{"id":22,"ok":null},"w":1792525907327.63}
  #|{"step":"answered chat.place","w":1792525907345.672}
  #|{"step":"until 端到端测试","w":1792525907362.274}
  #|{"step":"rest","w":1792525907362.312}
  #|{"step":"now rest","w":1792525907762.003}
  #|{"step":"","w":1792525907778.921}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
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
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[14,400,0,"再问一次 post:这一条应当显示为未读 082947"],"r":[0,1,13.891050583657588,63,1,1,13.891050583657588,64,2,1,13.891050583657588,65,3,1,13.891050583657588,66,4,1,3.787109375,-1,5,1,8.39453125,67,6,1,8.12109375,68,7,1,7.1435546875,69,8,1,4.9013671875,61,9,1,4.005859375,70,10,1,13.891050583657588,71,11,1,13.891050583657588,65,12,1,13.891050583657574,72,13,1,13.891050583657602,73,14,1,13.891050583657602,74,15,1,13.891050583657602,75,16,1,13.891050583657602,76,17,1,13.891050583657602,77,18,1,13.891050583657602,78,19,1,13.891050583657602,79,20,1,3.787109375,-1,21,1,8.66796875,80,22,1,8.791015625,81,23,1,8.298828125,82,24,1,8.763671875,83,25,1,8.859375,84,26,1,7.8203125,85]}}
  #|{"textrec":{"g":63,"r":[666,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":64,"r":[682,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":65,"r":[697,0,15,4,-1,-7,0]}}
  #|{"textrec":{"g":66,"r":[713,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":67,"r":[730,0,9,13,0,-9,0]}}
  #|{"textrec":{"g":68,"r":[740,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":69,"r":[751,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":70,"r":[761,0,4,10,0,-8,0]}}
  #|{"textrec":{"g":71,"r":[766,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[783,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[800,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":74,"r":[816,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":75,"r":[831,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":76,"r":[847,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":77,"r":[863,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":78,"r":[879,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":79,"r":[895,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":80,"r":[912,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":81,"r":[923,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":82,"r":[935,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":83,"r":[945,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":84,"r":[957,0,11,12,-1,-11,0]}}
  #|{"textrec":{"g":85,"r":[969,0,10,12,-1,-11,0]}}
  #|{"textrec":{"ib":["4d86d66493b1cccd",478,64],"r":[10,10,10,10]}}
  #|{"textrec":{"ib":["02541fc7198938f9",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["6f82c7cbf7569fa3",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["679f302030527791",478,64],"r":[10,10,10,10]}}
  #|{"textrec":{"ib":["300a2f236cf831e5",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a8cb2e2c6d7be6ab",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["2983009ed2b8e490",478,64],"r":[10,10,10,10]}}
  #|{"textrec":{"ib":["a9f7a1b57263ab11",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[14,400,0,"这一条应当显示为未读 082947"],"r":[0,1,13.891050583657588,71,1,1,13.891050583657588,65,2,1,13.891050583657588,72,3,1,13.891050583657588,73,4,1,13.891050583657588,74,5,1,13.891050583657588,75,6,1,13.891050583657588,76,7,1,13.891050583657588,77,8,1,13.891050583657588,78,9,1,13.891050583657588,79,10,1,3.787109375,-1,11,1,8.66796875,80,12,1,8.791015625,81,13,1,8.298828125,82,14,1,8.763671875,83,15,1,8.859375,84,16,1,7.8203125,85]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,86]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11]}}
  #|{"textrec":{"s":[13,500,0,"以下是新消息"],"r":[0,1,12.898832684824903,87,1,1,12.898832684824903,88,2,1,12.898832684824903,89,3,1,12.898832684824903,90,4,1,12.898832684824896,91,5,1,12.898832684824896,92]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,93,1,1,14.883268482490273,94,2,1,14.883268482490273,95,3,1,14.883268482490273,96]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[10,400,0,"3 分钟前"],"r":[0,1,6.38671875,97,1,1,2.9296875,-1,2,1,9.941634241245136,98,3,1,9.941634241245136,99,4,1,9.941634241245133,100]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,101,1,1,14.883268482490273,102,2,1,15.087548638132297,103,3,1,14.883268482490273,104,4,1,14.883268482490266,105,5,1,14.88326848249028,106,6,1,14.88326848249028,107,7,1,14.88326848249028,108,8,1,14.88326848249028,109,9,1,3.984375,-1,10,1,8.0419921875,110,11,1,8.90625,111,12,1,8.3349609375,112,13,1,8.51806640625,113,14,1,5.21484375,114]}}
  #|{"textrec":{"s":[16,400,0,"再问一次 post:这一条应当显示为未读 082947"],"r":[0,1,15.875486381322958,115,1,1,15.875486381322958,116,2,1,15.875486381322958,117,3,1,15.875486381322958,118,4,1,4.1875,-1,5,1,9.453125,119,6,1,9.140625,120,7,1,8.0234375,121,8,1,5.4609375,122,9,1,4.4375,123,10,1,15.875486381322958,124,11,1,15.875486381322958,117,12,1,15.875486381322958,125,13,1,15.875486381322958,126,14,1,15.875486381322958,127,15,1,15.875486381322958,128,16,1,15.875486381322958,129,17,1,15.875486381322958,130,18,1,15.875486381322958,131,19,1,15.875486381322958,132,20,1,4.1875,-1,21,1,9.765625,133,22,1,9.90625,134,23,1,9.34375,135,24,1,9.875,136,25,1,9.984375,137,26,1,8.796875,138]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,139,1,1,9.941634241245136,139]}}
  #|{"textrec":{"s":[15,400,0,"这一条应当显示为未读 082947"],"r":[0,1,14.883268482490273,140,1,1,14.883268482490273,141,2,1,14.883268482490273,142,3,1,14.883268482490273,143,4,1,14.88326848249028,144,5,1,14.88326848249028,145,6,1,14.88326848249028,146,7,1,14.88326848249028,147,8,1,14.88326848249028,148,9,1,14.88326848249028,149,10,1,3.984375,-1,11,1,9.2138671875,150,12,1,9.345703125,151,13,1,8.818359375,152,14,1,9.31640625,153,15,1,9.4189453125,154,16,1,8.3056640625,155]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,156,1,1,15.875486381322958,157,2,1,15.875486381322958,156,3,1,15.875486381322958,158,4,1,15.875486381322958,159,5,1,15.875486381322958,160,6,1,15.875486381322958,161,7,1,15.875486381322958,162,8,1,4.1875,-1,9,1,9.453125,119,10,1,9.140625,120,11,1,8.0234375,121,12,1,5.4609375,122,13,1,4.4375,123,14,1,15.875486381322958,163,15,1,15.875486381322958,164,16,1,16.09338521400778,165,17,1,15.875486381322958,166,18,1,15.875486381322958,167,19,1,15.87548638132293,158,20,1,15.875486381322958,159,21,1,15.875486381322958,168,22,1,15.875486381322958,160,23,1,4.1875,-1,24,1,8.515625,169,25,1,9.4375,170,26,1,8.828125,171,27,1,9.0234375,172,28,1,5.5,122]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,14.076484680175781,62]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,173,1,1,4.330078125,174,2,1,7.001953125,175,3,1,7.37109375,176,4,1,2.96484375,177,5,1,7.08984375,178]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,14.076484680175781,62]}}
  #|{"textrec":{"g":101,"r":[980,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":102,"r":[997,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":103,"r":[1014,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":104,"r":[1020,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":105,"r":[1038,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":106,"r":[1055,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":107,"r":[1072,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":108,"r":[1090,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":109,"r":[1106,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":110,"r":[1122,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":111,"r":[1133,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":112,"r":[1144,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":113,"r":[1155,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":114,"r":[1165,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":140,"r":[1173,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":141,"r":[1190,0,16,4,-1,-7,0]}}
  #|{"textrec":{"g":142,"r":[1207,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":143,"r":[1224,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":144,"r":[1241,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":145,"r":[1256,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":146,"r":[1273,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":147,"r":[1290,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":148,"r":[1306,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":149,"r":[1323,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":150,"r":[1341,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":151,"r":[1353,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1365,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":153,"r":[1376,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[1388,0,11,13,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[1400,0,10,13,-1,-12,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":156,"r":[1411,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":157,"r":[1429,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":158,"r":[1447,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":159,"r":[1465,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":160,"r":[1484,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":161,"r":[1501,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":162,"r":[1519,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":119,"r":[1538,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":120,"r":[1549,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":121,"r":[1561,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":122,"r":[1572,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":123,"r":[1581,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":163,"r":[1587,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":164,"r":[1605,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":165,"r":[1623,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":166,"r":[1630,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":167,"r":[1648,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":168,"r":[1666,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":169,"r":[1683,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":170,"r":[1694,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":171,"r":[1706,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":172,"r":[1718,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":93,"r":[1729,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":94,"r":[1747,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":95,"r":[1765,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":96,"r":[1783,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":115,"r":[1800,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":116,"r":[1818,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":117,"r":[1835,0,17,4,-1,-8,0]}}
  #|{"textrec":{"g":118,"r":[1853,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":124,"r":[1872,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":125,"r":[1890,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":126,"r":[1908,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":127,"r":[1926,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":128,"r":[1942,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":129,"r":[1960,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1978,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":131,"r":[1995,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":132,"r":[2013,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":133,"r":[2032,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":134,"r":[0,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":135,"r":[12,20,10,14,0,-13,0]}}
  #|{"textrec":{"g":136,"r":[23,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":137,"r":[35,20,12,14,-1,-13,0]}}
  #|{"textrec":{"g":138,"r":[48,20,11,14,-1,-13,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,179,1,1,15.875486381322958,180,2,1,15.875486381322958,181]}}
  #|{"textrec":{"g":179,"r":[60,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":180,"r":[78,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":181,"r":[96,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":97,"r":[114,20,8,11,-1,-9,0]}}
  #|{"textrec":{"g":98,"r":[123,20,12,12,-1,-9,0]}}
  #|{"textrec":{"g":99,"r":[136,20,11,12,-1,-9,0]}}
  #|{"textrec":{"g":100,"r":[148,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":139,"r":[161,20,11,11,-1,-9,0]}}
  #|{"textrec":{"g":87,"r":[173,20,14,15,0,-12,0]}}
  #|{"textrec":{"g":88,"r":[188,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":89,"r":[203,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":90,"r":[218,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":91,"r":[234,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":92,"r":[249,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":86,"r":[265,20,8,8,-1,-7,0]}}
  #|{"textrec":{"g":173,"r":[274,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":174,"r":[283,20,6,11,-1,-9,0]}}
  #|{"textrec":{"g":175,"r":[290,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":176,"r":[300,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":177,"r":[310,20,5,11,-1,-10,0]}}
  #|{"textrec":{"g":178,"r":[316,20,9,10,-1,-8,0]}}
  #|{"textrec":{"ib":["2b45ffca62dc37ab",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[12,500,0,"归档"],"r":[0,1,11.918287937743191,182,1,1,11.918287937743191,183]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[14,400,0,"answered the question that was asked"],"r":[0,1,7.57421875,57,1,1,8.0185546875,60,2,1,7.0751953125,69,3,1,10.4521484375,184,4,1,7.7109375,59,5,1,5.0791015625,185,6,1,7.7451171875,59,7,1,8.44921875,186,8,1,3.787109375,-1,9,1,4.935546875,61,10,1,8.0869140625,187,11,1,7.84765625,59,12,1,3.787109375,-1,13,1,8.380859375,188,14,1,8.0185546875,189,15,1,7.84765625,59,16,1,7.1435546875,69,17,1,4.9013671875,61,18,1,3.30859375,190,19,1,8.12109375,68,20,1,8.0185546875,60,21,1,3.787109375,-1,22,1,4.935546875,61,23,1,8.0869140625,187,24,1,7.57421875,57,25,1,4.935546875,61,26,1,3.787109375,-1,27,1,10.5888671875,184,28,1,7.4716796875,57,29,1,7.177734375,69,30,1,3.787109375,-1,31,1,7.57421875,57,32,1,7.177734375,69,33,1,7.2802734375,191,34,1,7.6767578125,59,35,1,8.44921875,186]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,192]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试…"],"r":[0,1,15.875486381322958,156,1,1,15.875486381322958,157,2,1,15.875486381322958,156,3,1,15.875486381322958,158,4,1,15.875486381322958,159,5,1,15.875486381322958,160,6,1,15.875486381322958,161,7,1,15.875486381322958,162,8,1,4.1875,-1,9,1,9.453125,119,10,1,9.140625,120,11,1,8.0234375,121,12,1,5.4609375,122,13,1,4.4375,123,14,1,15.875486381322958,163,15,1,15.875486381322958,164,16,1,16.09338521400778,165,17,1,15.875486381322958,166,18,1,15.875486381322958,167,19,1,15.87548638132293,158,20,1,15.875486381322958,159,21,1,12.5625,192]}}
  #|{"textrec":{"g":192,"r":[326,20,13,5,0,-3,0]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.497894287109375,35,12,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.329673767089844,34,11,1,13.973621368408203,193]}}
  #|{"textrec":{"g":193,"r":[340,20,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.721336364746094,33,10,1,13.973621368408203,193]}}
  #|{"textrec":{"g":184,"r":[355,20,13,10,-1,-9,0]}}
  #|{"textrec":{"g":185,"r":[369,20,6,10,0,-9,0]}}
  #|{"textrec":{"g":186,"r":[376,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":187,"r":[387,20,9,13,0,-12,0]}}
  #|{"textrec":{"g":188,"r":[397,20,10,13,-1,-9,0]}}
  #|{"textrec":{"g":189,"r":[408,20,9,11,0,-9,0]}}
  #|{"textrec":{"g":190,"r":[418,20,5,13,-1,-12,0]}}
  #|{"textrec":{"g":191,"r":[424,20,9,13,0,-12,0]}}
  #|{"textrec":{"ib":["fa5cd9c3d11340b0",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":182,"r":[434,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":183,"r":[448,20,14,14,-1,-11,0]}}
