# AGENTS.md（tools/git-repo-sh-tools）

> 2026-10-04 由 `tools/repo` **改名**而来（项目身份就是路径，ADR-0037）——
> GitHub 仓库名仍是 `allinkernel/wtool-repo`；清单里的 `path=` 已改成
> `tools/git-repo-sh-tools`。

> 给后续的 AI 助手看。用户级规则在 `~/.dsh/AGENTS.md`，工作区规则在根目录 `AGENTS.md`；
> 本文件只讲**动这个仓库**必须知道的事。

## 1. README.md 是这个项目给用户的完整功能说明书

- **代码/配置一有变化，必须同步更新本仓库的 `README.md`** —— 别让 README 和代码说两种话。
  改了命令、参数、报错文字、退出码、环境变量、gerrit 服务器查找顺序、`my_repo.py` /
  `gerrit_query.py` 的动作或输出列，都要回到 README 对应那一行改。
- **README 里不写"怎么装"** —— 安装统一由 wtool 管，README 的「安装」一节只有一句话
  加一个链接，指向 GitHub 上的 wtool README（`allinkernel/wtool` 仓库的 `README.md`）。
  项目自己的 `install.sh` / `uninstall.sh` 已经退休，**别把它们写进文档**，
  也别在文档里叫用户直接跑。
- **README 的章节结构**（改动时保持这个骨架，别自创一套）：

  | 章节 | 写什么 |
  |---|---|
  | 功能说明 | 每条命令/函数**到底做什么**：参数、行为、失败时的报错原文与退出码、依赖 |
  | 安装（由 wtool 统一管） | 一句话 + wtool README 链接；本仓库只是源码/配置 |
  | 配置项 | 读哪些环境变量 / 配置文件、默认值、优先级 |
  | 快捷键 | key binding / 补全；本仓库没有就明确写"没有"，并指出实际来自哪个项目 |
  | 排错 | 报错原文 → 原因 → 怎么办 |
  | 测试 | 跑什么命令、几条、夹具在测什么 |
  | 依赖 | 外部命令（python3 / ssh / GNU grep -P / rg / nproc / repo） |
  | 文件 | 每个文件一句话 |

- **只写从代码里读出来的东西。** 每个命令名、变量名、报错文字、退出码、依赖都要对着
  `env.zsh` / `env.bash` / `my_repo.py` / `gerrit_query.py` / `tests/run_tests.sh` 核过再写；
  核不实的宁可不写。特别地：**别把"应该有"的函数写进去** —— 例如
  `repo_mfst_get_url_from_path` 就不存在（只有 `url_from_name`）。

## 2. 这个仓库的硬规矩

- **`env.zsh` 和 `env.bash` 必须同改。** 同一批命令、同样的报错文字、同样的退出码。
  报错前缀两个 shell 都取"当前函数名"（zsh `funcstack[1]` / bash `FUNCNAME[0]`），
  改报错时别把这条弄丢。
- zsh 版可以用 zsh 专有语法（`${var:h}`、`(N)` glob、`<->`……），bash 版不行
  （`${var%/*}` + `case`、`shopt -s nullglob`）。`sh -n` 查不出 bashism，别只靠它。
- **`my_repo.py` 不许 import repo 的内部实现**（`.repo/repo/manifest_xml.py`）。
  公司机器可能是 go 版 repo，发布包里也没有 `.repo/repo` —— 这条曾经把公司机器卡住，
  测试里专门有一节钉它（"没有 `.repo/repo` 也能跑"）。
  两个 python 工具**只用标准库**（python3.6+），也别引入第三方包。
- **命令通过 `$WTOOL_PROJECT_DIR` 找工具**，不写仓库真实路径；
  `WTOOL_REPO_TOOL` / `WTOOL_GERRIT_TOOL` 由 env 文件自己 export，别人会读它们。
- 清单解析的优先级是契约（代码 `my_repo.py:88`：
  `upstream` > **`dest-branch`** > `project revision` > remote `revision` > `<default revision>`，
  且 upstream / dest-branch 各自还有 `<default …>` 兜底；输出剥 `refs/heads/`），
  别随手改。⚠️ 这句原来漏了 `dest-branch`（2026-10-04 订正，README §4 同步改了）。
- **项目身份 = 路径 `tools/git-repo-sh-tools`**（ADR-0037 删掉了 `id=` 属性）：中转链接路径、state 目录、rc 块名都用它。
- **新增命令要用户点头**：对用户可见的命令 / 别名 / 函数（rc 里敲得到的）**只有用户能加**，代理只能加
  只在脚本内部用的隐藏函数（不暴露给用户、不写进 README 这类用户文档）—— 见用户级
  `~/.dsh/AGENTS.md` §1「🔴 谁能新增项目 / 谁能新增命令」（2026-10-09）。

