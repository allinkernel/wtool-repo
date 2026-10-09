# tools/git-repo-sh-tools —— repo / git / gerrit 辅助命令

从 `~/source/mytool/android`（原 `wsw-androidrc`）迁移过来的一套 **repo/git 辅助命令**：
在多仓（repo 客户端）工作区里定位、查清单、推送、送 gerrit 检视、同步、构建。

本项目是**纯 env 项目**：`wtool.xml` 里没有 `<link>`，所有能力靠往 rc 文件注入 env 脚本提供
（命令通过 `$WTOOL_PROJECT_DIR` 找到本目录下的两个 python 工具）。
**zsh 和 bash 各一份**（`env.zsh` / `env.bash`，内容等价）：受众里有人机器上没有 zsh。

- 项目路径（**身份就是它**，ADR-0037）：`tools/git-repo-sh-tools`，`priority=40`
- 本仓库没有 `scripts/`（不需要构建/安装脚本）

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
| 定位 | `cdd <目标>` | cd 到某个项目（可按项目名、路径、现存文件/目录、**gerrit 提交编号**） |
| 定位 | `cdd_path <目标>` | 同上但只打印绝对路径，不 cd（`ggcp` 内部用） |
| 查询 | `cnp` / `cnn` | 当前项目在清单里的路径 / 名字（**都不带参数**） |
| 查询 | `repo_mfst_get_*` | 7 个查询函数，见下（包 `my_repo.py`） |
| git | `cnb` / `cnr` | 当前项目在清单里声明的分支 / remote |
| git | `gb` | **打印** push/pull/fetch 命令（只在有 `polygerrit` remote 时多列一行送检命令） |
| git | `gpun [<深度>\|--depth=<深度>]` | 把 `gb` 打印的 `git pull <remote> <branch> --unshallow` **真的跑掉**（带深度就换成 `--depth=<深度>`） |
| git | `gbb` | 按 `gb` 给出的命令**真的推**（公司 gerrit 环境可切成送检） |
| git | `ggco <分支\|tag\|commit>` | 抓远端某个 ref 下来并**直接切过去**（fetch → checkout） |
| gerrit | `ggcp <编号\|链接\|Change-Id> ...` | 把 gerrit 上的提交抓回本地、cd 到对应项目、cherry-pick（支持多编号 / 链接 / 按 Change-Id 展开后逐个问） |
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

1. **目标当前就存在**：是文件 → `cd` 到它的父目录；是目录 → `cd` 进去；
2. **清单里的项目名**（如 `allinkernel/wtool.git`）→ `cd` 到 `<repo 根>/<清单里的 path>`；
3. **相对 repo 根的路径**（目录存在且在清单里有这个 path）→ `cd` 过去；
4. **纯数字 = gerrit 提交编号**（就是 `ggcp` 用的那个）：去 gerrit 查这个编号属于哪个项目
   （走 `ggcp` 同一套服务器解析 + `${WTOOL_GERRIT_TOOL} patchset`），拿到项目名后
   **坍缩成 `cdd <项目名>`** —— 也就是走上面第 2 条。例：`cdd 1234`。

找不到时的报错（都是 stderr）：

| 情况 | 报错 | 返回码 |
|---|---|---|
| 参数个数 ≠ 1 | `Usage: cdd TARGET` + 四行说明 | 2 |
| 一路往上找不到 `.repo` | `cdd: 当前目录不在 repo 工作区里（一路往上都找不到 .repo）` + `想按名字跳转得先站在 repo 工作区里` | 1 |
| 清单里有这个项目、但目录还不存在 | `cdd: 项目 'X' 已在清单里，但目录还不存在：` + 绝对路径 + `先 repo sync X` | 1 |
| 名字和路径都对不上 | `cdd: 清单里没有 'X' 这个项目名或路径` + `看看都有什么：<my_repo.py> list --root <root>` | 1 |
| 编号对应的仓库不在工作区 | `cdd: N 对应的仓库名 X 在当前 repo 工作区不存在`（清单里也没这个项目时再多一行 `（本地清单里也没有 X 这个项目）`） | 1 |
| 知道不了 gerrit 在哪 | `cdd: 按提交编号跳转得先知道 gerrit 服务器在哪：` + 两条途径 | 1 |
| gerrit 连不上 / 查不到这个编号 | `cdd: 连 <user>@<host>:<port> 查询 change N 失败` / `cdd: gerrit 上查不到 change N（编号对不对？有没有权限？）` | 1 |

> 数字这条路是**加在第 1~3 条之后**的：现存目录/文件、清单项目名、相对路径都优先，
> 所以原来的两种用法行为不变（`cdd 12345` 在真有个叫 `12345` 的目录时，还是进那个目录）。

