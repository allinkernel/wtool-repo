#!/bin/sh
# run_tests.sh —— tools/git-repo-sh-tools（原名 tools/repo）的测试
#
# 重点是 my_repo.py：它原来 import repo 的 .repo/repo/manifest_xml.py，
# 在公司机器上会断（go 版 repo 没有这个模块；发布包里也没有 .repo/repo）。
# 这里的夹具就按"公司环境"造：
#
#   * .repo/repo/  <- **不存在**
#   * .repo/manifest.xml 软链到 manifests/default.xml（repo 的标准布局）
#   * manifests/ 里用 <include>（默认分支/remote 在 include 前后都能用）
#   * local_manifests/*.xml 里 remove-project / 覆盖 revision / 新增项目
#   * remote 级别的 revision、project 级别的 upstream
#
# 全程在临时目录里跑，不碰真工作区。
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
TOOL="$here/../my_repo.py"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$*"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1（期望 [$3] 实际 [$2]）"; fi; }

T=$(mktemp -d "${TMPDIR:-/tmp}/wtool-repo-tests.XXXXXX")
trap 'rm -rf -- "$T"' EXIT INT TERM

# ---------------------------------------------------------------------------
# 全程不碰真 $HOME：夹具跑的 git 和被测 shell 都用临时 HOME / XDG。
# 两个好处：① 测试绝不读写用户家目录（git 的 ~/.gitconfig、zsh 的 ~/.zshenv）；
# ② git 只看见空配置，不受用户全局 insteadOf / pull.rebase 之类的影响。
# ---------------------------------------------------------------------------
HOME="$T/home"
XDG_CONFIG_HOME="$T/xdg/config"
XDG_CACHE_HOME="$T/xdg/cache"
XDG_DATA_HOME="$T/xdg/data"
XDG_STATE_HOME="$T/xdg/state"
export HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

WS="$T/company"
mkdir -p "$WS/.repo/manifests" "$WS/.repo/local_manifests" \
         "$WS/device/emui/generic_a15" "$WS/kernel/common" "$WS/vendor/company/foo"

cat > "$WS/.repo/manifests/default.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!-- 模拟公司 AOSP 清单：include + 两种 remote + 默认 revision -->
<manifest>
    <remote name="company" fetch="ssh://user@gerrit.company.com:29418/" />
    <remote name="mirror" fetch="https://mirror.company.com/git/" revision="main" />
    <default revision="master" remote="company" sync-j="8" />

    <include name="extra.xml" />
    <include name="vendor.xml" revision="refs/heads/company-15" />

    <project path="device/emui/generic_a15" name="device/emui/generic_a15" groups="device,emui" />
    <project path="vendor/company/foo" name="vendor/company/foo" remote="mirror" revision="stable" />
    <project path="build/soong" name="platform/build/soong" />
    <project path="prebuilts/tools" name="prebuilts/tools" revision="refs/heads/android14-release" upstream="android14-release" />
    <project path="gone/project" name="gone/project" />
</manifest>
EOF

cat > "$WS/.repo/manifests/extra.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project path="kernel/common" name="kernel/common" revision="android13-6.1" />
    <project path="external/zlib" name="platform/external/zlib" />
</manifest>
EOF

cat > "$WS/.repo/manifests/vendor.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <!-- 没写 revision：应该继承 <include revision="refs/heads/company-15"> -->
    <project path="vendor/company/bar" name="vendor/company/bar" />
</manifest>
EOF

cat > "$WS/.repo/local_manifests/company.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remove-project name="gone/project" />
    <project path="device/emui/generic_a15" name="device/emui/generic_a15" revision="refs/heads/emui-15" upstream="emui-15" />
    <project path="local/only" name="local/only" />
    <extend-project name="platform/build/soong" groups="extended" />
</manifest>
EOF

# repo 的标准布局：.repo/manifest.xml 是指向 manifests/ 的软链
ln -s manifests/default.xml "$WS/.repo/manifest.xml"

M="python3 $TOOL"

echo "== my_repo.py：基本查询 =="
chk "name_from_path（相对路径）" "$($M name_from_path device/emui/generic_a15 --root "$WS")" "device/emui/generic_a15"
chk "path_from_name" "$($M path_from_name platform/external/zlib --root "$WS")" "external/zlib"
chk "path_from_name 容忍 .git 后缀" "$($M path_from_name platform/external/zlib.git --root "$WS")" "external/zlib"
chk "name_from_path 容忍 cwd 相对" "$(cd "$WS/device" && $M name_from_path emui/generic_a15)" "device/emui/generic_a15"
chk "name_from_path 接受 .（cwd 就在项目里）" "$(cd "$WS/kernel/common" && $M name_from_path .)" "kernel/common"
chk "root 探测" "$(cd "$WS/kernel/common" && $M root)" "$WS"
chk "root 是相对路径也认" "$(cd "$WS" && $M root --root .)" "$WS"

echo "== my_repo.py：分支 / remote 解析 =="
chk "local_manifests 覆盖 revision" "$($M branch_from_name device/emui/generic_a15 --root "$WS")" "emui-15"
chk "upstream 优先于 revision" "$($M branch_from_name prebuilts/tools --root "$WS")" "android14-release"
chk "include 的 revision 继承" "$($M branch_from_name vendor/company/bar --root "$WS")" "company-15"
chk "project revision 优先于 remote revision" "$($M branch_from_name vendor/company/foo --root "$WS")" "stable"
chk "default revision 兜底" "$($M branch_from_name platform/build/soong --root "$WS")" "master"
chk "refs/heads/ 前缀被剥掉" "$($M branch_from_name kernel/common --root "$WS" )" "android13-6.1"
chk "remote_from_path" "$($M remote_from_path vendor/company/foo --root "$WS")" "mirror"
chk "remote_from_name（走 default）" "$($M remote_from_name platform/build/soong --root "$WS")" "company"
chk "url_from_name（ssh remote）" "$($M url_from_name kernel/common --root "$WS")" "ssh://user@gerrit.company.com:29418/kernel/common"
chk "url_from_name（https remote）" "$($M url_from_name vendor/company/foo --root "$WS")" "https://mirror.company.com/git/vendor/company/foo"

echo "== my_repo.py：local_manifests 的增删 =="
chk "local_manifests 新增的项目" "$($M path_from_name local/only --root "$WS")" "local/only"
if $M path_from_name gone/project --root "$WS" >/dev/null 2>&1; then
    bad "remove-project 应该让项目消失"
else
    ok "remove-project 让项目消失"
fi

echo "== my_repo.py：list =="
n=$($M list --root "$WS" | wc -l | tr -d ' ')
chk "list 行数（5 + 2 + 1 + 1 - 1 删除）" "$n" "8"
if $M list --format json --root "$WS" | python3 -c '
import json,sys
rows=json.load(sys.stdin)
assert isinstance(rows,list) and rows
want={"path","name","branch","revision","remote","url","groups"}
assert want <= set(rows[0]), rows[0]
assert any(r["path"]=="kernel/common" and r["branch"]=="android13-6.1" for r in rows)
' 2>/dev/null; then ok "list --format json 结构正确"; else bad "list --format json 结构不正确"; fi
if $M list --root "$WS" | grep -q "^local/only"; then ok "list 含 local_manifests 项目"; else bad "list 少了 local_manifests 项目"; fi

echo "== my_repo.py：错误处理（要的是清晰退出码，不是 traceback）=="
if err=$($M path_from_name nope/nope --root "$WS" 2>&1); then
    bad "不存在的项目应该失败"
else
    case "$err" in
        *"清单里没有这个项目名"*) ok "不存在的项目：报错清楚且退出码非 0" ;;
        *) bad "不存在的项目：报错内容不对 [$err]" ;;
    esac
fi
if err=$(cd "$T" && $M path_from_name x 2>&1); then
    bad "不在 repo 工作区里应该失败"
else
    case "$err" in
        *"没找到 .repo"*) ok "不在 repo 工作区：报错清楚且退出码非 0" ;;
        *) bad "不在 repo 工作区：报错内容不对 [$err]" ;;
    esac
fi
if $M list --root "$T" >/dev/null 2>&1; then
    bad "--root 指到非工作区应该失败"
else
    ok "--root 指到非工作区会失败"
fi

echo "== my_repo.py：没有 .repo/repo 也能跑（就是这条曾经把公司机器卡住）=="
if [ -e "$WS/.repo/repo" ]; then
    bad "夹具里不该有 .repo/repo"
else
    ok "夹具确认没有 .repo/repo（go 版 repo / 发布包的形态）"
fi
if python3 -c "import sys; sys.path.insert(0, '$WS/.repo/repo'); import manifest_xml" 2>/dev/null; then
    bad "夹具不该能 import manifest_xml"
else
    ok "manifest_xml 不可用，但上面的查询全部通过"
fi

# ---------------------------------------------------------------------------
# gerrit_query.py：解析 `gerrit query --format=JSON` 的输出
# （ggcp / gchk 的"半条命"在这里，另外半条是 ssh）
# ---------------------------------------------------------------------------
G="$here/../gerrit_query.py"

cat > "$T/q.json" <<'EOF'
{"change_id":"I1111111111111111111111111111111111111111","project":"platform/frameworks/base","branch":"main","number":1234,"subject":"demo change","url":"http://gerrit.example.com/c/platform/frameworks/base/+/1234","status":"NEW","currentPatchSet":{"number":2,"revision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","ref":"refs/changes/34/1234/2","approvals":[{"type":"Code-Review","value":"+1","by":{"username":"someone"}}]},"patchSets":[{"number":1,"revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ref":"refs/changes/34/1234/1"},{"number":2,"revision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","ref":"refs/changes/34/1234/2","approvals":[{"type":"Code-Review","value":"+1","by":{"username":"someone"}}]}]}
{"type":"stats","rowCount":1,"runTimeMilliseconds":5,"moreChanges":false}
EOF

echo "== gerrit_query.py：patchset 选择（ggcp 的关键：patchset 不能猜）=="
chk "不给 patchset 时取 current" \
    "$(python3 $G patchset 1234 < "$T/q.json" | cut -f2)" "2"
chk "显式 patchset 1" \
    "$(python3 $G patchset 1234 1 < "$T/q.json" | cut -f2,3)" "1	aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
chk "显式 patchset 2 的 ref" \
    "$(python3 $G patchset 1234 2 < "$T/q.json" | cut -f4)" "refs/changes/34/1234/2"
chk "从 URL 形态的 change 号也能查" \
    "$(python3 $G patchset 1234 < "$T/q.json" | cut -f5)" "platform/frameworks/base"
# ggcp 的"同 Change-Id 已在本地"预检和 ggrvt 都靠这两列：Change-Id + 所有 patchset
chk "patchset 第 9 列是 Change-Id（新版 gerrit 的 change_id）" \
    "$(python3 $G patchset 1234 < "$T/q.json" | cut -f9)" "I1111111111111111111111111111111111111111"
chk "patchset 第 10 列是所有 patchset 的 编号:revision:ref" \
    "$(python3 $G patchset 1234 < "$T/q.json" | cut -f10)" \
    "1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:refs/changes/34/1234/1 2:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:refs/changes/34/1234/2"
# 老 gerrit 没有 change_id，只有 id（project~branch~Change-Id）
sed 's/"change_id":"I1111111111111111111111111111111111111111",/"id":"platform\/frameworks\/base~main~I1111111111111111111111111111111111111111",/' \
    "$T/q.json" > "$T/q-id.json"
chk "change_id 缺失时从老的 id 字段兜底" \
    "$(python3 $G patchset 1234 < "$T/q-id.json" | cut -f9)" "I1111111111111111111111111111111111111111"
# 两个字段都没有（夹具/非 gerrit 提交）：列是空的，ggcp 的预检自动跳过
sed 's/"change_id":"I1111111111111111111111111111111111111111",//' "$T/q.json" > "$T/q-nocid.json"
chk "两个字段都没有时 Change-Id 列是空的（预检会跳过）" \
    "$(python3 $G patchset 1234 < "$T/q-nocid.json" | cut -f9)" ""

# ggrvt 允许拿整个 Change-Id 当参数：查询本身就是 change:<id>，恰好一条就用它
chk "patchset 用 Change-Id 也能查出编号（ggrvt 的入口）" \
    "$(python3 $G patchset I1111111111111111111111111111111111111111 < "$T/q.json" | cut -f1)" "1234"
# 同一 Change-Id 横跨多个 change（多条结果）时不替用户挑，让他改用编号
{ sed -n 1p "$T/q.json"; sed -n 1p "$T/q.json" | sed 's/"number":1234/"number":4321/'; } > "$T/q-multi.json"
if python3 $G patchset I1111111111111111111111111111111111111111 < "$T/q-multi.json" >/dev/null 2>"$T/e2"; then
    bad "Change-Id 对应多个 change 时应该失败"
else
    grep -q "对应 2 个提交" "$T/e2" && ok "Change-Id 多条结果：报错让改用编号" \
                                   || bad "Change-Id 多条结果的报错不对 [$(cat "$T/e2")]"
fi

if python3 $G patchset 1234 9 < "$T/q.json" >/dev/null 2>"$T/e1"; then
    bad "不存在的 patchset 应该失败"
else
    grep -q "没有 patchset 9" "$T/e1" && ok "不存在的 patchset：报错且退出码非 0" \
                                       || bad "不存在的 patchset：报错不对 [$(cat "$T/e1")]"
fi
if python3 $G patchset 999 < "$T/q.json" >/dev/null 2>&1; then
    bad "不存在的 change 应该失败"
else
    ok "不存在的 change：退出码非 0"
fi

echo "== gerrit_query.py：check（能不能推 main）=="
if python3 $G check 1234 < "$T/q.json"; then
    bad "只有 +1 的 change 不该判成可推"
else
    ok "只有 +1：不是可推状态"
fi
sed 's/"value":"+1"/"value":"+2"/g; s/"username":"someone"/"username":"mindul"/g' "$T/q.json" > "$T/q-p2.json"
if python3 $G check 1234 < "$T/q-p2.json" >/dev/null; then
    bad "+2 但没 merged 不该判成可推"
