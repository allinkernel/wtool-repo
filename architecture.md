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
| `gerrit_query.py` | 解析 `gerrit query --format=JSON` 的输出，只用标准库；动作 `patchset`（10 列，后两列是 Change-Id + 这个 change 所有 patchset 的 `编号:revision:ref`）/ `commits` / `table` / **`result-table`** / `check` / `list` / `raw` |
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
| 跳项目 | `cdd <目标>` `cdd_path <目标>` | 按"**一串点（往上跳 N-1 层）** → **`-N` = gerrit 提交编号** → 现存文件/目录 → 清单项目名 → 相对 repo 根的路径 → **纯数字（老写法）= gerrit 提交编号**"找 |
| 当前项目 | `cnp` `cnn` `cnb` `cnr` | 路径 / 名字 / 分支 / remote（走 `my_repo.py`） |
| 清单查询 | `repo_mfst_get_name_from_path` 等 7 个 | 包 `my_repo.py` 的对应动作 |
| 推送 | `gb` `gpun` `gbb` | `gb` 只打印命令；`gpun` 把那条 `git pull … --unshallow` 真跑掉（助手可执行）；`gbb` 会 `eval` 真的推（**助手不执行**） |
| 抓取 | `ggco <分支\|tag\|commit>` | fetch 之后直接 checkout（不 cherry-pick、不 reset、不 push） |
| gerrit | `ggcp <编号\|链接\|Change-Id> ...` `ggrvt <编号\|链接\|Change-Id>` `gchk <change>` `gq [-r] <change>` `gpush [remote]` | 走 `ssh <gerrit> gerrit query`；`ggrvt` 只动本地（`git revert`） |
| 同步/构建 | `rs` `rscur` `wninja` | `rs`/`rscur` 带 `--force-sync -d`（**会丢弃本地改动**） |

### 4.0 `ggcp` / `cdd -N` 的实现要点（2026-10-21 两阶段重写）

**`ggcp` 的参数坍缩**：所有入口最后都变成 `_GGCP_ITEMS` 里的 `"编号|patchset"`，
再交给两阶段流水线（旧版那个"边查边打"的 `_gr_apply_change` 已经删掉）。

- `_gr_collect_args`：先按英文逗号切 token（空格列表由 `$@` 天然拆开，两种可混用），
  再逐个认 —— `I<40hex>` → `_GGCP_IDS`（Change-Id，稍后展开）；`http*://*` →
  `_gerrit_parse_change_arg` 取编号（老式 `#/c/N[/P]` 和新式 `/+/N[/P]` 都认）；
  `N/M` → 编号+patchset；纯数字 → 编号；其余报错返回 2。
- `_gerrit_parse_change_arg` 也认裸 Change-Id：置 `_GERRIT_CHANGEID`，
  `_GERRIT_CHANGE` 也等于它（`change:<Change-Id>` 在 gerrit query 里合法）。
  Change-Id 不许再跟 patchset（返回 2）。
- `_gr_expand_changeids`：`_gerrit_query_capture <Change-Id>` → `gerrit_query.py commits`
  把**每个 patchset 各一行**（`number patchset project revision ref url branch`）→ 用
  `_repo_project_relpath` 给每个项目算本地路径 → `gerrit_query.py table --path-map <文件>`
  打选择表 → 逐行 `_gr_ask`（y/回车/n/q），答应的条目追进 `_GGCP_ITEMS`。
  `-y` / `-n` 跳过询问。
- `_gr_query_info <change> [wanted]`：**ggcp / ggrvt / cdd 共用的唯一查询函数** ——
  `_gerrit_query_capture` → `gerrit_query.py patchset`，成功时 stdout 打一行 10 列 TSV
  （`number patchset revision ref project branch url subject change-id patchsets`）；
  失败时把原因打到 stderr（并放在 `_GR_QUERY_ERR` 里），返回 1。
  `_cdd_project_from_change` 只调它一次（只取第 5 列 project）。
  第 9 列是 Change-Id（gerrit 新版给 `change_id`，老版从 `id`（`project~branch~I…`）
  里拆），第 10 列是这个 change **所有** patchset 的 `编号:revision:ref`
  （空格分隔）—— 预检 / ggrvt 靠它认"本地那个提交是第几个 patchset"。
