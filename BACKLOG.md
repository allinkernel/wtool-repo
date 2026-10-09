# BACKLOG —— tools/git-repo-sh-tools

> 这个文件是这个项目"接下来做什么、做到哪了"的**唯一权威**。
> 引擎/跨项目的事在 `~/self/wtool/harness/BACKLOG.md`，别混。
>
> 状态：⬜ 待做 · 🔄 在做 · ✅ 做完（写清怎么做的、验证到什么程度）· ⏸ 待决定（要人来拍）

---

## ✅ `ggco`：fetch 之后直接 checkout —— 做完（2026-10-06，提交 `48dea0b`）

**做了什么**：`env.zsh` / `env.bash` 各加一个 `ggco <分支|tag|commit>`，把远端某个 ref
抓下来之后直接切过去；不 push、不 reset、不用 `checkout -f` / `-B`。本地已经有同名分支时
只切过去比对，不一致就报错（**不**替用户 reset 本地分支）。接口、每一条报错文字与退出码
在 `README.md` §6，实现要点在 `architecture.md` §4.1。

**验证到什么程度**：

- `sh tests/run_tests.sh` → **107 通过 / 0 失败**（改前 77 条：把 HEAD 那份 `git archive`
  到临时目录对旧代码跑过一遍，77 通过 0 失败）；
- 端到端（**临时本地裸仓**，不联网）：`git init --bare` + `git clone`，往裸仓推一条
  只有远端才有的分支 `feature`；在 clone 里跑 `ggco feature`，随后
  `git rev-parse HEAD` == 裸仓 `git rev-parse feature`，且本地建出了跟踪分支 `feature`；
- 失败路径各有断言：本地同名分支落后（返回 1 且分支**原样不动**）、远端没有这个 ref、
  工作树有本地改动、用法错误（返回 2）、不在 git 仓库里；
- **同一张用例表跑 zsh 和 bash 两个 shell**（这一节在 `for SHELL_NAME in zsh bash` 循环里）；
- 夹具只往 `$T/ggco/bare.git` 这个临时裸仓 push，不碰真 remote、不碰真工作区。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/tools/git-repo-sh-tools && sh tests/run_tests.sh    # 107 通过, 0 失败
```

**没做/没验**：容器里只做到"装得上、两个 shell 里都在"这一步
（`ubuntu:24.04` + `container-raw.sh` → `install.sh` → `sudo-bootstrap` →
`wtool install tools/git-repo-sh-tools`，`type ggco` 在 zsh 和 bash 里都有）；
`ggco` 的端到端是上面那套临时裸仓测试验的，没在容器里再跑一遍。
`ggco` 没有补全、没有 `-f` 之类的开关，参数就是 `ggco <分支|tag|commit>`。

---

## ✅ `gpun`：把 `gb` 那条 `--unshallow` 真跑掉 —— 做完（2026-10-09；用户 2026-10-08 要求）

**做了什么**：`env.zsh` / `env.bash` 各加一个 `gpun [<深度> | --depth=<深度>]`。
它跑 `gb`，从输出里挑出那条 `git pull <remote> <branch> --unshallow`，**真的执行**
（`gb` 只打印、`gbb` 只挑 push 那条，这条专管 pull/补历史）；`gpun -30`（或
`gpun --depth=30`）把命令里的 `--unshallow` 换成 `--depth=30`。执行前先回显
`gpun: 执行 <命令>`，挑不到那条命令（`gb` 没给 / `gb` 自己失败）就报错返回 1，
**不静默当成功**；`gb` 的整段输出不刷给用户。接口、每条报错文字与退出码在 `README.md` §5，
实现要点在 `architecture.md` §4.2。

**验证到什么程度**：

- `sh tests/run_tests.sh` → **173 通过 / 0 失败**（改前 107 条，都是 0 失败）；
- 端到端（**临时本地裸仓，不联网**、`gb` 用桩函数覆盖）：裸仓 40 个提交、各用例从
  `git clone --depth=1 file://…` 的 shallow 仓起步，判据是
  `git rev-parse --is-shallow-repository` + `git rev-list --count HEAD`：
  - `gpun` → 不再是 shallow 仓、40 个提交齐全（证明真跑了 `--unshallow`）；
  - `gpun -30` / `gpun --depth=30` → **仍是** shallow 仓、正好 30 个提交
    （证明 `--unshallow` 真被换成了 `--depth=30`，而不是原样跑）；
  - 桩 `gb` 不给那条命令 → 返回 1，且夹具**一个 commit 都没多**（没跑任何东西）；
  - 桩 `gb` 给两条 → 只跑第一条（40 个提交，第二个 remote 不存在，跑错就非 0）；
  - `gb` 自己失败 → 返回 1；完整仓（非 shallow）→ 由 git 报
    `fatal: --unshallow on a complete repository does not make sense`、gpun 回显失败行并按 git 的退出码返回；
  - 五种用法错误（`abc` / `-0` / `--depth=` / `--depth=x` / 两个参数）→ 返回 2 + 打用法；
- **同一张用例表跑 zsh 和 bash 两个 shell**（这一节在 `for SHELL_NAME in zsh bash` 循环里，
  两个 shell 各 33 条）；
- 测试全程 `HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_DATA_HOME` / `XDG_STATE_HOME`
  都指向临时目录：跑完对真 `$HOME` 下 13 个路径比 `stat -c '%n|%s|%T@'`，**逐字未变**；
- 显示效果（真跑，两种情形各自的真实终端输出）留在 `/tmp/gpun-demo.txt`：
  临时目录 + 本地裸仓 + `file://` + 桩 `gb`，zsh / bash 各跑 `gpun` 与 `gpun -30`。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/tools/git-repo-sh-tools && sh tests/run_tests.sh    # 173 通过, 0 失败
```

**没做/没验**：

- **没有对真远端跑过 `gpun`**（会真 `git pull` 真 GitHub）—— 测试和演示都只用本地裸仓；
  助手没有在真仓库里执行过 `gpun` 本体；
- 没在容器里跑（`wtool.xml` 没动，装出来的东西和 `ggco` 那次一样）；
- "多于一条候选时取第一条" 只由桩用例覆盖，真 `gb` 正常只给一条；
- 没有补全、没有 `--depth N`（空格）这种写法（只认 `-30` 和 `--depth=30`），
  也没有 `-f` 之类的开关。

> 本篇和这次改动在同一个提交里（提交号用 `git log -1 --stat -- BACKLOG.md` 看）。

---

## ⏸ 待拍板

（暂时没有。）