else
    ok "+2 但还没 merged：不是可推状态"
fi
sed 's/"status":"NEW"/"status":"MERGED"/' "$T/q-p2.json" > "$T/q-merged.json"
if python3 $G check 1234 < "$T/q-merged.json" > "$T/o1"; then
    grep -q "mindul" "$T/o1" && ok "MERGED + 你的 +2：判成可推，并写出是谁投的" \
                             || bad "MERGED：没写出投票人 [$(cat "$T/o1")]"
else
    bad "MERGED + +2 应该判成可推"
fi
if python3 $G check 999 < "$T/q.json" >/dev/null 2>&1; then
    bad "查不到的 change 应该返回非 0"
else
    [ $? -eq 2 ] && ok "查不到的 change：退出码 2（和无 +2 区分开）" \
                 || ok "查不到的 change：退出码非 0"
fi

echo "== gerrit_query.py：list / raw / 坏输入 =="
chk "list 跳过 stats 行" "$(python3 $G list < "$T/q.json" | wc -l | tr -d ' ')" "1"
chk "list 第一列是编号" "$(python3 $G list < "$T/q.json" | cut -f1)" "1234"
if python3 $G raw < "$T/q.json" | grep -Eq '"number": *1234'; then
    ok "raw 原样吐 JSON"
else
    bad "raw 没吐出 JSON"
fi
if printf 'not json\n' | python3 $G list >/dev/null 2>&1; then
    bad "坏输入应该报错"
else
    ok "坏输入：报错且退出码非 0"
fi

echo "== gerrit_query.py：result-table（ggcp 的结果表，CJK 对齐）=="
RT_INPUT=$(printf 'platform/mylib\tmylib\tdeadbeefcafe\t1\t成功\n平台/中文仓库\t中文路径\tcafebabe1234\t2\tabc.txt 文件冲突\n-\t-\t-\t-\t查询失败：查不到\n')
RT=$(printf '%s' "$RT_INPUT" | python3 $G result-table)
chk "result-table 行数（表头 + 分隔线 + 3 行）" \
    "$(printf '%s\n' "$RT" | wc -l | tr -d ' ')" "5"
case $(printf '%s\n' "$RT" | head -1) in
    *项目名*项目路径*提交*id*patchset*结果说明*) ok "result-table 表头 5 列都在" ;;
    *) bad "result-table 表头不对：$(printf '%s\n' "$RT" | head -1)" ;;
esac
case $(printf '%s\n' "$RT" | sed -n 3p) in
    *platform/mylib*成功*) ok "result-table 第一行是提交结果" ;;
    *) bad "result-table 第一行不对：$(printf '%s\n' "$RT" | sed -n 3p)" ;;
esac
if python3 - "$G" <<'PY' 2>/dev/null
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gq", sys.argv[1])
gq = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gq)
# CJK 全角按 2 列：这是表格对齐的唯一依赖
assert gq.disp_width("项目名") == 6
assert gq.disp_width("中a") == 3
assert gq.disp_width("abc") == 3
# pad 只补空格，且补到指定显示宽度
assert gq.pad("中", 4) == "中  "
assert gq.pad("abc", 3) == "abc"
PY
then
    ok "result-table 中文宽度：全角按 2 列、pad 补齐"
else
    bad "result-table 中文宽度没对齐"
fi
if printf 'x\n' | python3 $G result-table >/dev/null 2>&1; then
    bad "result-table 坏输入应该失败"
else
    ok "result-table 坏输入：退出码非 0"
fi

# ---------------------------------------------------------------------------
# ggco 的夹具：本地裸仓 + 一个 clone（fetch -> checkout，端到端，不联网）
# ---------------------------------------------------------------------------
GGCO_OK=0
GGCO_BARE="$T/ggco/bare.git"
GGCO_WORK="$T/ggco/work"
GGCO_FEATURE_SHA=""
if command -v git >/dev/null 2>&1; then
    mkdir -p "$T/ggco"
    git init -q --bare "$GGCO_BARE"
    git clone -q "$GGCO_BARE" "$GGCO_WORK" 2>/dev/null
    (
        cd "$GGCO_WORK"
        git config user.name t
        git config user.email t@t
        printf 'hello\n' > README.md
        git add -A
        git commit -qm init
        git branch -M main
        git push -q -u origin main
        # 远端多一条 feature：指向一个本地还没有的提交
        git checkout -q -B tmp main
        git commit -q --allow-empty -m remote-only
        git push -q origin tmp:feature
        git push -q origin tmp:old
        git checkout -q main
        git branch -qD tmp
    )
    GGCO_FEATURE_SHA=$(git -C "$GGCO_BARE" rev-parse feature)
    GGCO_OK=1
fi

# ---------------------------------------------------------------------------
# ggcp / cdd <编号> 的夹具：一个"假 gerrit"（本地裸仓里放 refs/changes/NN/N/P）
#                            + 一个真 repo 工作区 + 桩 _gerrit_ssh（喂 JSON）
#
#   * **不联网、不碰真 gerrit**：查询走桩（cat 一个 JSON 文件），fetch 走本地裸仓；
#   * 一个 Change-Id 两个 patchset：远端有 refs/changes/01/1/1 和 …/1/2；
#   * cdd 的三条路各一个编号：9001 仓库在工作区里、9002 在清单里但目录没有、
#     9003 清单里根本没有这个项目。
# ---------------------------------------------------------------------------
GGCP_OK=0
GGCP_ROOT="$T/ggcp"
GGCP_BARE="$GGCP_ROOT/remote/proj.git"
GGCP_WS="$GGCP_ROOT/ws"
GGCP_WORK="$GGCP_WS/mylib"
GGCP_OTHER="$GGCP_WS/other"
GGCP_JSON="$GGCP_ROOT/json"
GGCP_BASE_SHA=""
if command -v git >/dev/null 2>&1; then
    mkdir -p "$GGCP_ROOT/remote" "$GGCP_WS/.repo/manifests" "$GGCP_WS/.gerrit" "$GGCP_JSON"
    git init -q --bare "$GGCP_BARE"
    git clone -q "$GGCP_BARE" "$GGCP_ROOT/src" 2>/dev/null
    (
        cd "$GGCP_ROOT/src"
        git config user.name t
        git config user.email t@t
        git checkout -q -b main
        printf 'base\n' > base.txt
        git add -A
        git commit -qm 'base'
        git branch -M main
        BASE=$(git rev-parse HEAD)
        # change 1 patchset 1：加 ps1.txt（**带 Change-Id** —— ggcp 的预检靠它认
        # "这个 Change-Id 已经在本地历史里了"）
        printf 'ps1\n' > ps1.txt
        git add -A
        git commit -qm 'lab: change one (ps1)' -m 'Change-Id: I1111111111111111111111111111111111111111'
        PS1=$(git rev-parse HEAD)
        # change 1 patchset 2：同一个 change 的新版本（ps1.txt 一样 + 多一个 ps2.txt）
        git reset -q --hard "$BASE"
        printf 'ps1\n' > ps1.txt
        printf 'ps2\n' > ps2.txt
        git add -A
        git commit -qm 'lab: change one (ps2)' -m 'Change-Id: I1111111111111111111111111111111111111111'
        PS2=$(git rev-parse HEAD)
        # change 2：另一个提交（加 two.txt）
        git reset -q --hard "$BASE"
        printf 'two\n' > two.txt
        git add -A
        git commit -qm 'lab: change two' -m 'Change-Id: I2222222222222222222222222222222222222222'
        TWO=$(git rev-parse HEAD)
        # change 1234：两个 patchset，ps2 只在 ps1 上多一个文件 —— 这就是用户报的
        # 那个场景（先打 1 再打 2 会让 git log 出现两个同 Change-Id 的提交）。
        git reset -q --hard "$BASE"
        printf '1234ps1\n' > 1234ps1.txt
        git add -A
        git commit -qm 'lab: change 1234 (ps1)' -m 'Change-Id: I1234567890abcdef1234567890abcdef12345678'
        C1234_PS1=$(git rev-parse HEAD)
        git reset -q --hard "$BASE"
        printf '1234ps1\n' > 1234ps1.txt
        printf '1234ps2\n' > 1234ps2.txt
        git add -A
        git commit -qm 'lab: change 1234 (ps2)' -m 'Change-Id: I1234567890abcdef1234567890abcdef12345678'
        C1234_PS2=$(git rev-parse HEAD)
        # 四笔跨两个仓库的补丁：101/102 是同一个文件的两步（顺序反了会冲突），
        # 103/104 在另一个仓库里做同样的事 —— 用来钉"同仓库串行、不同仓库并行"。
        git reset -q --hard "$BASE"
        printf 'a1\n' > a.txt
        git add -A
        git commit -qm 'lab: A1'
        A1=$(git rev-parse HEAD)
        printf 'a2\n' >> a.txt
        git add -A
        git commit -qm 'lab: A2'
        A2=$(git rev-parse HEAD)
        git reset -q --hard "$BASE"
        printf 'b1\n' > b.txt
        git add -A
        git commit -qm 'lab: B1'
        B1=$(git rev-parse HEAD)
        printf 'b2\n' >> b.txt
        git add -A
        git commit -qm 'lab: B2'
        B2=$(git rev-parse HEAD)
        # 把"gerrit 服务器"（本地裸仓）上的 ref 都推上去
        git push -q origin "$BASE":refs/heads/main
        git push -q origin \
            "$PS1":refs/changes/01/1/1 \
            "$PS2":refs/changes/01/1/2 \
            "$TWO":refs/changes/02/2/1 \
            "$A1":refs/changes/01/101/1 \
            "$A2":refs/changes/02/102/1 \
            "$B1":refs/changes/03/103/1 \
            "$B2":refs/changes/04/104/1 \
            "$C1234_PS1":refs/changes/34/1234/1 \
            "$C1234_PS2":refs/changes/34/1234/2
        printf '%s %s %s %s %s %s %s %s %s %s\n' \
            "$BASE" "$PS1" "$PS2" "$TWO" "$A1" "$A2" "$B1" "$B2" \
            "$C1234_PS1" "$C1234_PS2" > "$GGCP_ROOT/shas"
        git -C "$GGCP_BARE" symbolic-ref HEAD refs/heads/main
    )
    read -r GGCP_BASE_SHA GGCP_PS1_SHA GGCP_PS2_SHA GGCP_TWO_SHA \
        GGCP_A1_SHA GGCP_A2_SHA GGCP_B1_SHA GGCP_B2_SHA \
        GGCP_C1234_PS1_SHA GGCP_C1234_PS2_SHA < "$GGCP_ROOT/shas"
    # 三个 Change-Id（夹具里的提交消息里就是它们）
    GGCP_CID1='I1111111111111111111111111111111111111111'
    GGCP_CID2='I2222222222222222222222222222222222222222'
    GGCP_CID1234='I1234567890abcdef1234567890abcdef12345678'

    # 工作区：清单 + client.conf + 项目目录（真 git 仓，remote 叫 polygerrit）
    cat > "$GGCP_WS/.repo/manifests/default.xml" <<'X'
<?xml version="1.0"?>
<manifest>
    <remote name="polygerrit" fetch="ssh://t@127.0.0.1:29418/" />
    <default revision="main" remote="polygerrit" />
    <project path="mylib" name="platform/mylib" />
    <project path="other" name="platform/other" />
    <project path="device/emui/generic_a15" name="device/emui/generic_a15" />
    <project path="gone/project" name="gone/project" />
</manifest>
X
    ln -sfn manifests/default.xml "$GGCP_WS/.repo/manifest.xml"
    cat > "$GGCP_WS/.gerrit/client.conf" <<'X'
