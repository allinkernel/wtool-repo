# tools/git-repo-sh-tools —— repo / git / gerrit 辅助命令

从 `~/source/mytool/android`（原 `wsw-androidrc`）迁移过来的一套 **repo/git 辅助命令**：
在多仓（repo 客户端）工作区里定位、查清单、推送、送 gerrit 检视、同步、构建。

本项目是**纯 env 项目**：`wtool.xml` 里没有 `<link>`，所有能力靠往 rc 文件注入 env 脚本提供
（命令通过 `$WTOOL_PROJECT_DIR` 找到本目录下的两个 python 工具）。
**zsh 和 bash 各一份**（`env.zsh` / `env.bash`，内容等价）：受众里有人机器上没有 zsh。

**这份 README 是给用户看的命令说明书**：这个仓提供哪些命令、各干什么、怎么执行
（每条都写了参数、选项、退出码和报错原文）。**下载的内容不在这里** ——
见文末「下载」一节的链接。进度看 `BACKLOG.md`，决策看 `docs/adr/`。

- 项目路径（**身份就是它**，ADR-0037）：`tools/git-repo-sh-tools`，`priority=40`
- `scripts/` 里只有 `release.json`（发布账，**没有** build/install 脚本）

> **改过名**（2026-10-04）：原来叫 `tools/repo`。项目身份就是路径，所以改名 =
> 换身份 —— 清单里的 `path=`、中转链接、state 目录、rc 块名都跟着变了，
> 只 `mv` 目录会留下一整套对不上的孤儿（见 `wtool move`）。
> **GitHub 仓库名没变**，还是 [allinkernel/wtool-repo](https://github.com/allinkernel/wtool-repo)。

---

## 功能说明

所有命令都在 **repo 工作区内**使用（一路往上找得到 `.repo`）；不在工作区里会报
`not in repo dir!!!`。**例外是 `ggco`**：它只要求当前目录是个 git 仓库
（remote 那一步再按下面的顺序挑），不要求站在 repo 工作区里。

### 命令总表

| 类别 | 命令 | 一句话 |
|---|---|---|
| 定位 | `cs` / `css` | 走到 / 打印含 `.repo` 的目录（repo 根） |
| 定位 | `ct` / `ctt` | 走到 / 打印含 `.git` 的目录（单仓根） |
| 定位 | `cm` / `cmm` | 走到 / 打印 `<repo 根>/.repo/manifests` |
| 定位 | `cdd <目标>` | cd 到某个项目（可按项目名、路径、现存文件/目录、**`-N` gerrit 提交编号**、**一串点往上跳**；纯数字老写法也认） |
| 定位 | `cdd_path <目标>` | 同上但只打印绝对路径，不 cd（`ggcp` 内部用） |
| 查询 | `cnp` / `cnn` | 当前项目在清单里的路径 / 名字（**都不带参数**） |
| 查询 | `repo_mfst_get_*` | 7 个查询函数，见下（包 `my_repo.py`） |
| git | `cnb` / `cnr` | 当前项目在清单里声明的分支 / remote |
| git | `gb` | **打印** push/pull/fetch 命令（只在有 `polygerrit` remote 时多列一行送检命令） |
| git | `gpun [<深度>\|--depth=<深度>]` | 把 `gb` 打印的 `git pull <remote> <branch> --unshallow` **真的跑掉**（带深度就换成 `--depth=<深度>`） |
| git | `gbb` | 按 `gb` 给出的命令**真的推**（公司 gerrit 环境可切成送检） |
| git | `ggco <分支\|tag\|commit>` | 抓远端某个 ref 下来并**直接切过去**（fetch → checkout） |
| gerrit | `ggcp <编号\|链接\|Change-Id> ...` | 把 gerrit 上的提交抓回本地、按仓库并行/串行 cherry-pick；**并行查询、结果按仓库聚拢成一张表**（支持多编号 / 跨仓库 / 链接 / Change-Id）；**同 Change-Id 已在本地历史时该行失败**并提示 `ggrvt` |
| gerrit | `ggrvt <编号\|链接\|Change-Id>` | 把本地历史里**同 Change-Id 的那个提交** `git revert` 掉（**不接受 patchset**）；给 `ggcp` 重新打这个 change 的新 patchset 用 |
| gerrit | `gchk <change>` | 这个 change 有没有 +2 / 有没有 merged（决定能不能推 main） |
| gerrit | `gq [-r] <change>` | change 摘要（`-r`/`--raw` 出原始 JSON） |
| gerrit | `gpush [remote]` | 把当前 HEAD 推到 `refs/for/<清单声明的分支>`（默认 remote `polygerrit`） |
| repo | `rs` | 把当前清单钉住再 `repo sync`（强制同步） |
| repo | `rscur` | 只 sync 当前目录名下的子项目（交互确认） |
| 构建 | `wninja [参数...]` | 优先用 Android prebuilt ninja 构建 |

### 1. 定位：`cs` / `css` / `ct` / `ctt` / `cm` / `cmm`

| 命令 | 行为 | 失败时 |
|---|---|---|
| `cs` | 从 `$PWD` 往上找 `.repo`，`cd` 过去 | `<函数名>: not in repo dir!!!`（stderr，返回 1） |
| `css` | 同上，但只**打印**那个目录 | 同上 |
| `ct` | 从 `$PWD` 往上找 `.git`，`cd` 过去 | `<函数名>: not in git dir!!!`（返回 1） |
| `ctt` | 同上，但只**打印** | 同上 |
| `cm` | 找到 `.repo` 后 `cd <repo 根>/.repo/manifests` | `<函数名>: not in repo dir!!!`（返回 1） |
| `cmm` | 同上，但只**打印** `<repo 根>/.repo/manifests` | 同上 |

> 报错前缀就是函数自己的名字（zsh 用 `funcstack[1]`，bash 用 `FUNCNAME[0]`），
> 所以两个 shell 的报错文字一致。
> `cs` / `ct` 用 `&&` 串联时注意：它们失败返回 1，链子后面的命令不会跑。

### 2. 跳项目：`cdd <目标>` / `cdd_path <目标>`

`cdd` 按这个顺序找目标（命中即停）：

0. **一串点**（`..` / `...` / `....` / …）：**N 个点 = 往上 N-1 层**。
   `..` = 上一层、`...` = 上两层、`....` = 上三层、`........`（8 个点）= 上七层；
   - **不限点数**（没有"最多 6 个点"这回事），**zsh 和 bash 都认**；
   - **不用站在 repo 工作区里**（它不查清单，在任何目录里都能往上跳）；
   - 点到头了就**停在 `/`**：退出码 **0**、什么都不打印（**不算错**）；
     站在 `/` 上再往上还是 `/`；
   - 只有"**整个参数都是点、且至少 2 个点**"才算点参数：`..x`（含别的字符）、
     `.`（只有 1 个点）都不算，照旧走下面 1~5 条；
   - 点参数**优先于"现存目录"**：`cdd ...` 就是往上两层，哪怕当前目录里真有个
     叫 `...` 的目录也不进去（`..` 本身就是个真目录，所以这一条得排在最前面判）。
1. **`-N` = gerrit 提交编号**（新写法）：`-12345` 一眼就能和目录名区分开 ——
   `cdd` 看到 `-` 加数字就知道"这不是路径，是提交"，去 gerrit 查这个编号属于哪个项目
   （走 `ggcp` 同一套服务器解析 + 同一个内部查询函数 `_gr_query_info`，**不复制第二份
   ssh/JSON 代码**），再到本地清单里找那个项目的路径、`cd` 过去。例：`cdd -12345`。
   - `-N` 的判断排在"现存文件/目录"**前面**：哪怕当前目录真有个叫 `-12345` 的目录，
     也按提交编号处理（用户要的就是"`-` 开头一定不是目录"）。
   - 项目在清单里、但目录没检出：`cdd: change N 属于项目 X，但本地还没检出（清单路径 Y）`
     + `先 repo sync Y`，返回 **1**；
   - 项目不在本地清单里：`cdd: change N 属于项目 X，但当前工作区的清单里没有它`，返回 **1**。
2. **目标当前就存在**：是文件 → `cd` 到它的父目录；是目录 → `cd` 进去；
3. **清单里的项目名**（如 `allinkernel/wtool-doc.git`）→ `cd` 到 `<repo 根>/<清单里的 path>`；
4. **相对 repo 根的路径**（目录存在且在清单里有这个 path）→ `cd` 过去；
5. **纯数字 = gerrit 提交编号**（老写法，保留兼容）：`cdd 1234` 也查 gerrit，但它排在
   第 2~4 条"现存文件/目录 → 项目名 → 相对路径"**之后** —— 当前目录真有个叫 `1234`
   的目录时还是进目录。想明确按提交跳，用 `-1234`。

找不到时的报错（都是 stderr）：

| 情况 | 报错 | 返回码 |
|---|---|---|
| 参数个数 ≠ 1 | `Usage: cdd TARGET` + 五行说明 | 2 |
| 一路往上找不到 `.repo` | `cdd: 当前目录不在 repo 工作区里（一路往上都找不到 .repo）` + `想按名字跳转得先站在 repo 工作区里` | 1 |
| 清单里有这个项目、但目录还不存在 | `cdd: 项目 'X' 已在清单里，但目录还不存在：` + 绝对路径 + `先 repo sync X` | 1 |
| 名字和路径都对不上 | `cdd: 清单里没有 'X' 这个项目名或路径` + `看看都有什么：<my_repo.py> list --root <root>` | 1 |
| `-N` 对应的项目在清单里、但目录没检出 | `cdd: change N 属于项目 X，但本地还没检出（清单路径 Y）` + `先 repo sync Y` | 1 |
| `-N` 对应的项目不在本地清单里 | `cdd: change N 属于项目 X，但当前工作区的清单里没有它` | 1 |
| 知道不了 gerrit 在哪 | `cdd: 按提交编号跳转得先知道 gerrit 服务器在哪：` + 两条途径 | 1 |
| gerrit 连不上 / 查不到这个编号 | `cdd: <查询失败原因>`（里面会点出 `change N` 和服务器，例如 `cdd: gerrit 上查不到 change N（编号对不对？有没有权限？）`） | 1 |

> **点参数（第 0 条）没有自己的报错**：命中点参数就往上跳 —— 最坏是停在 `/`（退出码 0），
> 点参数相关的报错根本不存在。不是点参数就交给下面几条，去报它们自己的错。

> **和 zsh 那套 `cd ...` 的关系**：zsh 自己**不认** `cd ...` —— 那是 **oh-my-zsh**
> 的 `lib/directories.zsh` 挂的 4 条 global alias（`...` → `../..`、`....` → `../../..`、
> `.....` → `../../../..`、`......` → `../../../../..`）。所以那条路**只到 6 个点**
> （7 个点就 `no such file or directory`），而且 global alias 是 zsh 专有物，
> **bash 里没有对应东西**（bash 里 `cd ...` 直接 `No such file or directory`）。
> `cdd` 的点参数是自己实现的：两个 shell 都有、几个点都行。
> 顺带一提，真机交互式 zsh 里那 4 条 alias 会**先把 `cdd ...` 改写成 `cdd ../..`**，
> 于是走的是第 2 条（现存目录）—— 落点一样，`cdd` 不依赖那套 alias。

> **`-N` 和纯数字的优先级不同**：`-N` 排在第 2 条前面（`-` 开头就不是目录）；
> 纯数字排在第 2~4 条后面（`cdd 12345` 在真有个叫 `12345` 的目录时，还是进那个目录）。
> 原有的项目名 / 路径 / 现存文件/目录三条路行为不变。

`cdd_path` 是 `cdd` 的"不跳转版"：只打印绝对路径，供 `ggcp` 之类的脚本用。
**点参数只有 `cdd` 有**：`cdd_path` 照旧只认"清单里的名字/路径"（它不 cd，也就没有"往上跳"这回事）。

### 3. 问"我在哪个项目"：`cnp` / `cnn` / `cnb` / `cnr`

| 命令 | 输出 | 说明 |
|---|---|---|
| `cnp` | 当前目录所属项目在清单里的 **path** | 名字沿用历史（叫 `cnp` 但打的是 path）；**不接受参数** |
| `cnn` | 当前项目的清单 **name** | **不接受参数** |
| `cnb` | 清单里声明的 **分支** | 内部走 `cnp` + `repo_mfst_get_branch_from_path` |
| `cnr` | 清单里声明的 **remote 名** | 内部走 `cnp` + `repo_mfst_get_remote_from_path` |

- 传了参数：`cnp: 不接受参数（它报告当前目录属于哪个项目）` / `cnn: 不接受参数（它打印当前项目的清单名字）`，
  返回码 **2**，并提示该用 `cdd <参数>`。
- 不在 repo 工作区的某个 git 仓库里：`cnp: 当前目录不在 repo 工作区的某个 git 仓库里（试试 cdd <项目名>）`，返回 1。
- 在 git 仓库里但清单没这个 path：`cnp: 清单里没有 path='X' 的项目`，返回 1。

### 4. 清单查询族（`repo_mfst_get_*`）与 `my_repo.py`

7 个 shell 函数，把 `my_repo.py` 包成"输出即结果、失败即非 0"的形式（方便 `$(...)` 取值）：

| 函数 | 对应的 `my_repo.py` 动作 |
|---|---|
| `repo_mfst_get_name_from_path <path>` | `name_from_path` |
| `repo_mfst_get_path_from_name <name>` | `path_from_name` |
| `repo_mfst_get_branch_from_path <path>` | `branch_from_path` |
| `repo_mfst_get_branch_from_name <name>` | `branch_from_name` |
| `repo_mfst_get_remote_from_name <name>` | `remote_from_name` |
| `repo_mfst_get_remote_from_path <path>` | `remote_from_path` |
| `repo_mfst_get_url_from_name <name>` | `url_from_name` |

> **没有** `repo_mfst_get_url_from_path` —— `my_repo.py` 的 `url_*` 只有"按名字"一种。
> 失败时打印 `<函数名>: <工具路径>: no project with path:'X' in your manifests!!!`（name 版就是 `name:'X'`），返回 1。

`my_repo.py` 的完整命令行（**自包含解析清单**，只依赖 python3 标准库，3.6+）：

```sh
python3 my_repo.py <action> [value] [--root ROOT] [--manifest FILE] [--format tsv|json]

action: name_from_path | path_from_name
        branch_from_path | branch_from_name
        remote_from_path | remote_from_name
        url_from_name
        list | root
```

- `--root` 省略时，从当前目录往上找含 `.repo` 的目录；`--manifest` 省略时用 `.repo/manifest.xml`。
- `list` 默认 TSV，每行 5 列：`path  name  branch  remote  url`；`--format json` 时每项含
  `path / name / branch / revision / remote / url / groups`。
- `url` 是用清单 remote 的 `fetch` 前缀 + 项目 name 拼出来的（`ssh://user@host:29418/...` 或 https 都能拼）。
- 支持的清单语法：`<remote>` / `<default>` / `<project>` / `<include>` / `<remove-project>` /
  `<extend-project>` / `<linkfile>` / `<copyfile>`，外加 `.repo/local_manifests/*.xml`。
  **未识别的标签/属性忽略而不报错**（新版 repo 加的东西不该把这个工具弄挂）。
- 分支解析优先级（`Project.branch`，代码是
  `self.upstream or self.dest_branch or self.revision_expr`）：
  `<project upstream>`（没写就退到 `<default upstream>`）> `<project dest-branch>`
  （没写就退到 `<default dest-branch>`）> `<project revision>` > remote 级 `revision`
  > `<default revision>`；输出时剥掉 `refs/heads/` 前缀。
  ⚠️ 这里原来只列了 4 级、**漏掉 `dest-branch`**（2026-10-04 按 `my_repo.py:88` 订正）；
  测试目前只钉住"upstream 优先于 revision"那一条。
- 找不到项目/路径：stderr 一行原因，退出码 **1**（不是 traceback）。

### 5. 推送与补历史：`gb` / `gpun` / `gbb`

`gb` **只打印**（不执行）—— 在项目目录里跑一次，把该敲的命令抄下来：

```
git push <remote> HEAD:refs/for/<branch>      # 送检
git push <remote> HEAD:<branch>               # 直推
git pull <remote> <branch> --unshallow
git pull <remote> <branch>
git fetch <remote> <branch> --unshallow
git fetch <remote> <branch>
remote: <remote>
branch: <branch>
git remote -v 的输出
```

仓库里有 `polygerrit` remote 时，额外多一行：

```
polygerrit: git push polygerrit HEAD:refs/for/<branch>   # 送检（+2 后才进 main）
```

#### `gpun [<深度> | --depth=<深度>]` —— 把 `gb` 那条 `--unshallow` 真跑掉

```sh
gpun              # 跑 gb 给出的 `git pull <remote> <branch> --unshallow`（补全整个历史）
gpun -30          # 同上，但把 --unshallow 换成 --depth=30（只拉 30 层，不补全）
gpun --depth=30   # 同上（等价写法）
```

`gb` / `gbb` / `gpun` 三条是一套：`gb` **只打印**，`gbb` 只挑 **push** 那条，`gpun` 只挑
**pull** 那条（`git pull <remote> <branch> --unshallow`）—— 它是给 shallow 仓补历史的。

行为：

1. 先跑 `gb`，从它的输出里挑出**唯一**那条 `git pull … --unshallow`
   （`^git pull .*[[:space:]]--unshallow$`，只认 GNU/POSIX `grep -E`，**不需要 `-P`**）；
   挑不出来（`gb` 没给、或 `gb` 自己失败）就报错返回 1，**不静默当成功**。
   多条时取第一条（`gb` 正常只给一条）。
2. 在执行**之前**回显一行 `gpun: 执行 <命令>` —— 让你看清到底跑了什么；
   `gb` 的其它输出（push 那几行、`remote:` / `branch:`、`git remote -v`）**不会**刷出来。
3. **真的执行**它（`eval`），然后把 git 的退出码原样返回；非 0 时多说一句
   `gpun: 上面这条 pull 失败（退出码 <N>）`。

参数与退出码：

| 情形 | 输出 | 退出码 |
|---|---|---|
| `gpun` | `gpun: 执行 git pull <remote> <branch> --unshallow` + git 的输出 | git 的退出码（成功 0） |
| `gpun -30` / `gpun --depth=30` | `gpun: 执行 git pull <remote> <branch> --depth=30` + git 的输出 | 同上 |
| 参数不认（`gpun abc`）、深度不是正整数（`-0` / `--depth=` / `--depth=x`）、参数多于 1 个 | `gpun: <原因>` + `Usage: gpun …`（stderr） | **2** |
| `gb` 挑不出那条命令 | `gpun: gb 没给出 'git pull <remote> <branch> --unshallow' 那条命令` | **1** |
| `gb` 自己失败（不在项目目录里） | `gpun: 拿不到 gb 的输出，没法确定要跑哪条 pull 命令` | **1** |
| git 自己失败（例如**不是** shallow 仓） | git 的报错 + `gpun: 上面这条 pull 失败（退出码 <N>）` | git 的退出码（如 1） |

> `gpun` 不自己判断"是不是 shallow 仓"：`gb` 不管仓浅不浅都会打印那条命令，
> 所以完整仓上跑 `gpun` 会由 git 自己报
> `fatal: --unshallow on a complete repository does not make sense`（退出码 1）。
> 想只加深或只想拉浅一点，用 `gpun -<深度>`。

`gbb` **真的推**，规则：

1. 项目根下如果有个叫 `gbb` 的文件 → 执行 `zsh <项目根>/gbb` 然后结束（留给项目自己定制）；
2. 否则拿 `gb` 的输出，用 `grep -P` 挑一行执行：
   - `need_to_review=1`（**默认**）→ 挑"直推分支"那条 `HEAD:<branch>`；
   - `need_to_review=0` → 挑"送检"那条 `HEAD:refs/for/<branch>`（**公司 gerrit 环境要改这个**，
     改法就是脚本里那个 `need_to_review=1`，见代码注释）。
3. 依赖 GNU grep 的 `-P`（PCRE）。

### 6. 抓取与 gerrit：`ggco` / `ggcp` / `ggrvt` / `gchk` / `gq` / `gpush`

#### `ggco <分支|tag|commit>` —— 抓远端一个 ref，直接切过去

```sh
ggco main         # 切到远端 main（本地没有就建跟踪分支）
ggco v1.2.3       # tag（detached HEAD）
ggco 1a2b3c4      # commit（远端得允许按 SHA 取）
```

只做一件事：**fetch 之后直接 checkout**。和 `ggcp` 的区别是它不 cherry-pick、
不动你已有的提交；它也不 push、不 reset（`--hard` 更没有）、不用 `checkout -f`。步骤：

1. 参数不是 1 个（或以 `-` 开头）→ `Usage: ggco <分支|tag|commit>` + 三行例子（stderr），返回 **2**；
2. 不在 git 仓库里 → `ggco: 当前目录不是 git 仓库`，返回 1；
3. 工作树有**已跟踪文件**的本地改动（未跟踪文件不算）→
   `ggco: 工作树有本地改动，先 git stash 或 git commit（本命令不覆盖本地改动）：`
   加 `git status --porcelain` 的那几行，返回 1；
4. 选 remote：和 `ggcp` 同一套 —— 有 `polygerrit` 就用它，否则用清单里声明的（`cnr`），
   再否则用第一条；一条都没有 → `ggco: 在 <目录> 里找不到可用的 git remote。现有的：`
   加 `git remote -v`，返回 1；
5. `git fetch <remote> <ref>`；失败 →
   `ggco: 远端没有这个 ref（或取不到）：<remote> <ref>` +
   `看看远端有什么：git ls-remote --heads --tags <remote>`，返回 1；
6. 取下来的东西必须是 commit（`git rev-parse --verify FETCH_HEAD^{commit}`），
   不是 → `ggco: <remote> 的 <ref> 取下来不是 commit，切不过去`，返回 1；
7. 切过去：
   - 本地**没有**同名分支 → `git checkout <ref>`：分支名会建成本地跟踪分支
     （`git fetch` 已经把 tracking ref 更新了），tag / commit 就是 detached HEAD；
   - 本地**有**同名分支 → `git checkout <ref>` 之后和刚 fetch 的 commit 比一下：
     一样就成功；不一样 →
     `ggco: 本地分支 X 停在 <A>，不是刚 fetch 的 <B>` +
     `本命令不 reset 本地分支；要更新就自己 git merge --ff-only FETCH_HEAD`，返回 1。

成功时打一行：`ggco: <目录> 现在在 <分支名|detached> @ <短 sha>（来自 <remote> <ref>）`。

> `ggco` 不需要 gerrit 服务器：remote 名和 URL 都从当前仓库自己取，
> 所以普通 git 仓库（只有 `origin`）里也能用。

#### 服务器地址是怎么找到的（先命中先用）

1. 环境变量：`WTOOL_GERRIT_HOST`（可写 `user@host:29418`）、`WTOOL_GERRIT_PORT`、
   `WTOOL_GERRIT_USER`、`WTOOL_GERRIT_SSH_KEY`；
2. 配置文件（**按 shell 语法 source 的几行变量**）：
   `$WTOOL_GERRIT_CONF` → `<repo 根>/.gerrit/client.conf` → `~/.wtool/gerrit.conf`；
3. 自动猜：当前 git remote / 清单 remote 里 URL 带 `29418` 或 `gerrit` 的那条
   （`ssh://user@host:port/path` 和老式 `user@host:path` 都认，`http(s)://` 不当 ssh 端点用）。

配置文件长这样（键名就是这四个）：

```sh
host=gerrit.company.com
port=29418
user=mindul
sshkey=~/.ssh/id_rsa
```

默认值：`port` 没给就是 `29418`，`user` 没给就是 `$USER`。都找不到时 `ggcp` 会打印
`ggcp: 不知道 gerrit 服务器在哪。请任选一种方式告诉它：` 加三条途径，返回 1
（`ggrvt` 同一条报错，前缀换成 `ggrvt:` —— 报错前缀跟着敲的命令走）。

#### `ggcp <编号|链接|Change-Id> ...`

**所有入口最后都坍缩成"按 gerrit 编号打补丁"这一件事**：内部先 `_gr_query_one` 查询，
再按项目分组交给 `_gr_repo_batch` 执行（每个仓库一个后台任务）。

```sh
ggcp 1234                                   # 一个编号（当前 patchset）
ggcp 1,2,3                                  # 英文逗号分隔的编号列表
ggcp 1 2 3                                  # 空格分隔的编号列表（和上面等价）
ggcp 1,2 3                                  # 两种可以混用
ggcp 101 102 103 104                        # 四笔（可以跨仓库）
ggcp 1234/2                                 # 指定第 2 个 patchset
ggcp -p 2 1234 5678                         # -p 给这一批都指定 patchset
ggcp https://gerrit.company.com/c/proj/+/1234     # 链接里自动取编号
ggcp https://gerrit.company.com/#/c/1234/2        # 老式链接也认
ggcp I1111111111111111111111111111111111111111    # 按 Change-Id（见下）
ggcp -y I1111…                              # 全打，不再问
ggcp -n I1111…                              # 全跳过，只打表
```

| 选项 | 作用 |
|---|---|
| `-p <n>` / `--patchset <n>` / `--patchset=<n>` | 这一批都用第 n 个 patchset（默认：各自当前的 patchset；也可以写成 `1234/2`） |
| `-y` / `--yes` | 不再逐个问，全都打（只影响 Change-Id 那条路） |
| `-n` / `--no` | 不再逐个问，全都跳过 |
| `-h` / `--help` | 打用法 |

##### 两阶段执行：并行查询 → 按仓库分组

1. **阶段 1：并行查询。** 用户给的每一笔补丁（`ggcp 1,2,3` 就是三笔）各起一条 gerrit
   查询，**全部并行**；每条查询拿到 `project / commit SHA / patchset / ref`，并算出本地
   清单里的相对路径。
2. **阶段 2：按仓库分组。** 同一个项目（= 同一个仓库）的提交**串行**、按用户给的顺序
   cherry-pick；不同项目**并行**。每个仓库的结果先写进自己的缓冲文件，**这个仓库全部
   结束**（成功或失败）后才交给总表；不同仓库的输出不会互相穿插。
3. 所有仓库结束后，按**本地项目路径排序**合并成**一张表**；同一个仓库的多行连续，
   行内顺序就是用户给的顺序。查询失败的排在最后（没有仓库可归）。

##### 输出：一行总述 + 一张表（单笔也是表）

> **成功路径 stderr 是空的（0 字节），表格只走 stdout。** 两阶段的后台作业跑在一个
> 子 shell 里，交互式 shell 不会往终端打 `[1] 12345` / `[1]+ Done ...` 这类作业控制
> 提示，所以 `ggcp 1,2,3 2>err` 的 `err` 是空的。只有失败路径才会有诊断信息走 stderr
> （例如 Change-Id 查不到的具体原因），表格照样走 stdout。

**单笔** `ggcp 1234` 也只打一张表，不再有"正在下载 / 正在打补丁 / 打补丁成功"这种叙述行：

```text
1 个仓库 / 1 笔提交 / 成功 1 / 失败 0
项目名          项目路径  提交 id       patchset  结果说明
--------------  --------  ------------  --------  --------
platform/mylib  mylib     263f1383dbca  1         成功
```

**四笔、跨两个仓库**（`ggcp 101 102 103 104`）合并成同一张表；两行 `mylib` 连续、
两行 `other` 连续，仓库之间按路径排序：

```text
2 个仓库 / 4 笔提交 / 成功 4 / 失败 0
项目名          项目路径  提交 id       patchset  结果说明
--------------  --------  ------------  --------  --------
platform/mylib  mylib     40be6b51f7a4  1         成功
platform/mylib  mylib     bd95b5f1546b  1         成功
platform/other  other     b8a044ca0cd8  1         成功
platform/other  other     088d75bf36eb  1         成功
```

列的含义：

| 列 | 内容 |
|---|---|
| 项目名 | gerrit 的项目名（如 `platform/mylib`） |
| 项目路径 | 本工作区里的相对路径（如 `mylib`）；清单里找不到时写 `-` |
| 提交 id | cherry-pick 用的 commit id 的**前 12 位**（短 SHA） |
| patchset | 实际打的那个 patchset 号（没指定就取 gerrit 的 current） |
| 结果说明 | `成功` / 失败原因（见下）；表格**不上色**，避免 ANSI 码破坏中文对齐 |

> **为什么没有"查询中 → 下载中 → cherry-pick 中"的进度行**：表格是一次性打印的，
> 做不到原地刷新；按用户口径，这时就"只在该仓库全部结束后输出它的行，状态直接给最终
> 结果"，用最上面一行总述看总体进度（`N 个仓库 / N 笔提交 / 成功 N / 失败 N`）。

##### 失败原因：三种分类

`结果说明` 列按下面顺序判断（`git status --porcelain --untracked-files=no`）：

| 情况 | 结果说明 | 说明 |
|---|---|---|
| cherry-pick 成功 | `成功` | — |
| **同一个 Change-Id 已经在本地历史里** | `此 Change-Id 已在本地历史（提交 <短 sha>，patchset <n>）→ 先 ggrvt <编号> 回退，再打 <编号>/<patchset>` | **不 fetch、不 cherry-pick**，该行算失败；先 `ggrvt` 回退旧的那个（见下）。历史里同名 Change-Id 有好几个提交时改成列出全部 SHA + `ggrvt <编号> 会拒绝回退，请手工处理` |
| cherry-pick 失败，且 `git status` **为空** | `此提交本地已经有了（可能已合入）` | 空提交/已经合入，没产生冲突文件。**没有 Change-Id 的提交**走这条（有 Change-Id 的会被上面的预检先拦下，根本走不到 cherry-pick） |
| cherry-pick 失败，且 `git status` **有文件** | `<文件1> <文件2> … 文件冲突` | 逐个列出冲突文件（如 `ps1.txt 文件冲突`） |
| 其它失败（fetch / 校验 / 进不了目录 …） | `下载失败：<关键 stderr 行>` / `抓到的 commit（X）和 gerrit 说的（Y）不一致` / `项目目录不存在：X（先 repo sync X）` / `本地清单里没有项目 X` / `查询失败：<关键 stderr 行>` | 只取关键行，不把整段 git/ssh 输出塞进表格 |
| 工作树原本就有已跟踪文件的改动 | `工作树有本地改动（先 stash/commit）` | **不动**这样的工作树；先自己 stash/commit |
| gerrit 没配置 / Change-Id 展开失败 | `查询失败：不知道 gerrit 服务器在哪` / `查询失败：Change-Id 展开失败` | 连"补丁结果"都没进入的失败也打表；详细原因（配置途径 / 哪个 Change-Id）仍在 stderr |

**冲突后一定收干净**：失败时如果 `CHERRY_PICK_HEAD` 还在，执行
`git cherry-pick --abort`（**只用 `--abort`，绝不 `reset --hard`**）；然后重新看
`git status --porcelain --untracked-files=no`，确认工作树回到打补丁前的状态。
万一 `--abort` 失败就用 `git cherry-pick --quit` 清状态，并在结果里加
`（工作树没清干净，请手工处理）` —— 不会悄悄把冲突态留给你。

##### 同 Change-Id 预检：本地已经有了就不打

**为什么有这条**：`ggcp 1234/1` 打过 ps1 之后，再 `ggcp 1234/2` —— ps2 只是比 ps1
多改了一个文件，`git cherry-pick` 会**成功**，于是 `git log` 里出现**两个同
Change-Id 的提交**（推 gerrit 时就成了同一笔的重复提交）。所以现在进 cherry-pick
之前先查本地历史：

1. 在**目标仓库里**（已经 `cd` 到项目目录）用
   `git log --format=%H --grep='^Change-Id: <Change-Id>$'` 找**同 Change-Id** 的提交；
   Change-Id 是 gerrit query 返回的（新版 gerrit 的 `change_id`，老版从
   `id`（`project~branch~I…`）里拆出来）；
2. 找到了就**不再 fetch、不再 cherry-pick**，该行结果写清楚，并且**该行算失败**
   （整条命令返回 **1**，其它仓库 / 其它 change 照常处理，不会因为一个失败就全停）：

   ```text
   此 Change-Id 已在本地历史（提交 68dd4339ead8，patchset 1）→ 先 ggrvt 1234 回退，再打 1234/2
   ```

   "patchset 1"是**比出来的**：把这个 change 的所有 patchset ref 一次 fetch 下来
   （只下对象），再和本地那个提交比 `git patch-id`（同一个补丁 cherry-pick 之后
   patch-id 不变）。认不出就只写到"提交 <sha>"为止；
3. **同一个 Change-Id 在本地有多个提交**（历史遗留）时，报错里列出**全部** SHA，并提示
   `ggrvt 1234 会拒绝回退，请手工处理` —— `ggrvt` 只会回退"恰好一个"的情况。

> **已经被 `ggrvt` 回退掉的提交不算"还在"**：`git revert` 不会删历史，那个提交
> 连同它的 `Change-Id:` 行还躺在 `git log` 里。预检会把"被 revert 掉的"剔掉
> （依据 revert 提交里的 `This reverts commit <sha>.` 那行），所以 `ggrvt` 之后
> `ggcp 1234/2` 就能打了，而且**有效的同 Change-Id 提交始终只有一个**。
>
> 已知边界：把 revert 再 revert 回来（补丁重新生效），预检认不出来，仍按
> "已被回退"处理 —— 这种情况下先手工 `git log` 确认。
>
> 不带 patchset 的 `ggcp 1234` 行为和以前一样；`ggcp 1234/1` **重复打**同样命中
> 这条预检（同 Change-Id 已经在历史里了），结果是失败 + `ggrvt` 提示，而不是
> "空提交成功"。

##### 退出码与失败隔离

- 全部成功 → **0**；只要有一笔失败 → **1**；
- 同一个仓库里一笔失败**不影响后面的提交**（冲突后 abort，接着打下一笔）；
- **已经成功的提交保留**，不会因为后面的失败回滚；不同仓库互不影响；
- `git fetch` / `cherry-pick` 的原始输出默认不刷屏，只有关键错误会进 `结果说明`。

##### 指定 patchset：只有 `1234/2` 和 `-p 2` 两种写法

⚠️ **指定 patchset 只有两种写法：`1234/2`（斜杠）和 `-p 2`**。
**老写法 `ggcp 1234 1` 故意不支持** —— 第二个位置参数现在也是"一个编号"，
所以 `ggcp 1234 1` 会被当成**编号 1234 和编号 1 两个补丁**（这正是"空格分隔多个编号"的代价，
用户 2026-10-09 明确认可 `1234/2` 斜杠写法）。

| 你想表达 | 写法 | 结果 |
|---|---|---|
| 编号 1234 的**第 2 个** patchset | `ggcp 1234/2` 或 `ggcp -p 2 1234` | 打 1234 的 ps2 |
| 编号 1234 的当前 patchset | `ggcp 1234` | 打 1234 的 current |
| 编号 1234 **和** 编号 1 两个补丁 | `ggcp 1234 1` | 打两个（**不是** ps1） |
| 编号 1234 **和**编号 2 两个补丁 | `ggcp 1234,2` 或 `ggcp 1234 2` | 打两个（**不是** ps2） |
| 这一批都用第 2 个 patchset | `ggcp -p 2 1 2 3` | 三个编号都打 ps2 |

> 逗号**是编号分隔符**，不是 patchset 分隔符：`_gr_collect_args` 先按逗号把每个参数
> 拆成多个编号，所以 `1234,2` 和 `1234 2` 一样都是**两个编号**。
> （内部函数 `_gerrit_parse_change_arg` 单独调用时确实认 `1234,2` 为"编号+patchset"，
> 但 `ggcp` 的公开入口永远先过逗号拆分 —— 所以**对用户只有斜杠和 `-p` 两种**。
> 测试里那条 `_gerrit_parse_change_arg 1234,2` 测的是内部函数，不代表 `ggcp 1234,2`
> 的公开行为。）

**按 Change-Id 打**（`I` + 40 位十六进制）时，它先去 gerrit 查这个 Change-Id 的**所有提交**
（同一个 Change-Id 可能横跨多个分支 / 多个 change，每个还有多个 patchset），打一张
**选择表**，再**挨个问**"给这个仓库打这个补丁吗？"：

```text
编号  patchset  仓库                      路径             提交链接
----  --------  ------------------------  ---------------  ------------------------------------------------------
1     1         platform/libnativehelper  libnativehelper  http://127.0.0.1:8080/c/platform/libnativehelper/+/1/1
1     2         platform/libnativehelper  libnativehelper  http://127.0.0.1:8080/c/platform/libnativehelper/+/1/2
给仓库 platform/libnativehelper 打补丁 1 (patchset 1) 吗？[y/N/q]
```

- 答 `y` 就打，回车/`n` 跳过，`q` = 不再问了（剩下的都跳过）；
- **stdin 不是 tty**（比如 `printf 'y\nn\n' | ggcp …`）时读不到就按"跳过"处理，不会挂住；
- 选择表里的"路径"是本地的工作区相对路径，找不到时写 `（目录不存在）` / `（不在本地清单里）`；
- 选完之后，答应打的那几笔走上面同一套两阶段流程，最后再打**结果表**；
- ⚠️ 同一个 Change-Id 的**多个 patchset 连着答应打**时，只有第一个会成功：第一个打上之后，
  后面的都会被"同 Change-Id 已在本地历史"预检拦下（**这正是想要的** —— 它们互相覆盖，
  全打上就是两个同 Change-Id 的提交）。要换 patchset 就先 `ggrvt <编号>` 回退旧的。

它做的事（每一步都能在 `env.zsh` 里找到）：

0. `_gr_collect_args` 把参数**坍缩成 `编号|patchset` 列表**（逗号 / 空格 / 链接 / `1234/2`），
   Change-Id 单独收集，稍后用 `_gr_expand_changeids` 展开成同样的列表；
1. `_gerrit_resolve` 解析 gerrit 服务器（上面那套）；
2. **阶段 1**：每个补丁起一个后台查询 `_gr_query_one`（内部是 `_gr_query_info`）：
   `ssh <user>@<host> -p <port> gerrit query --format=JSON --patch-sets --current-patch-set "change:<n>"`
   （**ssh 的 stdin 被挡成 `/dev/null`** —— 不然它会把用户要敲的答案吞掉），
   再用 `gerrit_query.py patchset <n> [ps]` 选 patchset、拿 `revision`/`ref`，
   并算本地路径；
3. **阶段 2**：按项目分组，每个仓库一个后台 `_gr_repo_batch`；仓库内部逐个提交
   `cd` 到项目目录、选 remote（`polygerrit` → 清单声明的 → 第一条）、
   **先做同 Change-Id 预检**（命中就写失败行，**不 fetch、不 cherry-pick**）、
   `git fetch <remote> <ref>`、核对 `FETCH_HEAD == revision`、`git cherry-pick <revision>`；
4. 失败时按上面三种分类写 `结果说明`，必要时 `git cherry-pick --abort`，继续下一笔；
5. 所有仓库结束后合并 `rows.*`，打**总述 + 一张表**，按有没有失败返回 0 / 1。

#### `ggrvt <编号|链接|Change-Id>` —— 回退本地那笔（`ggcp` 预检叫你来的）

```sh
ggrvt 1234                                        # 回退本地历史里 change 1234 那个提交
ggrvt https://gerrit.company.com/c/proj/+/1234    # 链接也认
ggrvt I1111111111111111111111111111111111111111   # 按 Change-Id 也认
ggrvt 1234/2                                      # ✗ 不接受 patchset（返回 2）
```

只做一件事：在本地把**同 Change-Id 的那个提交** `git revert --no-edit <sha>` 掉
（`LC_ALL=C`，让 revert 消息里的 `This reverts commit <sha>.` 永远是英文 ——
`ggcp` 的预检靠这行认出"这个提交已经被回退过"）。**不动远端、不 reset、不改别的提交、
不碰工作树里别的改动。**

它做的事：

1. **查 gerrit 拿项目名**：`_gr_query_info`（和 `ggcp` / `cdd -N` 同一份查询函数，不复制
   ssh/JSON 代码）；编号 / 两种 gerrit 链接 / Change-Id 都认（复用
   `_gerrit_parse_change_arg`），但**一次只接一个 change、且不接受 patchset**。
   给 **Change-Id** 时要求它在 gerrit 上**唯一对应一个 change**；同一个 Change-Id 横跨
   多个分支 / 项目时（gerrit 会回多条）不替你挑，报
   `Change-Id I… 对应 N 个提交（可能跨分支/项目），请改用编号` —— 换成编号再来；
2. **定位仓库**：和 `cdd -N` 一样 —— gerrit 给项目名 → 本地清单给路径 → `cd` 过去。
   清单里没有 / 目录没检出 / 不在 repo 工作区里都明确报错；
3. 在项目目录里用 `git log --format=%H --grep='^Change-Id: <id>$'` 找本地提交，
   **被 revert 掉的算没有**（所以重复回退不会把同一个提交 revert 两次）；
4. 结果分三种：
   - **恰好一个** → `git revert --no-edit <sha>`；成功后打一行：
     `已回退 68dd4339ead8（change 1234, patchset 1）→ 现在可以 ggcp 1234/2`
     （patchset 那个数还是比 `git patch-id` 认出来的，认不出就只写 change 号；
     建议的 patchset 是 gerrit 上的 **current**）；
   - **零个** → `ggrvt: 本地历史里没有该 Change-Id 的提交（change 1234 还没打上？）`
     + `先 ggcp 1234`，返回 **1**；
   - **多个** → `ggrvt: 本地历史里有 N 个同 Change-Id 的提交，不敢替你决定回退哪个：`
     跟着**逐个列出 SHA + subject**，**不擅自 revert**，返回 **1**（自己挑一个
     `git revert --no-edit <sha>`）。
5. **冲突 / 失败**：先 `git revert --abort`（**只用 `--abort`，绝不 `reset --hard`**）把
   中间态收干净，再报 `ggrvt: 回退 <sha> 失败：<关键行>`，返回 **1**；工作树真的没清干净
   会额外打 `工作树没清干净，请手工处理：` + `git status` 那几行。

| 退出码 | 含义 |
|---|---|
| 0 | 回退成功（stdout 只有一行，**stderr 0 字节**） |
| 1 | 查不到 / 项目没检出 / 零命中 / 多命中 / 工作树脏 / revert 冲突（原因都在 stderr） |
| 2 | 参数不对（没给、给多了、给了 patchset、给了列表、认不出来） |

##### 完整工作流：先 1 后 2（失败）→ 回退 → 再打 2（成功）

```sh
$ ggcp 1234/1
1 个仓库 / 1 笔提交 / 成功 1 / 失败 0
项目名          项目路径  提交 id       patchset  结果说明
--------------  --------  ------------  --------  --------
platform/mylib  mylib     68dd4339ead8  1         成功

$ ggcp 1234/2                  # ← 同一个 Change-Id 已经在本地历史里
1 个仓库 / 1 笔提交 / 成功 0 / 失败 1
项目名          项目路径  提交 id       patchset  结果说明
--------------  --------  ------------  --------  -------------------------------------------------------------------------------------------
platform/mylib  mylib     7662edd59300  2         此 Change-Id 已在本地历史（提交 68dd4339ead8，patchset 1）→ 先 ggrvt 1234 回退，再打 1234/2

$ ggrvt 1234
已回退 68dd4339ead8（change 1234, patchset 1）→ 现在可以 ggcp 1234/2

$ ggcp 1234/2
1 个仓库 / 1 笔提交 / 成功 1 / 失败 0
项目名          项目路径  提交 id       patchset  结果说明
--------------  --------  ------------  --------  --------
platform/mylib  mylib     7662edd59300  2         成功
```

对应的 `git log --oneline`（证明不会出现两个**有效**的同 Change-Id 提交）：

```text
打完 1234/1              被预检拦下              ggrvt 之后             重打 1234/2 之后
68dd433 ps1             68dd433 ps1            d15b0a6 Revert "…"     3035853 ps2
213fe42 base            213fe42 base           68dd433 ps1            d15b0a6 Revert "…"
                                                213fe42 base           68dd433 ps1
                                                                       213fe42 base
```

> `git revert` **不删历史**：ps1 那个提交（以及它的 `Change-Id:` 行）一直在 `git log`
> 里。所以"同 Change-Id 提交只有一个"指的是**有效的**只有一个 —— `ggcp` 的预检把
> 被 revert 掉的剔掉，`ggrvt` 回退之后就能重新打。重打完再 `ggcp 1234/2` 仍然会被
> 预检拦下，这也是断言里钉着的。

#### `gchk <change>` —— 能不能推 main

```sh
gchk 1234; echo $?
```

| 退出码 | 含义 |
|---|---|
| 0 | 已 merged（并且当前 patchset 上能看到 +2，会打印是谁给的） |
| 1 | 还没 merged（显示有没有 +2）；`ABANDONED` 也是 1 |
| 2 | 参数不对 / 服务器没解析出来 / 查询失败 |

输出是给人看的摘要：change 号 + 状态、project、branch、subject、patchset 号 + revision 前 12 位、
投票列表、链接。

#### `gq [-r|--raw] <change>`

- 默认：TSV 摘要（`number  status  project  subject`，由 `gerrit_query.py list` 生成）；
- `-r` / `--raw`：原样打印 `gerrit query` 的 JSON（去掉最后的 `stats` 行）。

#### `gpush [remote] [额外参数...]`

```sh
gpush                       # 推到 polygerrit 的 refs/for/<清单声明的分支>
gpush github                # 换 remote
gpush polygerrit --dry-run  # 额外参数透传给 git push
```

- 不是 git 仓库 → `gpush: 当前目录不是 git 仓库`，返回 1；
- 取不到清单声明的分支（`cnb` 失败）→ 报错返回 1；
- 指定/默认的 remote 不存在 → `gpush: 这个仓库没有 remote 'X'。现有的：` + `git remote -v`，返回 1；
- 默认 remote 是 **`polygerrit`**（不是 `github`）。

### 7. 同步与构建：`rs` / `rscur` / `wninja`

#### `rs` —— 钉住当前清单再强同步

```sh
rs
```

实际跑两条：

```sh
repo manifest -o <mktemp 出来的文件>.xml
repo sync -c -j<cpu 数> --force-sync --force-checkout -d -m <上面那个文件>
```

`-j` 的数值 = `/proc/cpuinfo` 里 `processor` 行数。**会丢弃未提交改动/强制覆盖本地**
（`--force-sync --force-checkout -d`），用之前想清楚。

#### `rscur` —— 只同步"当前目录名下"的子项目

```sh
cd <repo 根>/vendor/company
rscur
# total N repos in vendor/company, execute it? ({ENTER/Y/y}/{N/n/*})
```

- 站在某个项目目录里（`cnn` 能给出项目 path）→ 直接 `repo sync -c <项目 path>`；
- 否则收集 `repo list` 里以"当前目录相对 repo 根的路径"开头的子项目名，
  **打印将要执行的命令**（`==>repo sync ...`），问一句，回车 / `Y` / `y` 才执行；
- 用 `repo sync --force-sync -d -c <子项目...> -j$(nproc)`；
- 依赖 **ripgrep（`rg`，用到 `--pcre2`）** 和 `nproc`；
- 当前目录在 `repo list` 里没有任何子项目 → `rscur: TODO: repo list has no such dir before download it!!!`。

#### `wninja [ninja 参数...]` —— 找对 ninja 再构建

```sh
wninja -C out build_image
```

1. 先 `cs` 跳到 repo 根；
2. 选 ninja 二进制：`<repo 根>/prebuilts/build-tools/linux-x86/bin/ninja` 存在就用它，
   否则回退 PATH 里的 `ninja`；
3. 按顺序找构建文件，用第一个存在的：
   `out/combined-*.ninja` → `out/build.ninja` → `out/*/*/build.ninja`；
4. 都没有 → `Error: No ninja build file found.`，返回 1。

（两份实现的机制不同：zsh 用 `(N)` glob 限定符、bash 用 `shopt -s nullglob`，
都是"没匹配就是空"；选择顺序两边一样。**这段是读代码得出的，测试里没有覆盖 `wninja`**。）

> ⚠️ 还有一处两份不一样（2026-10-04 补充）：`env.zsh` 的 `wninja` 开头有
> `if [[ -z $ZSH_VERSION ]]; then return; fi`（代码注释写着 "this only for zsh"），
> 所以**把 `env.zsh` 拿到 bash 里 source 的话 `wninja` 什么都不做**（静默 return 0）；
> `env.bash` 那份没有这道门。正常用法不受影响（zsh 用 `env.zsh`、bash 用 `env.bash`），
> 但"两份等价"这句话对 `wninja` 只在各自的 shell 里成立。

---

## 安装（由 wtool 统一管）

安装由 wtool 统一管：见 [wtool 的 README（GitHub：allinkernel/wtool）](https://github.com/allinkernel/wtool-doc/blob/main/README.md) —— 本仓库只是源码/配置，
装的时候是 `wtool install tools/git-repo-sh-tools`（**项目路径就是它的身份** —— 没有单独的 id，见 ADR-0037）。

> ⚠️ **wtool 的项目只在容器里装 / 测**（用户级规矩，2026-10-04）：本机（WSL）是临时
> 的手工环境，wtool 彻底调通之前**不在本地落地**。要在容器里验证就 `--network=host`
> 挂工作区；**真机上装本项目必须由用户明确同意**，助手不得自行 `wtool install`。

## 配置项

| 变量 | 谁设的 | 含义 |
|---|---|---|
| `WTOOL_PROJECT_DIR` | wtool 块；本文件里给了兜底默认值 | 本项目的中转链接 `~/.wtool/wtool-work-dir/links/tools/git-repo-sh-tools`；下面两个工具路径都从它拼 |
| `WTOOL_REPO_TOOL` | `env.zsh` / `env.bash` 自己 export | `$WTOOL_PROJECT_DIR/my_repo.py`，清单查询工具 |
| `WTOOL_GERRIT_TOOL` | `env.zsh` / `env.bash` 自己 export | `$WTOOL_PROJECT_DIR/gerrit_query.py`，解析 gerrit query JSON |
| `WTOOL_GERRIT_HOST` | 你 | gerrit 主机；可写 `user@host:port`（这时 user/port 也从这里拆） |
| `WTOOL_GERRIT_PORT` | 你 | ssh 端口，默认 `29418` |
| `WTOOL_GERRIT_USER` | 你 | ssh 用户名，默认 `$USER` |
| `WTOOL_GERRIT_SSH_KEY` | 你 | ssh 私钥，给了就 `-i <key> -o IdentitiesOnly=yes` |
| `WTOOL_GERRIT_CONF` | 你 | 额外的 gerrit 配置文件路径（优先于另外两个默认位置） |

gerrit 配置文件的另外两个默认位置：`<repo 根>/.gerrit/client.conf`、`~/.wtool/gerrit.conf`；
键名 `host` / `port` / `user` / `sshkey`。`gb` / `gbb` 读的是**清单**里声明的 branch/remote
（`cnb` / `cnr`），不是 git 自己的 `branch.<name>.remote`。

## 快捷键

本仓库**不定义任何快捷键 / key binding / 补全**（env 文件里没有 `bindkey`、`bind -x`、`complete`）。
补全由别的项目提供：wtool 自己的命令补全挂在 `wtool-base-tools` 项目的 env 上
（`completion/wtool.zsh` / `completion/wtool.bash`）。

## 排错

| 现象 / 报错 | 原因 / 怎么办 |
|---|---|
| `cs: not in repo dir!!!`（或 `ct: not in git dir!!!`） | 当前目录一路往上没有 `.repo`（或 `.git`）；先 `cd` 进工作区 |
| `cnp: 不接受参数（它报告当前目录属于哪个项目）`（返回 2） | `cnp` / `cnn` 都不带参数；想按名字跳转用 `cdd <项目名>` |
| `cnp: 当前目录不在 repo 工作区的某个 git 仓库里（试试 cdd <项目名>）` | 当前目录不在工作区的任何项目里（比如就在 repo 根）：`cdd <项目名>` |
| `cnp: 清单里没有 path='X' 的项目` | 这个目录不在清单里（可能是没 sync 下来的目录）；`cdd <项目名>` 或 `my_repo.py list` 看有哪些 |
| `cdd: 当前目录不在 repo 工作区里（一路往上都找不到 .repo）` | 按名字跳转必须先站在工作区里 |
| `cdd: 项目 'X' 已在清单里，但目录还不存在：` | 先 `repo sync X` |
| `cdd: 清单里没有 'X' 这个项目名或路径` | 名字/路径拼错；按提示跑 `my_repo.py list --root <root>` |
| `cdd: change N 属于项目 X，但本地还没检出（清单路径 Y）` | 这个 gerrit 编号对应的项目还没 sync 下来；按提示 `repo sync Y` |
| `cdd: change N 属于项目 X，但当前工作区的清单里没有它` | 编号对应的项目不在这份清单里（用错工作区 / 清单不同步）；换对工作区，或先更新清单 |
| `cdd: 按提交编号跳转得先知道 gerrit 服务器在哪：` | 按提示设 `WTOOL_GERRIT_HOST`，或写 `<repo 根>/.gerrit/client.conf` |
| `cdd: gerrit 上查不到 change N（编号对不对？有没有权限？）` | 编号错、或这个编号不在这台 gerrit 上；`cdd -N` 和纯数字 `cdd N` 都会走这条 |
| zsh 里 `cd ...` 好使、`cd .......`（7 个点）报 `no such file or directory` | 那是 oh-my-zsh 的 4 条 global alias（只到 6 个点），不是 zsh 本体；用 `cdd .......` —— 它不限点数，bash 里也一样 |
| `cdd ..x` 报 `cdd: 清单里没有 '..x' 这个项目名或路径`（以为它会往上跳） | 只有"**整个参数都是点、且至少 2 个点**"才算点参数；含别的字符的照旧按项目名/路径解析 |
| `ggcp: 不知道 gerrit 服务器在哪。请任选一种方式告诉它：` | 按提示设 `WTOOL_GERRIT_HOST` / 写 `~/.wtool/gerrit.conf` / 放 `<repo 根>/.gerrit/client.conf` |
| 结果表里 `查询失败：连 <user>@<host>:<port> 查询 change N 失败` | ssh 不通或公钥没在 gerrit 登记；先手敲一次 `ssh -p <port> <user>@<host> gerrit version` |
| 结果表里 `查询失败：gerrit 上查不到 change N（编号对不对？有没有权限？）` | 编号错或没权限；`ggcp -h` 看参数写法 |
| 结果表里 `此提交本地已经有了（可能已合入）` | 这个补丁已经在当前分支里（或等价的空提交，**没有 Change-Id 的提交**才走这条）；不用再打，退出码 1 |
| 结果表里 `此 Change-Id 已在本地历史（提交 X，patchset N）→ 先 ggrvt <编号> 回退，再打 <编号>/<patchset>` | 同一个 change 的旧 patchset 还在本地历史里（再打就是两个同 Change-Id 的提交）。按提示 `ggrvt <编号>` 回退旧的再打；**不要**手工删提交、也不要 `reset --hard` |
| 结果表里 `此 Change-Id 在本地历史里有 N 个提交（a b …）→ ggrvt <编号> 会拒绝回退，请手工处理` | 历史遗留：同一个 Change-Id 有好几笔本地提交（可能有人手工 cherry-pick 过）。`ggrvt` 不替你挑；自己 `git log --grep` 看清楚再 `git revert --no-edit <sha>` |
| `ggrvt: 本地历史里没有该 Change-Id 的提交（change N 还没打上？）` | 这个 change 的提交不在当前分支历史里（没打过 / 打在了别的分支上）；先 `ggcp N`，或 `cdd -N` 看看项目对不对 |
| `ggrvt: 本地历史里有 N 个同 Change-Id 的提交，不敢替你决定回退哪个：` | 同上有多个；按列出的 SHA 自己挑一个 revert（`ggrvt` 一次只回退一个） |
| `ggrvt: 不接受 patchset（'1234/2'）——回退的是整个提交`（返回 2） | `ggrvt` 回退的是整笔提交，不接受 patchset；用 `ggrvt 1234` |
| `ggrvt: change N 属于项目 X，但本地还没检出（清单路径 Y）` | 按提示 `repo sync Y` |
| `ggrvt: 回退 <sha> 失败：…` + `工作树没清干净，请手工处理：` | revert 冲突且 `--abort` 没收干净（少见）；按 `git status` 手工处理，**别** `reset --hard` |
| 结果表里 `XXX 文件冲突`（可能多个文件） | cherry-pick 和本地文件冲突；命令已经 `git cherry-pick --abort` 收干净，按列出的文件手工处理后再来 |
| 结果表里 `下载失败：…` | 网络/权限/ref 没了；先 `git fetch <remote> <ref>` 手工试一次看完整报错 |
| 结果表里 `抓到的 commit（X）和 gerrit 说的（Y）不一致` | patchset/ref 选错了（或 change 刚被更新）；`gq` 确认后再来 |
| 结果表里 `工作树有本地改动（先 stash/commit）` | 这个仓库有已跟踪文件的改动；`git stash` 或 `git commit` 后再跑（未跟踪文件不影响） |
| `ggcp: N 不是提交编号、gerrit 链接或 Change-Id`（返回 2） | 参数不对；`ggcp -h` 看用法 |
| `ggcp: Change-Id 'I…' 不能指定 patchset（它对应很多个提交）`（返回 2） | 要指定 patchset 就用编号：`ggcp 1234/2` |
| `ggco: 工作树有本地改动，先 git stash 或 git commit（本命令不覆盖本地改动）：` | 先把已跟踪文件的改动 stash / commit 掉；未跟踪文件不影响它 |
| `ggco: 远端没有这个 ref（或取不到）：<remote> <ref>` | ref 名拼错、或 fetch 本身失败（网络/权限）。按提示 `git ls-remote --heads --tags <remote>` 看远端有什么 |
| `ggco: 本地分支 X 停在 A，不是刚 fetch 的 B` | 本地同名分支和远端不一致；本命令**不会**替你 reset。按提示 `git merge --ff-only FETCH_HEAD`，或自己决定怎么处理 |
| `ggco: 在 <目录> 里找不到可用的 git remote。现有的：` | 这个仓库一个 remote 都没有（新的 `git init`？）；先 `git remote add origin <url>` |
| `gpush: 这个仓库没有 remote 'polygerrit'。现有的：` | 换 remote：`gpush <remote>` |
| `rscur: TODO: repo list has no such dir before download it!!!` | 这个目录还没 sync 下来，`repo list` 里没有它的子项目 |
| `rs` / `rscur` 把本地改动弄没了 | 它们带 `--force-sync -d`，就是会丢弃本地改动/强制覆盖 —— 跑之前先 commit 或 stash |
| `wninja` 报 `Error: No ninja build file found.` | 没找到 `out/combined-*.ninja` / `out/build.ninja` / `out/*/*/build.ninja`；先按项目的构建流程生成 |
| `gbb` 说 `grep: -P` 之类的错 | 它用 GNU grep 的 `-P`；BusyBox grep / macOS 自带 grep 不认 |
| `gpun: gb 没给出 'git pull <remote> <branch> --unshallow' 那条命令`（返回 1） | `gb` 的输出里没有那条（不在项目目录里？项目自己盖了 `gb`？）；先单独跑一次 `gb` 看它打印了什么。**这条不会替你猜一条命令去跑** |
| `gpun: 拿不到 gb 的输出，没法确定要跑哪条 pull 命令`（返回 1） | `gb` 自己失败了（多半是"不在项目目录里"，`gb: not in project dir!!!` 就在上面一行）；先 `cd` 进项目 |
| `gpun: 深度要是正整数（>= 1）：'-0'`（返回 2） | 深度只认十进制正整数；`-0` / `--depth=` / `--depth=x` 都不行，看一眼它打出的 `Usage` |
| `gpun: 上面这条 pull 失败（退出码 1）` + `fatal: --unshallow on a complete repository does not make sense` | 这个仓本来就**不是** shallow 仓，`--unshallow` 没意义；想拉就用 `gpun -<深度>`，或直接 `git pull` |
| `gpun: 上面这条 pull 失败（退出码 …）` + 别的 git 报错 | git 自己失败（网络/权限/冲突…），按 git 的报错处理；`gpun` 只回显和转发退出码 |

## 测试

```sh
sh tests/run_tests.sh      # 622 条（六段合计，以脚本最后打印的通过/失败数为准；
                           #   2026-10-22 实测 622 通过 0 失败 —— 这一版加了
                           #   ggcp 的同 Change-Id 预检 + ggrvt，+142 条）
```

测试分六段（都在临时目录里造"公司环境"的假工作区 / 假裸仓 / 假 gerrit，不碰真工作区、不连网）：

1. **`my_repo.py`**（基本查询、分支/remote 解析、`local_manifests` 的增删、`list`、错误处理、
   "没有 `.repo/repo` 也能跑"）；
2. **`gerrit_query.py`**（patchset 选择、`check` 的退出码、`list` / `raw` / 坏输入、
   `commits` 展开与 `table` 打表、**`result-table` 的 5 列 / CJK 宽度 / 坏输入**）；
3. **`env.zsh` / `env.bash` 对比**（`cnp` / `cdd` 的用法报错、**`cdd` 的点参数**
   （2～7 个点各落哪一层、8 个点、12 个点、点到根停在 `/`、`..x` 和 `.` 不被当点参数、
   不在工作区里也能跳、zsh 那 4 条 global alias 把 `...` 改写成 `../..` 时落点一样）、
   `ggcp` 的参数坍缩、颜色退化、`ggco` 端到端、`gpun` 端到端 —— 不连网），
   **同一张用例表跑两个 shell**，用来钉住"两份等价"；
4. **`ggco` 的裸仓夹具**（本地 `git init --bare` + clone，`git push` 只推到那个临时裸仓）：
   新分支 fetch→checkout 后 `HEAD` 必须等于裸仓那条 ref、本地同名分支落后时拒绝并保持原位、
   远端没有这个 ref、工作树脏、用法错误、不在 git 仓库里 —— 每一条的退出码和报错文字都断言。
5. **`gpun` 的 shallow 夹具**（本地裸仓 40 个提交 + `git clone --depth=1 file://…`，
   `gb` 用桩函数覆盖）：`gpun` 之后**不再是** shallow 仓且 40 个提交齐全（证明真跑了
   `--unshallow`）、`gpun -30` / `gpun --depth=30` 之后**仍是** shallow 仓且正好 30 个提交
   （证明 `--unshallow` 真被换成了 `--depth=30`）、桩 `gb` 不给那条命令时返回 1 且**一个
   commit 都没多**、`gb` 自己失败时返回 1、完整仓上由 git 报错并按 git 的退出码返回、
   桩 `gb` 给两条时只跑第一条、五种用法错误返回 2 —— 每一条的退出码、回显的命令、
   报错文字都断言。
6. **`ggcp` / `cdd -N` 的"假 gerrit"夹具**：`_gerrit_ssh` 用桩（`cat` 一个 JSON 文件，
   **一条 ssh 都不发、一个网都不连**），"gerrit 服务器"就是本地裸仓里那几条
   `refs/changes/…`，项目目录是两个真 git 仓（`mylib` / `other`，remote 叫 `polygerrit`，
   都指向那个裸仓）。钉的是：
   - **参数坍缩**：`1,2,3` / `1 2 3` / `1,2 3` 等价、`1234/2`、两种链接、
     `<链接>` 带 `?` 后缀、Change-Id 单独收集、乱参数返回 2；
   - **单笔输出**：正好 4 行（总述 + 表头 + 分隔线 + 一行结果），不是五行叙述；
   - **多笔同仓库**：合并成一张表，两行 `mylib`，总述 `1 个仓库 / 2 笔提交 / 成功 2`；
   - **四笔跨两个仓库**（`101 102 103 104`）：查询桩记录 `start/end` 并 `sleep 0.2`，
     断言**最多同时 ≥2 条查询**（并行查询）；`git` 包装记录 cherry-pick 的
     `start/end`，断言**同一仓库同时最多 1 个**（串行）、**两个仓库同时 ≥2 个**（并行）；
     合并后表里 `mylib` 两行连续、`other` 两行连续，行顺序 = 用户给的顺序；
   - **失败分类**：重复打 → `此提交本地已经有了（可能已合入）`；先造一个改 `ps1.txt`
     的本地提交再打 → `ps1.txt 文件冲突`；两种情况都断言
     `git status --porcelain` 为空、`CHERRY_PICK_HEAD` 不存在、原来的本地提交还在
     （证明 `--abort` 收干净了）；同一个仓库里"1 冲突 + 2 成功"→ 退出码 1、
     `成功 1 / 失败 1`、成功的那个真进来了（**已成功的保留**）；
   - **其它失败**：change 查不到 → `查询失败：…`；项目在清单里但目录没检出 →
     `项目目录不存在：gone/project（先 repo sync …）`；项目不在清单里 →
     `本地清单里没有项目 nope/nope`；
   - **Change-Id**：选择表（编号/patchset/仓库/路径/提交链接）、逐个问两次、答 y 的打上、
     答 n 的不打；`-n` 一个都不打；`-y` 给同一个 change 的两个 patchset 时**只成第一个**
     （第二个被预检拦下 —— 见下）；
   - **同 Change-Id 预检 + `ggrvt`**：change 1234 的两个 patchset（ps2 只在 ps1 上多一个
     文件，正是用户报的场景）—— `ggcp 1234/1` 成功后 `ggcp 1234/2` **必须失败**
     （退出码 1、总述 `成功 0 / 失败 1`、说明里含"已在本地历史" + `patchset 1` + `ggrvt 1234`、
     ps2 的文件**没进来**、`git log --grep` 里同 Change-Id 的提交只有 1 个、HEAD 没动、
     工作树干净、没有 `CHERRY_PICK_HEAD`）；重复打 `1234/1` 同样被拦；`ggrvt 1234` 回退成功
     （HEAD 变成 `Revert "…"`、ps1 文件被撤掉、**有效的**同 Change-Id 提交 0 个）→ 再
     `ggcp 1234/2` 成功、**有效的**同 Change-Id 提交只有 1 个、log 顶部是
     `ps2 / Revert / ps1` → 再打一次又失败（证明不会攒出第二个）；另钉 `ggrvt` 的
     零命中 / 多命中（列出两个 SHA、不擅自 revert）/ 不给参数 / 带 patchset / 列表 /
     项目没检出 / gerrit 没给 Change-Id 各种报错与退出码，以及 `ggcp 1234/1`、`ggrvt 1234`
     **成功路径 stderr 0 字节**；
   - **`cdd -N`**：`-9001`（仓库在工作区里）跳到那个目录、`9001` 老写法也能跳、
     `-9002`（清单里有、目录没检出）打 `属于项目 gone/project，但本地还没检出` 且返回 1、
     `-9003`（清单里没这个项目）打 `属于项目 nope/nope，但当前工作区的清单里没有它`、
     `-9999` 查不到返回 1；同时回归 `cdd` 原来的三条路（现存目录/项目名/现存文件）
     优先级不被抢；
   - **`ggco` 冻结**：`ggco` 的函数体 `cksum` 逐字节比对（zsh `2879919872 2380`、
     bash `3925425235 2531`）—— 用户明确要求"ggco 一个字都不许变"；
   - **stderr / 作业控制噪声**：成功路径 `stderr` 必须 **0 字节**（单独收集，不和
     stdout 混）；再用 `script(1)` 起**真 PTY 的交互式 shell**（monitor 是 on）跑一遍，
     断言终端里没有 `[1] 12345` / `[1]+ Done` / `no job control`，且跑完
     `monitor`/`notify` 保持原值（原本 on 还是 on、原本 off 还是 off）。

夹具故意造成"公司环境"的样子：**没有 `.repo/repo`**、清单里有 `<include>`、
`local_manifests` 里 `remove-project` / 覆盖 revision。

> 整份测试跑的时候 `HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_DATA_HOME` /
> `XDG_STATE_HOME` 全部指向临时目录 —— 夹具的 `git` 和被测 shell 都只看见这份空配置，
> **不读写真 `$HOME`**，也不受用户全局 `insteadOf` / `pull.rebase` 之类的影响。
>
> ⚠️ 本机 PATH 里 `zsh` 可能先命中 wtool 自己装的那份（`~/.wtool/usr/bin/zsh`，
> 它的 `module_path` 指向 `/root/...`，`zsh/regex` 加载不了，测试会大面积红）。
> 跑测试时把 PATH 收干净，例如
> `env $(env | sed -n 's/^\(WTOOL[A-Z_]*\)=.*/-u \1/p') PATH=/usr/bin:/bin sh tests/run_tests.sh`
> （用系统 `/usr/bin/zsh`）—— 这是环境问题，不是代码问题。

## 依赖

- **python3**（3.6+）：`my_repo.py` / `gerrit_query.py` 只用标准库，不装第三方包。
- **zsh 或 bash**：两个 shell 各一份 env，命令、报错、退出码一致。
  `tests/run_tests.sh` 用**同一张用例表**把两个 shell 都跑一遍，它覆盖的是
  `cnp` / `cnn` / `cdd`（含点参数）的报错、落点与退出码、`ggcp` 的拆参数、
  `ggcp` 的同 Change-Id 预检、`ggrvt`、`ggco` 与 `gpun` 的端到端；
  其余命令的"两份等价"靠的是**同改两份文件**，不是测试。
- **git**：`ggco` / `gpun` 全程只用 `git`（`ggco`：`rev-parse` / `status` / `fetch` /
  `checkout` / `show-ref` / `remote`；`gpun`：`pull`），不需要 python、不需要 ssh 配置
  （remote URL 是 https / file:// 也能用）。
- **ssh**：`ggcp` / `ggrvt` / `gchk` / `gq` 走 `ssh <gerrit> gerrit query`，公钥要在 gerrit 上登记过。
- **git（预检 / 回退那几个子命令）**：`ggcp` 的预检用 `git log --grep` + `git patch-id`
  + `git fetch`（把所有 patchset 的 ref 一次拉下来认 patchset）；`ggrvt` 用
  `git log --grep` + `git revert --no-edit`（失败时 `git revert --abort`）。
- **GNU grep（要 `-P`）**：`gbb` 挑命令行用。
- **grep（`-E` 即可）+ `head`**：`gpun` 从 `gb` 的输出里挑那条 `git pull … --unshallow`
  （POSIX ERE，BusyBox / macOS 自带 grep 也认；这是它和 `gbb` 的一处不同）。
- **`rg`（ripgrep，要 `--pcre2`）** 和 **`nproc`**：`rscur` 用；
  `rs` 用 `/proc/cpuinfo` 数 CPU。
- **repo 客户端**：`rs` / `rscur` / `wninja` 分别调用 `repo manifest` / `repo sync` /
  `repo list`，以及 repo 根下的 prebuilt ninja。
- **POSIX 小工具**：`awk`（数成功行、合并日志）、`sort`（结果表按项目路径排序）、
  `mktemp` / `cut` / `tr`（临时文件、短 SHA、去掉表格里的换行）—— 都是系统自带的，
  不装额外包；**表格对齐本身只用 python3**（`gerrit_query.py result-table`）。

## 用的还是"稳定地址"

命令里不写仓库真实路径，而写 `$WTOOL_PROJECT_DIR`
（= `~/.wtool/wtool-work-dir/links/tools/git-repo-sh-tools`，引擎 install 时自动创建、指向本项目根）。
把 wtool 下载到任何目录，这个链接都指向它，命令**在所有机器上行为一致**。

## 与 mytool 版本的差异

| 原 mytool | 现在 | 原因 |
|---|---|---|
| `export WSW_ANDROID_DIR=$(get_this_dir)` | `$WTOOL_PROJECT_DIR` | 加载器已经导出稳定地址，不再需要 `get_this_dir` |
| `$WSW_ANDROID_DIR/my_repo.py` | `$WTOOL_REPO_TOOL`（= `$WTOOL_PROJECT_DIR/my_repo.py`） | 统一命名，且独立于安装位置 |
| `_up_to_have_dir` 依赖外部 source 链 | 内联在 env 文件里 | 本项目停用 `source_all_env.sh` 后要自包含 |
| `my_repo.py` import repo 内部 `manifest_xml` | 自己解析 XML | 公司机器可能是 go 版 repo / 发布包里没有 `.repo/repo`，import 那条路会断 |
| 无 | `ggcp` / `ggrvt` / `gchk` / `gq` / `gpush` | gerrit 检视流程（`ggrvt` 是本地回退） |
| `cdd` 的**点参数**（用户 2026-10-09 说"mytool 就有这个功能，wtool 你给我删了"） | 加回来：`cdd ..` / `cdd ...` / `cdd ....` …，N 个点 = 往上 N-1 层，**不限点数**、**bash 也认**、点到根停在 `/` | wtool 中途丢了这条；zsh 那边只有 oh-my-zsh 的 4 条 global alias（≤6 个点），bash 完全没有 |
| 无 | `cdd -N`（编号 → 项目目录）；纯数字 `cdd N` 保留为老写法 | 用户要求：`-` 开头一眼区分"这是提交，不是目录"；纯数字会和同名目录打架 |

## 文件

| 文件 | 作用 |
|---|---|
| `wtool.xml` | 清单：1 个 `<zshrc>` + 1 个 `<bashrc>`（无 link） |
| `env.zsh` / `env.bash` | 全部命令 + 内联 `_up_to_have_dir` + 两个工具路径（zsh / bash 两份，等价） |
| `my_repo.py` | manifest 查询工具（自包含解析，见上） |
| `gerrit_query.py` | 解析 `gerrit query --format=JSON` 的输出（供 `ggcp` / `ggrvt` / `gchk` / `gq` 用）；动作：`patchset`（10 列 TSV，后两列是 Change-Id 和这个 change 所有 patchset 的 `编号:revision:ref`，给预检/`ggrvt` 认 patchset 用）/ `commits`（一个 Change-Id 的每个 patchset 一行 TSV）/ `table`（把那些行打成对齐的表，`--path-map` 给"项目名→本地路径"）/ **`result-table`（ggcp 的 5 列结果表，CJK 按 2 列对齐）** / `check` / `list` / `raw` |
| `tests/run_tests.sh` | 上面两个 python 工具的测试 + `env.zsh`/`env.bash` 的行为对比（含 `ggco` / `gpun` 的裸仓端到端，以及 `ggcp` 的假 gerrit / 四笔跨两仓库 / 冲突清理 / **同 Change-Id 预检 + `ggrvt`** 夹具） |
| `scripts/release.json` | 发布账：这一版发了哪些资产（名字 / 字节数 / sha256）——**wtool 生成**，`download-release` 按它校验 |
| `docs/download.md` | 给用户看的下载页（这版发了什么、直链在哪）——**wtool 生成**，别手改（见文末「下载」） |
| `architecture.md` | 代码现在长什么样（现状，只写现状） |
| `BACKLOG.md` | 这个项目"接下来做什么、做到哪了" |

> 老版本 README 里"安装"一节写的是叫用户自己 `wtool install`；
> 现在安装口径统一收到 wtool 的 README（本仓库不再讲怎么装）。

## 下载

**下载的内容单独一篇：[`docs/download.md`](docs/download.md)** ——
上面那些直链、这一版发了什么、只有浏览器的机器怎么下，全在那里面，
这份 README 不复述（命令说明书和下载页分开）。

> ⚠️ `docs/download.md` 是 **wtool 生成的**（`wtool pack-release` 每次发布写一遍，
> 见 `wtool-base-tools/wtool.sh` 的 pack-release 与 `wtool-base-tools/docs/spec.md` §生成物清单），
> **不要手改它** —— 改了下次发布会被覆盖。
> 它的内容来自 `scripts/release.json` 和发布账，要改就改发布流程。
