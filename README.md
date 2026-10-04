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
`not in repo dir!!!`。

### 命令总表

| 类别 | 命令 | 一句话 |
|---|---|---|
| 定位 | `cs` / `css` | 走到 / 打印含 `.repo` 的目录（repo 根） |
| 定位 | `ct` / `ctt` | 走到 / 打印含 `.git` 的目录（单仓根） |
| 定位 | `cm` / `cmm` | 走到 / 打印 `<repo 根>/.repo/manifests` |
| 定位 | `cdd <目标>` | cd 到某个项目（可按项目名、路径、现存文件/目录） |
| 定位 | `cdd_path <目标>` | 同上但只打印绝对路径，不 cd（`ggcp` 内部用） |
| 查询 | `cnp` / `cnn` | 当前项目在清单里的路径 / 名字（**都不带参数**） |
| 查询 | `repo_mfst_get_*` | 7 个查询函数，见下（包 `my_repo.py`） |
| git | `cnb` / `cnr` | 当前项目在清单里声明的分支 / remote |
| git | `gb` | **打印** push/pull/fetch 命令（只在有 `polygerrit` remote 时多列一行送检命令） |
| git | `gbb` | 按 `gb` 给出的命令**真的推**（公司 gerrit 环境可切成送检） |
| gerrit | `ggcp <change> [patchset]` | 把 gerrit 上某个 patchset 抓回本地、cd 到对应项目、cherry-pick |
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
3. **相对 repo 根的路径**（目录存在且在清单里有这个 path）→ `cd` 过去。

找不到时的报错（都是 stderr）：

| 情况 | 报错 | 返回码 |
|---|---|---|
| 参数个数 ≠ 1 | `Usage: cdd TARGET` + 三行说明 | 2 |
| 一路往上找不到 `.repo` | `cdd: 当前目录不在 repo 工作区里（一路往上都找不到 .repo）` + `想按名字跳转得先站在 repo 工作区里` | 1 |
| 清单里有这个项目、但目录还不存在 | `cdd: 项目 'X' 已在清单里，但目录还不存在：` + 绝对路径 + `先 repo sync X` | 1 |
| 名字和路径都对不上 | `cdd: 清单里没有 'X' 这个项目名或路径` + `看看都有什么：<my_repo.py> list --root <root>` | 1 |

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

### 5. 推送：`gb` / `gbb`

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

`gbb` **真的推**，规则：

1. 项目根下如果有个叫 `gbb` 的文件 → 执行 `zsh <项目根>/gbb` 然后结束（留给项目自己定制）；
2. 否则拿 `gb` 的输出，用 `grep -P` 挑一行执行：
   - `need_to_review=1`（**默认**）→ 挑"直推分支"那条 `HEAD:<branch>`；
   - `need_to_review=0` → 挑"送检"那条 `HEAD:refs/for/<branch>`（**公司 gerrit 环境要改这个**，
     改法就是脚本里那个 `need_to_review=1`，见代码注释）。
3. 依赖 GNU grep 的 `-P`（PCRE）。

### 6. gerrit：`ggcp` / `gchk` / `gq` / `gpush`

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

#### `ggcp <change> [patchset]`

```sh
ggcp 1234                                   # 当前（最新）patchset
ggcp 1234 1                                 # 第 1 个 patchset
ggcp 1234/2                                 # 同上（/ 或 , 都认）
ggcp https://gerrit.company.com/c/proj/+/1234/2
ggcp https://gerrit.company.com/#/c/1234/2  # 老式链接也认
```

它做的事（每一步都能在 `env.zsh` 里找到）：

1. 拆参数（编号 + patchset；`patchset` 必须是数字，否则返回 2）；
2. 解析 gerrit 服务器（上面那套）；
3. `ssh <user>@<host> -p <port> gerrit query --format=JSON --patch-sets --current-patch-set "change:<n>"`；
4. 用 `gerrit_query.py patchset <n> [ps]` 选出 patchset（不指定就取 current），
   拿到 `revision` 和 `ref`；
5. `cdd_path <项目名>` 找到本地目录（找不到/目录不存在会告诉你 `先 repo sync <项目>`）；
6. 选 remote：有 `polygerrit` 就用它，否则用清单声明的，再否则用第一个；
7. `git fetch <remote> <ref>`（走同一把 ssh key）；
8. **核对**：`git rev-parse FETCH_HEAD` 必须等于 gerrit 报的 `revision`，不等就**不 cherry-pick**
   （报错并让你用 `gq <n>` 看 patchset 列表）；