host=127.0.0.1
port=29418
user=t
X
    mkdir -p "$GGCP_WORK" "$GGCP_WS/device/emui/generic_a15"
    git init -q "$GGCP_WORK"
    git -C "$GGCP_WORK" config user.name t
    git -C "$GGCP_WORK" config user.email t@t
    printf 'base\n' > "$GGCP_WORK/base.txt"
    git -C "$GGCP_WORK" add -A
    git -C "$GGCP_WORK" commit -qm base
    git -C "$GGCP_WORK" branch -M ds_dev
    git -C "$GGCP_WORK" remote add polygerrit "$GGCP_BARE"
    # 第二个仓库：从同一个裸仓 clone（这样 base 的 SHA 和 mylib 完全一样）
    git clone -q "$GGCP_BARE" "$GGCP_OTHER" 2>/dev/null
    git -C "$GGCP_OTHER" config user.name t
    git -C "$GGCP_OTHER" config user.email t@t
    git -C "$GGCP_OTHER" checkout -q -B ds_dev "$GGCP_BASE_SHA" 2>/dev/null || true
    git -C "$GGCP_OTHER" remote add polygerrit "$GGCP_BARE"

    # 桩 _gerrit_ssh 喂的 JSON（最后一行是 gerrit 固定的 stats）
    _stats='{"type":"stats","rowCount":1,"runTimeMilliseconds":1,"moreChanges":false}'
    # change 1 有**两个 patchset**（真的 gerrit 也是这样：`change:1` 一次回全部 patchset）
    cat > "$GGCP_JSON/change-1.json" <<X
{"number":1,"change_id":"I1111111111111111111111111111111111111111","project":"platform/mylib","branch":"main","subject":"lab: change one","url":"http://g.example.com/c/platform/mylib/+/1","currentPatchSet":{"number":1,"revision":"$GGCP_PS1_SHA","ref":"refs/changes/01/1/1"},"patchSets":[{"number":1,"revision":"$GGCP_PS1_SHA","ref":"refs/changes/01/1/1"},{"number":2,"revision":"$GGCP_PS2_SHA","ref":"refs/changes/01/1/2"}]}
$_stats
X
    # 老 gerrit 只有 id（project~branch~Change-Id），没有 change_id —— 走兜底
    cat > "$GGCP_JSON/change-2.json" <<X
{"number":2,"id":"platform/mylib~main~I2222222222222222222222222222222222222222","project":"platform/mylib","branch":"main","subject":"lab: change two","url":"http://g.example.com/c/platform/mylib/+/2","currentPatchSet":{"number":1,"revision":"$GGCP_TWO_SHA","ref":"refs/changes/02/2/1"},"patchSets":[{"number":1,"revision":"$GGCP_TWO_SHA","ref":"refs/changes/02/2/1"}]}
$_stats
X
    cat > "$GGCP_JSON/change-1234.json" <<X
{"number":1234,"change_id":"I1234567890abcdef1234567890abcdef12345678","project":"platform/mylib","branch":"main","subject":"lab: change 1234","url":"http://g.example.com/c/platform/mylib/+/1234","currentPatchSet":{"number":2,"revision":"$GGCP_C1234_PS2_SHA","ref":"refs/changes/34/1234/2"},"patchSets":[{"number":1,"revision":"$GGCP_C1234_PS1_SHA","ref":"refs/changes/34/1234/1"},{"number":2,"revision":"$GGCP_C1234_PS2_SHA","ref":"refs/changes/34/1234/2"}]}
$_stats
X
    # 四笔跨两个仓库的补丁（101/102 -> mylib，103/104 -> other）
    cat > "$GGCP_JSON/change-101.json" <<X
{"number":101,"project":"platform/mylib","branch":"main","subject":"lab: A1","url":"http://g.example.com/c/platform/mylib/+/101","currentPatchSet":{"number":1,"revision":"$GGCP_A1_SHA","ref":"refs/changes/01/101/1"},"patchSets":[{"number":1,"revision":"$GGCP_A1_SHA","ref":"refs/changes/01/101/1"}]}
$_stats
X
    cat > "$GGCP_JSON/change-102.json" <<X
{"number":102,"project":"platform/mylib","branch":"main","subject":"lab: A2","url":"http://g.example.com/c/platform/mylib/+/102","currentPatchSet":{"number":1,"revision":"$GGCP_A2_SHA","ref":"refs/changes/02/102/1"},"patchSets":[{"number":1,"revision":"$GGCP_A2_SHA","ref":"refs/changes/02/102/1"}]}
$_stats
X
    cat > "$GGCP_JSON/change-103.json" <<X
{"number":103,"project":"platform/other","branch":"main","subject":"lab: B1","url":"http://g.example.com/c/platform/other/+/103","currentPatchSet":{"number":1,"revision":"$GGCP_B1_SHA","ref":"refs/changes/03/103/1"},"patchSets":[{"number":1,"revision":"$GGCP_B1_SHA","ref":"refs/changes/03/103/1"}]}
$_stats
X
    cat > "$GGCP_JSON/change-104.json" <<X
{"number":104,"project":"platform/other","branch":"main","subject":"lab: B2","url":"http://g.example.com/c/platform/other/+/104","currentPatchSet":{"number":1,"revision":"$GGCP_B2_SHA","ref":"refs/changes/04/104/1"},"patchSets":[{"number":1,"revision":"$GGCP_B2_SHA","ref":"refs/changes/04/104/1"}]}
$_stats
X
    # cdd <编号> 的三个假 change
    for spec in "9001|platform/mylib" "9002|gone/project" "9003|nope/nope"; do
        n=${spec%%|*}; p=${spec#*|}
        cat > "$GGCP_JSON/cdd-$n.json" <<X
{"number":$n,"project":"$p","branch":"main","subject":"lab: cdd $n","url":"http://g.example.com/c/$p/+/$n","currentPatchSet":{"number":1,"revision":"$GGCP_TWO_SHA","ref":"refs/changes/02/2/1"},"patchSets":[{"number":1,"revision":"$GGCP_TWO_SHA","ref":"refs/changes/02/2/1"}]}
$_stats
X
    done
    printf '{"type":"stats","rowCount":0,"runTimeMilliseconds":1,"moreChanges":false}\n' > "$GGCP_JSON/empty.json"
    # 桩 _gerrit_ssh：按 `change:<x>` 里的 <x> 挑一个 JSON 喂回去。
    # 写成文件是为了两个 shell 共用同一份（snippet 里 source 它）。
    cat > "$GGCP_ROOT/stub.sh" <<X
_gerrit_ssh () {
    local c="" a
    for a in "\$@"; do c=\$a; done
    case \${c#change:} in
        1)    cat "$GGCP_JSON/change-1.json" ;;
        2)    cat "$GGCP_JSON/change-2.json" ;;
        101|102|103|104|1234)
            # 只有测试显式设了 GR_QUERY_LOG 才记日志/延迟（平时查询不拖时间）
            if [ -n "\${GR_QUERY_LOG:-}" ]; then
                printf 'start %s\n' "\${c#change:}" >> "\$GR_QUERY_LOG"
                sleep 0.2
                printf 'end %s\n' "\${c#change:}" >> "\$GR_QUERY_LOG"
            fi
            cat "$GGCP_JSON/change-\${c#change:}.json" ;;
        I1111111111111111111111111111111111111111) cat "$GGCP_JSON/change-1.json" ;;
        I1234567890abcdef1234567890abcdef12345678) cat "$GGCP_JSON/change-1234.json" ;;
        9001|9002|9003) cat "$GGCP_JSON/cdd-\${c#change:}.json" ;;
        *)    cat "$GGCP_JSON/empty.json" ;;
    esac
}
X
        # 测试用的 git 包装：只记录 cherry-pick 的开始/结束（用来钉"同仓库串行、
    # 不同仓库并行"），其它命令原样转给真 git。
    cat > "$GGCP_ROOT/gitwrap.sh" <<'X'
git () {
    case "$1" in
      cherry-pick)
        printf 'start-cherry\t%s\n' "$PWD" >> "$GR_CHERRY_LOG"
        sleep 0.2
        command git "$@"; rc=$?
        printf 'end-cherry\t%s\n' "$PWD" >> "$GR_CHERRY_LOG"
        return $rc ;;
      *) command git "$@" ;;
    esac
}
X

    GGCP_OK=1
fi

# 每条用例都从同一个起点开始：detached 回到 base，并且清掉上一次的现场
ggcp_reset () {
    for d in "$GGCP_WORK" "$GGCP_OTHER"; do
        [ -d "$d/.git" ] || continue
        git -C "$d" cherry-pick --abort >/dev/null 2>&1 || true
        git -C "$d" checkout -q -f "$GGCP_BASE_SHA" 2>/dev/null || true
        git -C "$d" clean -qfd
    done
}

# ---------------------------------------------------------------------------
# gpun 的夹具：本地裸仓（40 个提交）+ 一个 --depth=1 的 shallow clone
#
#   * 远端只是 $T 下的裸仓，URL 是 file:// —— **绝不碰真 remote、不联网**；
#   * 40 个提交是有意的：--depth=30 之后还剩 10 个没拉下来，
#     所以"跑了 --depth=30"（仍是 shallow、只多到 30 个提交）和
#     "跑了 --unshallow"（不再是 shallow、40 个提交）能被严格区分开；
#   * gb 用桩函数覆盖（真 gb 要站在 repo 工作区里、还要读清单），
#     桩只打印和真 gb 逐字同形的那些行。
# ---------------------------------------------------------------------------
GPUN_OK=0
GPUN_BARE="$T/gpun/bare.git"
GPUN_SEED="$T/gpun/seed"
GPUN_SHALLOW="$T/gpun/shallow"
GPUN_TOTAL=40
if command -v git >/dev/null 2>&1; then
    mkdir -p "$T/gpun"
    git init -q --bare "$GPUN_BARE"
    git clone -q "$GPUN_BARE" "$GPUN_SEED" 2>/dev/null
    (
        cd "$GPUN_SEED"
        git config user.name t
        git config user.email t@t
        git checkout -q -b main
        i=1
        while [ "$i" -le "$GPUN_TOTAL" ]; do
            printf 'c%s\n' "$i" > f.txt
            git add -A
            git commit -qm "c$i"
            i=$((i + 1))
        done
        git push -q -u origin main
    )
    # 裸仓的 HEAD 默认指 master（这里没有那条分支）：指到 main，clone 才不会空手而归
    git -C "$GPUN_BARE" symbolic-ref HEAD refs/heads/main
    GPUN_OK=1
fi

# 重新造一个 --depth=1 的 shallow clone（每条用例都从同一个起点开始）
gpun_shallow_reset () {
    rm -rf "$GPUN_SHALLOW"
    git clone -q --depth=1 "file://$GPUN_BARE" "$GPUN_SHALLOW" 2>/dev/null
    git -C "$GPUN_SHALLOW" config user.name t
    git -C "$GPUN_SHALLOW" config user.email t@t
}

# 桩 gb：形状和真 gb 一样（含那条 git pull … --unshallow），但远端只有本地裸仓
GPUN_GB_STUB="gb () { printf '%s\n' 'git push origin HEAD:refs/for/main' 'git push origin HEAD:main' 'git pull origin main --unshallow' 'git pull origin main' 'git fetch origin main --unshallow' 'git fetch origin main' 'remote: origin' 'branch: main'; }"

# ---------------------------------------------------------------------------
# env.zsh：zsh 层的用法报错
# 这一节钉的就是"在公司敲了 cnp <路径> 没反应"那类事：
# 命令必须明确告诉你"参数用错了/该用哪条命令"，而不是静默忽略或含糊其辞。
# ---------------------------------------------------------------------------
# cdd 的"点参数"夹具（下面同一张表跑两个 shell 用）：
#
#   $DOT_DEEP = $T/dots/l1/…/l8   8 层深。8 个点 = 往上 7 层 -> $T/dots/l1
#                                 （zsh 原生那条路只到 6 个点，这条是钉差异用的）
#   $WS/kernel/common/...         名字**真叫 `...`** 的目录：钉"点参数优先于现存目录"
#
# 这棵树**故意不在 repo 工作区里**（没有 .repo）：点参数不查清单，站在哪儿都能往上跳。
# ---------------------------------------------------------------------------
DOT_ROOT="$T/dots"
DOT_DEEP="$DOT_ROOT/l1/l2/l3/l4/l5/l6/l7/l8"
mkdir -p "$DOT_DEEP" "$WS/kernel/common/..."

