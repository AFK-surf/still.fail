// e2e/traces/share.trace, made by scripts/trace.py from 02-share.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_share : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792556121}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792555824085.995}
  #|{"in":{"id":1,"ok":null},"w":1792555824181.855}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792555824181.88}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792555824181.89}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792555824183.346}
  #|{"step":"timeout 90000","w":1792555824183.353}
  #|{"step":"answered client.device","w":1792555824183.356}
  #|{"step":"answered client.focus","w":1792555824199.209}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792555824265.175}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792555824265.228}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792555824265.278}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792555824265.288}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5EAE6J5KXDPTTX2BA4TCN52","name":"Dev","role":"owner","created_at":1792555817,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792555817000,"ago":"刚刚","full":"10/21 12:10:17","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792555824281.849}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792555824281.869}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5EAE6J5KXDPTTX2BA4TCN52"},"keyed":true},"w":1792555824281.916}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5EAE6J5KXDPTTX2BA4TCN52","mine":false},"keyed":true},"w":1792555824281.934}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792555824281.945}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5EAE6J5KXDPTTX2BA4TCN52"},"keyed":true},"w":1792555824282.066}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5EAE6J5KXDPTTX2BA4TCN52"},"keyed":true},"w":1792555824282.102}
  #|{"out":{"id":11,"subscribe":{"topic":"shareIn","scope":"01M5EAE6J5KXDPTTX2BA4TCN52","source":"https://www.youtube.com/watch?v=e2e105609","query":""},"keyed":true},"w":1792555824287.445}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5EAE6J5KXDPTTX2BA4TCN52"}},"w":1792555824290.957}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792555824290.967}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5EAE6J5KXDPTTX2BA4TCN52"},"keyed":true},"w":1792555824290.975}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"a38c3828bfcbc9b5047d0b1197727102ade9627e46779edd92336dc521a2b95b","code":"Q3Z-3MS","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792555824301.183}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","id":"f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792555821774,"label":"今天","items":[{"id":"ember:c-356b8ef7c9","session":"ember:c-356b8ef7c9","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-356b8ef7c9","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"31b4acd7-7903-47b6-8959-ed999249f84a","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792555821703,"endedAt":1792555821777},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-356b8ef7c9","text":"你好，我是测试用的 agent","createdAt":1792555821774,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792555821774,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792555821774,"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","stationName":"studio","time":{"lastActiveAt":{"at":1792555821774,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-8e80575cea32197e5b","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792555824301.217}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792555824301.238}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5EAE6J5KXDPTTX2BA4TCN52":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792555824301.248}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792555824301.258}
  #|{"in":{"id":11,"value":{"site":"youtube.com","items":[{"id":"ember:c-356b8ef7c9","session":"ember:c-356b8ef7c9","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-356b8ef7c9","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"31b4acd7-7903-47b6-8959-ed999249f84a","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792555821703,"endedAt":1792555821777},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-356b8ef7c9","text":"你好，我是测试用的 agent","createdAt":1792555821774,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792555821774,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792555821774,"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","stationName":"studio","time":{"lastActiveAt":{"at":1792555821774,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-8e80575cea32197e5b","pinned":false,"tone":"done"}],"stations":[{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","name":"studio"}],"newOn":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","loading":false}},"w":1792555824301.277}
  #|{"in":{"id":12,"ok":null},"w":1792555824301.293}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792555824301.3}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792555824301.304}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5EAE6J5KXDPTTX2BA4TCN52"},"keyed":true},"w":1792555824301.354}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792555824304.772}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792555824315.17}
  #|{"in":{"id":16,"ok":null},"w":1792555824315.177}
  #|{"step":"#env MBUI_SHARE_TEXT=https://www.youtube.com/watch?v=e2e105609","w":1792555824318.021}
  #|{"step":"#env MBUI_SHARE_TITLE=列表视频105609","w":1792555824318.025}
  #|{"step":"answered notify.permission","w":1792555824318.028}
  #|{"step":"until 发到","w":1792555824332.201}
  #|{"step":"until 列表视频105609","w":1792555824332.209}
  #|{"step":"until 新 chat","w":1792555824332.213}
  #|{"step":"tap 端到端测试","w":1792555824365.504}
  #|{"step":"tap 端到端测试","acted":true,"w":1792555824365.538}
  #|{"out":{"id":17,"call":"shareIn.open","params":{"scope":"01M5EAE6J5KXDPTTX2BA4TCN52","source":"https://www.youtube.com/watch?v=e2e105609","station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","id":"ember:c-356b8ef7c9","title":"列表视频105609"}},"w":1792555824381.954}
  #|{"step":"answered shareIn.open","w":1792555824382.229}
  #|{"in":{"id":17,"ok":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","key":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db:ember:c-356b8ef7c9","session":"ember:c-356b8ef7c9","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent"}},"w":1792555824398.507}
  #|{"in":{"id":11,"delta":[{"path":["kept"],"set":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","id":"ember:c-356b8ef7c9","text":"youtube.com 的链接上次发到这里"}}]},"w":1792555824398.534}
  #|{"out":{"id":18,"subscribe":{"topic":"chat","station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","session":"ember:c-356b8ef7c9"},"keyed":true},"w":1792555824398.585}
  #|{"out":{"id":19,"call":"draft.get","params":{"key":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db:ember:c-356b8ef7c9"}},"w":1792555824399.109}
  #|{"in":{"id":19,"ok":{"text":"","quotes":[],"files":[],"links":[{"url":"https://www.youtube.com/watch?v=e2e105609","title":"列表视频105609","site":"youtube.com"}],"id":"draft-08a7dd945b253e39e7"}},"w":1792555824415.169}
  #|{"in":{"id":18,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792555821.651000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792555821652,"sessions":[{"thread":1,"session":"ember:c-356b8ef7c9","connect":"ember","joinedAt":1792555821652}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792555821.774000","authorKind":"agent","author":"ember:c-356b8ef7c9","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792555821774,"time":{"createdAt":{"at":1792555821774,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792555821652,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-356b8ef7c9","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"f565ae90-f41e-4531-a8fc-0359983d995c","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-356b8ef7c9/workspace","running":false,"createdAt":1792555821650,"lastActiveAt":1792555821777,"process":"warm","turns":1,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"31b4acd7-7903-47b6-8959-ed999249f84a","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792555821703,"endedAt":1792555821777},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792555821650,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792555821777,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792555821564,"time":{"checkedAt":{"at":1792555821564,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792555821680,"time":{"checkedAt":{"at":1792555821680,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792555821680,"time":{"checkedAt":{"at":1792555821680,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792555821680,"time":{"checkedAt":{"at":1792555821680,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792555821680,"time":{"checkedAt":{"at":1792555821680,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"31b4acd7-7903-47b6-8959-ed999249f84a","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792555821703,"endedAt":1792555821777}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792555821.651000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792555821652,"sessions":[{"thread":1,"session":"ember:c-356b8ef7c9","connect":"ember","joinedAt":1792555821652}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792555821.774000","authorKind":"agent","author":"ember:c-356b8ef7c9","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792555821774,"time":{"createdAt":{"at":1792555821774,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792555821652,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792555821.691000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792555821691,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792555821691,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792555821.774000","authorKind":"agent","author":"ember:c-356b8ef7c9","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792555821774,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-356b8ef7c9","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792555821774,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":2,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792555824415.263}
  #|{"out":{"id":20,"subscribe":{"topic":"stations","scope":"01M5EAE6J5KXDPTTX2BA4TCN52"},"keyed":true},"w":1792555824415.376}
  #|{"out":{"id":21,"subscribe":{"topic":"chatJobs","station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","session":"ember:c-356b8ef7c9"},"keyed":true},"w":1792555824415.384}
  #|{"out":{"id":22,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792555824415.395}
  #|{"out":{"id":23,"call":"client.focus","params":{"chat":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","session":"ember:c-356b8ef7c9","thread":1,"end":true}}},"w":1792555824417.874}
  #|{"step":"answered draft.get","w":1792555824418.174}
  #|{"in":{"id":20,"value":[{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","id":"f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792555821,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792555821680,"time":{"checkedAt":{"at":1792555821680,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5EAE6J5KXDPTTX2BA4TCN52","device":"a38c3828bfcbc9b5047d0b1197727102ade9627e46779edd92336dc521a2b95b"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792555821564,"time":{"checkedAt":{"at":1792555821564,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792555821680,"time":{"checkedAt":{"at":1792555821680,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","workspace":"Dev","workspaceId":"01M5EAE6J5KXDPTTX2BA4TCN52","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":39959212032,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792555819430},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792555819430},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792555819430},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792555819430},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792555819430},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792555819430},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792555819430}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[{"path":"/tmp/mbe2e-C/home/e2e-105609","name":"e2e-105609","state":"ok"}],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.46,"cpuBusy":0.28,"uptimeSec":35185,"memory":{"totalBytes":17179869184,"usedBytes":9240428544,"swapUsedBytes":300742083},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":39959580672},"emberRssBytes":159463704,"checkedAt":1792555823312,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 9 小时"],"meters":[{"label":"CPU","short":"CPU","percent":28,"left":72,"level":"ok","value":"28%","remaining":"空闲 72%","big":"72","unit":"%","title":"CPU 空闲","total":"负载 4.6","note":"负载 4.6 · Apple M4"},{"label":"内存","short":"内存","percent":54,"left":46,"level":"ok","value":"8.6 GB / 16.0 GB","remaining":"剩 7.4 G","big":"7.4","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":84,"left":16,"level":"amber","value":"剩余 37.2 GB / 228 GB","remaining":"剩 37.2 G","big":"37.2","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"9 小时"},{"label":"still.fail","value":"进程占用 152 MB"}],"usage":"内存 8.6 GB / 16.0 GB · 磁盘 剩余 37.2 GB / 228 GB","emberText":"still.fail 152 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792555821000,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内","past":true}},"joined":false}]},"w":1792555824431.93}
  #|{"in":{"id":21,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792555824432.013}
  #|{"in":{"id":23,"ok":null},"w":1792555824432.019}
  #|{"step":"answered picture","w":1792555824432.903}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5EAE6J5KXDPTTX2BA4TCN52"],"set":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","key":"ember:c-356b8ef7c9"}}]},"w":1792555824465.17}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5EAE6J5KXDPTTX2BA4TCN52","chat"],"set":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","key":"ember:c-356b8ef7c9"}}]},"w":1792555824465.185}
  #|{"in":{"id":18,"delta":[{"path":["agents",0,"threads",0,"read"],"set":2},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["thread","read"],"set":2},{"path":["thread","unread"],"set":0}]},"w":1792555824481.845}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","ember:c-356b8ef7c9"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792555824481.872}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5EAE6J5KXDPTTX2BA4TCN52","unread"],"set":0},{"path":["workspaces","01M5EAE6J5KXDPTTX2BA4TCN52","label"],"remove":true},{"path":["workspaces","01M5EAE6J5KXDPTTX2BA4TCN52","mineTone"],"remove":true},{"path":["workspaces","01M5EAE6J5KXDPTTX2BA4TCN52","tone"],"remove":true}]},"w":1792555824481.891}
  #|{"in":{"id":22,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792555824598.555}
  #|{"in":{"id":11,"delta":[{"path":["items",0,"archivable"],"set":true},{"path":["items",0,"settled"],"set":true},{"path":["items",0,"stateText"],"set":"已完成：answered the question that was asked"},{"path":["items",0,"unread"],"set":false},{"path":["items",0,"tone"],"remove":true}]},"w":1792555824615.203}
  #|{"step":"answered client.focus","w":1792555824617.76}
  #|{"step":"until youtube.com","w":1792555824634.817}
  #|{"step":"tap icon:arrow-up","w":1792555824634.842}
  #|{"step":"tap icon:arrow-up","acted":true,"w":1792555824634.923}
  #|{"out":{"id":24,"call":"draft.put","params":{"text":"","quotes":[],"files":[],"key":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db:ember:c-356b8ef7c9"}},"w":1792555824648.963}
  #|{"out":{"id":25,"call":"chat.send","params":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","text":"列表视频105609\nhttps://www.youtube.com/watch?v=e2e105609","attachments":[],"quotes":[],"thread":1}},"w":1792555824649.042}
  #|{"step":"answered draft.put","w":1792555824655.998}
  #|{"in":{"id":24,"ok":{"id":"draft-69001808873b76df90"}},"w":1792555824665.287}
  #|{"step":"answered chat.send","w":1792555824682.415}
  #|{"in":{"id":25,"ok":{"seq":3}},"w":1792555824715.178}
  #|{"in":{"id":18,"delta":[{"path":["agents",0,"badge"],"set":"failed"},{"path":["agents",0,"session","badgeText"],"set":"失败，需要处理"},{"path":["agents",0,"session","lastActiveAt"],"set":1792555824672},{"path":["agents",0,"session","lastTurn","endedAt"],"set":1792555824672},{"path":["agents",0,"session","lastTurn","id"],"set":"dd231496-af08-440e-a02e-3c8638e49b35"},{"path":["agents",0,"session","lastTurn","kind"],"set":"nudge"},{"path":["agents",0,"session","lastTurn","startedAt"],"set":1792555824670},{"path":["agents",0,"session","lastTurn","declared"],"remove":true},{"path":["agents",0,"session","lastTurn","ending"],"remove":true},{"path":["agents",0,"session","lastTurn","need"],"remove":true},{"path":["agents",0,"session","mark"],"set":"failed"},{"path":["agents",0,"session","statusText"],"set":"出错：意外停止"},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792555824672},{"path":["agents",0,"session","time","lastActiveAt","full"],"set":"10/21 12:10:24"},{"path":["agents",0,"session","tone"],"set":"red"},{"path":["agents",0,"session","turns"],"set":4},{"path":["agents",0,"status"],"set":"unexpected"},{"path":["agents",0,"threads",0,"last"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","author"],"set":"ember"},{"path":["agents",0,"threads",0,"lastMessage","authorKind"],"set":"ember"},{"path":["agents",0,"threads",0,"lastMessage","authorName"],"set":"still.fail"},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792555824673},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","text"],"set":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work."},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792555824673},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","full"],"set":"10/21 12:10:24"},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792555824.673000"},{"path":["agents",0,"threads",0,"lastMessage","declared"],"remove":true},{"path":["agents",0,"threads",0,"lastMessage","ending"],"remove":true},{"path":["agents",0,"threads",0,"unread"],"set":1},{"path":["agents",0,"turns"],"append":[{"id":"eb145833-d6bb-42d1-afe1-abe88255c2a3","kind":"input","startedAt":1792555824657},{"id":"18324254-fb37-4927-b1cf-04cc73e2db16","kind":"nudge","startedAt":1792555824665},{"id":"dd231496-af08-440e-a02e-3c8638e49b35","kind":"nudge","outcome":"completed","startedAt":1792555824670,"endedAt":1792555824672}]},{"path":["outbox"],"key":["id"],"put":{"id":"out-fc8d314c2e34b8e2bc","text":"列表视频105609\nhttps://www.youtube.com/watch?v=e2e105609","attachments":[],"quotes":[],"createdAt":1792555824650,"state":"sending","seq":3,"time":{"createdAt":{"at":1792555824650,"ago":"刚刚","full":"10/21 12:10:24","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","last"],"set":4},{"path":["thread","lastMessage","author"],"set":"ember"},{"path":["thread","lastMessage","authorKind"],"set":"ember"},{"path":["thread","lastMessage","authorName"],"set":"still.fail"},{"path":["thread","lastMessage","createdAt"],"set":1792555824673},{"path":["thread","lastMessage","seq"],"set":4},{"path":["thread","lastMessage","text"],"set":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work."},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792555824673},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/21 12:10:24"},{"path":["thread","lastMessage","ts"],"set":"1792555824.673000"},{"path":["thread","lastMessage","declared"],"remove":true},{"path":["thread","lastMessage","ending"],"remove":true},{"path":["thread","unread"],"set":1},{"path":["archivable"],"remove":true}]},"w":1792555824715.24}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5EAE6J5KXDPTTX2BA4TCN52":{"alert":1,"unread":0,"tone":"alert","label":"1 个出错","chat":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","key":"ember:c-356b8ef7c9"},"badge":1,"items":[{"kind":"alert","workspace":"01M5EAE6J5KXDPTTX2BA4TCN52","workspaceName":"Dev","station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","stationName":"studio","session":"ember:c-356b8ef7c9","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"出错：意外停止","seen":false,"at":1792555824673}],"mineTone":"alert"}},"badge":1,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792555824715.398}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"put":{"daysAgo":0,"at":1792555824673,"label":"今天","items":[{"id":"ember:c-356b8ef7c9","session":"ember:c-356b8ef7c9","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-356b8ef7c9","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"dd231496-af08-440e-a02e-3c8638e49b35","kind":"nudge","outcome":"completed","startedAt":1792555824670,"endedAt":1792555824672},"agentText":"默认模型","mark":"failed","statusText":"出错：意外停止","badgeText":"失败，需要处理"}],"last":{"seq":4,"authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","createdAt":1792555824673,"by":{"kind":"ember","name":"still.fail","mine":false,"label":"still.fail"},"preview":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","time":{"createdAt":{"at":1792555824673,"ago":"刚刚","full":"10/21 12:10:24","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792555824673,"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","stationName":"studio","state":"failed","time":{"lastActiveAt":{"at":1792555824673,"ago":"刚刚","full":"10/21 12:10:24","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-8e80575cea32197e5b","pinned":false,"stateText":"出错：意外停止","tone":"alert"}]}}]},"w":1792555824715.42}
  #|{"in":{"id":20,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":39958032384}]},"w":1792555824715.444}
  #|{"step":"wait 600","w":1792555824732.316}
  #|{"in":{"id":18,"delta":[{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":4,"thread":1,"ts":"1792555824.673000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792555824673,"mine":false,"system":true,"reportable":true,"by":{"name":"still.fail"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792555824673,"ago":"刚刚","full":"10/21 12:10:24","until":"1 分钟内","past":true}}},"before":null},{"path":["messages"],"key":["seq","outgoing"],"put":{"outgoing":"out-fc8d314c2e34b8e2bc","seq":3,"thread":1,"ts":"1792555824.654000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"列表视频105609\nhttps://www.youtube.com/watch?v=e2e105609","attachments":[],"quotes":[],"createdAt":1792555824654,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792555824654,"ago":"刚刚","full":"10/21 12:10:24","until":"1 分钟内","past":true}}},"before":[4,null]},{"path":["outbox"],"key":["id"],"drop":"out-fc8d314c2e34b8e2bc"}]},"w":1792555824781.868}
  #|{"in":{"id":11,"delta":[{"path":["items",0,"agents",0,"badgeText"],"set":"失败，需要处理"},{"path":["items",0,"agents",0,"lastTurn","endedAt"],"set":1792555824672},{"path":["items",0,"agents",0,"lastTurn","id"],"set":"dd231496-af08-440e-a02e-3c8638e49b35"},{"path":["items",0,"agents",0,"lastTurn","kind"],"set":"nudge"},{"path":["items",0,"agents",0,"lastTurn","startedAt"],"set":1792555824670},{"path":["items",0,"agents",0,"lastTurn","declared"],"remove":true},{"path":["items",0,"agents",0,"lastTurn","ending"],"remove":true},{"path":["items",0,"agents",0,"lastTurn","need"],"remove":true},{"path":["items",0,"agents",0,"mark"],"set":"failed"},{"path":["items",0,"agents",0,"statusText"],"set":"出错：意外停止"},{"path":["items",0,"last","author"],"set":"ember"},{"path":["items",0,"last","authorKind"],"set":"ember"},{"path":["items",0,"last","authorName"],"set":"still.fail"},{"path":["items",0,"last","by","kind"],"set":"ember"},{"path":["items",0,"last","by","label"],"set":"still.fail"},{"path":["items",0,"last","by","name"],"set":"still.fail"},{"path":["items",0,"last","by","runtime"],"remove":true},{"path":["items",0,"last","createdAt"],"set":1792555824673},{"path":["items",0,"last","preview"],"set":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a"},{"path":["items",0,"last","seq"],"set":4},{"path":["items",0,"last","text"],"set":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a"},{"path":["items",0,"last","time","createdAt","at"],"set":1792555824673},{"path":["items",0,"last","time","createdAt","full"],"set":"10/21 12:10:24"},{"path":["items",0,"lastActiveAt"],"set":1792555824673},{"path":["items",0,"state"],"set":"failed"},{"path":["items",0,"stateText"],"set":"出错：意外停止"},{"path":["items",0,"time","lastActiveAt","at"],"set":1792555824673},{"path":["items",0,"time","lastActiveAt","full"],"set":"10/21 12:10:24"},{"path":["items",0,"tone"],"set":"alert"},{"path":["items",0,"unread"],"set":true},{"path":["items",0,"archivable"],"remove":true},{"path":["items",0,"settled"],"remove":true}]},"w":1792555824781.923}
  #|{"in":{"id":20,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":39957897216}]},"w":1792555824781.99}
  #|{"in":{"id":18,"delta":[{"path":["agents",0,"threads",0,"read"],"set":4},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["thread","read"],"set":4},{"path":["thread","unread"],"set":0}]},"w":1792555824831.84}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","ember:c-356b8ef7c9"],"ops":[{"path":["unread"],"set":false}]}]}]},"w":1792555824831.863}
  #|{"in":{"id":9,"delta":[{"path":["badge"],"set":0},{"path":["workspaces","01M5EAE6J5KXDPTTX2BA4TCN52","badge"],"set":0},{"path":["workspaces","01M5EAE6J5KXDPTTX2BA4TCN52","items",0,"seen"],"set":true}]},"w":1792555824831.875}
  #|{"in":{"id":11,"delta":[{"path":["items",0,"unread"],"set":false}]},"w":1792555824898.509}
  #|{"step":"now gone 正在发送","w":1792555825333.059}
  #|{"step":"until 列表视频105609","w":1792555825333.103}
  #|{"step":"back","w":1792555825333.146}
  #|{"step":"back","acted":true,"w":1792555825333.162}
  #|{"step":"answered client.focus","w":1792555825351.97}
  #|{"out":{"id":26,"call":"client.focus","params":{"left":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","session":"ember:c-356b8ef7c9","thread":1}}},"w":1792555825649.619}
  #|{"out":{"id":27,"call":"chat.place","params":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","thread":1}},"w":1792555825649.677}
  #|{"out":{"id":18,"unsubscribe":true},"w":1792555825649.721}
  #|{"in":{"id":26,"ok":null},"w":1792555825665.512}
  #|{"in":{"id":27,"ok":null},"w":1792555825665.577}
  #|{"step":"answered chat.place","w":1792555825683.158}
  #|{"step":"until 端到端测试","w":1792555825699.603}
  #|{"step":"tap icon:folder","w":1792555825699.634}
  #|{"step":"tap icon:folder","acted":true,"w":1792555825699.67}
  #|{"out":{"id":28,"subscribe":{"topic":"workspace","workspace":"01M5EAE6J5KXDPTTX2BA4TCN52"},"keyed":true},"w":1792555825715.817}
  #|{"step":"until =文件","w":1792555825720.523}
  #|{"step":"wait 300","w":1792555825720.552}
  #|{"in":{"id":28,"value":{"id":"01M5EAE6J5KXDPTTX2BA4TCN52","name":"Dev","role":"owner","created_at":1792555817,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792555817}],"stations":[{"id":"f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","name":"studio","emoji":null,"icon":null,"enrolled_at":1792555818,"enrolled_by":"alice","last_seen":1792555821,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792555821000,"ago":"刚刚","full":"10/21 12:10:21","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792555817000,"ago":"刚刚","full":"10/21 12:10:17","until":"1 分钟内"}}}},"w":1792555825731.899}
  #|{"step":"now tap =e2e-105609","w":1792555826032.985}
  #|{"step":"now tap =e2e-105609","acted":true,"w":1792555826033.066}
  #|{"out":{"id":29,"subscribe":{"topic":"drive","station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","root":"/tmp/mbe2e-C/home/e2e-105609","path":""},"keyed":true},"w":1792555826049.259}
  #|{"step":"hold 800 说明.txt","w":1792555826054.563}
  #|{"in":{"id":29,"value":{"path":"","entries":[{"name":"子文件夹","dir":true,"size":0,"mtime":1792555822329,"type":"","kind":"folder","sizeText":"","timeText":"12:10"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792555822344,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"12:10"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792555822329,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"12:10"}],"truncated":false,"folders":1,"files":2,"countText":"1 个文件夹 · 2 个文件"}},"w":1792555826065.22}
  #|{"out":{"id":30,"subscribe":{"topic":"drivePlace","station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","root":"/tmp/mbe2e-C/home/e2e-105609","path":"小说-e2e.txt"},"keyed":true},"w":1792555826067.566}
  #|{"out":{"id":31,"subscribe":{"topic":"drivePlace","station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","root":"/tmp/mbe2e-C/home/e2e-105609","path":"说明.txt"},"keyed":true},"w":1792555826068.326}
  #|{"in":{"id":30,"value":null},"w":1792555826081.86}
  #|{"in":{"id":31,"value":null},"w":1792555826081.895}
  #|{"step":"hold 800 说明.txt","acted":true,"w":1792555826133.015}
  #|{"step":"until 已选 1 项","w":1792555826966.204}
  #|{"step":"tap icon:more","w":1792555826966.284}
  #|{"step":"tap icon:more","acted":true,"w":1792555826966.329}
  #|{"step":"tap 分享","w":1792555826992.32}
  #|{"step":"tap 分享","acted":true,"w":1792555827099.814}
  #|{"out":{"id":32,"call":"drive.read","params":{"station":"01M5EAE6J5KXDPTTX2BA4TCN52/f98fedf088f16662aa3cc54e4014a23d589e3db0115031301cf2814aa2ac98db","root":"/tmp/mbe2e-C/home/e2e-105609","path":"说明.txt","offset":0,"length":4194304}},"w":1792555827115.697}
  #|{"step":"answered drive.read","w":1792555827118.556}
  #|{"in":{"id":32,"ok":{"type":"text/plain; charset=utf-8","total":43,"mtime":1792555822329}},"w":1792555827131.955,"b":"e8bf99e698afe7abafe588b0e7abafe6b58be8af95e794a8e79a84e8afb4e6988ee69687e4bbb6e380820a"}
  #|{"step":"","w":1792555827309.967}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"s":[17,700,0,"列表视频105609"],"r":[0,1,16.851167315175097,18,1,1,16.851167315175097,19,2,1,16.851167315175097,20,3,1,16.851167315175097,21,4,1,10.392578125,22,5,1,11.2060546875,23,6,1,10.844970703125,24,7,1,11.189453125,25,8,1,11.2060546875,23,9,1,11.189453125,26]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[13,400,0,"https://www.youtube.com/watch?v=e2e105609"],"r":[0,1,7.57275390625,27,1,1,4.646484375,28,2,1,4.646484375,28,3,1,7.8583984375,11,4,1,6.728515625,10,5,1,3.783203125,29,6,1,3.884765625,30,7,1,3.884765625,30,8,1,9.9912109375,6,9,1,9.9912109375,6,10,1,9.51513671875,6,11,1,2.8310546875,31,12,1,6.37939453125,32,13,1,7.4775390625,7,14,1,7.50927734375,33,15,1,4.646484375,28,16,1,7.50927734375,33,17,1,7.9091796875,34,18,1,7.3505859375,14,19,1,3.65625,31,20,1,7.0712890625,13,21,1,7.6044921875,7,22,1,11.2353515625,35,23,1,3.884765625,30,24,1,9.89599609375,6,25,1,7.00146484375,12,26,1,4.598876953125,28,27,1,7.150634765625,13,28,1,7.57275390625,27,29,1,6.5888671875,36,30,1,6.7158203125,37,31,1,7.8583984375,38,32,1,7.3505859375,14,33,1,7.73779296875,39,34,1,7.31884765625,14,35,1,5.9541015625,40,36,1,8.1123046875,41,37,1,7.9599609375,42,38,1,8.201171875,43,39,1,8.1123046875,41,40,1,8.201171875,44]}}
  #|{"textrec":{"s":[13,400,0,"发到"],"r":[0,1,12.898832684824903,45,1,1,12.898832684824903,46]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"g":18,"r":[51,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":19,"r":[70,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":20,"r":[89,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":21,"r":[109,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":22,"r":[128,0,8,14,0,-13,0]}}
  #|{"textrec":{"g":23,"r":[137,0,12,16,0,-14,0]}}
  #|{"textrec":{"g":24,"r":[150,0,12,15,0,-13,0]}}
  #|{"textrec":{"g":25,"r":[163,0,12,16,0,-14,0]}}
  #|{"textrec":{"g":26,"r":[176,0,12,16,0,-14,0]}}
  #|{"textrec":{"g":27,"r":[189,0,8,12,0,-11,0]}}
  #|{"textrec":{"g":28,"r":[198,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":11,"r":[206,0,9,12,0,-8,0]}}
  #|{"textrec":{"g":10,"r":[216,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":29,"r":[226,0,4,10,0,-8,0]}}
  #|{"textrec":{"g":30,"r":[231,0,6,15,-1,-11,0]}}
  #|{"textrec":{"g":6,"r":[238,0,12,9,-1,-8,0]}}
  #|{"textrec":{"g":31,"r":[251,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":32,"r":[256,0,9,12,-1,-8,0]}}
  #|{"textrec":{"g":7,"r":[266,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":33,"r":[276,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":34,"r":[286,0,9,13,0,-11,0]}}
  #|{"textrec":{"g":14,"r":[296,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":13,"r":[306,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":35,"r":[316,0,12,9,0,-8,0]}}
  #|{"textrec":{"g":12,"r":[329,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":36,"r":[339,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":37,"r":[348,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":38,"r":[358,0,10,7,-1,-7,0]}}
  #|{"textrec":{"g":39,"r":[369,0,9,12,-1,-11,0]}}
  #|{"textrec":{"g":40,"r":[379,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":41,"r":[387,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":42,"r":[398,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":43,"r":[409,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":44,"r":[420,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":45,"r":[431,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":46,"r":[446,0,14,15,-1,-12,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["858b57fe65cfa80c",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[15,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,47,1,1,14.883268482490273,48,2,1,14.883268482490273,47,3,1,14.883268482490273,49,4,1,14.88326848249028,50,5,1,14.88326848249028,51,6,1,14.88326848249028,52,7,1,14.88326848249028,53,8,1,3.984375,-1,9,1,8.9208984375,54,10,1,8.6279296875,55,11,1,7.58056640625,56,12,1,5.17822265625,57,13,1,4.21875,58,14,1,14.88326848249028,59,15,1,14.88326848249028,60,16,1,15.08754863813229,61,17,1,14.88326848249028,62,18,1,14.88326848249028,63,19,1,14.88326848249028,49,20,1,14.88326848249028,50,21,1,14.88326848249028,64,22,1,14.88326848249028,51,23,1,3.984375,-1,24,1,8.0419921875,65,25,1,8.90625,66,26,1,8.3349609375,67,27,1,8.51806640625,68,28,1,5.21484375,57]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[13,400,0,"你好，我是测试用的 agent"],"r":[0,1,12.898832684824903,4,1,1,12.898832684824903,69,2,1,13.075875486381321,70,3,1,12.898832684824903,71,4,1,12.898832684824903,72,5,1,12.89883268482491,73,6,1,12.898832684824896,74,7,1,12.898832684824896,75,8,1,12.898832684824896,5,9,1,3.580078125,-1,10,1,7.0966796875,12,11,1,7.845703125,76,12,1,7.3505859375,14,13,1,7.50927734375,77,14,1,4.646484375,28]}}
  #|{"textrec":{"s":[15,400,0,"新 chat"],"r":[0,1,14.883268482490273,78,1,1,3.984375,-1,2,1,8.1591796875,79,3,1,8.59130859375,80,4,1,8.0419921875,65,5,1,5.21484375,57]}}
  #|{"textrec":{"s":[13,400,0,"在 studio 上开"],"r":[0,1,12.898832684824903,1,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,28,4,1,7.50927734375,33,5,1,7.9091796875,81,6,1,3.1357421875,82,7,1,7.6044921875,7,8,1,3.580078125,-1,9,1,12.898832684824903,83,10,1,12.89883268482491,84]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,85,1,1,14.883268482490273,86,2,1,14.883268482490273,87,3,1,14.883268482490273,88,4,1,14.88326848249028,89,5,1,14.88326848249028,90]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,91,1,1,14.883268482490273,92]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,93,1,1,15.875486381322958,94,2,1,15.875486381322958,93,3,1,15.875486381322958,95,4,1,15.875486381322958,96,5,1,15.875486381322958,97,6,1,15.875486381322958,98,7,1,15.875486381322958,99,8,1,3.95001220703125,-1,9,1,9.824199676513672,100,10,1,9.432537078857422,101,11,1,8.471200942993164,102,12,1,5.973020553588867,103,13,1,4.952056884765625,104,14,1,15.875486381322958,105,15,1,15.875486381322958,106,16,1,16.09338521400778,107,17,1,15.875486381322958,108,18,1,15.875486381322958,109,19,1,15.87548638132293,95,20,1,15.875486381322958,96,21,1,15.875486381322958,110,22,1,15.875486381322958,97,23,1,3.95001220703125,-1,24,1,8.899068832397461,111,25,1,9.801153182983398,112,26,1,9.127458572387695,113,27,1,9.466253280639648,114,28,1,5.999713897705078,103]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,115,1,1,13.891050583657588,116,2,1,14.081712062256813,117,3,1,13.891050583657588,118,4,1,13.891050583657588,119,5,1,13.891050583657588,120,6,1,13.891050583657588,121,7,1,13.891050583657588,122,8,1,13.891050583657588,123,9,1,3.787109375000014,-1,10,1,7.57421875,124,11,1,8.380859375,125,12,1,7.84765625,126,13,1,8.0185546875,127,14,1,4.935546875,128]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,129]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,93,1,1,15.875486381322958,94,2,1,15.875486381322958,93,3,1,15.875486381322958,95,4,1,15.875486381322958,96,5,1,15.875486381322958,97,6,1,15.875486381322958,98,7,1,15.875486381322958,99,8,1,3.95001220703125,-1,9,1,9.824199676513672,100,10,1,9.432537078857422,101,11,1,8.471200942993164,102,12,1,5.973020553588867,103,13,1,4.952056884765625,104,14,1,15.875486381322958,105,15,1,15.875486381322958,106,16,1,16.09338521400778,107,17,1,15.875486381322958,108,18,1,15.875486381322958,109,19,1,15.87548638132293,95,20,1,15.875486381322958,96,21,1,15.875486381322958,110,22,1,15.875486381322958,97,23,1,14.076484680175781,129]}}
  #|{"textrec":{"s":[15,400,0,"…"],"r":[0,1,11.8359375,130]}}
  #|{"textrec":{"s":[15,400,0,"端到端测试的对话 post:你好，我是测试用的 a…"],"r":[0,1,14.883268482490273,47,1,1,14.883268482490273,48,2,1,14.883268482490273,47,3,1,14.883268482490273,49,4,1,14.88326848249028,50,5,1,14.88326848249028,51,6,1,14.88326848249028,52,7,1,14.88326848249028,53,8,1,3.984375,-1,9,1,8.9208984375,54,10,1,8.6279296875,55,11,1,7.58056640625,56,12,1,5.17822265625,57,13,1,4.21875,58,14,1,14.88326848249028,59,15,1,14.88326848249028,60,16,1,15.08754863813229,61,17,1,14.88326848249028,62,18,1,14.88326848249028,63,19,1,14.88326848249028,49,20,1,14.88326848249028,50,21,1,14.88326848249028,64,22,1,14.88326848249028,51,23,1,3.984375,-1,24,1,8.0419921875,65,25,1,11.8359375,130]}}
  #|{"textrec":{"g":85,"r":[461,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":86,"r":[479,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":87,"r":[496,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":88,"r":[514,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":89,"r":[531,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":90,"r":[547,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":91,"r":[564,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":92,"r":[582,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":93,"r":[600,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":94,"r":[618,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":95,"r":[636,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":96,"r":[654,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":97,"r":[673,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":98,"r":[690,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":99,"r":[708,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":100,"r":[727,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":101,"r":[739,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":102,"r":[751,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":103,"r":[763,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":104,"r":[772,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":105,"r":[778,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[796,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":107,"r":[814,0,6,8,0,-4,0]}}
  #|{"textrec":{"g":108,"r":[821,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":109,"r":[840,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":110,"r":[858,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":129,"r":[875,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":115,"r":[890,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":116,"r":[906,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":117,"r":[923,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":118,"r":[929,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":119,"r":[946,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":120,"r":[962,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":121,"r":[978,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":122,"r":[995,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":123,"r":[1011,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":124,"r":[1026,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":125,"r":[1036,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":126,"r":[1047,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":127,"r":[1058,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":128,"r":[1068,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":47,"r":[1076,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":48,"r":[1093,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":49,"r":[1110,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":50,"r":[1127,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":51,"r":[1145,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":52,"r":[1161,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":53,"r":[1178,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[1196,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":55,"r":[1207,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":56,"r":[1219,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":57,"r":[1230,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":58,"r":[1238,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":59,"r":[1244,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":60,"r":[1261,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":61,"r":[1278,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":62,"r":[1284,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":63,"r":[1302,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":64,"r":[1319,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":65,"r":[1335,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":130,"r":[1346,0,12,5,0,-3,0]}}
  #|{"textrec":{"g":4,"r":[1359,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":69,"r":[1374,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":70,"r":[1390,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":71,"r":[1396,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":72,"r":[1412,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":73,"r":[1427,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":74,"r":[1442,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":75,"r":[1458,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":5,"r":[1473,0,13,15,0,-12,0]}}
  #|{"textrec":{"g":76,"r":[1487,0,9,12,-1,-8,0]}}
  #|{"textrec":{"g":77,"r":[1497,0,8,9,0,-8,0]}}
  #|{"textrec":{"g":78,"r":[1506,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":79,"r":[1524,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":80,"r":[1535,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":1,"r":[1545,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":81,"r":[1560,0,9,13,-1,-11,0]}}
  #|{"textrec":{"g":82,"r":[1570,0,5,12,-1,-11,0]}}
  #|{"textrec":{"g":83,"r":[1576,0,14,14,-1,-12,0]}}
  #|{"textrec":{"g":84,"r":[1591,0,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["acc3b78c444a2e9a",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,131]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11,7.734375,1.6875,0]}}
  #|{"textrec":{"s":[15,400,0,"列表视频105609"],"r":[0,1,14.883268482490273,132,1,1,14.883268482490273,133,2,1,14.883268482490273,134,3,1,14.883268482490273,135,4,1,8.5986328125,136,5,1,9.2138671875,137,6,1,9.0380859375,138,7,1,9.31640625,139,8,1,9.2138671875,137,9,1,9.31640625,140]}}
  #|{"textrec":{"s":[11,400,0,"youtube.com"],"r":[0,1,5.9296875,141,1,1,6.4560546875,142,2,1,6.48291015625,143,3,1,4.060546875,144,4,1,6.48291015625,143,5,1,6.8212890625,145,6,1,6.3486328125,146,7,1,3.22265625,147,8,1,6.1123046875,148,9,1,6.5634765625,142,10,1,9.6357421875,149]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[13,500,0,"以下是新消息"],"r":[0,1,12.898832684824903,150,1,1,12.898832684824903,151,2,1,12.898832684824903,152,3,1,12.898832684824903,153,4,1,12.898832684824896,154,5,1,12.898832684824896,155]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,156,1,1,14.883268482490273,157,2,1,14.883268482490273,158,3,1,14.883268482490273,159]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,160,1,1,9.941634241245136,160]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14,9.66796875,2.109375,0]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,59,1,1,14.883268482490273,60,2,1,15.087548638132297,61,3,1,14.883268482490273,62,4,1,14.883268482490266,63,5,1,14.88326848249028,49,6,1,14.88326848249028,50,7,1,14.88326848249028,64,8,1,14.88326848249028,51,9,1,3.984375,-1,10,1,8.0419921875,65,11,1,8.90625,66,12,1,8.3349609375,67,13,1,8.51806640625,68,14,1,5.21484375,57]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,161,1,1,15.875486381322958,162,2,1,15.875486381322958,161,3,1,15.875486381322958,163,4,1,15.875486381322958,164,5,1,15.875486381322958,165,6,1,15.875486381322958,166,7,1,15.875486381322958,167,8,1,4.1875,-1,9,1,9.453125,168,10,1,9.140625,169,11,1,8.0234375,170,12,1,5.4609375,171,13,1,4.4375,172,14,1,15.875486381322958,173,15,1,15.875486381322958,174,16,1,16.09338521400778,175,17,1,15.875486381322958,176,18,1,15.875486381322958,177,19,1,15.87548638132293,163,20,1,15.875486381322958,164,21,1,15.875486381322958,178,22,1,15.875486381322958,165,23,1,4.1875,-1,24,1,8.515625,179,25,1,9.4375,180,26,1,8.828125,181,27,1,9.0234375,182,28,1,5.5,171]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好…"],"r":[0,1,15.875486381322958,93,1,1,15.875486381322958,94,2,1,15.875486381322958,93,3,1,15.875486381322958,95,4,1,15.875486381322958,96,5,1,15.875486381322958,97,6,1,15.875486381322958,98,7,1,15.875486381322958,99,8,1,3.95001220703125,-1,9,1,9.824199676513672,100,10,1,9.432537078857422,101,11,1,8.471200942993164,102,12,1,5.973020553588867,103,13,1,4.952056884765625,104,14,1,15.875486381322958,105,15,1,15.875486381322958,106,16,1,14.076484680175781,129]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,183,1,1,4.330078125,184,2,1,7.001953125,185,3,1,7.37109375,186,4,1,2.96484375,187,5,1,7.08984375,188]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,93,1,1,15.875486381322958,94,2,1,15.875486381322958,93,3,1,15.875486381322958,95,4,1,15.875486381322958,96,5,1,15.875486381322958,97,6,1,15.875486381322958,98,7,1,15.875486381322958,99,8,1,3.95001220703125,-1,9,1,9.824199676513672,100,10,1,9.432537078857422,101,11,1,8.471200942993164,102,12,1,5.973020553588867,103,13,1,4.952056884765625,104,14,1,14.076484680175781,129]}}
  #|{"textrec":{"g":66,"r":[1606,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":67,"r":[1617,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":68,"r":[1628,0,9,11,0,-10,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,189,1,1,15.875486381322958,190,2,1,15.875486381322958,191]}}
  #|{"textrec":{"g":189,"r":[1638,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":190,"r":[1656,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":191,"r":[1674,0,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":161,"r":[1692,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":162,"r":[1710,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":163,"r":[1728,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":164,"r":[1746,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":165,"r":[1765,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":166,"r":[1782,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":167,"r":[1800,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":168,"r":[1819,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":169,"r":[1830,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":170,"r":[1842,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":171,"r":[1853,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":172,"r":[1862,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":173,"r":[1868,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":174,"r":[1886,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":175,"r":[1904,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":176,"r":[1911,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":177,"r":[1929,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":178,"r":[1947,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":179,"r":[1964,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":180,"r":[1975,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":181,"r":[1987,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":182,"r":[1999,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":156,"r":[2010,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[2028,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[0,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[18,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":132,"r":[35,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":133,"r":[52,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":134,"r":[69,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":135,"r":[87,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":136,"r":[104,20,8,13,-1,-12,0]}}
  #|{"textrec":{"g":137,"r":[113,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":138,"r":[125,20,10,14,0,-12,0]}}
  #|{"textrec":{"g":139,"r":[136,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":140,"r":[148,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[160,20,8,11,-1,-7,0]}}
  #|{"textrec":{"g":142,"r":[169,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":143,"r":[178,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":144,"r":[187,20,6,11,-1,-9,0]}}
  #|{"textrec":{"g":145,"r":[194,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":146,"r":[204,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":147,"r":[213,20,5,5,-1,-3,0]}}
  #|{"textrec":{"g":148,"r":[219,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":149,"r":[228,20,11,8,-1,-7,0]}}
  #|{"textrec":{"s":[12,500,0,"归档"],"r":[0,1,11.918287937743191,192,1,1,11.918287937743191,193]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[14,400,0,"answered the question that was asked"],"r":[0,1,7.57421875,124,1,1,8.0185546875,127,2,1,7.0751953125,194,3,1,10.4521484375,195,4,1,7.7109375,126,5,1,5.0791015625,196,6,1,7.7451171875,126,7,1,8.44921875,197,8,1,3.787109375,-1,9,1,4.935546875,128,10,1,8.0869140625,198,11,1,7.84765625,126,12,1,3.787109375,-1,13,1,8.380859375,199,14,1,8.0185546875,200,15,1,7.84765625,126,16,1,7.1435546875,194,17,1,4.9013671875,128,18,1,3.30859375,201,19,1,8.12109375,202,20,1,8.0185546875,127,21,1,3.787109375,-1,22,1,4.935546875,128,23,1,8.0869140625,198,24,1,7.57421875,124,25,1,4.935546875,128,26,1,3.787109375,-1,27,1,10.5888671875,195,28,1,7.4716796875,124,29,1,7.177734375,194,30,1,3.787109375,-1,31,1,7.57421875,124,32,1,7.177734375,194,33,1,7.2802734375,203,34,1,7.6767578125,126,35,1,8.44921875,197]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,204]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试…"],"r":[0,1,15.875486381322958,161,1,1,15.875486381322958,162,2,1,15.875486381322958,161,3,1,15.875486381322958,163,4,1,15.875486381322958,164,5,1,15.875486381322958,165,6,1,15.875486381322958,166,7,1,15.875486381322958,167,8,1,4.1875,-1,9,1,9.453125,168,10,1,9.140625,169,11,1,8.0234375,170,12,1,5.4609375,171,13,1,4.4375,172,14,1,15.875486381322958,173,15,1,15.875486381322958,174,16,1,16.09338521400778,175,17,1,15.875486381322958,176,18,1,15.875486381322958,177,19,1,15.87548638132293,163,20,1,15.875486381322958,164,21,1,12.5625,204]}}
  #|{"textrec":{"g":204,"r":[240,20,13,5,0,-3,0]}}
  #|{"textrec":{"g":194,"r":[254,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":195,"r":[264,20,13,10,-1,-9,0]}}
  #|{"textrec":{"g":196,"r":[278,20,6,10,0,-9,0]}}
  #|{"textrec":{"g":197,"r":[285,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":198,"r":[296,20,9,13,0,-12,0]}}
  #|{"textrec":{"g":199,"r":[306,20,10,13,-1,-9,0]}}
  #|{"textrec":{"g":200,"r":[317,20,9,11,0,-9,0]}}
  #|{"textrec":{"g":201,"r":[327,20,5,13,-1,-12,0]}}
  #|{"textrec":{"g":202,"r":[333,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":203,"r":[344,20,9,13,0,-12,0]}}
  #|{"textrec":{"g":160,"r":[354,20,11,11,-1,-9,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,93,1,1,15.875486381322958,94,2,1,15.875486381322958,93,3,1,15.875486381322958,95,4,1,15.875486381322958,96,5,1,15.875486381322958,97,6,1,15.875486381322958,98,7,1,15.875486381322958,99,8,1,3.95001220703125,-1,9,1,9.824199676513672,100,10,1,9.432537078857422,101,11,1,8.471200942993164,102,12,1,5.973020553588867,103,13,1,14.076484680175781,129]}}
  #|{"textrec":{"g":150,"r":[366,20,14,15,0,-12,0]}}
  #|{"textrec":{"g":151,"r":[381,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":152,"r":[396,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":153,"r":[411,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[427,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[442,20,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,93,1,1,15.875486381322958,94,2,1,15.875486381322958,93,3,1,15.875486381322958,95,4,1,15.875486381322958,96,5,1,15.875486381322958,97,6,1,15.875486381322958,98,7,1,15.875486381322958,99,8,1,3.95001220703125,-1,9,1,9.824199676513672,100,10,1,9.432537078857422,101,11,1,8.497894287109375,102,12,1,14.076484680175781,129]}}
  #|{"textrec":{"ib":["50f6cd6f265f8a8c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,93,1,1,15.875486381322958,94,2,1,15.875486381322958,93,3,1,15.875486381322958,95,4,1,15.875486381322958,96,5,1,15.875486381322958,97,6,1,15.875486381322958,98,7,1,15.875486381322958,99,8,1,3.95001220703125,-1,9,1,9.824199676513672,100,10,1,9.329673767089844,101,11,1,13.973621368408203,205]}}
  #|{"textrec":{"g":205,"r":[458,20,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"g":131,"r":[473,20,8,8,-1,-7,0]}}
  #|{"textrec":{"g":183,"r":[482,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":184,"r":[491,20,6,11,-1,-9,0]}}
  #|{"textrec":{"g":185,"r":[498,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":186,"r":[508,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":187,"r":[518,20,5,11,-1,-10,0]}}
  #|{"textrec":{"g":188,"r":[524,20,9,10,-1,-8,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,93,1,1,15.875486381322958,94,2,1,15.875486381322958,93,3,1,15.875486381322958,95,4,1,15.875486381322958,96,5,1,15.875486381322958,97,6,1,15.875486381322958,98,7,1,15.875486381322958,99,8,1,3.95001220703125,-1,9,1,9.721336364746094,100,10,1,13.973621368408203,205]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["9699dbc96b0fdfd9",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,400,0,"列表视频105609\nhttps://www.youtube.com/watch?v=e2e105609"],"r":[0,1,15.875486381322958,206,1,1,15.875486381322958,207,2,1,15.875486381322958,208,3,1,15.875486381322958,209,4,1,9.109375,210,5,1,9.765625,211,6,1,9.578125,212,7,1,9.875,213,8,1,9.765625,211,9,1,9.875,214,10,1,0,-1,11,1,9.1015625,215,12,1,5.5,171,13,1,5.5,171,14,1,9.453125,168,15,1,8.0625,170,16,1,4.4375,172,17,1,4.5625,216,18,1,4.5625,216,19,1,12.078125,217,20,1,12.078125,217,21,1,11.4921875,217,22,1,3.265625,218,23,1,7.6328125,219,24,1,8.984375,169,25,1,9.0234375,220,26,1,5.5,171,27,1,9.0234375,220,28,1,9.515625,221,29,1,8.828125,181,30,1,4.28125,218,31,1,8.484375,222,32,1,9.140625,169,33,1,13.609375,223,34,1,4.5625,216,35,1,11.9609375,217,36,1,8.3984375,179,37,1,5.44140625,171,38,1,8.58203125,222,39,1,9.1015625,215,40,1,7.890625,224,41,1,8.046875,225,42,1,9.453125,226,43,1,8.828125,181,44,1,9.3046875,227,45,1,8.7890625,181,46,1,7.109375,210,47,1,9.765625,211,48,1,9.578125,212,49,1,9.875,213,50,1,9.765625,211,51,1,9.875,214]}}
  #|{"textrec":{"g":206,"r":[534,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":207,"r":[552,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":208,"r":[570,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":209,"r":[589,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":210,"r":[607,20,7,14,0,-13,0]}}
  #|{"textrec":{"g":211,"r":[615,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":212,"r":[627,20,10,15,0,-13,0]}}
  #|{"textrec":{"g":213,"r":[638,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":214,"r":[650,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":215,"r":[662,20,10,14,0,-13,0]}}
  #|{"textrec":{"g":216,"r":[673,20,7,17,-1,-13,0]}}
  #|{"textrec":{"g":217,"r":[681,20,14,11,-1,-10,0]}}
  #|{"textrec":{"g":218,"r":[696,20,5,5,0,-3,0]}}
  #|{"textrec":{"g":219,"r":[702,20,11,14,-1,-10,0]}}
  #|{"textrec":{"g":220,"r":[714,20,10,12,0,-10,0]}}
  #|{"textrec":{"g":221,"r":[725,20,10,15,0,-13,0]}}
  #|{"textrec":{"g":222,"r":[736,20,11,12,-1,-10,0]}}
  #|{"textrec":{"g":223,"r":[748,20,14,11,0,-10,0]}}
  #|{"textrec":{"g":224,"r":[763,20,10,15,-1,-13,0]}}
  #|{"textrec":{"ib":["b277602c41d156e7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,400,0,"列表视频105609\n"],"r":[0,1,15.875486381322958,206,1,1,15.875486381322958,207,2,1,15.875486381322958,208,3,1,15.875486381322958,209,4,1,9.109375,210,5,1,9.765625,211,6,1,9.578125,212,7,1,9.875,213,8,1,9.765625,211,9,1,9.875,214,10,1,0,-1]}}
  #|{"textrec":{"s":[16,400,0,"https://www.youtube.com/watch?v=e2e105609"],"r":[0,1,9.1015625,215,1,1,5.5,171,2,1,5.5,171,3,1,9.453125,168,4,1,8.0625,170,5,1,4.4375,172,6,1,4.5625,216,7,1,4.5625,216,8,1,12.078125,217,9,1,12.078125,217,10,1,11.4921875,217,11,1,3.265625,218,12,1,7.6328125,219,13,1,8.984375,169,14,1,9.0234375,220,15,1,5.5,171,16,1,9.0234375,220,17,1,9.515625,221,18,1,8.828125,181,19,1,4.28125,218,20,1,8.484375,222,21,1,9.140625,169,22,1,13.609375,223,23,1,4.5625,216,24,1,11.9609375,217,25,1,8.3984375,179,26,1,5.44140625,171,27,1,8.58203125,222,28,1,9.1015625,215,29,1,7.890625,224,30,1,8.046875,225,31,1,9.453125,226,32,1,8.828125,181,33,1,9.3046875,227,34,1,8.7890625,181,35,1,7.109375,210,36,1,9.765625,211,37,1,9.578125,212,38,1,9.875,213,39,1,9.765625,211,40,1,9.875,214]}}
  #|{"textrec":{"s":[10,400,0,"正在发送"],"r":[0,1,9.941634241245136,228,1,1,9.941634241245136,229,2,1,9.941634241245136,230,3,1,9.941634241245136,231]}}
  #|{"textrec":{"g":225,"r":[774,20,11,11,-1,-10,0]}}
  #|{"textrec":{"g":226,"r":[786,20,11,9,0,-9,0]}}
  #|{"textrec":{"g":227,"r":[798,20,10,14,0,-13,0]}}
  #|{"textrec":{"g":228,"r":[809,20,12,11,-1,-9,0]}}
  #|{"textrec":{"g":229,"r":[822,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":230,"r":[835,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":231,"r":[848,20,12,13,-1,-10,0]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续："],"r":[0,1,14.883268482490273,232,1,1,14.883268482490273,233,2,1,3.984375,-1,3,1,8.0419921875,65,4,1,8.90625,66,5,1,8.3349609375,67,6,1,8.51806640625,68,7,1,5.21484375,57,8,1,3.984375,-1,9,1,14.883268482490266,234,10,1,14.88326848249028,235,11,1,14.88326848249028,52,12,1,14.88326848249028,53,13,1,14.88326848249028,236,14,1,14.88326848249028,237,15,1,14.88326848249028,238,16,1,15.08754863813229,61,17,1,14.88326848249028,239,18,1,14.88326848249028,240,19,1,14.88326848249028,63,20,1,14.88326848249028,241,21,1,14.88326848249028,242,22,1,14.88326848249028,243,23,1,14.88326848249028,244,24,1,14.88326848249028,245,25,1,14.88326848249028,51,26,1,14.88326848249028,246,27,1,14.88326848249028,247,28,1,15.087548638132319,61,29,1,14.88326848249028,248,30,1,3.984375,-1,31,1,7.58056640625,56,32,1,5.17822265625,57,33,1,8.0419921875,65,34,1,5.21484375,57,35,1,3.4716796875,249,36,1,8.6279296875,55,37,1,8.51806640625,68,38,1,3.984375,-1,39,1,14.88326848249028,250,40,1,14.88326848249028,251,41,1,14.88326848249028,252,42,1,22.38326848249028,253,43,1,4.698443579766547,254,44,1,14.88326848249028,255,45,1,14.88326848249028,256,46,1,14.88326848249028,241,47,1,14.88326848249028,253,48,1,14.88326848249028,257,49,1,14.88326848249028,51,50,1,14.88326848249028,258,51,1,14.88326848249028,259,52,1,6.296206225680976,260,53,1,15.087548638132262,261,54,1,14.88326848249028,237,55,1,14.88326848249028,238,56,1,14.88326848249028,262,57,1,14.88326848249028,263,58,1,14.88326848249028,264,59,1,14.88326848249028,265,60,1,7.587548638132262,266]}}
  #|{"textrec":{"s":[15,400,0," · "],"r":[0,1,3.984375,-1,1,1,7.186782927948601,267,2,1,3.984375,-1]}}
  #|{"textrec":{"s":[15,600,0,"上报"],"r":[0,1,14.883268482490273,268,1,1,14.883268482490273,269]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后…"],"r":[0,1,14.883268482490273,232,1,1,14.883268482490273,233,2,1,3.984375,-1,3,1,8.0419921875,65,4,1,8.90625,66,5,1,8.3349609375,67,6,1,8.51806640625,68,7,1,5.21484375,57,8,1,3.984375,-1,9,1,14.883268482490266,234,10,1,14.88326848249028,235,11,1,14.88326848249028,52,12,1,14.88326848249028,53,13,1,14.88326848249028,236,14,1,14.88326848249028,237,15,1,14.88326848249028,238,16,1,15.08754863813229,61,17,1,14.88326848249028,239,18,1,14.88326848249028,240,19,1,14.88326848249028,63,20,1,14.88326848249028,241,21,1,14.88326848249028,242,22,1,14.88326848249028,243,23,1,11.8359375,130]}}
  #|{"textrec":{"g":232,"r":[861,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":233,"r":[879,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":234,"r":[897,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":235,"r":[914,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":236,"r":[931,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":237,"r":[947,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":238,"r":[963,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":239,"r":[980,20,16,16,0,-13,0]}}
  #|{"textrec":{"g":240,"r":[997,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":241,"r":[1014,20,15,17,0,-14,0]}}
  #|{"textrec":{"g":242,"r":[1030,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":243,"r":[1047,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":267,"r":[1064,20,5,5,1,-8,0]}}
  #|{"textrec":{"g":268,"r":[1070,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":269,"r":[1087,20,17,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"出错：意外停止"],"r":[0,1,13.891050583657588,270,1,1,13.891050583657588,271,2,1,14.081712062256813,272,3,1,13.891050583657588,273,4,1,13.891050583657588,274,5,1,13.891050583657588,275,6,1,13.891050583657588,276]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,161,1,1,15.875486381322958,162,2,1,15.875486381322958,161,3,1,15.875486381322958,163,4,1,15.875486381322958,164,5,1,15.875486381322958,165,6,1,15.875486381322958,166,7,1,15.875486381322958,167,8,1,4.1875,-1,9,1,9.453125,168,10,1,9.140625,169,11,1,8.0234375,170,12,1,5.4609375,171,13,1,4.4375,172,14,1,15.875486381322958,173,15,1,15.875486381322958,174,16,1,16.09338521400778,175,17,1,15.875486381322958,176,18,1,15.875486381322958,177,19,1,15.87548638132293,163,20,1,15.875486381322958,164,21,1,15.875486381322958,178,22,1,15.875486381322958,165,23,1,12.5625,204]}}
  #|{"textrec":{"g":270,"r":[1105,20,14,16,0,-13,0]}}
  #|{"textrec":{"g":271,"r":[1120,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":272,"r":[1137,20,5,10,1,-10,0]}}
  #|{"textrec":{"g":273,"r":[1143,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":274,"r":[1160,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":275,"r":[1177,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[1193,20,15,15,-1,-13,0]}}
  #|{"textrec":{"s":[24,700,0,"文件"],"r":[0,1,22.849624060150376,277,1,1,22.849624060150376,278]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,279,1,1,5.658300518989563,280,2,1,8.93320620059967,281,3,1,9.332013130187988,282,4,1,3.8520312309265137,283,5,1,8.901597261428833,284]}}
  #|{"textrec":{"s":[16,400,0,"主目录"],"r":[0,1,15.875486381322958,285,1,1,15.875486381322958,286,2,1,15.875486381322958,287]}}
  #|{"textrec":{"s":[16,400,0,"e2e-105609"],"r":[0,1,8.828125,181,1,1,9.3046875,227,2,1,8.7890625,181,3,1,7.234375,288,4,1,7.109375,210,5,1,9.765625,211,6,1,9.578125,212,7,1,9.875,213,8,1,9.765625,211,9,1,9.875,214]}}
  #|{"textrec":{"g":279,"r":[1209,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":280,"r":[1220,20,8,13,-1,-11,0]}}
  #|{"textrec":{"g":281,"r":[1229,20,10,12,0,-10,0]}}
  #|{"textrec":{"g":282,"r":[1240,20,11,15,-1,-13,0]}}
  #|{"textrec":{"g":283,"r":[1252,20,6,14,-1,-13,0]}}
  #|{"textrec":{"g":284,"r":[1259,20,11,12,-1,-10,0]}}
  #|{"textrec":{"g":285,"r":[1271,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":286,"r":[1289,20,14,16,1,-13,0]}}
  #|{"textrec":{"g":287,"r":[1304,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":288,"r":[1322,20,8,5,0,-7,0]}}
  #|{"textrec":{"g":277,"r":[1331,20,24,24,-1,-20,0]}}
  #|{"textrec":{"g":278,"r":[1356,20,24,24,-1,-20,0]}}
  #|{"textrec":{"ib":["4165e1c325ff4b32",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["7d024a54eca23c07",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["6727d74824d9e7b3",3698,64],"r":[30,30,30,30]}}
  #|{"textrec":{"ib":["e8253a4a9ea8c5de",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[16,600,0,"文件"],"r":[0,1,15.875486381322958,289,1,1,15.875486381322958,290]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,291,1,1,16.851167315175097,292]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[16,600,0,"e2e-105609"],"r":[0,1,9.127458572387695,113,1,1,9.717817306518555,293,2,1,9.100765228271484,113,3,1,7.363014221191406,294,4,1,7.594245910644531,295,5,1,10.31976318359375,296,6,1,10.035783767700195,297,7,1,10.3499755859375,298,8,1,10.31976318359375,296,9,1,10.3499755859375,299]}}
  #|{"textrec":{"s":[17,400,0,"文件"],"r":[0,1,16.851167315175097,300,1,1,16.851167315175097,301]}}
  #|{"textrec":{"g":289,"r":[1381,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":290,"r":[1400,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":291,"r":[1418,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":292,"r":[1438,20,18,17,-1,-14,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[13,400,0,"1 个文件夹 · 2 个文件"],"r":[0,1,5.9541015625,40,1,1,3.580078125,-1,2,1,12.898832684824903,302,3,1,12.898832684824903,303,4,1,12.898832684824903,304,5,1,12.898832684824903,305,6,1,3.580078125,-1,7,1,6.228545204222115,306,8,1,3.580078125,-1,9,1,7.76953125,39,10,1,3.580078125,-1,11,1,12.898832684824896,302,12,1,12.898832684824896,303,13,1,12.898832684824896,304]}}
  #|{"textrec":{"s":[15,400,0,"子文件夹"],"r":[0,1,14.883268482490273,307,1,1,14.883268482490273,246,2,1,14.883268482490273,308,3,1,14.883268482490273,309]}}
  #|{"textrec":{"s":[12,400,0,"12:10"],"r":[0,1,5.56640625,310,1,1,7.2421875,311,2,1,3.5625,312,3,1,5.56640625,310,4,1,7.55859375,313]}}
  #|{"textrec":{"s":[15,400,0,"小说-e2e.txt"],"r":[0,1,14.883268482490273,314,1,1,14.883268482490273,315,2,1,6.8408203125,316,3,1,8.3349609375,67,4,1,8.78173828125,317,5,1,8.29833984375,67,6,1,4.072265625,318,7,1,5.068359375,57,8,1,7.6318359375,319,9,1,5.21484375,57]}}
  #|{"textrec":{"s":[12,400,0,"36 KB · 12:10"],"r":[0,1,7.5234375,320,1,1,7.640625,321,2,1,3.375,-1,3,1,7.904296875,322,4,1,7.88671875,323,5,1,3.375,-1,6,1,5.754933455713626,324,7,1,3.375,-1,8,1,5.56640625,310,9,1,7.2421875,311,10,1,3.5625,312,11,1,5.56640625,310,12,1,7.55859375,313]}}
  #|{"textrec":{"s":[15,400,0,"说明.txt"],"r":[0,1,14.883268482490273,315,1,1,14.883268482490273,325,2,1,4.072265625,318,3,1,5.068359375,57,4,1,7.6318359375,319,5,1,5.21484375,57]}}
  #|{"textrec":{"s":[12,400,0,"43 B · 12:10"],"r":[0,1,7.72265625,326,1,1,7.5234375,320,2,1,3.375,-1,3,1,7.88671875,323,4,1,3.375,-1,5,1,5.754933455713626,324,6,1,3.375,-1,7,1,5.56640625,310,8,1,7.2421875,311,9,1,3.5625,312,10,1,5.56640625,310,11,1,7.55859375,313]}}
  #|{"textrec":{"g":300,"r":[1457,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":301,"r":[1476,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":302,"r":[1495,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[1511,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[1527,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":305,"r":[1543,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[1559,20,4,5,1,-7,0]}}
  #|{"textrec":{"ib":["b17c2fa67cbec771",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["275a1f2a0cb12622",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":307,"r":[1564,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":246,"r":[1581,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":308,"r":[1599,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":309,"r":[1616,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":310,"r":[1633,20,7,11,-1,-10,0]}}
  #|{"textrec":{"g":311,"r":[1641,20,9,11,-1,-10,0]}}
  #|{"textrec":{"g":312,"r":[1651,20,4,9,0,-7,0]}}
  #|{"textrec":{"g":313,"r":[1656,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":314,"r":[1666,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":315,"r":[1684,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":316,"r":[1702,20,7,4,0,-6,0]}}
  #|{"textrec":{"g":317,"r":[1710,20,10,13,0,-12,0]}}
  #|{"textrec":{"g":318,"r":[1721,20,5,5,0,-3,0]}}
  #|{"textrec":{"g":319,"r":[1727,20,10,10,-1,-9,0]}}
  #|{"textrec":{"g":320,"r":[1738,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":321,"r":[1748,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":322,"r":[1758,20,9,11,0,-10,0]}}
  #|{"textrec":{"g":323,"r":[1768,20,9,11,0,-10,0]}}
  #|{"textrec":{"g":324,"r":[1778,20,5,5,0,-7,0]}}
  #|{"textrec":{"g":325,"r":[1784,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":326,"r":[1800,20,10,11,-1,-10,0]}}
  #|{"textrec":{"g":113,"r":[1811,20,11,12,-1,-10,0]}}
  #|{"textrec":{"g":293,"r":[1823,20,11,14,0,-13,0]}}
  #|{"textrec":{"g":294,"r":[1835,20,8,5,0,-7,0]}}
  #|{"textrec":{"g":295,"r":[1844,20,7,14,0,-13,0]}}
  #|{"textrec":{"g":296,"r":[1852,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":297,"r":[1864,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":298,"r":[1876,20,12,15,-1,-13,0]}}
  #|{"textrec":{"g":299,"r":[1889,20,12,15,-1,-13,0]}}
  #|{"textrec":{"ib":["0e910fb4d25445a3",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[16,600,0,"已选 1 项"],"r":[0,1,15.875486381322958,327,1,1,15.875486381322958,328,2,1,3.95001220703125,-1,3,1,7.594245910644531,295,4,1,3.95001220703125,-1,5,1,15.875486381322958,329]}}
  #|{"textrec":{"s":[17,400,0,"取消"],"r":[0,1,16.851167315175097,330,1,1,16.851167315175097,331]}}
  #|{"textrec":{"s":[15,400,0,"全选"],"r":[0,1,14.883268482490273,87,1,1,14.883268482490273,332]}}
  #|{"textrec":{"g":327,"r":[1902,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":328,"r":[1919,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":329,"r":[1937,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":330,"r":[1956,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":331,"r":[1975,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":332,"r":[1994,20,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["d2e044956ae472e7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[17,700,0,"说明.txt"],"r":[0,1,16.851167315175097,333,1,1,16.851167315175097,334,2,1,5.3955078125,335,3,1,6.49951171875,336,4,1,9.43798828125,337,5,1,6.58251953125,336]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,338,1,1,14.883268482490273,339,2,1,14.883268482490273,340]}}
  #|{"textrec":{"s":[15,400,0,"下载"],"r":[0,1,14.883268482490273,240,1,1,14.883268482490273,341]}}
  #|{"textrec":{"s":[15,400,0,"分享"],"r":[0,1,14.883268482490273,342,1,1,14.883268482490273,343]}}
  #|{"textrec":{"s":[15,400,0,"复制路径"],"r":[0,1,14.883268482490273,238,1,1,14.883268482490273,344,2,1,14.883268482490273,345,3,1,14.883268482490273,346]}}
  #|{"textrec":{"s":[15,400,0,"删除"],"r":[0,1,14.883268482490273,347,1,1,14.883268482490273,348]}}
  #|{"textrec":{"g":333,"r":[2011,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":334,"r":[0,45,17,18,0,-15,0]}}
  #|{"textrec":{"g":335,"r":[18,45,6,6,0,-4,0]}}
  #|{"textrec":{"g":336,"r":[25,45,9,15,-1,-13,0]}}
  #|{"textrec":{"g":337,"r":[35,45,12,12,-1,-11,0]}}
  #|{"textrec":{"g":338,"r":[48,45,16,16,-1,-13,0]}}
  #|{"textrec":{"g":339,"r":[65,45,16,16,-1,-13,0]}}
  #|{"textrec":{"g":340,"r":[82,45,15,16,-1,-13,0]}}
  #|{"textrec":{"g":341,"r":[98,45,16,16,-1,-13,0]}}
  #|{"textrec":{"g":342,"r":[115,45,16,16,-1,-13,0]}}
  #|{"textrec":{"g":343,"r":[132,45,16,16,-1,-13,0]}}
  #|{"textrec":{"g":344,"r":[149,45,16,16,-1,-13,0]}}
  #|{"textrec":{"g":345,"r":[166,45,17,16,-1,-13,0]}}
  #|{"textrec":{"g":346,"r":[184,45,17,16,-1,-13,0]}}
  #|{"textrec":{"g":347,"r":[202,45,16,16,-1,-13,0]}}
  #|{"textrec":{"g":348,"r":[219,45,16,16,0,-13,0]}}
  #|{"textrec":{"ib":["e51cacbaf3e3367d",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["5586d6bf44ec35db",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["87df7748e7ef6ab9",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["9a47fa114a34d016",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["0c818ea1c0c4e805",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[11,600,0,"0%"],"r":[0,1,7.374134063720703,349,1,1,11.01141881942749,350]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"g":349,"r":[236,45,9,11,-1,-9,0]}}
  #|{"textrec":{"g":350,"r":[246,45,13,11,-1,-9,0]}}