- `_gr_query_one <change> <wanted>`：查询阶段的**一条**后台任务。调 `_gr_query_info`，
  再把第 5 列（project）交给 `_repo_project_relpath` 算本地相对路径，输出 10 列 TSV：
  `number patchset revision ref project branch url relpath change-id patchsets`
  （第 9/10 列原样带过去，给执行阶段的预检用）。

**ggcp 的两阶段**：

**两阶段的作业都跑在一个子 shell 里**（2026-10-22 修 job 控制噪声）：外层是
`( … ) || rc=$?`，bash 进子 shell 先 `set +m`、zsh 先 `unsetopt monitor notify`。
原因：交互式 shell 里 `cmd &` 会往 stderr 打 `[1] 12345`、作业结束时再打
`[1]+ Done ...`（bash 的启动提示连 `set +m` 都压不住，实测
`bash -ic 'set +m; sleep 1 &'` 照样打）—— 用户看到的就不只是表格。放进子 shell
（非交互式，zsh 子 shell 里 monitor 本来就是 off）后，父 shell 从头到尾不知道这些
作业存在，一个字都不打；用户 shell 的 `monitor`/`notify` **全程没被动过**，所以
不需要"改完恢复"（这比改了再恢复更稳：中途 Ctrl-C 也不会留下一个关掉作业控制的
shell）。**不 disown**：实测 disown 掉的 pid 再 `wait` 会立刻返回（bash 只等
~2ms、zsh rc=127），并行阶段就失去同步；子 shell 退出时作业表随之消失，不需要它。

还没进入补丁结果就失败时（`_gerrit_resolve` 失败 / `_gr_expand_changeids` 失败）先走
`_gr_fail_table <原因>`：给每个用户条目写一行
`-  -  -  <patchset|->  查询失败：<原因>`，再用 `_gr_result_table` 打表；详细原因仍在 stderr。

1. `work=$(mktemp -d "${TMPDIR:-/tmp}/ggcp.XXXXXX")`（在父 shell 里建，保证异常退出也能
   删），每个 `_GGCP_ITEMS` 条目写一个 `req.N`，然后在子 shell 里
   `( _gr_query_one … > out.N 2> err.N ) < /dev/null &` —— **全部并行**，
   pid 收进数组后逐个 `wait`。查询之间不共享 stdout/stderr，所以不会互相穿插。
2. 读 `out.N` 按第 5 列（project）分组；每个项目一个 `g.<id>.spec`，组的顺序按
   **第 8 列（本地相对路径）排序**（路径拿不到就用项目名），`LC_ALL=C sort`。
3. 每个组起一个后台 `_gr_repo_batch <project> <spec> <rows>`，**组内串行、组间并行**；
   同样逐个 `wait`。
4. 所有组结束后，按第 2 步的顺序把 `rows.<id>` 拼成 `rows.all`；查询失败的条目
   追加成 `-  -  -  <patchset>  查询失败：<第一行 stderr>` 的行。
5. `_gr_result_table rows.all <组数> <条目数>`：先打一行总述
   `<仓库数> 个仓库 / <笔数> 笔提交 / 成功 <S> / 失败 <F>`（成功数用
   `awk -F '\t' '$5 == "成功"'` 数），再用 `gerrit_query.py result-table` 打 5 列表：
   `项目名 | 项目路径 | 提交 id | patchset | 结果说明`。返回 0 = 全成功，1 = 有失败。
   它是子 shell 的最后一条命令，`( … )` 的退出码由 `|| rc=$?` 接住，父 shell 再
   `rm -rf "$work"` 并 `return ${rc}`。

**`_gr_repo_batch`（一个仓库，串行）**：

- 从第一个 spec 行取 `relpath`，`root=$(css)`，`dir=$root/$relpath`；`-` / 空 / 目录不存在 /
  `css` 失败都走 `_gr_repo_fail_all`，把该仓库所有提交标成同一个失败原因（**不碰 git**）。
- `cd dir`，`remote=$(_gerrit_project_remote)`（`polygerrit` → 清单 remote → 第一条）；
- **先看工作树**：`git status --porcelain --untracked-files=no` 非空就把所有提交标成
  `工作树有本地改动（先 stash/commit）`，不动工作树（这样失败后的"干净"才说得清）。