`cdd_path` 是 `cdd` 的"不跳转版"：只打印绝对路径，供 `ggcp` 之类的脚本用。

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

### 6. 抓取与 gerrit：`ggco` / `ggcp` / `gchk` / `gq` / `gpush`

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
`ggcp: 不知道 gerrit 服务器在哪。请任选一种方式告诉它：` 加三条途径，返回 1。

#### `ggcp <编号|链接|Change-Id> ...`

**所有入口最后都坍缩成"按 gerrit 编号打补丁"这一件事**（内部函数 `_gr_apply_change`）。

```sh
ggcp 1234                                   # 一个编号（当前 patchset）
ggcp 1,2,3                                  # 英文逗号分隔的编号列表
ggcp 1 2 3                                  # 空格分隔的编号列表（和上面等价）
ggcp 1,2 3                                  # 两种可以混用
ggcp https://gerrit.company.com/c/proj/+/1234     # 链接里自动取编号
ggcp https://gerrit.company.com/#/c/1234/2        # 老式链接也认
ggcp 1234/2                                 # 指定第 2 个 patchset
ggcp -p 2 1234 5678                         # -p 给这一批都指定 patchset
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

⚠️ **指定 patchset 只有两种写法：`1234/2`（斜杠）和 `-p 2`**。
**老写法 `ggcp 1234 1` 故意不支持** —— 第二个位置参数现在也是"一个编号"，
所以 `ggcp 1234 1` 会被当成**编号 1234 和编号 1 两个补丁**（这正是"空格分隔多个编号"的代价，
用户 2026-10-09 明确认可 `1234/2` 斜杠写法）。

**按 Change-Id 打**（`I` + 40 位十六进制）时，它先去 gerrit 查这个 Change-Id 的**所有提交**
（同一个 Change-Id 可能横跨多个分支 / 多个 change，每个还有多个 patchset），打一张表，
再**挨个问**"给这个仓库打这个补丁吗？"：

```
编号  patchset  仓库                      路径             提交链接
----  --------  ------------------------  ---------------  ------------------------------------------------------
1     1         platform/libnativehelper  libnativehelper  http://127.0.0.1:8080/c/platform/libnativehelper/+/1/1
1     2         platform/libnativehelper  libnativehelper  http://127.0.0.1:8080/c/platform/libnativehelper/+/1/2
给仓库 platform/libnativehelper 打补丁 1 (patchset 1) 吗？[y/N/q]
```

- 答 `y` 就打，回车/`n` 跳过，`q` = 不再问了（剩下的都跳过）；
- **stdin 不是 tty**（比如 `printf 'y\nn\n' | ggcp …`）时读不到就按"跳过"处理，不会挂住；
- 表里的"路径"是本地的工作区相对路径，找不到时写 `（目录不存在）` / `（不在本地清单里）`。

它做的事（每一步都能在 `env.zsh` 里找到）：

0. `_gr_collect_args` 把参数**坍缩成 `编号|patchset` 列表**（逗号 / 空格 / 链接 / `1234/2`），
   Change-Id 单独收集，稍后用 `_gr_expand_changeids` 展开成同样的列表；
1. 解析 gerrit 服务器（上面那套）；
2. `ssh <user>@<host> -p <port> gerrit query --format=JSON --patch-sets --current-patch-set "change:<n>"`
   （**ssh 的 stdin 被挡成 `/dev/null`** —— 不然它会把用户要敲的答案吞掉）；
3. 用 `gerrit_query.py patchset <n> [ps]` 选出 patchset（不指定就取 current），
   拿到 `revision` 和 `ref`；
4. `cdd_path <项目名>` 找到本地目录（找不到/目录不存在会告诉你 `先 repo sync <项目>`）；
5. 选 remote：有 `polygerrit` 就用它，否则用清单声明的，再否则用第一个；
6. `git fetch <remote> <ref>`（走同一把 ssh key），**输出吞掉**；
7. **核对**：`git rev-parse FETCH_HEAD` 必须等于 gerrit 报的 `revision`，不等就**不 cherry-pick**；
8. `git cherry-pick <revision>`，**输出吞掉**；冲突时提示 `git cherry-pick --continue` / `--skip` / `--abort`。

**正常路径只打这四行**（`git fetch` / `cherry-pick` 的原始输出一律不给用户看，
只有失败时才把关键错误打到 stderr）：

```
正在下载N          # N = gerrit 编号
正在打补丁N
打补丁成功          # 绿色
打补丁失败          # 红色
```

有几个编号就有几组这样的行。颜色**只有自动两条，没有开关**：设了 `NO_COLOR` 就不上色；
否则 **stdout 是 tty**（终端里）才上色，重定向/管道里自动退化成纯文本。
一个编号失败不影响后面的编号继续打，但**整体退出码是 1**。

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

安装由 wtool 统一管：见 [wtool 的 README（GitHub：allinkernel/wtool）](https://github.com/allinkernel/wtool/blob/main/README.md) —— 本仓库只是源码/配置，
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
补全由别的项目提供：wtool 自己的命令补全挂在 `bootstrap` 项目的 env 上
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
| `cdd: N 对应的仓库名 X 在当前 repo 工作区不存在` | 这个 gerrit 编号对应的项目还没 sync 下来（或用的是另一份清单）：`repo sync X` |
| `cdd: 按提交编号跳转得先知道 gerrit 服务器在哪：` | 按提示设 `WTOOL_GERRIT_HOST`，或写 `<repo 根>/.gerrit/client.conf` |
| `cdd: gerrit 上查不到 change N（编号对不对？有没有权限？）` | 编号错、或这个编号不在这台 gerrit 上 |
| `ggcp: 不知道 gerrit 服务器在哪。请任选一种方式告诉它：` | 按提示设 `WTOOL_GERRIT_HOST` / 写 `~/.wtool/gerrit.conf` / 放 `<repo 根>/.gerrit/client.conf` |
| `ggcp: 连 <user>@<host>:<port> 查询失败` | ssh 不通或公钥没在 gerrit 登记；先手敲一次 `ssh -p <port> <user>@<host> gerrit version` |
| `打补丁失败`（红）+ `ggcp: change N 查不到（编号对不对？有没有权限？）` | 编号错或没权限 |
| `ggcp: change N 抓到的 commit（X）和 gerrit 说的（Y）对不上，这次不 cherry-pick` | patchset/ref 选错了（或 change 刚被更新）；`gq` 确认后再来 |
| `打补丁失败`（红）+ `ggcp: cherry-pick 没走完（冲突，或者这个补丁已经打过了、变成空提交）：` | 按提示 `git cherry-pick --continue` / `--skip` / `--abort` 收尾 |
| `打补丁失败`（红）+ `ggcp: git fetch <remote> <ref> 失败：` | 网络/权限/ref 没了；下面几行是 `git fetch` 的原始报错 |
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
sh tests/run_tests.sh      # 303 条（六段合计，以脚本最后打印的通过/失败数为准）
```

