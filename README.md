# tools/repo

从 `~/source/mytool/android`（原 `wsw-androidrc`）迁移过来的一套 **repo/git 辅助命令**。
本项目是**纯 env 项目**：没有 `<link>`，所有内容靠往 `~/.zshrc` 注入 `env.zsh` 提供。

## 安装

```sh
wtool install tools/repo     # 建中转链接 ~/.wtool/links/tools/repo + 往 ~/.zshrc 写 wtool 块
```

## 提供哪些命令

| 类别 | 命令 | 说明 |
|---|---|---|
| 定位 | `cs` / `css` | 走到/打印含 `.repo` 的目录（repo 根） |
| 定位 | `ct` / `ctt` | 走到/打印含 `.git` 的目录（单仓根） |
| 定位 | `cm` / `cmm` | 走到/打印 `repo 根/.repo/manifests` |
| 定位 | `cdd <目标>` | cd 到某个项目（可按名字、路径、现存文件/目录） |
| 查询 | `cnp` / `cnn` | 当前项目在清单里的路径 / 清单里的名字（**都不带参数**） |
| 查询 | `repo_mfst_get_{name,path,branch,remote,url}_from_{path,name}` | 用 `my_repo.py` 查 manifest |
| git | `cnb` / `cnr` | 当前项目声明的分支 / remote |
| git | `gb` | 打印 push/pull/fetch 命令（含 gerrit `refs/for/`、有 polygerrit remote 时也列出来） |
| git | `gbb` | 直接推送（公司 gerrit 环境可关掉 review） |
| gerrit | `ggcp <change> [patchset]` | 把 gerrit 上第 N 号提交的某个 patchset 抓回本地、cd 到对应仓库、cherry-pick |
| gerrit | `gchk <change>` | 这个 change 有没有 +2 / merged（决定能不能推 main） |
| gerrit | `gq <change>` | change 摘要（`gq -r` 出原始 JSON） |
| gerrit | `gpush [remote]` | 把当前 HEAD 推到 `refs/for/<清单声明的分支>`（默认 remote `polygerrit`） |
| repo | `rs` | 按当前 `repo manifest` 锁定版本强制 sync |
| repo | `rscur` | 只 sync 当前目录名下的子项目 |
| 构建 | `wninja` | 优先用 Android prebuilt ninja 构建 |

### gerrit 命令怎么找到服务器

按顺序找，先命中先用：

1. 环境变量 `WTOOL_GERRIT_HOST`（可写 `user@host:29418`）、`WTOOL_GERRIT_PORT`、`WTOOL_GERRIT_USER`、`WTOOL_GERRIT_SSH_KEY`
2. 配置文件：`$WTOOL_GERRIT_CONF`、`<repo 根>/.gerrit/client.conf`、`~/.wtool/gerrit.conf`
3. 自动猜：当前 git remote / 清单 remote 里带 `29418` 或 `gerrit` 的那条

配置文件就是几行 shell 变量：

```sh
host=gerrit.company.com
port=29418
user=mindul
sshkey=~/.ssh/id_rsa
```

`ggcp` 认这些写法：

```sh
ggcp 1234                                   # 当前（最新）patchset
ggcp 1234 1                                 # 第 1 个 patchset
ggcp 1234/2                                 # 同上
ggcp https://gerrit.company.com/c/proj/+/1234/2
```

它做的事：ssh 问 gerrit `change:1234` 是哪个项目、哪个 patchset、commit id 是多少
→ `cdd` 到那个项目 → `git fetch <remote> refs/changes/..` → `git cherry-pick <commit>`。
**patchset 是必须确认的**：同一个 change 号有多个 patchset，不指定就用 current。

## 依赖

- **python3**（3.6+）：`my_repo.py` / `gerrit_query.py` 都是标准库，不装任何第三方包。
- **`my_repo.py` 自己解析清单**，**不再** import repo 的 `.repo/repo/manifest_xml.py`。
  老版本那样做在公司机器上会断：go 版 repo（git-repo）根本没有那个模块，
  发布包解出来的工作区也没有 `.repo/repo`，python 版 repo 各版本的构造函数还不一样
  （新版要求 `manifest_file` 必须是绝对路径）。
  现在支持 `<include>` / `<remove-project>` / `<extend-project>` / `.repo/local_manifests/*.xml`。
- **zsh**：用了 `${cur_dir:h}`、`${funcstack[1]}`、`(N)` 全局等 zsh 语法，只对 zsh 生效。
- **ssh**：`ggcp`/`gchk`/`gq` 走 `ssh <gerrit> gerrit query`，需要你的公钥在 gerrit 上登记过。
- **`rg` / `nproc` / `base64` 等**：`rscur` 用 `rg`，`rs` 用 `nproc`。
- 这些命令针对 repo 多仓/AOSP 场景，在非 repo 目录会报 `not in repo dir`。

## 测试

```sh
sh tests/run_tests.sh
```

夹具故意造成"公司环境"的样子：**没有 `.repo/repo`**、清单里有 `<include>`、
`local_manifests` 里 `remove-project`/覆盖 revision，用来钉住这几条：
相对/绝对 root、cwd 相对路径、分支与 remote 解析、include 的 revision 继承、
`ggcp` 依赖的 patchset 选择与 `+2/merged` 判断。

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
| `my_repo.py` import repo 内部 `manifest_xml` | 自己解析 XML | 见上面"依赖"一节 |
| 无 | `ggcp` / `gchk` / `gq` / `gpush` | gerrit 检视流程 |

## 文件

| 文件 | 作用 |
|---|---|
| `wtool.xml` | 清单：1 个 env（无 link） |
| `env.zsh` | 全部命令 + `_up_to_have_dir` + `$WTOOL_REPO_TOOL` |
| `my_repo.py` | manifest 查询工具（自包含解析） |
| `gerrit_query.py` | 解析 `gerrit query --format=JSON` 的输出（供 ggcp/gchk/gq 用） |
| `tests/run_tests.sh` | 上面两个 python 工具的测试 |
