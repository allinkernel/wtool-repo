# BACKLOG —— tools/git-repo-sh-tools

> 这个文件是这个项目"接下来做什么、做到哪了"的**唯一权威**。
> 引擎/跨项目的事在 `~/self/wtool/harness/BACKLOG.md`，别混。
>
> 状态：⬜ 待做 · 🔄 在做 · ✅ 做完（写清怎么做的、验证到什么程度）· ⏸ 待决定（要人来拍）

---

## ✅ `cdd` 的点参数（`..` / `...` / `....` …）加回来 —— 做完（2026-10-09）

**用户要求（原话）**："cdd 命令，可以跟 `....` 这种参数，功能相当于 zsh 的 `cd ...`。
但是 zsh 本身只支持最多 6 个点。而且 bash 不支持。**这个给我加回来，mytool 就有这个功能，
wtool 你给我删了**。"

**做了什么**（接口写在 `README.md` §2，实现要点在 `architecture.md` §4.3）：

1. **语义**：N 个点 = 往上 **N-1** 层（`..` 1 层、`...` 2 层、`....` 3 层……），
   **不限点数**（8 个点 = 7 层，用例里钉着），**两个 shell 都有**；
2. **到根就停**：点太多、跳过 `/` 了就在 `/` 停下 —— 退出码 **0**、一个字都不打，
   **不报错**（README 里写明了这条语义）；
3. **落点**：`cdd` 里的**第 0 条**，排在"现存文件/目录"**前面** —— `..` 本身就是个真目录，
   不先判就会被老规则抢走；顺带压住"当前目录里真有个叫 `...` 的目录"（点参数就是往上跳，
   不做路径解析）。判定收在一个内部函数 `_cdd_dots_up`（zsh / bash 各一份，逐字对应）；
4. **不查清单**：判点在 `css`（找 `.repo`）之前，所以不在 repo 工作区里也能往上跳；
5. **老用法一个字没动**：`cdd <项目名>` / `cdd <现存文件>` / `cdd <现存目录>` /
   `cdd <相对路径>` / `cdd <gerrit 编号>` 全部原样（旧用例表 + 新用例都盯着）；
   `cdd ..x`（含别的字符）、`cdd .`（只有 1 个点）都不算点参数，照旧走老路；
6. `Usage` 多一行（"四行说明"变"五行说明"）。**`cdd_path` 没动**（它不 cd，
   没有"往上跳"这回事；用户只要求 `cdd`）。

**顺手查清的一件事（用户原话里"zsh 本身只支持最多 6 个点"）**：zsh **本体不认** `cd ...` ——
`zsh -f -c 'cd ...'` 直接 `no such file or directory`。真机上好使是因为 **oh-my-zsh** 的
`lib/directories.zsh` 挂了 4 条 **global alias**（`...`→`../..`、`....`→`../../..`、
`.....`→`../../../..`、`......`→`../../../../..`），所以**只到 6 个点**；而 global alias
是 zsh 专有物，**bash 里没有对应东西**（这就是"bash 不支持"的根）。可原地复现：

```sh
zsh -f  -c 'cd /tmp && cd ...'          # zsh:cd:1: no such file or directory: ...
zsh -i  -c 'alias -g' | grep '\.\.'      # ...=../.. ……… ......=../../../../..
sed -n '8,11p' ~/self/wtool/shell/oh-my-zsh/lib/directories.zsh
```

**⚠️ 没找到 mytool 那段的实物（别把它当"我核过了"）**：用户说 mytool 有，但本机能找到的
mytool 副本里**没有**这段 —— `~/source/mytool/android/wsw_env.sh:264` 的 `cdd` 只有
"现存文件/目录 → 清单项目名/路径"两条路，`~/source/mytool/zsh/wsw_env.sh` 里压根没有 `cdd`；
本仓库 git 历史也搜不到（`git log --all -S'cdd_dots' -- env.zsh env.bash` 无输出）。
**所以这次的实现是按用户给的语义新写的**，参照物是上面那 4 条 global alias
（`cdd` 内部拼出来的字符串和 alias 展开的逐字一样）。

**验证到什么程度**：

- `sh tests/run_tests.sh` → **335 通过 / 0 失败**（改前 309）；新增 26 条
  （两个 shell 各 12 条 + zsh 专属 2 条），**同一张表跑 zsh + bash**：
  `cdd ..`/`...`/`....` 落到正确的层（判据是 `pwd` 的**完整绝对路径**，不用 `cd -`、
  不拿相对路径比）、**8 个点**（= 7 层，zsh 原生那条路只到 6 个点）、
  12 个点在浅目录里**停在 `/`**（退出码 0 且 stdout+stderr 一个字都没有）、
  站在 `/` 上再往上还是 `/`、**不在 repo 工作区里也能跳**、
  `..x` 不被当点参数（退出码 1 + `清单里没有` 那句原文）、`cdd .` 还是原地、
  夹具里那个真叫 `...` 的目录抢不走点参数；
  zsh 专属两条：把 oh-my-zsh 那 4 条 `alias -g` 原样挂上（`cdd ...` 收到的其实是 `../..`）
  —— 落点必须和点参数一致；