测试分六段（都在临时目录里造"公司环境"的假工作区 / 假裸仓 / 假 gerrit，不碰真工作区、不连网）：

1. **`my_repo.py`**（基本查询、分支/remote 解析、`local_manifests` 的增删、`list`、错误处理、
   "没有 `.repo/repo` 也能跑"）；
2. **`gerrit_query.py`**（patchset 选择、`check` 的退出码、`list` / `raw` / 坏输入、
   `commits` 展开与 `table` 打表）；
3. **`env.zsh` / `env.bash` 对比**（`cnp` / `cdd` 的用法报错、`ggcp` 的参数坍缩、颜色退化、
   `ggco` 端到端、`gpun` 端到端 —— 不连网），**同一张用例表跑两个 shell**，
   用来钉住"两份等价"；
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
6. **`ggcp` / `cdd <编号>` 的"假 gerrit"夹具**：`_gerrit_ssh` 用桩（`cat` 一个 JSON 文件，
   **一条 ssh 都不发、一个网都不连**），"gerrit 服务器"就是本地裸仓里那几条
   `refs/changes/01/1/1`、`…/1/2`、`…/02/2/1`，项目目录是个真 git 仓
   （remote 叫 `polygerrit`，指向那个裸仓）。钉的是：
   - **参数坍缩**：`1,2,3` / `1 2 3` / `1,2 3` 等价、`1234/2`、两种链接、
     `<链接>` 带 `?` 后缀、Change-Id 单独收集、乱参数返回 2；
   - **颜色**：非 tty（管道）里一个 ANSI 码都不许有；`NO_COLOR=1` 时也不许有；
     **真 pty**（`script -qec` 起伪终端，断言前 `tr -d '\r'`）里绿/红必须带 `\033[32m` /
     `\033[31m`，连真跑一次 `ggcp 1` 的成功行也要带色。⚠️ 用例里显式 `unset NO_COLOR` /
     `env -u NO_COLOR` —— 跑测试的环境自己可能就设了 `NO_COLOR`（本机实测有）；
   - **端到端**：`ggcp 1` 的输出**逐字节**等于三行（`正在下载1` / `正在打补丁1` / `打补丁成功`）
     且 HEAD 上真多了那个提交；`ggcp 1 2` 六行、两个都进来；同一个补丁打第二遍是
     `打补丁失败`（红）+ 退出码 1；Change-Id 会打表（编号/patchset/仓库/路径/提交链接）、
     逐个问两次、答 y 的打上、答 n 的不打；`-n` 一个都不打、`-y` 两个都打；
   - **`cdd <编号>`**：9001（仓库在工作区里）跳到那个目录、9002（清单里有、目录没有）打
     `cdd: 9002 对应的仓库名 gone/project 在当前 repo 工作区不存在` 且退出码 1、
     9003（清单里没这个项目）同理；同时回归 `cdd` 原来的三条路（现存目录/项目名/现存文件）
     优先级不被抢；
   - **`ggco` 冻结**：`ggco` 的函数体 `cksum` 逐字节比对（zsh `2879919872 2380`、
     bash `3925425235 2531`）—— 用户明确要求"ggco 一个字都不许变"。