# ---------------------------------------------------------------------------
# 同一个用例表跑两个 shell：env.zsh 和 env.bash 必须行为一致
# （命令名、退出码、报错文字都一样；只有实现语法不同）
for SHELL_NAME in zsh bash; do
    if ! command -v "$SHELL_NAME" >/dev/null 2>&1; then
        echo "== env.$SHELL_NAME：跳过（没装 $SHELL_NAME）=="
        continue
    fi
    echo "== env.$SHELL_NAME：cnp/cdd 的用法报错 =="
    mkdir -p "$WS/kernel/common/.git" "$WS/device/emui/generic_a15/.git"

    # 真 PTY 用例要拿绝对路径起交互式 shell（不能靠后半句的 PATH 里那个 shell）
    SHELL_BIN=$(command -v "$SHELL_NAME")
    # 读 / 关"作业控制通知"的写法两个 shell 不同，在这里集中定义一次。
    # ⚠️ MEASURE_MON 只给变量 MON 赋值，**不能写成 echo "$(...)"**：
    # zsh 的 `$(...)` 是子 shell，子 shell 里 monitor 本来就是 off（这也正是
    # env.zsh 把并行阶段放进子 shell 就能消掉提示的原因）—— 拿 $() 去测，
    # 交互式 shell 也会被误判成 off。
    if [ "$SHELL_NAME" = zsh ]; then
        MEASURE_MON='if [[ -o monitor ]]; then MON=on; else MON=off; fi'
        MON_OFF='unsetopt monitor notify'
        SHELL_RC_FLAG='-f'
    else
        MEASURE_MON='case $- in *m*) MON=on;; *) MON=off;; esac'
        MON_OFF='set +m'
        SHELL_RC_FLAG='--norc'
    fi

    shell_eval () {   # $1 = 在夹具里执行的片段
        cat > "$T/s.script" <<EOF
WTOOL_PROJECT_DIR='$here/..'
source "\$WTOOL_PROJECT_DIR/env.$SHELL_NAME"
cd '$WS/kernel/common'
$1
EOF
        "$SHELL_NAME" "$T/s.script" 2>&1
    }
    # set -e 下，"预期会失败"的命令必须用 `|| rc=$?` 接住，
    # 直接 `out=$(...)` 会让整个测试脚本在第一个失败用例上停住
    srun () {       # $1 = 片段；设置 out / rc
        rc=0
        out=$(shell_eval "$1") || rc=$?
    }
    # 和 shell_eval 一样，但 stderr 单独进文件、**不并进 out** ——
    # 「stderr 必须是 0 字节」这条只能这么测（2>&1 一混就看不出来了）
    shell_eval_err () {
        cat > "$T/e.script" <<EOF
WTOOL_PROJECT_DIR='$here/..'
source "\$WTOOL_PROJECT_DIR/env.$SHELL_NAME"
cd '$WS/kernel/common'
$1
EOF
        "$SHELL_NAME" "$T/e.script" 2>"$T/e.$SHELL_NAME"
    }
    erun () {       # $1 = 片段；设置 out / rc / errout
        rc=0
        out=$(shell_eval_err "$1") || rc=$?
        errout=$(cat "$T/e.$SHELL_NAME")
    }

    srun 'cnp device/emui/generic_a15'
    chk "cnp 给参数：退出码 2（不再静默忽略）" "$rc" "2"
    case $out in
        *cdd*) ok "cnp 的报错里点名了 cdd" ;;
        *) bad "cnp 的报错没提 cdd：[$out]" ;;
    esac

    srun 'cnp'
    chk "cnp 不带参数：报出当前项目路径" "$out" "kernel/common"
    srun 'cnn'
    chk "cnn 不带参数：报出清单名字" "$out" "kernel/common"

    srun 'cdd'
    chk "cdd 不给参数：退出码 2" "$rc" "2"

    srun 'cdd local/only'
    chk "cdd 到清单里有、目录没有的项目：退出码 1" "$rc" "1"
    case $out in
        *"repo sync"*) ok "cdd 提示先 repo sync" ;;
        *) bad "cdd 没提示 repo sync：[$out]" ;;
    esac

    srun 'cdd nope/nope'
    chk "cdd 到不存在的名字：退出码 1" "$rc" "1"
    case $out in
        *"清单里没有"*) ok "cdd 报错说清了" ;;
        *) bad "cdd 报错不清楚：[$out]" ;;
    esac

    srun 'cdd device/emui/generic_a15 >/dev/null 2>&1 && pwd'
    chk "cdd 到项目名能跳过去" "$out" "$WS/device/emui/generic_a15"
    srun 'cdd external/zlib >/dev/null 2>&1; cdd kernel/common >/dev/null 2>&1 && pwd'
    chk "cdd 到相对 repo 根的路径也能跳" "$out" "$WS/kernel/common"

    # ---- cdd 的点参数：N 个点 = 往上 N-1 层（`..` 1 层、`...` 2 层、`....` 3 层）----
    # 判据一律用 pwd 的**完整绝对路径**，不用 `cd -`、不拿相对路径比。
    echo "== env.$SHELL_NAME：cdd 的点参数 =="

    srun 'cdd .. >/dev/null 2>&1 && pwd'
    chk "cdd .. ：上一级（1 层）" "$out" "$WS/kernel"
    srun 'cdd ... >/dev/null 2>&1 && pwd'
    chk "cdd ... ：上两级（夹具里那个真叫 ... 的目录不抢）" "$out" "$WS"
    srun 'cdd .... >/dev/null 2>&1 && pwd'
    chk "cdd .... ：上三级" "$out" "$T"

    # 用户点名要的 2～7 个点都过一遍（8 个点那条专门钉"不限 6 个点"）
    srun "cd '$DOT_DEEP' && cdd ..... >/dev/null 2>&1 && pwd"
    chk "cdd 5 个点：往上 4 层" "$out" "$DOT_ROOT/l1/l2/l3/l4"
    srun "cd '$DOT_DEEP' && cdd ...... >/dev/null 2>&1 && pwd"
    chk "cdd 6 个点：往上 5 层" "$out" "$DOT_ROOT/l1/l2/l3"
    srun "cd '$DOT_DEEP' && cdd ....... >/dev/null 2>&1 && pwd"
    chk "cdd 7 个点：往上 6 层" "$out" "$DOT_ROOT/l1/l2"

    # 超过 6 个点：8 个点 = 往上 7 层。zsh 原生（oh-my-zsh 的 global alias）只到 6 个点，
    # 这条就是盯着"我们不限点数"这个差异的。
    srun "cd '$DOT_DEEP' && cdd ........ >/dev/null 2>&1 && pwd"
    chk "cdd 8 个点（zsh 原生只到 6 个）：往上 7 层" "$out" "$DOT_ROOT/l1"

    # 点到根：过了 / 就停在 /，**不算错**（退出码 0，一个字都不打）
    srun 'cdd ............'
    chk "cdd 12 个点（从浅目录跳过根）：退出码 0" "$rc" "0"
    chk "cdd 12 个点：一个字的输出都没有" "$out" ""
    srun 'cdd ............ && pwd'
    chk "cdd 12 个点：停在 /" "$out" "/"
    srun 'cd / && cdd ... >/dev/null 2>&1 && pwd'
    chk "cdd 站在 / 上再往上：还是 /" "$out" "/"

    # 点参数不查清单：在不带 .repo 的目录里也能往上跳（老的三条路都得先找到 .repo）
    srun "cd '$DOT_DEEP' && cdd ... >/dev/null 2>&1 && pwd"
    chk "点参数不需要 .repo（不在工作区里也能跳）" "$out" "$DOT_ROOT/l1/l2/l3/l4/l5/l6"

    # 不是点参数的照旧：`..x` 含别的字符、单个 `.` 只有 1 个点 —— 都不许被点参数抢走
    srun 'cdd ..x'
    chk "cdd ..x（不是点参数）：退出码 1" "$rc" "1"
    case $out in
        *"清单里没有"*) ok "cdd ..x：还是走"清单里没有"那条老路" ;;
        *) bad "cdd ..x 的报错不对：[$out]" ;;
    esac
    srun 'cdd . >/dev/null 2>&1 && pwd'
    chk "cdd .（只有 1 个点，不算点参数）：还是原地" "$out" "$WS/kernel/common"

    # zsh 专属：真机上 oh-my-zsh 给 `...`~`......` 挂了 **global alias**
    # （`alias -g ...='../..'`，见 shell/oh-my-zsh/lib/directories.zsh），
    # 所以交互式 zsh 里敲 `cdd ...`，cdd 收到的其实是 `../..` —— 走"现存目录"那条。
    # 这里把那些 alias 原样复现一遍，钉住"两条路落的点一样"。
    if [ "$SHELL_NAME" = zsh ]; then
        srun 'alias -g ...="../.."
cdd ... >/dev/null 2>&1 && pwd'
        chk "zsh 有 global alias 时（cdd 收到 ../..）：落的点一样" "$out" "$WS"
        srun 'alias -g ....="../../.."
cdd .... >/dev/null 2>&1 && pwd'
        chk "zsh 有 global alias 时（cdd 收到 ../../..）：落的点一样" "$out" "$T"
    fi

    echo "== env.$SHELL_NAME：ggcp 的参数解析（不连网，只测拆参数）=="
    srun '_gerrit_parse_change_arg 1234 && printf "%s\n" "$_GERRIT_CHANGE"'
    chk "1234 -> change" "$out" "1234"
    srun '_gerrit_parse_change_arg 1234/2 && printf "%s %s\n" "$_GERRIT_CHANGE" "$_GERRIT_PS"'
    chk "1234/2 -> change+patchset" "$out" "1234 2"
    srun '_gerrit_parse_change_arg 1234,2 && printf "%s %s\n" "$_GERRIT_CHANGE" "$_GERRIT_PS"'
    chk "1234,2 -> change+patchset" "$out" "1234 2"
    srun '_gerrit_parse_change_arg https://g.example.com/c/p/+/1234/3 9 && printf "%s %s\n" "$_GERRIT_CHANGE" "$_GERRIT_PS"'
    chk "显式 patchset 覆盖 URL 里的" "$out" "1234 9"
    srun "_gerrit_parse_change_arg 'https://g.example.com/#/c/1234/2' && printf \"%s %s\\n\" \"\$_GERRIT_CHANGE\" \"\$_GERRIT_PS\""
    chk "老式 #/c/ 链接" "$out" "1234 2"
    srun '_gerrit_parse_change_arg abc'
    chk "看不出编号：退出码 2" "$rc" "2"
    case $out in
        *patchset*) ok "报错里给了用法" ;;
        *) bad "报错里没给用法：[$out]" ;;
    esac

    # ---- Change-Id 也要认（ggcp 按 Change-Id 展开成多个提交要用它）----
    srun "_gerrit_parse_change_arg I1111111111111111111111111111111111111111 && printf '%s|%s' \"\$_GERRIT_CHANGEID\" \"\$_GERRIT_PS\""
    chk "裸 Change-Id 认得出来（且没有 patchset）" \
        "$out" "I1111111111111111111111111111111111111111|"
    srun "_gerrit_parse_change_arg I1111111111111111111111111111111111111111 2"
    chk "Change-Id 不许再指定 patchset：退出码 2" "$rc" "2"
    srun '_gerrit_parse_change_arg I1111'
    chk "像但不像 Change-Id（太短）：退出码 2" "$rc" "2"

    # ---- ggcp：参数坍缩成"编号|patchset"列表（不连网，只测拆参数）----
    _collect () {   # $1 = 用例；$2 = 想要的 items；$3 = 想要的 ids 个数
        srun "_gr_collect_args $1 && printf '%s;%s' \"\${(j:,:)_GGCP_ITEMS}\" \"\${#_GGCP_IDS}\""
        chk "ggcp 拆参数 $1" "$out" "$2;$3"
    }
    _collect_q () {   # 同上，但给参数加引号（链接里带 ? 时 zsh 会把它当 glob）
        srun "_gr_collect_args '$1' && printf '%s;%s' \"\${(j:,:)_GGCP_ITEMS}\" \"\${#_GGCP_IDS}\""
        chk "ggcp 拆参数 <$1>" "$out" "$2;$3"
    }
    if [ "$SHELL_NAME" = bash ]; then
        _collect () {
            srun "_gr_collect_args $1 && printf '%s;%s' \"\$(IFS=,; echo \"\${_GGCP_ITEMS[*]}\")\" \"\${#_GGCP_IDS[@]}\""
            chk "ggcp 拆参数 $1" "$out" "$2;$3"
        }
        _collect_q () {
            srun "_gr_collect_args '$1' && printf '%s;%s' \"\$(IFS=,; echo \"\${_GGCP_ITEMS[*]}\")\" \"\${#_GGCP_IDS[@]}\""
            chk "ggcp 拆参数 <$1>" "$out" "$2;$3"
        }
    fi
    _collect '1,2,3' '1|,2|,3|' 0
    _collect '1 2 3' '1|,2|,3|' 0
    _collect '1,2 3' '1|,2|,3|' 0
    _collect '1,2 3,4' '1|,2|,3|,4|' 0
    _collect '1234/2' '1234|2' 0
    _collect 'https://g.example.com/c/p/+/1234/3' '1234|3' 0
    _collect 'https://g.example.com/#/c/1234' '1234|' 0
    _collect_q 'https://g.example.com/c/p/+/1234/?x=1' '1234|' 0
    _collect '1,https://g.example.com/#/c/2,3' '1|,2|,3|' 0
    _collect 'I1111111111111111111111111111111111111111' '' 1
    _collect '1,I1111111111111111111111111111111111111111,2' '1|,2|' 1

    # ---- 不许依赖 zsh 的启动文件 / zsh/regex 模块（2026-10-23 修那 7 条真 PTY 红）----
    # 背景：`zsh -f` 不读 .zshenv；本仓自带的 zsh 构建（~/.wtool/usr/bin/zsh）编译期
    # module_path 指向 /root，于是 `=~`（要 zsh/regex 模块）加载不上 —— **zsh 会把
    # 整段 -c 脚本直接终止**，调用方的 shell 也不往下走。真 PTY 那组原来就是这么红的：
    # ggcp 一个字没打、后面 RC=/MON_AFTER= 全没出来、stderr 正好 207 字节。
    # 这里把 module_path 指到空目录，**稳定复现"模块不可用"**（不依赖本机 zsh 构建成什么样）：
    # 拆参数必须还对，而且脚本必须继续跑到 AFTER。
    if [ "$SHELL_NAME" = zsh ]; then
        cat > "$T/norc.zsh" <<EOF
