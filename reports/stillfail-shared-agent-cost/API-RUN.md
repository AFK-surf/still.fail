# 真实 API 实验交接

**当前状态：无真实 API 数据。** 本轮没有调用 API，没有命中率或实测金额，不能据此判定共享省多少钱。`report.md`、`benchmark.py` 和 `results/` 是旧版源码审计与推算，不能当作真实 usage。新脚本与旧脚本分开，避免混用。

## 本地运行

需要 Python 3.9+、Git、网络和 Anthropic Messages API key（订阅登录态不能代替 API key）。先在本地安全设置环境变量 `ANTHROPIC_API_KEY`；不要把 key 写入脚本、价格文件或发到聊天。

在仓库根目录，离线检查只需：

```sh
python3 reports/stillfail-shared-agent-cost/api-benchmark.py
```

真实调用的一条命令：

```sh
python3 reports/stillfail-shared-agent-cost/api-benchmark.py --run --prices /path/to/verified-prices.json --out ./api-benchmark-results
```

`verified-prices.json` 由执行者按照运行当日的 [Anthropic 官方价格](https://platform.claude.com/docs/en/about-claude/pricing) 填写，下列是**字段格式，不是可运行价格文件**，不提供未核验的价格数字：

```text
{
  "model": "claude-haiku-4-5-20251001",
  "input": <普通输入美元/百万 token>,
  "write_5m": <5 分钟缓存写入美元/百万 token>,
  "read": <缓存读取美元/百万 token>,
  "output": <输出美元/百万 token>,
  "source": "https://platform.claude.com/docs/en/about-claude/pricing",
  "checked": "<实际核验日期 YYYY-MM-DD>"
}
```

默认模型为上述固定版本。换模型须同时传 `--model` 并更新价格文件与 `--min-cache-tokens`；默认阈值 4096，执行者应按照运行当日 [缓存文档](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 核对模型最低缓存长度。程序校验价格字段及模型匹配，但不能自动保证价格来源真实、最新或账号无额外收费。

运行包含超过 5 分钟的真实等待，建议在稳定终端运行。不要重复使用输出目录；运行失败后先检查 `manifest.json` 和 provider 用量记录，不要盲目重跑。

## 做了什么

- workload 固定于运行时 HEAD，通过 `git show` 读取完整 README 原文作为 system；完整 `instructions.ts`、`cache-policy.ts` 作为源码上下文。原文不会改写或填充。任务直接取真实开发提交 `5e42d56b8e3c99a6a0856e61e6d064cc2c2b99d7` 的标题和正文，保留任务来源。是开发请求的回放，不是声称该请求在当前 HEAD 尚未实现。
- A：N=1/5/20，每个请求最开头添加不同随机标记，均使用 5m cache_control，测独立冷写入。A 不是关闭缓存的组，也不代表不同账号。
- B：每个 N 单独一个前缀，N 次顺序调用，除首个冷请求外观察真实复用。每次都是新进程，因此 B/C 的差别主要是调用时序。
- C：同一个 key/workspace、相同前缀、N 个全新 OS 进程并发。分别保留首次冷并发与显式 prime 后的暖并发，避免把首次同时启动的竞态误判成无法跨进程共享。冷并发后 prime 可能已经是 read；查看 usage，不能假定它是 write。
- TTL：新前缀先写、再验证确有 read；从 read 完成后等待至少 310 秒，无同前缀的其他请求；随后发一次观察过期，再一次观察重建后的复用。读取会刷新 TTL；这组观察不等于已覆盖所有续命间隔。
- A/B/C 各 N 之间用不同前缀，跨运行也隔离，防止之前的测试污染。保存完整请求、前缀哈希、源码哈希、commit 和任务原文，便于重跑核对。

总共 111 个 Messages 请求，另有逐请求 count_tokens 预检。预算上限默认且最高 $3；每批发出之前，用官方 count_tokens 返回值加保守余量，按该批全部冷写入预留成本，输出上限 128。预计复用不会用来降低预算预留。预检可能使实验提前停止；**预算保护属于保守检查，不是实际账单，也不能覆盖未返回 usage 的服务端计费、账号附加收费或错误价格。** 不自动重试，失败即停，保留已经完成的结果。价格算出的金额是 API usage 对应的标价成本，实际发票还应由账号管理员对账。

## 交回哪些文件

把整个 `api-benchmark-results/` 打包交回，至少包括：

- `manifest.json`：运行状态、版本、价格、预算和已记录 usage 的计价合计。`incomplete` 不能冒充完整实验。
- `usage.csv`：逐请求 model、三种输入 token、output、token 命中率、TTFT、总耗时、按 usage 计算的美元、request-id 和错误。命中率严格为 read / (input + creation + read)；分组汇总应先求 token 总和再除，不能平均每行比例。
- `*.raw.json`：原始 SSE 事件（含原始 usage 字段）与合并后的 usage，美元数可以追溯到对应请求和 `prices.json`。TTFT 指请求启动到首个 text_delta；没有文本则留空。
- `*.request.json`、`*.count.json`、`prices.json`、`system.txt`、`context.txt`、`task.txt`：复现与计费依据。不包含 API key，但可能含模型生成的源码讨论，请按仓库材料的权限共享。

## 待真实结果后再写的结论

尚无真实命中率、真实 usage 成本、真实账单，也无法量化与旧推算的差异。跨进程相同前缀若确有读取，只能证明此账号/workspace 下 provider 能跨进程复用，不能把它归功于 still.fail 独有能力。这个脚本直接访问 API，不经过 still.fail 或 Claude Code，不能独自证明产品实际请求有相同前缀或相同缓存行为。共享省不省、冷并发损失、TTL 重写成本与输出成本，均须等待真实数据。