- 逐个 spec 行：**先做同 Change-Id 预检**（见下）→ `git fetch <remote> <ref>`
  （输出吞掉）→ 核对 `FETCH_HEAD == revision` → `git cherry-pick <revision>`。失败时：
  - `git status --porcelain --untracked-files=no` **为空** → `此提交本地已经有了（可能已合入）`
    （典型是空提交/已合入）；
  - **有文件** → `cut -c4-` 取路径、空格连起来 → `<文件…> 文件冲突`；
  - 然后如果 `CHERRY_PICK_HEAD` 还在，`git cherry-pick --abort`（**只用 --abort，绝不
    reset --hard**）；abort 失败才 `git cherry-pick --quit` 并在结果里加
    `（工作树没清干净，请手工处理）`；最后再看一次 status，脏就提示。
  - 其它失败（fetch / commit 对不上）直接写 `下载失败：<关键行>` /
    `抓到的 commit（X）和 gerrit 说的（Y）不一致`；一笔失败不中断同仓库下一笔。
- 每笔结果写成 5 列 TSV：`project  relpath  短SHA(12)  patchset  result`；不直接打印。

**同 Change-Id 预检（2026-10-22 加，用户报的真 bug）**：spec 第 9 列非空时，
先在目标仓库里跑 `_gr_local_change_commits <Change-Id>`（`git log --format=%H
--grep='^Change-Id: <id>$'`，**剔掉已经被 revert 的**，见下）：
- 0 个 → 照旧 fetch + cherry-pick；
- 恰好 1 个 → **不 fetch、不 cherry-pick**，写一行失败：
  `此 Change-Id 已在本地历史（提交 <短sha>，patchset <n>）→ 先 ggrvt <编号> 回退，再打 <编号>/<patchset>`。
  `<n>` 由 `_gr_local_patchset` 比 `git patch-id` 认（把这些 patchset 的 ref 一次
  fetch 下来，只下对象、不建本地 ref、不碰工作树）；认不出就省略"patchset <n>"；
- 多个 → 写一行失败并列出**全部**短 SHA + `ggrvt <编号> 会拒绝回退，请手工处理`
  （`ggrvt` 只处理"恰好一个"）。**不擅自 revert**。
原因：`ggcp 1234/1` 之后 `ggcp 1234/2` 的 diff 只比 ps1 多一个文件，cherry-pick 会
"成功"，于是 `git log` 里出现两个同 Change-Id 的提交。该行算失败（`_gr_result_table`
照样算进 fail → 整条命令 rc=1），其它仓库 / 其它 change 继续。

**为什么 revert 过的要剔掉**：`git revert` 不删历史，ps1 那个提交（和它的
`Change-Id:` 行）一直在 `git log` 里。`_gr_local_change_commits` 从
`git log --format=%B` 里收 `This reverts commit <sha>.` 那一行的目标 SHA，从候选里剔掉；
`ggrvt` 用 `LC_ALL=C git revert`，保证这行**永远是英文**（git 的 revert 模板是 i18n
文案，中文 locale 下会被翻译，不固定的话换台机器就失灵）。
已知边界：把 revert 再 revert 回来认不出来，仍按"已回退"处理（README 排错里写了）。

**`cdd -N`（2026-10-21 加）**：`cdd` 里在**点参数之后、`[[ -e $target ]]` 之前**判
`-<数字>`（zsh `[[ ${target} == -<-> ]]`，bash `[[ ${target} =~ ^-[0-9]+$ ]]`）。
`_cdd_cd_to_change <change> <css_dir>` 调 `_cdd_project_from_change`（→ `_gr_query_info`）
拿 gerrit project，再 `_repo_project_relpath` 找本地清单路径：
- 目录存在 → `cd` 过去；
- 清单里有、目录没有 → `cdd: change N 属于项目 X，但本地还没检出（清单路径 Y）` +
  `先 repo sync Y`，返回 1；
