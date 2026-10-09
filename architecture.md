# architecture —— tools/git-repo-sh-tools（现状）

> 只写**代码现在长什么样**：有哪些文件、里面有什么、怎么跑测试。
> 为什么这么决策去 `docs/adr/`（本仓库没有 ADR），接下来做什么去 `BACKLOG.md`。

## 1. 这个项目是什么

repo（git-repo）工作区里的一套 shell 命令：定位项目、查清单、推/抓提交、同步、构建。
项目身份 = 工作区里的路径 `tools/git-repo-sh-tools`（`wtool.xml` 里没有 `id=`；
GitHub 仓库名仍是 `allinkernel/wtool-repo`，2026-10-04 由 `tools/repo` 改名而来）。
`wtool.xml` 里声明 1 个 `<zshrc>` + 1 个 `<bashrc>`，没有 link、没有 `scripts/`
（不构建、不安装实体）。

## 2. 文件

| 文件 | 是什么 |
|---|---|
| `env.zsh` | zsh 版：全部命令（别名 + 函数）与内联的 `_up_to_have_dir` |
| `env.bash` | bash 版：与 `env.zsh` 同一批命令、同样的报错与退出码 |
| `my_repo.py` | manifest 查询工具，自包含解析 XML（**不 import** `.repo/repo/manifest_xml.py`），只用标准库 |
| `gerrit_query.py` | 解析 `gerrit query --format=JSON` 的输出，只用标准库 |
| `wtool.xml` | 清单：`<zshrc src="env.zsh"/>` + `<bashrc src="env.bash"/>` |
| `tests/run_tests.sh` | 测试（POSIX sh），见 §5 |
| `README.md` | 给用户的完整功能说明书 |
| `AGENTS.md` | 动这个仓库要遵守的规矩 |
| `architecture.md` | 这份文件 |
| `BACKLOG.md` | 接下来做什么、做到哪了 |

两个 env 文件 export 两个稳定地址（都由 `$WTOOL_PROJECT_DIR` 推出来）：
`WTOOL_REPO_TOOL=$WTOOL_PROJECT_DIR/my_repo.py`、
`WTOOL_GERRIT_TOOL=$WTOOL_PROJECT_DIR/gerrit_query.py`。

## 3. 两个 shell 的等价约定

同一批命令、同样的报错文字、同样的退出码。语法差异：

| 地方 | env.zsh | env.bash |
|---|---|---|
| 测条件 | `[[ ... ]]` | `[ ... ]` |
| 取父目录 | `${var:h}` | `${var%/*}` + `case` |
| 报错前缀"当前函数名" | `funcstack[1]` | `FUNCNAME[0]` |
| 正则捕获 | `${match[1]}` | `BASH_REMATCH[1]` |
| 数字判断 | `<->` glob | `[[ =~ ^[0-9]+$ ]]` |
| 打印原样字符串 | `print -r --` | `printf '%s\n'` |
| 判"是不是一串点" | `[[ ${t} == *[!.]* ]]` + `(( ${#t} >= 2 ))` | `case ${t} in *[!.]*)` + `[ ${#t} -ge 2 ]` |

**已知不等价的一处**：`wninja` 在 `env.zsh` 里开头有 `[[ -z $ZSH_VERSION ]] && return`
（bash 里 source 它是静默 no-op），`env.bash` 那份没有这道门。README §7 已注明。

## 4. 命令分族

| 族 | 命令 | 说明 |
|---|---|---|
| 定位 | `cs` `css` `ct` `ctt` `cm` `cmm` | 往上找 `.repo` / `.git`，cd 或打印 |
| 跳项目 | `cdd <目标>` `cdd_path <目标>` | 按"**一串点（往上跳 N-1 层）** → 现存文件/目录 → 清单项目名 → 相对 repo 根的路径 → **纯数字 = gerrit 提交编号**"找 |
| 当前项目 | `cnp` `cnn` `cnb` `cnr` | 路径 / 名字 / 分支 / remote（走 `my_repo.py`） |
| 清单查询 | `repo_mfst_get_name_from_path` 等 7 个 | 包 `my_repo.py` 的对应动作 |
| 推送 | `gb` `gpun` `gbb` | `gb` 只打印命令；`gpun` 把那条 `git pull … --unshallow` 真跑掉（助手可执行）；`gbb` 会 `eval` 真的推（**助手不执行**） |
| 抓取 | `ggco <分支\|tag\|commit>` | fetch 之后直接 checkout（不 cherry-pick、不 reset、不 push） |
| gerrit | `ggcp <编号\|链接\|Change-Id> ...` `gchk <change>` `gq [-r] <change>` `gpush [remote]` | 走 `ssh <gerrit> gerrit query` |
| 同步/构建 | `rs` `rscur` `wninja` | `rs`/`rscur` 带 `--force-sync -d`（**会丢弃本地改动**） |