module_path=(/nonexistent)
WTOOL_PROJECT_DIR='$here/..'
. "\$WTOOL_PROJECT_DIR/env.zsh"
_gr_collect_args 1234/2 https://g.example.com/c/p/+/5678/3 I1111111111111111111111111111111111111111
printf 'ITEMS=%s\n' "\${(j:,:)_GGCP_ITEMS}"
printf 'IDS=%s\n' "\${(j:,:)_GGCP_IDS}"
ggcp abc 2>/dev/null
printf 'AFTER=%s\n' ok
EOF
        zf_rc=0
        zf_out=$("$SHELL_BIN" -f "$T/norc.zsh" 2>&1) || zf_rc=$?
        chk "zsh -f + 没有 zsh/regex 模块：拆参数照样对" \
            "$(printf '%s\n' "$zf_out" | sed -n 's/^ITEMS=//p')" "1234|2,5678|3"
        chk "zsh -f + 没有 zsh/regex 模块：Change-Id 也认得出来" \
            "$(printf '%s\n' "$zf_out" | sed -n 's/^IDS=//p')" \
            "I1111111111111111111111111111111111111111"
        chk "zsh -f + 没有 zsh/regex 模块：不会再带崩调用方的脚本" \
            "$(printf '%s\n' "$zf_out" | sed -n 's/^AFTER=//p')" "ok"
        chk "zsh -f + 没有 zsh/regex 模块：整段脚本退出码 0" "$zf_rc" "0"
    fi
    srun '_gr_collect_args abc'
    chk "ggcp 乱参数：退出码 2" "$rc" "2"
    case $out in
        *"不是提交编号"*) ok "ggcp 乱参数报错说清了" ;;
        *) bad "ggcp 乱参数报错不清楚：[$out]" ;;
    esac
    srun 'ggcp'
    chk "ggcp 不给参数：退出码 2" "$rc" "2"
    case $out in
        *"Usage: ggcp"*) ok "ggcp 不给参数打出用法" ;;
        *) bad "ggcp 没打用法：[$out]" ;;
    esac
    srun 'ggcp -p x 1'
    chk "ggcp -p 不是数字：退出码 2" "$rc" "2"

    # ---- 颜色：只有自动两条（NO_COLOR / stdout 是不是 tty），没有强制开关 ----
    # ⚠️ 跑测试的环境本身可能设了 NO_COLOR（本机实测就有 NO_COLOR=1）——
    #    所以"该上色"的用例必须显式 `unset NO_COLOR` / `env -u NO_COLOR`，
    #    否则测的是 NO_COLOR 那条规则，不是 tty 那条。
    ESC=$(printf '\033')
    srun 'unset NO_COLOR; ggcp 1 2>/dev/null'
    case $out in
        *"$ESC"*) bad "非 tty 时不该有 ANSI 颜色码：[$out]" ;;
        *) ok "非 tty（stdout 是管道）：输出是纯文本，一个 ANSI 码都没有" ;;
    esac
    srun 'NO_COLOR=1 _gr_red 打补丁失败'
    chk "NO_COLOR=1：红行退化成纯文本" "$out" "打补丁失败"

    # 真 pty：用 script(1) 起一个伪终端，stdout 就是 tty —— 这时候必须上色。
    # （script 会把 \n 写成 \r\n，断言前先 tr -d '\r'）
    if command -v script >/dev/null 2>&1; then
        pty_eval () {   # $1 = 片段；设置 out / rc（输出里保留 ANSI）
            cat > "$T/p.script" <<EOF
WTOOL_PROJECT_DIR='$here/..'
source "\$WTOOL_PROJECT_DIR/env.$SHELL_NAME"
cd '$WS/kernel/common'
$1
EOF
            rc=0
            # env -u NO_COLOR：见上面那条注释（环境自带 NO_COLOR 时这里测不出 tty 规则）
            # `</dev/null`：别把调用方的 stdin 喂进伪终端（那会变成 shell 的"命令"）
            out=$(script -qec "env -u NO_COLOR $SHELL_NAME $T/p.script" /dev/null \
                2>&1 </dev/null | tr -d '\r') || rc=$?
        }
        pty_eval '_gr_green 打补丁成功'
        case $out in
            *"$ESC[32m打补丁成功$ESC[0m"*) ok "真 pty（script）：绿行带 ANSI 色码" ;;
            *) bad "真 pty 里没上绿色：[$out]" ;;
        esac
        pty_eval '_gr_red 打补丁失败'
        case $out in
            *"$ESC[31m打补丁失败$ESC[0m"*) ok "真 pty（script）：红行带 ANSI 色码" ;;
            *) bad "真 pty 里没上红色：[$out]" ;;
        esac
        pty_eval 'NO_COLOR=1 _gr_green 打补丁成功'
        case $out in
            *"$ESC"*) bad "NO_COLOR 在真 pty 里也该关掉颜色：[$out]" ;;
            *) ok "真 pty + NO_COLOR：照样不给颜色" ;;
        esac
    else
        echo "  （没装 script，真 pty 那三条颜色用例跳过）"
    fi

    # ---- ggcp 端到端：桩 gerrit（喂 JSON）+ 本地裸仓（真 fetch / cherry-pick）----
    if [ "$GGCP_OK" != 1 ]; then
        echo "  （没装 git，ggcp 端到端这几条跳过）"
    else
        echo "== env.$SHELL_NAME：ggcp（桩 gerrit + 本地裸仓，不联网）=="

        # ---- 单笔：总述 + 一张只有一行的表（也是表格，不再有五行叙述）----
        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1"
        chk "ggcp 1：退出码 0" "$rc" "0"
        chk "ggcp 1：正好 4 行（总述 + 表头 + 分隔线 + 一行结果）" \
            "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4"
        chk "ggcp 1：总述行" \
            "$(printf '%s\n' "$out" | sed -n 1p)" "1 个仓库 / 1 笔提交 / 成功 1 / 失败 0"
        case $(printf '%s\n' "$out" | sed -n 2p) in
            *项目名*项目路径*提交*id*patchset*结果说明*) ok "ggcp 1：表头 5 列都在" ;;
            *) bad "ggcp 1 表头不对：$(printf '%s\n' "$out" | sed -n 2p)" ;;
        esac
        case $(printf '%s\n' "$out" | sed -n 4p) in
            *platform/mylib*mylib*1*成功*) ok "ggcp 1：结果行带项目名/路径/patchset/成功" ;;
            *) bad "ggcp 1 结果行不对：$(printf '%s\n' "$out" | sed -n 4p)" ;;
        esac
        chk "ggcp 1：真的 cherry-pick 上来了" \
            "$(git -C "$GGCP_WORK" log --oneline -1 --format=%s)" "lab: change one (ps1)"
        chk "ggcp 1：新文件在" "$(cat "$GGCP_WORK/ps1.txt" 2>/dev/null)" "ps1"

        # ---- 指定 patchset：1234/2 写法，表里的 patchset 列必须是 2 ----
        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1/2"
        chk "ggcp 1/2：退出码 0" "$rc" "0"
        chk "ggcp 1/2：表里 patchset 列是 2" \
            "$(printf '%s\n' "$out" | grep '^platform/mylib' | grep -c '  2  ')" "1"
        chk "ggcp 1/2：ps2 文件在" "$(cat "$GGCP_WORK/ps2.txt" 2>/dev/null)" "ps2"
        ggcp_reset

        # 真 pty：表格不带 ANSI 色码（颜色码会破坏中文对齐）
        if command -v script >/dev/null 2>&1; then
            ggcp_reset
            pty_eval "source $GGCP_ROOT/stub.sh
                cd $GGCP_WORK
                ggcp 1"
            chk "真 pty 里 ggcp 1：退出码 0" "$rc" "0"
            case $out in
                *"$ESC"*) bad "真 pty 里 ggcp 的表格不该带 ANSI 色码：[$out]" ;;
                *) ok "真 pty 里 ggcp 的表格不带 ANSI 色码（对齐不会被破坏）" ;;
            esac
            case $out in
                *项目名*结果说明*) ok "真 pty 里表格照样打出来" ;;
                *) bad "真 pty 里没打出表格：[$out]" ;;
            esac
            ggcp_reset
        fi

        # ---- 多笔同仓库：一行一个提交，成功 2 ----
        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1 2"
        chk "ggcp 1 2（空格分隔）：退出码 0" "$rc" "0"
        chk "ggcp 1 2：总述 1 个仓库 / 2 笔提交 / 成功 2" \
            "$(printf '%s\n' "$out" | sed -n 1p)" "1 个仓库 / 2 笔提交 / 成功 2 / 失败 0"
        chk "ggcp 1 2：表里两行（都指向 mylib）" \
            "$(printf '%s\n' "$out" | grep -c '^platform/mylib')" "2"
        chk "ggcp 1 2：两个补丁都进来了" \
            "$(git -C "$GGCP_WORK" log --oneline --format=%s | head -2 | tr '\n' '/')" \
            "lab: change two/lab: change one (ps1)/"

        # ---- 重复打（**没有 Change-Id** 的提交才走这条路）：空提交 -> 本地已有；
        #      失败后工作树必须干净。有 Change-Id 的重复打会被预检先拦下，见下面
        #      "同 Change-Id 预检 + ggrvt" 那一节。
        #      101/102 的夹具提交故意没有 Change-Id 行（钉住兜底分类）。
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 101"
        chk "101 先打一次：退出码 0" "$rc" "0"
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 101"
        chk "重复打同一个补丁（无 Change-Id）：退出码 1" "$rc" "1"
        chk "重复打（无 Change-Id）：总述失败 1" \
            "$(printf '%s\n' "$out" | sed -n 1p)" "1 个仓库 / 1 笔提交 / 成功 0 / 失败 1"
        case $out in
            *"此提交本地已经有了（可能已合入）"*) ok "重复打（无 Change-Id）：结果说明是「本地已有」" ;;
            *) bad "重复打（无 Change-Id）的结果说明不对：[$out]" ;;
        esac
        chk "重复打之后工作树干净" "$(git -C "$GGCP_WORK" status --porcelain)" ""
        chk "重复打之后没有 CHERRY_PICK_HEAD" \
            "$(git -C "$GGCP_WORK" rev-parse -q --verify CHERRY_PICK_HEAD 2>/dev/null || true)" ""
        ggcp_reset

        # ---- 链接：老式 #/c/1234 和新式 /c/proj/+/1234 ----
        TWO_SHORT=$(printf '%s' "$GGCP_TWO_SHA" | cut -c1-12)
        PS1_SHORT=$(printf '%s' "$GGCP_PS1_SHA" | cut -c1-12)
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 'https://g.example.com/#/c/2'"
        chk "ggcp <老式链接>：退出码 0" "$rc" "0"
        case $out in
            *platform/mylib*"$TWO_SHORT"*1*成功*) ok "ggcp <老式链接>：打的是 2 号" ;;
            *) bad "ggcp <老式链接> 的表不对：[$out]" ;;
        esac
        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 'https://g.example.com/c/platform/mylib/+/1/1'"
        chk "ggcp <新式链接>：退出码 0" "$rc" "0"
        case $out in
            *platform/mylib*"$PS1_SHORT"*1*成功*) ok "ggcp <新式链接>：编号从链接里取" ;;
            *) bad "ggcp <新式链接> 的表不对：[$out]" ;;
        esac
        ggcp_reset

        # ---- 查不到 / 项目不在工作区：都进表、非 0 ----
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 9"
        chk "change 查不到：退出码 1" "$rc" "1"
        case $out in
            *查询失败*) ok "change 查不到：结果表里写「查询失败」" ;;
            *) bad "change 查不到没进表：[$out]" ;;
        esac

        # gerrit 服务器都没配置：也打结果表（不是只甩一段 stderr）
        srun "cd $T
            unset WTOOL_GERRIT_HOST WTOOL_GERRIT_PORT WTOOL_GERRIT_USER WTOOL_GERRIT_SSH_KEY WTOOL_GERRIT_CONF
            source $GGCP_ROOT/stub.sh
            ggcp 1"
        chk "没配 gerrit：退出码 1" "$rc" "1"
        chk "没配 gerrit：总述一行失败" \
            "$(printf '%s\n' "$out" | grep '个仓库 / .* 笔提交' | tail -1)" \
            "0 个仓库 / 1 笔提交 / 成功 0 / 失败 1"
        case $out in
            *"查询失败：不知道 gerrit 服务器在哪"*) ok "没配 gerrit：结果表里也写清楚了" ;;
            *) bad "没配 gerrit 没进结果表：[$out]" ;;
        esac
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 9002"
        chk "项目在清单里、目录没检出：退出码 1" "$rc" "1"
        case $out in
            *"项目目录不存在：gone/project"*) ok "目录没检出：表里说清要 repo sync" ;;
            *) bad "目录没检出的结果说明不对：[$out]" ;;
        esac
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 9003"
        chk "项目不在清单里：退出码 1" "$rc" "1"
        case $out in
            *"本地清单里没有项目 nope/nope"*) ok "项目不在清单里：表里说清" ;;
            *) bad "项目不在清单里的结果说明不对：[$out]" ;;
        esac

        # ---- Change-Id：选择表 + 逐个询问（-y / -n / 交互三种）----
        ggcp_reset
        srun "printf 'y\nn\n' | {
                source $GGCP_ROOT/stub.sh
                cd $GGCP_WORK
                ggcp I1111111111111111111111111111111111111111
            }"
        chk "Change-Id 逐个问：退出码 0" "$rc" "0"
        case $out in
            *"编号  patchset  仓库"*) ok "Change-Id：打了选择表（编号/patchset/仓库/路径/提交链接）" ;;
            *) bad "Change-Id 没打选择表：[$out]" ;;
        esac
        chk "Change-Id：选择表里两个 patchset 各一行（看提交链接列）" \
            "$(printf '%s\n' "$out" | grep -c 'g.example.com/c/platform/mylib/+/1/')" "2"
        case $out in
            *"路径"*"mylib"*) ok "Change-Id：选择表里有本地路径" ;;
            *) bad "Change-Id 选择表里没路径：[$out]" ;;
        esac
        chk "Change-Id：逐个问了两次（y/n 各一次）" \
            "$(printf '%s\n' "$out" | grep -o '打补丁 1 (patchset' | wc -l | tr -d ' ')" "2"
        case $out in
            *"给仓库 platform/mylib 打补丁 1 (patchset 1) 吗？"*) ok "询问里点明了仓库/编号/patchset" ;;
            *) bad "询问文案看不明白：[$out]" ;;
        esac
        chk "Change-Id：答 y 的那个真打了（答 n 的没打）" \
            "$(git -C "$GGCP_WORK" log --oneline --format=%s | head -1)" "lab: change one (ps1)"
        chk "Change-Id：最终结果表里只有答应的那一行" \
            "$(printf '%s\n' "$out" | grep -c '^platform/mylib')" "1"
        case $out in
            *platform/mylib*mylib*1*成功*) ok "Change-Id：答应的那条在结果表里是成功" ;;
            *) bad "Change-Id 答应的没打成功：[$out]" ;;
        esac

        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp -n I1111111111111111111111111111111111111111"
        chk "ggcp -n：退出码 0、一个都不打" "$rc" "0"
        chk "ggcp -n：没动 HEAD" \
            "$(git -C "$GGCP_WORK" rev-parse HEAD)" "$GGCP_BASE_SHA"
        case $out in
            *"没有要打的补丁"*) ok "ggcp -n：明说没有要打的" ;;
            *) bad "ggcp -n 的输出不对：[$out]" ;;
        esac

        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp -y I1111111111111111111111111111111111111111"
        # 同一个 Change-Id 的两个 patchset 连着打：第一个成功，第二个必须被
        # "同 Change-Id 已在本地历史"预检拦住（用户报的正是"两个都能打成功"）。
        chk "ggcp -y（一个 Change-Id 两个 patchset）：退出码 1" "$rc" "1"
        chk "ggcp -y：总述 成功 1 / 失败 1" \
            "$(printf '%s\n' "$out" | grep '个仓库 / .* 笔提交' | tail -1)" \
            "1 个仓库 / 2 笔提交 / 成功 1 / 失败 1"
        chk "ggcp -y：表里两行（一行成功、一行预检失败）" \
            "$(printf '%s\n' "$out" | grep -c '^platform/mylib')" "2"
        chk "ggcp -y：只有一行是成功" \
            "$(printf '%s\n' "$out" | grep -c '^platform/mylib.*成功')" "1"
        case $out in
            *"ggrvt 1 回退"*) ok "ggcp -y：第二个 patchset 的结果里提示 ggrvt 1 回退" ;;
            *) bad "ggcp -y：第二个 patchset 没提示 ggrvt：[$out]" ;;
        esac
        chk "ggcp -y：只打了 ps1（ps2 的文件没有）" \
            "$(cat "$GGCP_WORK/ps1.txt" 2>/dev/null)/$(cat "$GGCP_WORK/ps2.txt" 2>/dev/null)" "ps1/"
        chk "ggcp -y：本地只有 1 个同 Change-Id 的提交" \
            "$(git -C "$GGCP_WORK" log --format=%H --grep="^Change-Id: $GGCP_CID1$" | wc -l | tr -d ' ')" "1"
        ggcp_reset

        # ---- 同 Change-Id 预检 + ggrvt（用户 2026-10-22 报的真 bug）----
        #
        # 现场：ggcp 1234/1 打过 ps1，再 ggcp 1234/2 —— ps2 只比 ps1 多一个文件，
        # cherry-pick 会"成功"，于是 git log 里出现**两个同 Change-Id 的提交**。
        # 现在的规矩：第二次必须失败、给出 ggrvt 提示、一个字节都不许 cherry-pick；
        # ggrvt 回退掉旧的之后，才能重新打。
        echo "== env.$SHELL_NAME：ggcp 预检（同 Change-Id 已在本地）+ ggrvt =="

        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1234/1"
        chk "ggcp 1234/1：退出码 0" "$rc" "0"
        chk "ggcp 1234/1：ps1 的文件打上了" "$(cat "$GGCP_WORK/1234ps1.txt" 2>/dev/null)" "1234ps1"
        chk "ggcp 1234/1：本地历史里有一个同 Change-Id 的提交" \
            "$(git -C "$GGCP_WORK" log --format=%H --grep="^Change-Id: $GGCP_CID1234$" | wc -l | tr -d ' ')" "1"

        # 关键用例：同一个 change 的 ps2 —— 必须失败
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1234/2"
        chk "ggcp 1234/2（同 Change-Id 已在本地）：退出码 1" "$rc" "1"
        chk "预检失败：总述 成功 0 / 失败 1" \
            "$(printf '%s\n' "$out" | sed -n 1p)" "1 个仓库 / 1 笔提交 / 成功 0 / 失败 1"
        case $out in
            *"此 Change-Id 已在本地历史"*) ok "预检失败：结果说明点明「此 Change-Id 已在本地历史」" ;;
            *) bad "预检失败的说明不对：[$out]" ;;
        esac
        case $out in
            *"patchset 1"*) ok "预检失败：认出历史里那个是 patchset 1（patch-id 比出来的）" ;;
            *) bad "预检失败没认出 patchset：[$out]" ;;
        esac
        case $out in
            *"ggrvt 1234 回退"*) ok "预检失败：提示先 ggrvt 1234 回退" ;;
            *) bad "预检失败没提示 ggrvt：[$out]" ;;
        esac
        chk "预检失败后：ps2 的文件**没有**被带进来" \
            "$(cat "$GGCP_WORK/1234ps2.txt" 2>/dev/null)" ""
        chk "预检失败后：本地仍然只有 1 个同 Change-Id 的提交" \
            "$(git -C "$GGCP_WORK" log --format=%H --grep="^Change-Id: $GGCP_CID1234$" | wc -l | tr -d ' ')" "1"
        chk "预检失败后：HEAD 没动（还是 ps1 那个提交）" \
            "$(git -C "$GGCP_WORK" log -1 --format=%s)" "lab: change 1234 (ps1)"
        chk "预检失败后：工作树干净" "$(git -C "$GGCP_WORK" status --porcelain)" ""
        chk "预检失败后：没有 CHERRY_PICK_HEAD" \
            "$(git -C "$GGCP_WORK" rev-parse -q --verify CHERRY_PICK_HEAD 2>/dev/null || true)" ""

        # 同一笔再打一次（ggcp 1234/1 重复）也命中这条预检
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1234/1"
        chk "重复打 1234/1：退出码 1（也被预检拦下）" "$rc" "1"
        case $out in
            *"ggrvt 1234 回退"*) ok "重复打 1234/1：同样提示 ggrvt" ;;
            *) bad "重复打 1234/1 的提示不对：[$out]" ;;
        esac

        # ---- ggrvt：回退 ps1 → 再打 ps2 成功（且不会出现第二个同 Change-Id 的有效提交）----
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggrvt 1234"
        chk "ggrvt 1234：退出码 0" "$rc" "0"
        case $out in
            *"已回退"*"change 1234, patchset 1"*) ok "ggrvt 1234：说明里写了 change/patchset" ;;
            *) bad "ggrvt 1234 的输出不对：[$out]" ;;
        esac
        case $out in
            *"现在可以 ggcp 1234/2"*) ok "ggrvt 1234：提示现在可以 ggcp 1234/2" ;;
            *) bad "ggrvt 1234 没提示下一步：[$out]" ;;
        esac
        chk "ggrvt 之后：HEAD 是 revert 提交" \
            "$(git -C "$GGCP_WORK" log -1 --format=%s)" 'Revert "lab: change 1234 (ps1)"'
        chk "ggrvt 之后：ps1 的文件被撤掉了" \
            "$(cat "$GGCP_WORK/1234ps1.txt" 2>/dev/null)" ""
        chk "ggrvt 之后：工作树干净" "$(git -C "$GGCP_WORK" status --porcelain)" ""
        # 历史里那个 ps1 提交还在（revert 不删历史），但**不算数了** ——
        # 这就是 ggcp 预检认的"有效提交"，不剔掉它 ggrvt 就白回退了。
        srun "cd $GGCP_WORK && _gr_local_change_commits $GGCP_CID1234 | wc -l | tr -d ' '"
        chk "ggrvt 之后：有效的同 Change-Id 提交 0 个" "$out" "0"

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1234/2"
        chk "ggrvt 之后 ggcp 1234/2：退出码 0（能重新打了）" "$rc" "0"
        chk "ggrvt 之后 ggcp 1234/2：ps2 的文件在" \
            "$(cat "$GGCP_WORK/1234ps2.txt" 2>/dev/null)" "1234ps2"
        chk "ggrvt 之后 ggcp 1234/2：ps1 的文件也在（ps2 的 diff 带着它）" \
            "$(cat "$GGCP_WORK/1234ps1.txt" 2>/dev/null)" "1234ps1"
        srun "cd $GGCP_WORK && _gr_local_change_commits $GGCP_CID1234 | wc -l | tr -d ' '"
        chk "ggrvt 之后重打：有效的同 Change-Id 提交只有 1 个" "$out" "1"
        chk "ggrvt 之后重打：log 顶部顺序是 ps2 / revert / ps1" \
            "$(git -C "$GGCP_WORK" log --format=%s -3 | tr '\n' '/')" \
            'lab: change 1234 (ps2)/Revert "lab: change 1234 (ps1)"/lab: change 1234 (ps1)/'
        # 再打一次就必须又被拦住 —— 证明"有效的同 Change-Id 提交"始终只有一个
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1234/2"
        chk "重打之后再打 1234/2：退出码 1（不会有第二个同 Change-Id 提交）" "$rc" "1"
        srun "cd $GGCP_WORK && _gr_local_change_commits $GGCP_CID1234 | wc -l | tr -d ' '"
        chk "重打之后再打：有效的同 Change-Id 提交还是 1 个" "$out" "1"

        # ---- 成功路径：stderr 必须是 0 字节（和 ggcp 同一条硬规矩）----
        ggcp_reset
        erun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1234/1"
        chk "ggcp 1234/1 成功路径：退出码 0" "$rc" "0"
        chk "ggcp 1234/1 成功路径：stderr 0 字节" \
            "$(wc -c < "$T/e.$SHELL_NAME" | tr -d ' ')" "0"
        erun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggrvt 1234"
        chk "ggrvt 成功路径：退出码 0" "$rc" "0"
        chk "ggrvt 成功路径：stderr 0 字节" \
            "$(wc -c < "$T/e.$SHELL_NAME" | tr -d ' ')" "0"
        chk "ggrvt 成功路径：stdout 只有一行" \
            "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"
        ggcp_reset

        # ---- ggrvt 的报错：零命中 / 多命中 / 不支持 patchset / 项目没检出 ----
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggrvt 2"
        chk "ggrvt 零命中（本地没打过 change 2）：退出码 1" "$rc" "1"
        case $out in
            *"本地历史里没有该 Change-Id 的提交"*) ok "ggrvt 零命中：报错说清了" ;;
            *) bad "ggrvt 零命中的报错不对：[$out]" ;;
        esac

        # 多命中：本地真有同 Change-Id 的两个提交（历史遗留）-> 拒绝，且列出两个 SHA
        DUP_A=$(cd "$GGCP_WORK" && git commit -q --allow-empty -m 'dup a' -m "Change-Id: $GGCP_CID1234" && git rev-parse HEAD)
        DUP_B=$(cd "$GGCP_WORK" && git commit -q --allow-empty -m 'dup b' -m "Change-Id: $GGCP_CID1234" && git rev-parse HEAD)
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggrvt 1234"
        chk "ggrvt 多个同 Change-Id 提交：退出码 1" "$rc" "1"
        case $out in
            *"2 个同 Change-Id 的提交"*) ok "ggrvt 多命中：说清有几个" ;;
            *) bad "ggrvt 多命中的报错不对：[$out]" ;;
        esac
        case $out in
            *"$DUP_A"*) ok "ggrvt 多命中：列出了第一个 SHA" ;;
            *) bad "ggrvt 多命中没列第一个 SHA：[$out]" ;;
        esac
        case $out in
            *"$DUP_B"*) ok "ggrvt 多命中：列出了第二个 SHA" ;;
            *) bad "ggrvt 多命中没列第二个 SHA：[$out]" ;;
        esac
        chk "ggrvt 多命中：没有擅自 revert（HEAD 没动）" \
            "$(git -C "$GGCP_WORK" rev-parse HEAD)" "$DUP_B"
        chk "ggrvt 多命中：工作树干净" "$(git -C "$GGCP_WORK" status --porcelain)" ""
        # ggcp 的预检遇多命中：也报出来，并且说 ggrvt 会拒绝
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1234/1"
        chk "预检遇多个同 Change-Id 提交：退出码 1" "$rc" "1"
        case $out in
            *"2 个提交"*"ggrvt 1234 会拒绝回退"*) ok "预检遇多命中：列出个数并说明 ggrvt 会拒绝" ;;
            *) bad "预检遇多命中的说明不对：[$out]" ;;
        esac
        case $out in
            *"$(printf '%s' "$DUP_A" | cut -c1-12)"*) ok "预检遇多命中：表里列出了第一个短 SHA" ;;
            *) bad "预检遇多命中没列第一个 SHA：[$out]" ;;
        esac
        case $out in
            *"$(printf '%s' "$DUP_B" | cut -c1-12)"*) ok "预检遇多命中：表里列出了第二个短 SHA" ;;
            *) bad "预检遇多命中没列第二个 SHA：[$out]" ;;
        esac
        ggcp_reset

        # ggrvt 的三条入口都能真回退：编号 / gerrit 链接 / Change-Id
        for ARG in "1234" \
                   "https://g.example.com/c/platform/mylib/+/1234" \
                   "$GGCP_CID1234"; do
            ggcp_reset
            srun "source $GGCP_ROOT/stub.sh
                cd $GGCP_WORK
                ggcp 1234/1"
            srun "source $GGCP_ROOT/stub.sh
                cd $GGCP_WORK
                ggrvt $ARG"
            chk "ggrvt 用参数 '$ARG'：退出码 0" "$rc" "0"
            chk "ggrvt 用参数 '$ARG'：真回退了（HEAD 是 Revert）" \
                "$(git -C "$GGCP_WORK" log -1 --format=%s)" 'Revert "lab: change 1234 (ps1)"'
        done
        ggcp_reset

        srun 'ggrvt'
        chk "ggrvt 不给参数：退出码 2" "$rc" "2"
        case $out in
            *"Usage: ggrvt"*) ok "ggrvt 不给参数：打出了用法" ;;
            *) bad "ggrvt 没打用法：[$out]" ;;
        esac
        srun 'ggrvt 1234/2'
        chk "ggrvt 1234/2：退出码 2（不接受 patchset）" "$rc" "2"
        case $out in
            *"不接受 patchset"*) ok "ggrvt 1234/2：说清了不接受 patchset" ;;
            *) bad "ggrvt 1234/2 的报错不对：[$out]" ;;
        esac
        srun 'ggrvt https://g.example.com/c/platform/mylib/+/1234/2'
        chk "ggrvt <带 patchset 的链接>：退出码 2" "$rc" "2"
        srun 'ggrvt 1,2'
        chk "ggrvt 1,2：退出码 2（一次只回退一个）" "$rc" "2"
        srun 'ggrvt abc'
        chk "ggrvt abc：退出码 2（参数不对）" "$rc" "2"
        srun 'ggrvt 1 2'
        chk "ggrvt 1 2：退出码 2（一次只回退一个）" "$rc" "2"

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggrvt 9002"
        chk "ggrvt 项目没检出：退出码 1" "$rc" "1"
        case $out in
            *"还没检出"*"repo sync gone/project"*) ok "ggrvt 项目没检出：提示 repo sync" ;;
            *) bad "ggrvt 项目没检出的报错不对：[$out]" ;;
        esac
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggrvt 9001"
        chk "ggrvt 查到的 change 没有 Change-Id：退出码 1" "$rc" "1"
        case $out in
            *"没给出 change 9001 的 Change-Id"*) ok "ggrvt 缺 Change-Id：报错说清了" ;;
            *) bad "ggrvt 缺 Change-Id 的报错不对：[$out]" ;;
        esac

        # ---- 四笔跨两个仓库：并行查询 + 同仓库串行 + 不同仓库并行 + 合并成一张表 ----
        GR_QLOG="$T/ggcp-query.$SHELL_NAME.log"
        GR_CLOG="$T/ggcp-cherry.$SHELL_NAME.log"
        rm -f "$GR_QLOG" "$GR_CLOG"
        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            source $GGCP_ROOT/gitwrap.sh
            export GR_QUERY_LOG=$GR_QLOG GR_CHERRY_LOG=$GR_CLOG
            cd $GGCP_WORK
            ggcp 101 102 103 104"
        chk "ggcp 四笔：退出码 0" "$rc" "0"
        chk "ggcp 四笔：总述 2 个仓库 / 4 笔提交 / 成功 4" \
            "$(printf '%s\n' "$out" | sed -n 1p)" "2 个仓库 / 4 笔提交 / 成功 4 / 失败 0"
        chk "ggcp 四笔：表里 2 行 mylib" \
            "$(printf '%s\n' "$out" | grep -c '^platform/mylib')" "2"
        chk "ggcp 四笔：表里 2 行 other" \
            "$(printf '%s\n' "$out" | grep -c '^platform/other')" "2"
        case $(printf '%s\n' "$out" | sed -n 4p; printf '%s\n' "$out" | sed -n 5p) in
            *platform/mylib*) ok "ggcp 四笔：mylib 的两行连续（先按路径分组）" ;;
            *) bad "ggcp 四笔：mylib 行不连续：[$out]" ;;
        esac
        case $(printf '%s\n' "$out" | sed -n 6p; printf '%s\n' "$out" | sed -n 7p) in
            *platform/other*) ok "ggcp 四笔：other 的两行连续" ;;
            *) bad "ggcp 四笔：other 行不连续：[$out]" ;;
        esac
        chk "ggcp 四笔：查询 4 次都开始/结束" \
            "$(grep -c '^start' "$GR_QLOG")/$(grep -c '^end' "$GR_QLOG")" "4/4"
        QMAX=$(awk '$1=="start"{n++; if(n>m)m=n} $1=="end"{n--} END{print m+0}' "$GR_QLOG")
        if [ "$QMAX" -ge 2 ]; then
            ok "ggcp 四笔：查询是并行的（最多同时 $QMAX 条）"
        else
            bad "ggcp 四笔：查询没有并行（最多同时 $QMAX 条）"
        fi
        CMAX_MY=$(awk -F '\t' '$1=="start-cherry" && $2 ~ /\/mylib$/ {n++; if(n>m)m=n} $1=="end-cherry" && $2 ~ /\/mylib$/ {n--} END{print m+0}' "$GR_CLOG")
        CMAX_OT=$(awk -F '\t' '$1=="start-cherry" && $2 ~ /\/other$/ {n++; if(n>m)m=n} $1=="end-cherry" && $2 ~ /\/other$/ {n--} END{print m+0}' "$GR_CLOG")
        CMAX_ALL=$(awk -F '\t' '$1=="start-cherry"{n++; if(n>m)m=n} $1=="end-cherry"{n--} END{print m+0}' "$GR_CLOG")
        chk "ggcp 四笔：mylib 内部串行（同时最多 1 个 cherry-pick）" "$CMAX_MY" "1"
        chk "ggcp 四笔：other 内部串行（同时最多 1 个 cherry-pick）" "$CMAX_OT" "1"
        if [ "$CMAX_ALL" -ge 2 ]; then
            ok "ggcp 四笔：不同仓库并行（最多同时 $CMAX_ALL 个）"
        else
            bad "ggcp 四笔：不同仓库没有并行（最多同时 $CMAX_ALL 个）"
        fi
        chk "ggcp 四笔：mylib 按用户给的顺序落（A2 在上）" \
            "$(git -C "$GGCP_WORK" log --format=%s -2 | tr '\n' '/')" "lab: A2/lab: A1/"
        chk "ggcp 四笔：other 按用户给的顺序落（B2 在上）" \
            "$(git -C "$GGCP_OTHER" log --format=%s -2 | tr '\n' '/')" "lab: B2/lab: B1/"
        chk "ggcp 四笔：两个工作树都干净" \
            "$(git -C "$GGCP_WORK" status --porcelain)$(git -C "$GGCP_OTHER" status --porcelain)" ""

        # ---- 成功路径：stderr 必须是 0 字节（非交互 shell 也一条都不许有）----
        # 用户报的现场是「表格之外还有一堆 shell 的 job 控制信息」。这些提示
        # 分两路：① shell 打 `[1] 12345` 时走的是**当前命令的 stderr**
        # （所以 `ggcp 2>err` 会把它收进 err，实测 bash 四笔 = 66 字节）；
        # ② 交互式 shell 在作业结束时又往终端补 `[1]+ Done ...`。
        # 这里先钉 ①：非交互 shell 里跑一遍，err 必须是空的。
        ggcp_reset
        erun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1 2"
        chk "ggcp 成功路径（非交互）：退出码 0" "$rc" "0"
        chk "ggcp 成功路径（非交互）：stderr 一个字节都没有" \
            "$(wc -c < "$T/e.$SHELL_NAME" | tr -d ' ')" "0"
        chk "ggcp 成功路径（非交互）：stdout 只有总述 + 表（5 行）" \
            "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "5"

        # 后台作业前后的 shell 选项：这个 shell 原本 monitor=off，跑完不许变成 on
        # （老写法里若有人无条件 `set -m` / `setopt monitor`，这条会红）
        ggcp_reset
        erun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1 2 >/dev/null
            $MEASURE_MON
            echo \"MON=\$MON\""
        chk "ggcp 跑完：非交互 shell 的 monitor 还是 off（没被打开）" \
            "$(printf '%s\n' "$out" | sed -n 's/^MON=//p')" "off"

        # ---- 真 PTY：交互式 shell 里 ggcp 只许有表格，不许有 job 控制噪声 ----
        # script(1) 给一个真 PTY + 交互式 shell（monitor=on），这正是用户看到
        # `[1] 12345` / `[1]+ Done ...` 的场景。⚠️ bash 必须用
        # `-ic "$(cat body)"`（当命令敲）才复现得出来；`-ic 'source body'`
        # 实测不打启动提示，拿它测等于没测。zsh 两条路都会打。
        if command -v script >/dev/null 2>&1; then
            # 起一个真 PTY 跑 $1（片段文件），transcript 落到 $2；pty_rc = 那个交互 shell
            # 的退出码（script -e 会把它带回来），pty_out = 去掉 \r 后的 transcript。
            #
            # ⚠️ `</dev/null` 不能省：不给 stdin 时 script 会去读**调用方**的输入再喂进
            #    伪终端，那会在 shell 里变成"命令"。以前能绿只是因为调用方恰好没输入。
            # ⚠️ 也不要写成 `script … | tr`：那样 `$?` 是 tr 的，shell 自己的退出码就丢了
            #    （2026-10-23 那 7 条红时它其实非 0，但测试没看它）。
            pty_run () {
                if script -qec "$SHELL_BIN $SHELL_RC_FLAG -i -c \"\$(cat '$1')\"" \
                        /dev/null > "$2" 2>&1 < /dev/null; then
                    pty_rc=0
                else
                    pty_rc=$?
                fi
                pty_out=$(tr -d '\r' < "$2")
            }
            # 万一 pty 里的 shell 没跑到 RC= 那行（stdin 被灌了东西、脚本被终止、
            # script 自己起不来……），把现场直接打出来 —— 否则日志里只剩
            # "[MON_BEFORE=on]"，看的人得从头猜。
            pty_diag () {   # $1 = 说明；$2 = ggcp 的 stderr 文件
                case $(printf '%s\n' "$pty_out") in
                    *RC=*) return 0 ;;
                esac
                echo "  ---- PTY 诊断（$1，交互 shell 退出码 $pty_rc）----"
                printf '  pty_out 末尾：%s\n' "$(printf '%s\n' "$pty_out" | tail -3 | tr '\n' ' ')"
                printf '  ggcp stderr（%s 字节）：%s\n' \
                    "$(wc -c < "$2" | tr -d ' ')" \
                    "$(head -c 400 "$2" | tr '\n' ' ')"
            }
            # (a) monitor 原本 on：跑完必须还是 on；stderr 0 字节；终端只有表
            ggcp_reset
            cat > "$T/ggcp-pty.$SHELL_NAME" <<EOF