9. `git cherry-pick <revision>`；冲突时提示 `git cherry-pick --continue` / `--abort`。

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
| `ggcp: 不知道 gerrit 服务器在哪。请任选一种方式告诉它：` | 按提示设 `WTOOL_GERRIT_HOST` / 写 `~/.wtool/gerrit.conf` / 放 `<repo 根>/.gerrit/client.conf` |
| `ggcp: 连 <user>@<host>:<port> 查询失败` | ssh 不通或公钥没在 gerrit 登记；先手敲一次 `ssh -p <port> <user>@<host> gerrit version` |
| `ggcp: change N 查不到（编号对不对？有没有权限？）` | 编号错或没权限 |
| `ggcp: 抓到的 commit（X）和 gerrit 说的（Y）对不上，这次不 cherry-pick。用 gq N 看看 patchset 列表` | patchset/ref 选错了（或 change 刚被更新）；`gq` 确认后再来 |
| `ggcp: cherry-pick 冲突了。…` | 按提示 `git cherry-pick --continue` 或 `--abort` |
| `ggcp: cherry-pick 没跑起来（工作区有没提交的改动？先 commit 或 git stash）` | 工作区脏 |
| `gpush: 这个仓库没有 remote 'polygerrit'。现有的：` | 换 remote：`gpush <remote>` |
| `rscur: TODO: repo list has no such dir before download it!!!` | 这个目录还没 sync 下来，`repo list` 里没有它的子项目 |
| `rs` / `rscur` 把本地改动弄没了 | 它们带 `--force-sync -d`，就是会丢弃本地改动/强制覆盖 —— 跑之前先 commit 或 stash |
| `wninja` 报 `Error: No ninja build file found.` | 没找到 `out/combined-*.ninja` / `out/build.ninja` / `out/*/*/build.ninja`；先按项目的构建流程生成 |
| `gbb` 说 `grep: -P` 之类的错 | 它用 GNU grep 的 `-P`；BusyBox grep / macOS 自带 grep 不认 |

## 测试

```sh
sh tests/run_tests.sh      # 77 条（三段合计，以脚本最后打印的通过/失败数为准）
```

测试分三段（都在临时目录里造"公司环境"的假工作区，不碰真工作区）：

1. **`my_repo.py`**（基本查询、分支/remote 解析、`local_manifests` 的增删、`list`、错误处理、
   "没有 `.repo/repo` 也能跑"）；
2. **`gerrit_query.py`**（patchset 选择、`check` 的退出码、`list` / `raw` / 坏输入）；
3. **`env.zsh` / `env.bash` 对比**（`cnp` / `cdd` 的用法报错、`ggcp` 的参数解析 —— 不连网），
   **同一张用例表跑两个 shell**，用来钉住"两份等价"。

夹具故意造成"公司环境"的样子：**没有 `.repo/repo`**、清单里有 `<include>`、
`local_manifests` 里 `remove-project` / 覆盖 revision。

## 依赖

- **python3**（3.6+）：`my_repo.py` / `gerrit_query.py` 只用标准库，不装第三方包。
- **zsh 或 bash**：两个 shell 各一份 env，命令、报错、退出码一致。
  `tests/run_tests.sh` 用**同一张用例表**把两个 shell 都跑一遍，但它覆盖的是
  `cnp` / `cnn` / `cdd` 的报错与退出码、以及 `ggcp` 的拆参数；
  其余命令的"两份等价"靠的是**同改两份文件**，不是测试。
- **ssh**：`ggcp` / `gchk` / `gq` 走 `ssh <gerrit> gerrit query`，公钥要在 gerrit 上登记过。
- **GNU grep（要 `-P`）**：`gbb` 挑命令行用。
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
| `gerrit_query.py` | 解析 `gerrit query --format=JSON` 的输出（供 `ggcp` / `gchk` / `gq` 用） |
| `tests/run_tests.sh` | 上面两个 python 工具的测试 + `env.zsh`/`env.bash` 的行为对比 |

> 老版本 README 里"安装"一节写的是叫用户自己 `wtool install`；
> 现在安装口径统一收到 wtool 的 README（本仓库不再讲怎么装）。