### 4.0 `ggcp` / `cdd <编号>` 的实现要点（2026-10-09 大改）

**`ggcp` 的参数坍缩**：所有入口最后都走同一个 `_gr_apply_change <编号> <patchset>`。

- `_gr_collect_args`：先按英文逗号切 token（空格列表由 `$@` 天然拆开，两种可混用），
  再逐个认 —— `I<40hex>` → `_GGCP_IDS`（Change-Id，稍后展开）；`http*://*` →
  `_gerrit_parse_change_arg` 取编号（老式 `#/c/N[/P]` 和新式 `/+/N[/P]` 都认）；
  `N/M` → 编号+patchset；纯数字 → 编号；其余报错返回 2。
- `_gerrit_parse_change_arg` 现在也认裸 Change-Id：置 `_GERRIT_CHANGEID`，
  `_GERRIT_CHANGE` 也等于它（`change:<Change-Id>` 在 gerrit query 里合法）。
  Change-Id 不许再跟 patchset（返回 2）。
- `_gr_expand_changeids`：`_gerrit_query_capture <Change-Id>` → `gerrit_query.py commits`
  把**每个 patchset 各一行**（`number patchset project revision ref url branch`）→ 用
  `_repo_project_relpath` 给每个项目算本地路径 → `gerrit_query.py table --path-map <文件>`
  打对齐的表 → 逐行 `_gr_ask`（y/回车/n/q），答应的条目追进 `_GGCP_ITEMS`。
  `-y` / `-n` 跳过询问。
- `_gr_apply_change`：查询 → `gerrit_query.py patchset` → `cdd_path` → `_gerrit_project_remote`
  → `git fetch`（输出吞进变量）→ 核对 `FETCH_HEAD == revision` → `git cherry-pick`（输出同上）。
  正常路径只打 `正在下载N` / `正在打补丁N` / `打补丁成功`；任何一步失败打 `打补丁失败` +
  关键错误到 stderr，返回 1。多个编号互不影响，最后整体返回"有没有失败过"。
- 颜色：`_gr_color_on` **只有自动两条** —— 设了 `NO_COLOR` → 不上色；否则 `[[ -t 1 ]]`
  （stdout 是 tty）→ 上色；管道/重定向里自动退化成纯文本。没有强制开关。
  `_gr_green` / `_gr_red` 按它决定加不加 `\033[32m` / `\033[31m`。
- patchset 的写法：`1234/2` 或 `-p <n>`。**第二个位置参数不再是 patchset** ——
  `ggcp 1234 1` 就是"编号 1234 + 编号 1"（用户 2026-10-09 认可斜杠写法，老写法故意不支持）。
- `_gerrit_query_change` 的 ssh 带 **`< /dev/null`**：ssh 会吞 stdin，而 Change-Id 那条路
  要用 stdin 问用户（这个坑是实测踩到的，不加就"问了读不到答案"）。

**`cdd <纯数字>`**：放在原有三条路（现存文件/目录 → 清单项目名 → 相对路径）**之后**，
所以老用法优先级不变。`_cdd_project_from_change` 复用 `_gerrit_resolve` +
`_gerrit_query_capture` + `gerrit_query.py patchset <n>`（第 5 列 = project），
拿到项目名后**直接调 `cdd <项目名>`**（真的坍缩，不是复制一份逻辑）；
仓库不在工作区时打 `cdd: N 对应的仓库名 X 在当前 repo 工作区不存在` 并返回 1。

### 4.3 `cdd` 的点参数（2026-10-09 加回来）