WTOOL_PROJECT_DIR='$here/..'
. "\$WTOOL_PROJECT_DIR/env.$SHELL_NAME"
. "$GGCP_ROOT/stub.sh"
cd "$GGCP_WORK"
$MEASURE_MON
echo "MON_BEFORE=\$MON"
ggcp -y 101 102 103 104 2> "$T/ggcp-pty.err.$SHELL_NAME"
echo "RC=\$?"
$MEASURE_MON
echo "MON_AFTER=\$MON"
EOF
            pty_run "$T/ggcp-pty.$SHELL_NAME" "$T/ggcp-pty.out.$SHELL_NAME"
            pty_diag "monitor 原本 on" "$T/ggcp-pty.err.$SHELL_NAME"
            chk "真 PTY（monitor 原本 on）ggcp 四笔：退出码 0" \
                "$(printf '%s\n' "$pty_out" | sed -n 's/^RC=//p' | tail -1)" "0"
            chk "真 PTY（monitor 原本 on）：交互 shell 自己干净退出（0）" "$pty_rc" "0"
            chk "真 PTY（monitor 原本 on）：跑前是 on" \
                "$(printf '%s\n' "$pty_out" | sed -n 's/^MON_BEFORE=//p' | tail -1)" "on"
            chk "真 PTY（monitor 原本 on）：跑完还是 on（没动用户的作业控制）" \
                "$(printf '%s\n' "$pty_out" | sed -n 's/^MON_AFTER=//p' | tail -1)" "on"
            chk "真 PTY（monitor 原本 on）：ggcp 的 stderr 是 0 字节" \
                "$(wc -c < "$T/ggcp-pty.err.$SHELL_NAME" | tr -d ' ')" "0"
            pty_noise=$(printf '%s\n' "$pty_out" \
                | grep -E '^\[[0-9]+\]|no job control|cannot set terminal process group|SIGHUPed' || true)
            chk "真 PTY（monitor 原本 on）：终端里没有任何 job 控制提示" "$pty_noise" ""
            case $pty_out in
                *项目名*结果说明*platform/mylib*成功*platform/other*成功*)
                    ok "真 PTY（monitor 原本 on）：表格照常打出来（两个仓库都成功）" ;;
                *) bad "真 PTY（monitor 原本 on）里表格不对：[$pty_out]" ;;
            esac

            # (b) monitor 原本 off：跑完必须还是 off（别"恢复"成 on）
            ggcp_reset
            cat > "$T/ggcp-pty2.$SHELL_NAME" <<EOF