## 3. 验证（改完必须跑）

```sh
sh tests/run_tests.sh      # 335 条，应该全绿（以脚本最后打印的通过/失败数为准；
                           #   2026-10-09 实测 309 通过 0 失败 —— 这个数字常变，
                           #   只有它**跑出来**的 PASS/FAIL 行算数，别手抄）
```

- 三段：`my_repo.py`、`gerrit_query.py`、`env.zsh`/`env.bash` 对比（同一张用例表跑两个 shell）。
- **不连网**：gerrit 相关的用例只测"拆参数"，别把真 ssh 塞进测试。
- 测试全程在临时目录里造假工作区，**不要**在真 `$HOME` / 真工作区上跑。
- ⚠️ **这份仓库里的命令有"写了就真干"的**：`gbb` **真的 `git push`**、
  `gpush` 真的推到 `refs/for/`、`rs`/`rscur` 带 `--force-sync -d`（**丢弃本地改动**）、
  `wninja` 真跑构建。**助手一律不执行它们**（用户级 `~/.dsh/AGENTS.md` 的硬规矩）；
  要验证就只用 `tests/run_tests.sh`（它造临时工作区、不连网）。
- **装 / 测只在容器里做**：真机上 `wtool install tools/git-repo-sh-tools`
  **必须由用户明确同意**。
- ⚠️ **别把 `wninja` 的两份写"等价"**：`env.zsh` 那份开头有
  `[[ -z $ZSH_VERSION ]] && return`，在 bash 里 source 时是**静默 no-op**；
  `env.bash` 那份没有这道门。README §7 已注明。
- 提交只提交到 `ds_dev`，`git add` 之前先 `git diff` 看一遍；不 push、不动 `main`。

## 4. 文档分工：README 是命令说明书，下载/进度/决策都不进 README

> **这是所有 wtool 子项目的通用要求**（2026-10-09 用户口径，原话见用户级
> `~/.dsh/AGENTS.md`）。本仓库照它执行，别的子项目也一样。

- **README = 给用户看的命令说明书。** 主体必须是**这个仓提供哪些命令、各干什么、怎么执行**：
  一句话用途 + 用法/参数 + 选项 + 退出码/典型输出 + 依赖的环境变量/配置。
  用户读完 README 就该知道"有哪些命令是干什么的、怎么执行"。
  **每条都要对着 `env.zsh` / `env.bash` 核过再写**（先
  `grep -n '^[a-z_]* ()' env.zsh` 数一遍函数，再照着写）；核不实的宁可不写。
- **下载的内容不写进 README** —— 放 `docs/download.md` 或 README 的**最后一节**，
  README 里**只留一行链接**。理由：`download.md` 只是下载，README 是给用户看的说明书。
  本仓库的下载页是 `docs/download.md`，README 末尾「下载」一节只留链接。
- **⚠️ `docs/download.md` 是引擎生成的，不要手改它。** `wtool pack-release` 每次发布
  重写一遍（`bootstrap/lib/wtool_fs.sh`、`bootstrap/lib/wtool_plan.py`），并登记进引擎的
  `$WTOOL_STATE/generated.tsv`（**状态目录里的册子，不在本仓库里**）——
  改它下次发布就被覆盖。要改下载页内容就改发布流程 / `scripts/release.json`，
  不要改这个文件本身。同理 `scripts/release.json` 也是生成的。
- **进度不写进 README，进 `BACKLOG.md`；决策不写进 README，进 `docs/adr/`。**
  README 只写"现在有什么、怎么用"，不写"做到哪了、为什么这么定"。
- **自检**：README 里出现的每个命令名，都要能在 `env.zsh` 或 `env.bash` 里
  `grep` 到；找不到的要么删掉，要么在 README 里说明它来自别的仓。命令列表示例：

  ```sh
  grep -oP '^[A-Za-z_][A-Za-z_0-9]*\s*\(\)' env.zsh  | sed 's/\s*()//' | sort -u
  grep -oP '^[A-Za-z_][A-Za-z_0-9]*\s*\(\)' env.bash | sed 's/\s*()//' | sort -u
  # 两边应该给出同一批名字；README 里的命令名应当是它们的子集（`_` 开头的是内部函数，不写进 README）
  ```