**判据**：`_cdd_dots_up <token>`（内部函数，两份 env 各一个、逐字对应）——
"整个 token 都是点、且至少 2 个点"才成立，成立就打印**往上跳的层数** `N-1`
（N = 点数），否则返回 1、什么都不打印。两份实现只差语法：
zsh 用 `[[ ${token} == *[!.]* ]] && return 1`，bash 用 `case ${token} in *[!.]*) return 1 ;; esac`。

**落点**：`cdd` 里**排在 `[[ -e $target ]]` 之前**（第 0 条），因为 `..` 本身就是个真目录，
不先判就会被"现存目录"那条抢走；顺带也压住了"当前目录里真有个叫 `...` 的目录"——
点参数就是往上跳，不做路径解析。不是点参数（含别的字符 / 只有 1 个点 / 空）就照旧往下走，
`cdd` 原来的四条路一个字没改。

**跳法**：把 `dots_up` 拼成 `..` + `/..` × (dots_up-1) 一次 `cd` 过去
（`up_path=..; for ((i=1; i<dots_up; i++)); do up_path+=/..; done; cd ${up_path}`）——
和 zsh 里 oh-my-zsh 那 4 条 global alias 展开出来的字符串逐字一样。
**跳过根就停在 `/`**：`cd ../..` 这种路径由 shell 自己钳在 `/`，退出码 0、不打任何东西
（实测 zsh 5.9 / bash 5.2 都是这个行为）。

**为什么不用站在 repo 工作区里**：判点在 `css`（找 `.repo`）之前，所以不在工作区里
也能往上跳；`Usage` 里多了一行（原来的"四行说明"变"五行说明"）。

**和 zsh 原生的关系（读代码时容易搞错）**：zsh **本体不认** `cd ...`（`zsh -f -c 'cd ...'`
报 `no such file or directory`），真机上好使是因为 **oh-my-zsh** 的
`shell/oh-my-zsh/lib/directories.zsh` 挂了 4 条 `alias -g`
（`...`~`......` → `../..`~`../../../../..`）—— 所以只到 6 个点，而且 bash 没有 global alias。
交互式 zsh 里敲 `cdd ...`，`cdd` 收到的其实已经是 `../..`（走"现存目录"那条），
落点与点参数一致；测试里有一条 zsh 专属用例把这个 alias 交互钉住了。

### 4.1 `ggco` 的实现要点

- 参数：恰好 1 个、不以 `-` 开头；否则用法打 stderr、返回 2；
- 前置检查：在 git 仓库里（`git rev-parse --git-dir`）、工作树没有已跟踪文件的改动
  （`git status --porcelain --untracked-files=no`）；
- remote：复用 gerrit 那套 `_gerrit_project_remote`（`polygerrit` → `cnr` → 第一条 remote）；
- `git fetch <remote> <ref>` → `git rev-parse --verify 'FETCH_HEAD^{commit}'` 拿目标 commit；
- 本地**没有** `refs/heads/<ref>` 时 `git checkout <ref>`（分支 DWIM 建跟踪分支、
  tag/commit 是 detached）；**有**的时候 `git checkout <ref>` 后比对 HEAD 与刚 fetch 的
  commit，不一致就报错返回 1（**不 reset 本地分支**）；
- 成功打一行 `ggco: <目录> 现在在 <分支|detached> @ <短 sha>（来自 <remote> <ref>）`。

### 4.2 `gpun` 的实现要点

- 参数：0 个、`-<十进制深度>`、`--depth=<十进制深度>` 三种；其余（含 `abc` / `-0` /
  `--depth=` / `--depth=x` / 多于 1 个参数）打 `Usage` 到 stderr、返回 2。
  深度只用 `case` 的通配（`*[!0-9]*` / `*[!0]*`）判"是不是正整数"，不做算术。
- 挑命令：`out=$(gb)`（`gb` 失败就报错返回 1），
  再 `print -r -- "${out}" | grep -E '^git pull .*[[:space:]]--unshallow$' | head -n 1`。
  用 POSIX ERE（**不用** `gbb` 那种 `grep -P`）；`head -n 1` 兜住"万一多于一条"
  （`gb` 正常只给一条）。挑不到 → 两行报错、返回 1、**不跑任何东西**。
- 深度替换：`cmd="${cmd%--unshallow}--depth=${depth}"` —— `%` 只剥掉结尾的
  `--unshallow`，原有的分隔空格留在里面；所以不用手写空格，也不会碰 `git fetch …` 那条。
