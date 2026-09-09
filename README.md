# tools/repo

从 `~/source/mytool/android`（原 `wsw-androidrc`）迁移过来的一套 **repo/git 辅助命令**。
本项目是**纯 env 项目**：没有 `<link>`，所有内容靠往 `~/.zshrc` 注入 `env.zsh` 提供。

## 安装

```sh
./install.sh      # 建中转链接 + 往 ~/.zshrc 写 wtool 块
./uninstall.sh    # 完全回退
```

> 首次使用（尚未 `git init`）需 `./install.sh --force`；提交之后不需要。

## 提供哪些命令

| 类别 | 命令 | 说明 |
|---|---|---|
| 定位 | `cs` / `css` | 走到/打印含 `.repo` 的目录（repo 根） |
| 定位 | `ct` / `ctt` | 走到/打印含 `.git` 的目录（单仓根） |
| 定位 | `cm` / `cmm` | 走到/打印 `repo 根/.repo/manifests` |
| 定位 | `cdd <目标>` | cd 到某个项目（可按名字或路径） |
| 查询 | `cnp` / `cnn` | 当前路径的项目名 / 打印项目名 |
| 查询 | `repo_mfst_get_{name,path,branch,remote}_from_{path,name}` | 用 `my_repo.py` 查 manifest |
| git | `cnb` / `cnr` | 当前项目的分支 / remote |
| git | `gb` | 打印 push/pull/fetch 命令（含 gerrit `refs/for/`） |
| git | `gbb` | 直接推送（公司 gerrit 环境可关掉 review） |
| repo | `rs` | 按当前 `repo manifest` 锁定版本强制 sync |
| repo | `rscur` | 只 sync 当前目录名下的子项目 |
| 构建 | `wninja` | 优先用 Android prebuilt ninja 构建 |

## 依赖

- **`my_repo.py`**：读取 `repo` manifest 的小工具（从 `repo` 内部依赖 `manifest_xml.py`）。
  命令通过 `$WTOOL_REPO_TOOL` 找到它，所以**不需**把它软链到 PATH。
- **`_up_to_have_dir`**：向上找 `./.git` 或 `./.repo` 的辅助函数，原本定义在
  `mytool/zsh/wsw-zshrc/wsw.zsh` 里；为了让本项目**独立可用**，已内联到 `env.zsh`。
- **zsh**：用了 `${cur_dir:h}`、`${funcstack[1]}`、`(N)` 全局等 zsh 语法，只对 zsh 生效。
- **`rg` / `nproc` / `base64` 等**：`rscur` 用 `rg`，`rs` 用 `nproc`。
- 这些命令针对 repo 多仓/AOSP 场景，在非 repo 目录会报 `not in repo dir`。

## 用的还是"稳定地址"

和 `terminal/tmux` 一样的约定：命令里不写仓库真实路径，而写 `$WTOOL_PROJECT_DIR`
（= `~/.wtool/links/tools/repo`，引擎 install 时自动创建、指向本项目根）。
把 wtool 下载到任何目录，`~/.wtool/links/tools/repo` 都指向它，命令**在所有机器上行为一致**。

## 与 mytool 版本的差异

| 原 mytool | 现在 | 原因 |
|---|---|---|
| `export WSW_ANDROID_DIR=$(get_this_dir)` | `$WTOOL_PROJECT_DIR` | 加载器已经导出稳定地址，不再需要 `get_this_dir` |
| `$WSW_ANDROID_DIR/my_repo.py` | `$WTOOL_REPO_TOOL`（= `$WTOOL_PROJECT_DIR/my_repo.py`） | 统一命名，且独立于安装位置 |
| `_up_to_have_dir` 依赖外部 source 链 | 内联在 `env.zsh` | 本项目停用 `source_all_env.sh` 后要自包含 |

## 文件

| 文件 | 作用 |
|---|---|
| `wtool.xml` | 清单：1 个 env（无 link） |
| `env.zsh` | 全部命令 + `_up_to_have_dir` + `$WTOOL_REPO_TOOL` |
| `my_repo.py` | manifest 查询工具 |
| `install.sh` / `uninstall.sh` | bootstrap 存根 |