WTOOL_PROJECT_DIR='$here/..'
. "\$WTOOL_PROJECT_DIR/env.$SHELL_NAME"
. "$GGCP_ROOT/stub.sh"
cd "$GGCP_WORK"
$MON_OFF
$MEASURE_MON
echo "MON_BEFORE=\$MON"
ggcp -y 101 102 103 104 > /dev/null 2> "$T/ggcp-pty2.err.$SHELL_NAME"
echo "RC=\$?"
$MEASURE_MON
echo "MON_AFTER=\$MON"
EOF
            pty_run "$T/ggcp-pty2.$SHELL_NAME" "$T/ggcp-pty2.out.$SHELL_NAME"
            pty_diag "monitor 原本 off" "$T/ggcp-pty2.err.$SHELL_NAME"
            chk "真 PTY（monitor 原本 off）ggcp 四笔：退出码 0" \
                "$(printf '%s\n' "$pty_out" | sed -n 's/^RC=//p' | tail -1)" "0"
            chk "真 PTY（monitor 原本 off）：交互 shell 自己干净退出（0）" "$pty_rc" "0"
            chk "真 PTY（monitor 原本 off）：跑前是 off" \
                "$(printf '%s\n' "$pty_out" | sed -n 's/^MON_BEFORE=//p' | tail -1)" "off"
            chk "真 PTY（monitor 原本 off）：跑完还是 off（没被恢复成 on）" \
                "$(printf '%s\n' "$pty_out" | sed -n 's/^MON_AFTER=//p' | tail -1)" "off"
            chk "真 PTY（monitor 原本 off）：stderr 是 0 字节" \
                "$(wc -c < "$T/ggcp-pty2.err.$SHELL_NAME" | tr -d ' ')" "0"
            ggcp_reset
        else
            echo "  （没装 script(1)，真 PTY 那一组（颜色/表格/作业控制噪声/退出码）跳过 ——"
            echo "    它们只能在有 pty 的机器上跑，没有就大声说，不静默跳过）"
        fi

        # ---- 文件冲突：逐文件写出来，然后 --abort 收干净 ----
        ggcp_reset
        printf 'local\n' > "$GGCP_WORK/ps1.txt"
        git -C "$GGCP_WORK" add -A
        git -C "$GGCP_WORK" commit -qm local
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1"
        chk "文件冲突：退出码 1" "$rc" "1"
        chk "文件冲突：总述失败 1" \
            "$(printf '%s\n' "$out" | sed -n 1p)" "1 个仓库 / 1 笔提交 / 成功 0 / 失败 1"
        case $out in
            *"ps1.txt 文件冲突"*) ok "文件冲突：结果说明列出具体文件 ps1.txt" ;;
            *) bad "文件冲突的结果说明没列文件：[$out]" ;;
        esac
        chk "文件冲突后工作树干净" "$(git -C "$GGCP_WORK" status --porcelain)" ""
        chk "文件冲突后没有 CHERRY_PICK_HEAD" \
            "$(git -C "$GGCP_WORK" rev-parse -q --verify CHERRY_PICK_HEAD 2>/dev/null || true)" ""
        chk "文件冲突后本地已有的提交保留" \
            "$(git -C "$GGCP_WORK" log -1 --format=%s)" "local"
        ggcp_reset

        # ---- 同仓库一笔失败不影响下一笔：失败的不回滚、成功的保留 ----
        ggcp_reset
        printf 'local\n' > "$GGCP_WORK/ps1.txt"
        git -C "$GGCP_WORK" add -A
        git -C "$GGCP_WORK" commit -qm local
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1 2"
        chk "同仓库一败一成：退出码 1" "$rc" "1"
        chk "同仓库一败一成：总述 成功 1 / 失败 1" \
            "$(printf '%s\n' "$out" | sed -n 1p)" "1 个仓库 / 2 笔提交 / 成功 1 / 失败 1"
        chk "同仓库一败一成：冲突行列出 ps1.txt" \
            "$(printf '%s\n' "$out" | grep -c 'ps1.txt 文件冲突')" "1"
        chk "同仓库一败一成：后一笔成功行还在" \
            "$(printf '%s\n' "$out" | grep -c '^platform/mylib.*成功')" "1"
        chk "同仓库一败一成：成功的那笔真进来了" \
            "$(git -C "$GGCP_WORK" log -1 --format=%s)" "lab: change two"
        chk "同仓库一败一成：工作树干净" "$(git -C "$GGCP_WORK" status --porcelain)" ""
        ggcp_reset

        # 下游工具坏了/查不到，别把 stderr 混进表格
        srun "printf 'n\n' | {
                source $GGCP_ROOT/stub.sh
                cd $GGCP_WORK
                ggcp I9999999999999999999999999999999999999999
            }"
        chk "Change-Id 查不到：退出码 1" "$rc" "1"
        case $out in
            *"在 gerrit 上查不到"*) ok "Change-Id 查不到时报得清楚" ;;
            *) bad "Change-Id 查不到的报错不清楚：[$out]" ;;
        esac
        chk "Change-Id 查不到：也打结果表" \
            "$(printf '%s\n' "$out" | grep '个仓库 / .* 笔提交' | tail -1)" \
            "0 个仓库 / 1 笔提交 / 成功 0 / 失败 1"
        case $out in
            *"查询失败：Change-Id 展开失败"*) ok "Change-Id 查不到：结果表里写明了" ;;
            *) bad "Change-Id 查不到没进结果表：[$out]" ;;
        esac
    fi

    # ---- cdd <gerrit 编号>：坍缩成 cdd <仓库名> ----
    if [ "$GGCP_OK" != 1 ]; then
        echo "  （没装 git，cdd <编号> 这几条跳过）"
    else
        echo "== env.$SHELL_NAME：cdd -N（gerrit 编号 -> 项目目录）=="

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd -9001 >/dev/null 2>&1 && pwd"
        chk "cdd -9001：跳到 gerrit 说的那个仓库" "$out" "$GGCP_WORK"

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd 9001 >/dev/null 2>&1 && pwd"
        chk "cdd 9001（老写法）：也跳到那个仓库" "$out" "$GGCP_WORK"

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd -9002"
        chk "cdd -9002（清单里有、目录没检出）：退出码 1" "$rc" "1"
        case $out in
            *"cdd: change 9002 属于项目 gone/project，但本地还没检出（清单路径 gone/project）"*)
                ok "cdd -9002：说清属于哪个项目、但本地没检出" ;;
            *) bad "cdd -9002 的报错不对：[$out]" ;;
        esac
        case $out in
            *"先 repo sync gone/project"*) ok "cdd -9002：给了 repo sync 的下一步" ;;
            *) bad "cdd -9002 没给下一步：[$out]" ;;
        esac

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd -9003"
        chk "cdd -9003（清单里没这个项目）：退出码 1" "$rc" "1"
        case $out in
            *"cdd: change 9003 属于项目 nope/nope，但当前工作区的清单里没有它"*)
                ok "cdd -9003：说清项目、也说了清单里没有" ;;
            *) bad "cdd -9003 的报错不对：[$out]" ;;
        esac

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd -9999"
        chk "cdd -9999（gerrit 查不到）：退出码 1" "$rc" "1"
        case $out in
            *"cdd:"*"9999"*) ok "cdd -9999：报错里点了编号" ;;
            *) bad "cdd -9999 的报错不清楚：[$out]" ;;
        esac

        # 原有三条路不许被抢：现存目录 / 项目名 / 现存文件
        mkdir -p "$GGCP_ROOT/12345"
        srun "cd $GGCP_ROOT
            source $GGCP_ROOT/stub.sh
            cdd 12345 >/dev/null 2>&1 && pwd"
        chk "cdd <纯数字目录>：还是先按现存目录跳（不抢）" "$out" "$GGCP_ROOT/12345"
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd device/emui/generic_a15 >/dev/null 2>&1 && pwd"
        chk "cdd <项目名>：还是走清单那套（不抢）" "$out" "$GGCP_WS/device/emui/generic_a15"
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd other >/dev/null 2>&1 && pwd"
        chk "cdd <第二个项目名>：也能跳" "$out" "$GGCP_OTHER"
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd base.txt >/dev/null 2>&1 && pwd"
        chk "cdd <现存文件>：跳到它所在目录（不抢）" "$out" "$GGCP_WORK"
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd nope/nope"
        chk "cdd <不存在的名字>：还是退出码 1" "$rc" "1"
        case $out in
            *"清单里没有"*) ok "cdd <不存在的名字>：报错没变" ;;
            *) bad "cdd <不存在的名字> 报错变了：[$out]" ;;
        esac
    fi

    # ---- ggco：临时裸仓里 fetch -> checkout（同一张表跑两个 shell）----
    if [ "$GGCO_OK" != 1 ]; then
        echo "  （没装 git，ggco 这几条跳过）"
    else
        echo "== env.$SHELL_NAME：ggco（临时裸仓，不联网）=="

        srun "cd $GGCO_WORK
            git checkout -q HEAD -- . 2>/dev/null
            git checkout -q main 2>/dev/null
            git branch -qD feature 2>/dev/null
            ggco feature"
        chk "ggco 新分支：退出码 0" "$rc" "0"
        chk "ggco 新分支：HEAD 就是远端那条 ref" \
            "$(git -C "$GGCO_WORK" rev-parse HEAD)" "$GGCO_FEATURE_SHA"
        chk "ggco 新分支：本地建了跟踪分支" \
            "$(git -C "$GGCO_WORK" rev-parse --abbrev-ref HEAD)" "feature"
        case $out in
            *"现在在 feature"*) ok "ggco 打印落在哪条分支上" ;;
            *) bad "ggco 没说落在哪：[$out]" ;;
        esac

        srun "cd $GGCO_WORK
            git checkout -q HEAD -- . 2>/dev/null
            git checkout -q main 2>/dev/null
            git branch -qD old 2>/dev/null
            git branch old main
            ggco old"
        chk "ggco 本地同名分支落后：退出码 1" "$rc" "1"
        case $out in
            *"不是刚 fetch"*) ok "ggco 明说本地分支和刚 fetch 的不一致" ;;
            *) bad "ggco 没点出本地分支没跟上：[$out]" ;;
        esac
        chk "ggco 不 reset 本地分支" \
            "$(git -C "$GGCO_WORK" rev-parse old)" "$(git -C "$GGCO_WORK" rev-parse main)"

        srun "cd $GGCO_WORK
            git checkout -q HEAD -- . 2>/dev/null
            ggco no-such-branch"
        chk "ggco 远端没有这个 ref：退出码 1" "$rc" "1"
        case $out in
            *"远端没有这个 ref"*) ok "ggco 说清是远端没有这个 ref" ;;
            *) bad "ggco 的报错不清楚：[$out]" ;;
        esac

        srun "cd $GGCO_WORK
            git checkout -q HEAD -- . 2>/dev/null
            git checkout -q main 2>/dev/null
            printf 'x\n' >> README.md
            git add -A
            ggco feature"
        chk "ggco 工作树有本地改动：退出码 1" "$rc" "1"
        case $out in
            *"工作树有本地改动"*) ok "ggco 提示先 stash / commit" ;;
            *) bad "ggco 没说工作树脏：[$out]" ;;
        esac
        # 收拾干净，别影响下一个 shell 的那一遍
        git -C "$GGCO_WORK" checkout -q HEAD -- . 2>/dev/null || true

        srun 'ggco'
        chk "ggco 不带参数：退出码 2" "$rc" "2"
        case $out in
            *"Usage: ggco"*) ok "ggco 打出了用法" ;;
            *) bad "ggco 没打用法：[$out]" ;;
        esac

        srun "cd $T
            ggco main"
        chk "ggco 不在 git 仓库里：退出码 1" "$rc" "1"
        case $out in
            *"不是 git 仓库"*) ok "ggco 说清不在 git 仓库里" ;;
            *) bad "ggco 的报错不清楚：[$out]" ;;
        esac
    fi

    # ---- ggco 冻结：用户明确要求"ggco 一个字都不许变" ----
    # 除了上面的行为用例，这里再钉一次**逐字节**：ggco 的函数体不许动。
    # 真想改 ggco -> 先跟用户确认，改完把这两个数一起更新（它们是"当时的原文"）。
    #
    #   zsh 版 cksum = 2879919872 2380
    #   bash 版 cksum = 3925425235 2531
    ggco_sum () {
        sed -n '/^ggco ()/,/^}/p' "$here/../env.$1" | cksum
    }
    case "$SHELL_NAME" in
        zsh)  _want="2879919872 2380" ;;
        bash) _want="3925425235 2531" ;;
    esac
    chk "ggco 一字未改（env.$SHELL_NAME，cksum）" "$(ggco_sum "$SHELL_NAME")" "$_want"

    # ---- gpun：把 gb 给出的那条 git pull --unshallow 真跑掉（本地裸仓，不联网）----
    if [ "$GPUN_OK" != 1 ]; then
        echo "  （没装 git，gpun 这几条跳过）"
    else
        echo "== env.$SHELL_NAME：gpun（临时裸仓 + 桩 gb，不联网）=="

        # (1) 不带参数：跑 --unshallow，shallow 仓被补全
        gpun_shallow_reset
        srun "cd $GPUN_SHALLOW
            $GPUN_GB_STUB
            gpun"
        chk "gpun 正常：退出码 0" "$rc" "0"
        case $out in
            *"gpun: 执行 git pull origin main --unshallow"*) ok "gpun 回显了要跑的那条命令" ;;
            *) bad "gpun 没回显要跑的命令：[$out]" ;;
        esac
        case $out in
            *"remote: origin"*|*"git push origin"*|*"git fetch origin"*)
                bad "gpun 把 gb 的整段输出刷出来了：[$out]" ;;
            *) ok "gpun 没把 gb 的整段输出刷出来" ;;
        esac
        chk "gpun 真的跑成了（不再是 shallow 仓）" \
            "$(git -C "$GPUN_SHALLOW" rev-parse --is-shallow-repository)" "false"
        chk "gpun 补齐了全部 $GPUN_TOTAL 个提交" \
            "$(git -C "$GPUN_SHALLOW" rev-list --count HEAD)" "$GPUN_TOTAL"

        # (2) gpun -30：--unshallow 换成 --depth=30，仓仍是 shallow、只多到 30 个提交
        gpun_shallow_reset
        srun "cd $GPUN_SHALLOW
            $GPUN_GB_STUB
            gpun -30"
        chk "gpun -30：退出码 0" "$rc" "0"
        case $out in
            *"gpun: 执行 git pull origin main --depth=30"*) ok "gpun -30 换成了 --depth=30" ;;
            *) bad "gpun -30 换出来的命令不对：[$out]" ;;
        esac
        chk "gpun -30：仓库仍然是 shallow（没被 --unshallow 补全）" \
            "$(git -C "$GPUN_SHALLOW" rev-parse --is-shallow-repository)" "true"
        chk "gpun -30：深度正好是 30" \
            "$(git -C "$GPUN_SHALLOW" rev-list --count HEAD)" "30"

        # (3) --depth=30 这种写法等价
        gpun_shallow_reset
        srun "cd $GPUN_SHALLOW
            $GPUN_GB_STUB
            gpun --depth=30"
        chk "gpun --depth=30：退出码 0" "$rc" "0"
        case $out in
            *"gpun: 执行 git pull origin main --depth=30"*) ok "gpun --depth=30 和 -30 等价" ;;
            *) bad "gpun --depth=30 换出来的命令不对：[$out]" ;;
        esac
        chk "gpun --depth=30：深度正好是 30" \
            "$(git -C "$GPUN_SHALLOW" rev-list --count HEAD)" "30"

        # (4) gb 没给出那条命令：明确报错、非 0，且**不跑任何 pull**
        gpun_shallow_reset
        srun "cd $GPUN_SHALLOW
            gb () { printf '%s\n' 'git push origin HEAD:main' 'remote: origin' 'branch: main'; }
            gpun"
        chk "gpun 挑不到那条命令：退出码 1" "$rc" "1"
        case $out in
            *"gb 没给出 'git pull <remote> <branch> --unshallow' 那条命令"*)
                ok "gpun 明说 gb 没给出那条命令" ;;
            *) bad "gpun 的报错不清楚：[$out]" ;;
        esac
        chk "gpun 挑不到命令时什么都不跑" \
            "$(git -C "$GPUN_SHALLOW" rev-list --count HEAD)" "1"

        # (5) gb 自己失败（不在项目目录里）：不把失败当成功
        srun "gb () { printf 'gb: not in project dir!!!\n' >&2; return 1; }
            gpun"
        chk "gpun 在 gb 失败时：退出码 1" "$rc" "1"
        case $out in
            *"拿不到 gb 的输出"*) ok "gpun 说清是 gb 没给出输出" ;;
            *) bad "gpun 的报错不清楚：[$out]" ;;
        esac

        # (6) 完整仓（不是 shallow）：gb 照样给那条命令，由 git 自己报错，gpun 如实传出来
        srun "cd $GPUN_SEED
            $GPUN_GB_STUB
            gpun"
        if [ "$rc" -ne 0 ]; then
            ok "完整仓跑 gpun：git 报错、退出码非 0（$rc）"
        else
            bad "完整仓跑 gpun 应该失败，却退出码 0"
        fi
        case $out in
            *"gpun: 上面这条 pull 失败（退出码"*) ok "gpun 说明了这条 pull 失败" ;;
            *) bad "gpun 没说 pull 失败：[$out]" ;;
        esac
        chk "完整仓不会被 gpun 弄坏" \
            "$(git -C "$GPUN_SEED" rev-list --count HEAD)" "$GPUN_TOTAL"

        # (7) 用法错误：一律退出码 2 + 打出用法
        for _case in 'abc' '-0' '--depth=' '--depth=x' '-30 -40'; do
            srun "gpun $_case"
            chk "gpun $_case：退出码 2" "$rc" "2"
            case $out in
                *"Usage: gpun"*) ok "gpun $_case：打出了用法" ;;
                *) bad "gpun $_case 没打用法：[$out]" ;;
            esac
        done

        # (8) 万一 gb 给了多条（正常不会）：取第一条，不把两条拼一起跑
        gpun_shallow_reset
        srun "cd $GPUN_SHALLOW
            gb () { printf '%s\n' 'git pull origin main --unshallow' 'git pull backup main --unshallow'; }
            gpun"
        chk "gb 给多条时：退出码 0（只跑第一条）" "$rc" "0"
        case $out in
            *"gpun: 执行 git pull origin main --unshallow"*)
                ok "gb 给多条时取第一条" ;;
            *) bad "gb 给多条时的行为不对：[$out]" ;;
        esac
        chk "gb 给多条时：真的只补了这一个仓" \
            "$(git -C "$GPUN_SHALLOW" rev-list --count HEAD)" "$GPUN_TOTAL"
    fi
done

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
