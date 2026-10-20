// e2e/traces/lock-wait.trace, made by scripts/trace.py from 01-lock_wait.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_lock_wait : String =
  #|{"step":"peer lock-on"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18950","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792501389}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792501093243.747}
  #|{"in":{"id":1,"ok":null},"w":1792501093329.938}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792501093329.964}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792501093329.975}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792501093331.407}
  #|{"step":"timeout 90000","w":1792501093331.413}
  #|{"step":"answered client.device","w":1792501093331.415}
  #|{"step":"#before peer lock-on","w":1792501093358.928}
  #|{"step":"until 等待批准此设备","w":1792501093358.932}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792501093424.864}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792501093424.895}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792501093424.925}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792501093424.937}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5CP7WSFDHMQHRAHAS90J0ND","name":"Dev","role":"owner","created_at":1792501084,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792501084000,"ago":"刚刚","full":"10/20 20:58:04","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18990","loaded":true,"beta":true}]},"w":1792501093442.605}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792501093442.63}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5CP7WSFDHMQHRAHAS90J0ND"},"keyed":true},"w":1792501093442.669}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5CP7WSFDHMQHRAHAS90J0ND","mine":false},"keyed":true},"w":1792501093442.684}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5CP7WSFDHMQHRAHAS90J0ND"},"keyed":true},"w":1792501093442.814}
  #|{"out":{"id":9,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5CP7WSFDHMQHRAHAS90J0ND"}},"w":1792501093448.755}
  #|{"out":{"id":10,"subscribe":{"topic":"notify"},"keyed":true},"w":1792501093448.771}
  #|{"out":{"id":11,"subscribe":{"topic":"notify","workspace":"01M5CP7WSFDHMQHRAHAS90J0ND"},"keyed":true},"w":1792501093448.778}
  #|{"in":{"id":6,"value":{"available":true,"locked":true,"notice":false,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"eaff05ea260c67dbfb0b396c70f299d5d4d9399c2c9352f0c368cadcc9bb01ce","code":"98B-NPH","kind":"app","confirmed":false,"waiting":true,"asked":false},"signers":1,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","you":true,"devices":[{"id":"fac849f2678c5bce63ec9f74d9723d739f96c5cdd356a41656a57a4db3999cbb","kind":"app","label":"","signs":true,"older":false,"mine":false,"renewSoon":false,"recent":false}]}],"stations":[{"id":"64ff219394019859e5ffb1ade8ee100d237d2d6b092aa1b1c796b2b6bf3cd35e","name":"studio","version":"0.1.0","online":true,"protected":true}],"protected":1,"requests":[],"renew":[],"attention":0}},"w":1792501093458.147}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5CP7WSFDHMQHRAHAS90J0ND/64ff219394019859e5ffb1ade8ee100d237d2d6b092aa1b1c796b2b6bf3cd35e","id":"64ff219394019859e5ffb1ade8ee100d237d2d6b092aa1b1c796b2b6bf3cd35e","name":"studio","state":"offline"}],"loading":false,"days":[{"daysAgo":0,"at":1792501089140,"label":"今天","items":[{"id":"ember:c-b485577fd0","session":"ember:c-b485577fd0","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-b485577fd0","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"6cbd2fc5-8f81-4999-af69-f9c76f5e69aa","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792501089063,"endedAt":1792501089143},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-b485577fd0","text":"你好，我是测试用的 agent","createdAt":1792501089140,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792501089140,"ago":"刚刚","full":"10/20 20:58:09","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792501089140,"station":"01M5CP7WSFDHMQHRAHAS90J0ND/64ff219394019859e5ffb1ade8ee100d237d2d6b092aa1b1c796b2b6bf3cd35e","stationName":"studio","offline":"studio 离线","time":{"lastActiveAt":{"at":1792501089140,"ago":"刚刚","full":"10/20 20:58:09","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-eb04b8342b6a688070","pinned":false,"tone":"done"}]}],"trouble":{"text":"studio 离线","state":"offline","retry":false},"members":1,"leading":"agents","glyph":{"online":0,"dim":1,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，0 台在线，1 台离线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792501093458.187}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5CP7WSFDHMQHRAHAS90J0ND":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792501093458.215}
  #|{"in":{"id":9,"ok":null},"w":1792501093458.221}
  #|{"in":{"id":10,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792501093458.23}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792501093458.235}
  #|{"out":{"id":12,"subscribe":{"topic":"doing"},"keyed":true},"w":1792501093458.266}
  #|{"out":{"id":13,"call":"notify.permission","params":{"state":"unknown"}},"w":1792501093467.1}
  #|{"step":"until 发送批准请求","w":1792501093479.65}
  #|{"step":"log do: peer lock-await 60","w":1792501093479.656}
  #|{"step":"peer lock-await 60"}
  #|{"step":"tap 发送批准请求","w":1792501093479.66}
  #|{"in":{"id":12,"value":{"doing":[]}},"w":1792501093479.727}
  #|{"in":{"id":13,"ok":null},"w":1792501093479.734}
  #|{"step":"tap 发送批准请求","acted":true,"w":1792501093490.683}
  #|{"out":{"id":14,"call":"lock.pair","params":{"workspace":"01M5CP7WSFDHMQHRAHAS90J0ND"}},"w":1792501093491.73}
  #|{"step":"answered client.focus","w":1792501093499.449}
  #|{"in":{"id":6,"delta":[{"path":["me","pair"],"set":{"state":"finding","devices":0}}]},"w":1792501093508.136}
  #|{"in":{"id":14,"ok":null},"w":1792501093508.151}
  #|{"step":"answered lock.pair","w":1792501093509.038}
  #|{"step":"answered notify.permission","w":1792501093525.074}
  #|{"step":"until 输入你的受信任设备上显示的安全码","w":1792501093541.78}
  #|{"in":{"id":6,"delta":[{"path":["me","pair","devices"],"set":1},{"path":["me","pair","state"],"set":"code"}]},"w":1792501094624.789}
  #|{"step":"type 000000","w":1792501094629.487}
  #|{"step":"type 000000","acted":true,"w":1792501094629.495}
  #|{"out":{"id":15,"call":"lock.pairCode","params":{"workspace":"01M5CP7WSFDHMQHRAHAS90J0ND","code":"000000"}},"w":1792501094641.556}
  #|{"step":"answered lock.pairCode","w":1792501094642.994}
  #|{"in":{"id":15,"error":{"code":"pair_wrong","message":"安全码不对，还可以试 2 次"}},"w":1792501094674.79}
  #|{"step":"until 安全码不对","w":1792501094691.769}
  #|{"in":{"id":6,"delta":[{"path":["me","pair","left"],"set":2},{"path":["me","pair","state"],"set":"wrong"}]},"w":1792501094724.789}
  #|{"step":"log do: peer lock-off","w":1792501094726.223}
  #|{"step":"peer lock-off"}
  #|{"step":"done 2-peer","w":1792501094726.227}
  #|{"step":"until 端到端测试","w":1792501106674.948}
  #|{"in":{"id":6,"delta":[{"path":["locked"],"set":false},{"path":["me","waiting"],"set":false},{"path":["me","pair"],"remove":true},{"path":["notice"],"set":true}]},"w":1792501106707.946}
  #|{"out":{"id":16,"subscribe":{"topic":"longJobs","scope":"01M5CP7WSFDHMQHRAHAS90J0ND"},"keyed":true},"w":1792501106708.047}
  #|{"step":"","w":1792501106712.011}