- 清单里没有 → `cdd: change N 属于项目 X，但当前工作区的清单里没有它`，返回 1。
- `-N` 排在"现存目录"**前面**：`-12345` 即使真是个目录也按提交处理。
- **老写法 `cdd <纯数字>` 保留**，但它排在"现存文件/目录 → 项目名 → 相对路径"**之后**，
  所以同名目录优先；两种写法最后都调 `_cdd_cd_to_change`，不复制逻辑。

**颜色**：`_gr_color_on` / `_gr_green` / `_gr_red` 仍在（`NO_COLOR` / tty 两条自动规则，
没有强制开关），但 **ggcp 的结果表不上色** —— ANSI 码会破坏中文对齐。测试里那几条
`_gr_green` / `_gr_red` 的单元用例保留。

**ssh stdin**：`_gerrit_query_change` 带 **`< /dev/null`**；本次新增的 fetch / cherry-pick /
abort 也都显式 `< /dev/null` —— ssh/git 不能吞掉 Change-Id 那条路要用的 stdin。

`-p` 的写法、`1234/2` 斜杠、`ggcp 1234 1` 是两个编号这些老规矩**没变**（见 README §6）。

### 4.4 `ggrvt` 的实现要点（2026-10-22 加）

`ggrvt <编号|链接|Change-Id>`：把本地历史里**同 Change-Id 的那个提交** revert 掉。
存在的理由：`ggcp` 的预检发现"同 Change-Id 已在本地历史"时会拒绝再打，用户得先把旧的
回退掉才能换 patchset（完整工作流见 README §6）。

- **参数**：复用 `_gerrit_parse_change_arg`（数字 / 老式 `#/c/N[/P]` / 新式 `/+/N[/P]` /
  Change-Id）。入口自己先挡三种不接的形状：`1234/2`（带 patchset）、`1,2`（列表）、
  多个参数 —— 都返回 2，报错前缀 `ggrvt:`。`_gerrit_parse_change_arg` 的报错文案写的是
  ggcp，所以那一路把它的 stderr 吞掉、由 `ggrvt` 自己出报错。
- **查 gerrit**：`_gerrit_resolve ggrvt`（第一个参数是报错前缀，默认 ggcp）→
  `_gr_query_info <change> ''`（**同一份查询函数**，不复制 ssh/JSON）。取 number /
  patchset（gerrit 的 current）/ project / 第 9 列 Change-Id / 第 10 列 patchset 清单；
  输入本身是 Change-Id 时，第 9 列为空就用输入值。
- **定位仓库**：和 `cdd -N` 完全一样 —— `css` 找 repo 根、`_repo_project_relpath`
  找清单路径；目录不在提示 `repo sync <路径>`，清单里没有单独报。
- **找提交**：`_gr_local_change_commits <Change-Id>`（和 ggcp 预检同一个函数，所以
  已经 revert 过的不算）。0 个 → `本地历史里没有该 Change-Id 的提交` + `先 ggcp N`，
  rc 1；>1 个 → 逐个列出 `<sha>  <subject>`、**不擅自 revert**，rc 1。
- **回退**：`LC_ALL=C git revert --no-edit <sha> < /dev/null`（输出全吞进变量）。
  失败：`REVERT_HEAD` 还在就 `git revert --abort`（**只用 --abort**，abort 失败才
  `--quit`），再报 `ggrvt: 回退 <短sha> 失败：<第一行>`；工作树还脏就补
  `工作树没清干净，请手工处理` + `git status` 那几行。
- **patchset 号**：`_gr_local_patchset <sha> <remote> <patchset 清单>` —— 把 change 的
  所有 patchset ref 一次 `git fetch`（只下对象）后逐个比 `git patch-id`，唯一命中才算；
  认不出就只写 change 号。建议的下一步是 `ggcp <编号>/<gerrit 的 current patchset>`。
- **输出**：成功只有一行（stdout）：
  `已回退 <短sha>（change N, patchset P）→ 现在可以 ggcp N/P`；成功路径 **stderr 0 字节**
  （和 ggcp 同一条规矩）。没有后台作业，不涉及 job 控制噪声。

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

`tests/run_tests.sh`（`#!/bin/sh` + `set -eu`，622 条，不连网）：

