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

**已知不等价的一处**：`wninja` 在 `env.zsh` 里开头有 `[[ -z $ZSH_VERSION ]] && return`
（bash 里 source 它是静默 no-op），`env.bash` 那份没有这道门。README §7 已注明。

## 4. 命令分族

| 族 | 命令 | 说明 |
|---|---|---|
| 定位 | `cs` `css` `ct` `ctt` `cm` `cmm` | 往上找 `.repo` / `.git`，cd 或打印 |
| 跳项目 | `cdd <目标>` `cdd_path <目标>` | 按"现存文件/目录 → 清单项目名 → 相对 repo 根的路径"找 |
| 当前项目 | `cnp` `cnn` `cnb` `cnr` | 路径 / 名字 / 分支 / remote（走 `my_repo.py`） |
| 清单查询 | `repo_mfst_get_name_from_path` 等 7 个 | 包 `my_repo.py` 的对应动作 |
| 推送 | `gb` `gbb` | `gb` 只打印命令；`gbb` 会 `eval` 真的推（**助手不执行**） |
| 抓取 | `ggco <分支\|tag\|commit>` | fetch 之后直接 checkout（不 cherry-pick、不 reset、不 push） |
| gerrit | `ggcp <change> [patchset]` `gchk <change>` `gq [-r] <change>` `gpush [remote]` | 走 `ssh <gerrit> gerrit query` |
| 同步/构建 | `rs` `rscur` `wninja` | `rs`/`rscur` 带 `--force-sync -d`（**会丢弃本地改动**） |

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

## 5. 测试

`tests/run_tests.sh`（`#!/bin/sh` + `set -eu`，107 条，不连网）：

1. `my_repo.py`：假工作区（`.repo/repo` **不存在**、`<include>`、`local_manifests`、
   remote/project 级 revision）上的查询、`list`、错误处理；
2. `gerrit_query.py`：patchset 选择、`check` 的退出码、`list` / `raw` / 坏输入；
3. `env.zsh` / `env.bash` 对比：`for SHELL_NAME in zsh bash`，同一张用例表跑两个 shell
   （`cnp` / `cnn` / `cdd` 的报错与退出码、`ggcp` 拆参数、`ggco` 端到端）；
4. `ggco` 夹具：`$T/ggco/bare.git`（`git init --bare`）+ `$T/ggco/work`（clone），
   往裸仓推一条只有远端才有的 `feature` / `old`，然后在 clone 里跑 `ggco`
   （只推这个临时裸仓，不碰任何真 remote）。

`env` 那一段的执行方式：把片段写进 `$T/s.script`（先 `source env.$SHELL_NAME`、
再 `cd` 进假工作区），用被测 shell 跑一遍，收集 stdout+stderr 与退出码。