- **回归**：把**改前的**用例表（`git show HEAD:tests/run_tests.sh`）拿新代码跑一遍 →
  **309 通过 / 0 失败**，与改前逐条一致（这也是"309"这个基数的实证，不是手抄）；
- **显示效果**（用户点名要）：真机 **WSL2** 上真跑，两个 shell 各一遍，
  留档 `/tmp/cdd-demo.txt`（`script -qec` 起真 pty；含 `pwd` → `cdd ...` → `pwd` →
  `cdd ....` → `pwd`、8 个点、12 个点停在 `/`、`cdd ..x` 报错，
  以及 zsh 原生 7 个点报错 / bash 原生 `cd ..` 报错的对照）；
- **`pwd` 被覆盖过的情形**（`shell/zsh` 里 `pwd` 是自定义函数，zsh / bash 两份都有）：
  `cdd` **只读 `$PWD`、函数体里一次都没调 `pwd`**（demo 里 `grep -c pwd` = 0），
  所以它不会把 `pwd` 那份 tee 记录弄乱；跳完再敲 `pwd` 记录自然就更新了。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/tools/git-repo-sh-tools && sh tests/run_tests.sh    # 335 通过, 0 失败
sh tests/run_tests.sh | grep -A14 'cdd 的点参数'                    # 两个 shell 各 14 行 ok
sed -n '1,40p' /tmp/cdd-demo.txt                                   # 真机演示（前面是表头）
```

**没做/没验**：

- `cdd_path` 不支持点参数（没要求；它不 cd）；
- 容器里没跑（`wtool.xml` 没动，装出来的还是"两份 rc 文件"，与上次一样）；
- 没有补全；点参数只吃**一个**参数 —— `cdd .. ..` 还是 `argv 个数 ≠ 1` → `Usage` + 退出码 2（没改）；
- 这次**没动**别的仓（`bootstrap` / `harness` / `wtool-base` 正被别的代理改）。

---

## ✅ 追加：`WTOOL_GGCP_COLOR` 按用户要求移除 + `1234/2` 写法写进文档（2026-10-09）

**背景**：上一条做完后用户回了两句 —— ① "1234/2，可以，斜杠就行"；
② 对 `WTOOL_GGCP_COLOR` 的反应是"不知道是干啥的"。

**做了什么**（**只追加这一节，上一条的历史条目一个字没改**）：

1. **删掉 `WTOOL_GGCP_COLOR`**（用户可见的旋钮只有用户能加）：`env.zsh` / `env.bash` 里
   `_gr_color_on` 现在**只有自动两条** —— 设了 `NO_COLOR` → 不上色；否则 `[[ -t 1 ]]`
   （stdout 是 tty）→ 上色；管道/重定向里自动退化成纯文本。
   README「配置项」表那一行、§6 的颜色说明、architecture.md §4.0 的描述一并删掉。
2. **`1234/2` 写成明确规则**：README §6 加一句"指定 patchset 只有 `1234/2` 和 `-p 2`
   两种写法，**老写法 `ggcp 1234 1` 故意不支持**（会被当成编号 1234 和编号 1）"；
   architecture.md §4.0 同步。
3. **测试跟着改**：原来靠 `WTOOL_GGCP_COLOR=always` 验颜色的三条用例删掉，换成
   **真 pty**（`script -qec … /dev/null`，断言前 `tr -d '\r'`）：绿行/红行必须带
   `\033[32m` / `\033[31m`、真 pty 里跑一次真 `ggcp 1` 成功行也要带色、
   真 pty + `NO_COLOR` 依旧无色；非 tty 那条改成"一个 ANSI 码都没有"。
   ⚠️ 踩到的坑：**跑测试的环境自己就设了 `NO_COLOR=1`**（本机实测 `env | grep NO_COLOR`），
   所以"该上色"的用例都显式 `unset NO_COLOR` / `env -u NO_COLOR` —— 否则测的是
   NO_COLOR 规则而不是 tty 规则（第一次跑就是这么红的，6 条 FAIL）。

**验证到什么程度**：`sh tests/run_tests.sh` → **309 通过 / 0 失败**（上一版 303）；
颜色两条规则都在用例里钉住了（真 pty 上色 / 非 tty 与 NO_COLOR 不上色）。
端到端演示重跑并覆盖了"真 pty 里是绿的、管道里是纯文本"两段：
`/tmp/ggcp-demo.txt`（重写）与 `/tmp/ggcp-demo2.txt`（只演颜色那两段）。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/tools/git-repo-sh-tools && sh tests/run_tests.sh   # 309 通过, 0 失败
grep -c $'\033\[32m' /tmp/ggcp-demo.txt                          # >0：演示文件里有真绿码
```

## ✅ `ggcp` 大改 + `cdd <gerrit 编号>` —— 做完（2026-10-09，提交见 `git log ds_dev`）

**做了什么**（用户逐条要求，接口写在 `README.md` §6，实现要点在 `architecture.md` §4.0）：

1. **多编号**：`ggcp 1,2,3` 与 `ggcp 1 2 3` 等价，可以混用（`ggcp 1,2 3`）；
2. **链接参数**：老式 `https://host/#/c/1234[/2]` 和新式 `https://host/c/proj/+/1234[/2]`
   都自动取编号（带 `?`、结尾 `/` 都稳）；多链接/链接混编号也能拆；
3. **Change-Id**：`ggcp I1111…` → 查 gerrit 上它的**所有提交**（一个 Change-Id 可能横跨
   多个分支/多个 change，每个还有多个 patchset）→ 打一张表（编号/patchset/仓库/路径/提交链接）
   → **逐个问**"给这个仓库打这个补丁吗？"（`-y` 全打、`-n` 全跳过）；
   不论哪条入口，最后都**坍缩成 `_gr_apply_change <编号> <patchset>`**；
4. **输出**：`git fetch` / `cherry-pick` 的原始输出一律吞掉（失败时才把关键错误打到 stderr），
   正常路径只打 `正在下载N` / `正在打补丁N` / `打补丁成功`（绿）/ `打补丁失败`（红），
   有几个编号就有几组；stdout 不是 tty 或设了 `NO_COLOR` 时自动退化成纯文本；
5. **`cdd 1234`**：去 gerrit 查这个编号属于哪个项目（复用 `ggcp` 那套解析 +
   `gerrit_query.py patchset` 的第 5 列），然后**坍缩成 `cdd <项目名>`**；
   仓库不在工作区时打 `cdd: 1234 对应的仓库名 X 在当前 repo 工作区不存在` 并返回 1。
   数字这条路**排在原有三条路之后**，`cdd` 原来的"现存文件/目录 / 项目名 / 相对路径"行为不变。
6. **`ggco` 一个字都没改** —— 除了原有行为用例，测试里再加一条 `cksum` 冻结
   （zsh `2879919872 2380`、bash `3925425235 2531`）。

**为什么要挪窝**：`ggcp` 原来在 `tools/gerrit-gate` 里也有一份，而**实际生效的是
gerrit-gate 那份**（wtool 按 priority 排：git-repo-sh-tools prio=40 → gerrit-gate prio=46，
后 source 的赢）。用户决定废弃 gerrit-gate，于是把实现并到本仓库
（`tools/git-repo-sh-tools/env.zsh` / `env.bash` 各一份），gerrit-gate 里那份**已删除**
（它的 `gchk` / `gq` / `gpush` 还在，没动）。

**验证到什么程度**：

- `sh tests/run_tests.sh` → **303 通过 / 0 失败**（改前 173 条）；
- 新增第 6 段夹具是"假 gerrit"（桩 `_gerrit_ssh` + 本地裸仓里的 `refs/changes/NN/N/P`），
  **不连网、不发一条 ssh**；覆盖参数坍缩、颜色退化、端到端 cherry-pick、Change-Id 表格 +
  逐个询问、`-y` / `-n`、红行失败路径、`cdd <编号>` 三种结局、`cdd` 老用法不被抢、
  `ggco` 冻结；
- 端到端演示（**真 gerrit-lab**，`wtool-lab` 容器）：`/tmp/ggcp-demo.txt`、`/tmp/cdd-demo.txt`
  （`script -qec` 留的真终端记录，带 ANSI 颜色）；
- `gb`/`gbb` 那类"会推真源"的命令**没碰**；lab 里只推过本地 gerrit-lab。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/tools/git-repo-sh-tools && sh tests/run_tests.sh    # 303 通过, 0 失败
sed -r 's/\x1b\[[0-9;]*m//g' /tmp/ggcp-demo.txt                  # 演示（去掉颜色码）
sed -r 's/\x1b\[[0-9;]*m//g' /tmp/cdd-demo.txt
```

**没做/没验**：没在 `ubuntu:24.04` 裸容器里再装一遍（`container-raw.sh` 那套）；
`ggcp -y` 在真实公司 gerrit 上没跑过（只有一个 Change-Id 横跨多分支的真实场景没造出来，
lab 里那个 Change-Id 只有两个 patchset）；`cdd <编号>` 在 gerrit 连不上时的 10 秒超时
（`ConnectTimeout=10`）没有专门测。

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