1. `my_repo.py`：假工作区（`.repo/repo` **不存在**、`<include>`、`local_manifests`、
   remote/project 级 revision）上的查询、`list`、错误处理；
2. `gerrit_query.py`：patchset 选择、`check` 的退出码、`list` / `raw` / 坏输入、
   `result-table`（5 列 / CJK 宽度 / 坏输入）；
3. `env.zsh` / `env.bash` 对比：`for SHELL_NAME in zsh bash`，同一张用例表跑两个 shell
   （`cnp` / `cnn` / `cdd` 的报错与退出码、**`cdd` 的点参数**（2～7 个点 + 8/12 个点，
   落点用 `pwd` 的绝对路径断言）、`ggcp` 参数坍缩与颜色退化、**`ggcp` 的同 Change-Id
   预检**、**`ggrvt`**（回退 / 零命中 / 多命中 / 各种参数错误）、`ggco` 端到端、
   `gpun` 端到端）；
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

6. `ggcp` / `ggrvt` / `cdd <编号>` 夹具：`$T/ggcp/` 下 —— `remote/proj.git`（"gerrit
   服务器"：里面有 `refs/changes/01/1/1`、`…/1/2`、`…/02/2/1`、`…/34/1234/1`、
   `…/34/1234/2` 等 ref；change 1 / 2 / 1234 的提交消息里各带一行 `Change-Id:`）、
   `ws/`（带 `.repo/manifests`
   和 `.gerrit/client.conf` 的假工作区）、`ws/mylib`（真 git 仓，remote `polygerrit` 指向
   那个裸仓）、`json/*.json`（`gerrit query` 的输出样本）、`stub.sh`（桩 `_gerrit_ssh`：
   按 `change:<x>` 挑一个 JSON `cat` 出来）。**一条 ssh 都不发、一个网都不连**。
   判据：**同 Change-Id 预检**（`ggcp 1234/1` 之后 `ggcp 1234/2` 退出码 1、结果说明里有
   `ggrvt 1234` 和 `patchset 1`、ps2 的文件没进来、`git log --grep` 里同 Change-Id 的
   提交只有 1 个、HEAD 没动、工作树干净）、**`ggrvt`**（回退后 `Revert "…"` 在 HEAD、
   有效的同 Change-Id 提交 0 个 → 再 `ggcp 1234/2` 成功且有效的仍只有 1 个 → 再打又失败；
   零命中 / 多命中列出两个 SHA 且不擅自动手；成功路径 stderr 0 字节）、
   单笔结果表正好 4 行（总述 / 表头 / 分隔线 / 一行结果）、
   四笔跨两个仓库合并成一张表（`mylib` 两行连续、`other` 两行连续）、
   查询桩的 `start/end` 日志算出**查询并行度 ≥2**、git 包装的 `start-cherry/end-cherry`
   日志算出**同仓库并行度 =1 / 跨仓库并行度 ≥2**、`git log --format=%s` 看顺序、
   `git status --porcelain` 与 `CHERRY_PICK_HEAD` 看冲突后是否收干净、
   `git rev-parse HEAD` 看 `-n` 时没动、`cksum` 比对 `ggco` 函数体。
   **stderr 与作业控制噪声**：`erun`（stderr 单独进 `$T/e.$SHELL_NAME`，不并进 stdout）
   断言成功路径 **0 字节**；再用 `script(1)` 起真 PTY 的交互式 shell（bash
   `--norc -i -c "$(cat body)"`、zsh `-f -i -c …`，monitor=on）断言终端里没有
   `[N]` / `Done` / `no job control`，且 `monitor`/`notify` 跑完保持原值
   （on→on、off→off）。⚠️ 测 monitor 不能写在 `$( … )` 里：zsh 的子 shell 里
   monitor 本来就是 off，会把自己误判成 off。

测试一开始就把 `HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_DATA_HOME` /
`XDG_STATE_HOME` 指向 `$T` 下的临时目录并 `export`（夹具的 git 和被测 shell 都只看见空配置，
不读写用户家目录）。

`env` 那一段的执行方式：把片段写进 `$T/s.script`（先 `source env.$SHELL_NAME`、
再 `cd` 进假工作区），用被测 shell 跑一遍，收集 stdout+stderr 与退出码。