夹具故意造成"公司环境"的样子：**没有 `.repo/repo`**、清单里有 `<include>`、
`local_manifests` 里 `remove-project` / 覆盖 revision。

> 整份测试跑的时候 `HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_DATA_HOME` /
> `XDG_STATE_HOME` 全部指向临时目录 —— 夹具的 `git` 和被测 shell 都只看见这份空配置，
> **不读写真 `$HOME`**，也不受用户全局 `insteadOf` / `pull.rebase` 之类的影响。

## 依赖

- **python3**（3.6+）：`my_repo.py` / `gerrit_query.py` 只用标准库，不装第三方包。
- **zsh 或 bash**：两个 shell 各一份 env，命令、报错、退出码一致。
  `tests/run_tests.sh` 用**同一张用例表**把两个 shell 都跑一遍，它覆盖的是
  `cnp` / `cnn` / `cdd` 的报错与退出码、`ggcp` 的拆参数、`ggco` 与 `gpun` 的端到端；
  其余命令的"两份等价"靠的是**同改两份文件**，不是测试。
- **git**：`ggco` / `gpun` 全程只用 `git`（`ggco`：`rev-parse` / `status` / `fetch` /
  `checkout` / `show-ref` / `remote`；`gpun`：`pull`），不需要 python、不需要 ssh 配置
  （remote URL 是 https / file:// 也能用）。
- **ssh**：`ggcp` / `gchk` / `gq` 走 `ssh <gerrit> gerrit query`，公钥要在 gerrit 上登记过。
- **GNU grep（要 `-P`）**：`gbb` 挑命令行用。
- **grep（`-E` 即可）+ `head`**：`gpun` 从 `gb` 的输出里挑那条 `git pull … --unshallow`
  （POSIX ERE，BusyBox / macOS 自带 grep 也认；这是它和 `gbb` 的一处不同）。
- **`rg`（ripgrep，要 `--pcre2`）** 和 **`nproc`**：`rscur` 用；
  `rs` 用 `/proc/cpuinfo` 数 CPU。
- **repo 客户端**：`rs` / `rscur` / `wninja` 分别调用 `repo manifest` / `repo sync` /
  `repo list`，以及 repo 根下的 prebuilt ninja。

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
| 无 | `ggcp` / `gchk` / `gq` / `gpush` | gerrit 检视流程 |

## 文件

| 文件 | 作用 |
|---|---|
| `wtool.xml` | 清单：1 个 `<zshrc>` + 1 个 `<bashrc>`（无 link） |
| `env.zsh` / `env.bash` | 全部命令 + 内联 `_up_to_have_dir` + 两个工具路径（zsh / bash 两份，等价） |
| `my_repo.py` | manifest 查询工具（自包含解析，见上） |
| `gerrit_query.py` | 解析 `gerrit query --format=JSON` 的输出（供 `ggcp` / `gchk` / `gq` 用）；
动作：`patchset` / `commits`（一个 Change-Id 的每个 patchset 一行 TSV）/ `table`（把那些行打成对齐的表，`--path-map` 给"项目名→本地路径"）/ `check` / `list` / `raw` |
| `tests/run_tests.sh` | 上面两个 python 工具的测试 + `env.zsh`/`env.bash` 的行为对比（含 `ggco` / `gpun` 的裸仓端到端） |
| `architecture.md` | 代码现在长什么样（现状，只写现状） |
| `BACKLOG.md` | 这个项目"接下来做什么、做到哪了" |

> 老版本 README 里"安装"一节写的是叫用户自己 `wtool install`；
> 现在安装口径统一收到 wtool 的 README（本仓库不再讲怎么装）。