- 执行：先 `echo "${me}: 执行 ${cmd}"`（`gb` 的其它输出不刷出来），
  再 `if eval "${cmd}"; then rc=0; else rc=$?; fi`（**`if` 包住，避免 `set -e` 下直接退出**），
  非 0 时多打一行到 stderr，最后 `return ${rc}`。
- 报错前缀取当前函数名（zsh `funcstack[1]` / bash `FUNCNAME[0]`），与 `gb` / `gbb` 同规矩。
- 不做"是不是 shallow 仓"的前置判断：`gb` 不管仓浅不浅都给那条命令，
  完整仓上由 git 自己 `fatal: --unshallow on a complete repository does not make sense`（退出码 1）。

## 5. 测试

`tests/run_tests.sh`（`#!/bin/sh` + `set -eu`，335 条，不连网）：

1. `my_repo.py`：假工作区（`.repo/repo` **不存在**、`<include>`、`local_manifests`、
   remote/project 级 revision）上的查询、`list`、错误处理；
2. `gerrit_query.py`：patchset 选择、`check` 的退出码、`list` / `raw` / 坏输入；
3. `env.zsh` / `env.bash` 对比：`for SHELL_NAME in zsh bash`，同一张用例表跑两个 shell
   （`cnp` / `cnn` / `cdd` 的报错与退出码、**`cdd` 的点参数**（落点用 `pwd` 的绝对路径断言）、
   `ggcp` 参数坍缩与颜色退化、`ggco` 端到端、`gpun` 端到端）；
   点参数的夹具：`$T/dots/l1/…/l8`（8 层深，给"8 个点"用）+
   `$WS/kernel/common/...`（名字真叫 `...` 的目录，钉"点参数优先于现存目录"）；
   zsh 那 4 条 global alias 的交互是 **zsh 专属**用例（片段里 `alias -g` 复现）；
4. `ggco` 夹具：`$T/ggco/bare.git`（`git init --bare`）+ `$T/ggco/work`（clone），
   往裸仓推一条只有远端才有的 `feature` / `old`，然后在 clone 里跑 `ggco`
   （只推这个临时裸仓，不碰任何真 remote）；
5. `gpun` 夹具：`$T/gpun/bare.git`（`git init --bare`，40 个提交，HEAD 指到 `main`）
   + `$T/gpun/shallow`（`git clone --depth=1 file://…`）+ `$T/gpun/seed`（完整 clone）。
   `gb` 由桩函数覆盖（`GPUN_GB_STUB`，形状与真 `gb` 逐字同形）。
   判据用 `git rev-parse --is-shallow-repository` 和 `git rev-list --count HEAD`：
   跑 `gpun` → 不再 shallow 且 40 个提交；跑 `gpun -30` / `gpun --depth=30` → 仍 shallow 且正好 30 个。

6. `ggcp` / `cdd <编号>` 夹具：`$T/ggcp/` 下 —— `remote/proj.git`（"gerrit 服务器"：里面
   有 `refs/changes/01/1/1`、`…/1/2`、`…/02/2/1` 三条 ref）、`ws/`（带 `.repo/manifests`
   和 `.gerrit/client.conf` 的假工作区）、`ws/mylib`（真 git 仓，remote `polygerrit` 指向
   那个裸仓）、`json/*.json`（`gerrit query` 的输出样本）、`stub.sh`（桩 `_gerrit_ssh`：
   按 `change:<x>` 挑一个 JSON `cat` 出来）。**一条 ssh 都不发、一个网都不连**。
   判据：输出逐行比对（`正在下载N` / `正在打补丁N` / `打补丁成功|失败`）、
   `git log --format=%s` 看 cherry-pick 落点、`git rev-parse HEAD` 看 `-n` 时没动、
   `grep -c '^打补丁失败$'` 数红行、`cksum` 比对 `ggco` 函数体。

测试一开始就把 `HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_DATA_HOME` /
`XDG_STATE_HOME` 指向 `$T` 下的临时目录并 `export`（夹具的 git 和被测 shell 都只看见空配置，
不读写用户家目录）。

`env` 那一段的执行方式：把片段写进 `$T/s.script`（先 `source env.$SHELL_NAME`、
再 `cd` 进假工作区），用被测 shell 跑一遍，收集 stdout+stderr 与退出码。
