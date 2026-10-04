# AGENTS.md（tools/repo）

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
- 清单解析的优先级是契约（`upstream` > `project revision` > remote `revision` >
  `<default revision>`；输出剥 `refs/heads/`），测试逐条钉着，别随手改。
- **项目身份 = 路径 `tools/repo`**（ADR-0037 删掉了 `id=` 属性）：中转链接路径、state 目录、rc 块名都用它。

## 3. 验证（改完必须跑）

```sh
sh tests/run_tests.sh      # 77 条，应该全绿
```

- 三段：`my_repo.py`、`gerrit_query.py`、`env.zsh`/`env.bash` 对比（同一张用例表跑两个 shell）。
- **不连网**：gerrit 相关的用例只测"拆参数"，别把真 ssh 塞进测试。
- 测试全程在临时目录里造假工作区，**不要**在真 `$HOME` / 真工作区上跑。
- 提交只提交到 `ds_dev`，`git add` 之前先 `git diff` 看一遍；不 push、不动 `main`。
