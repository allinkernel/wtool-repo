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
{"project":"platform/frameworks/base","branch":"main","number":1234,"subject":"demo change","url":"http://gerrit.example.com/c/platform/frameworks/base/+/1234","status":"NEW","currentPatchSet":{"number":2,"revision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","ref":"refs/changes/34/1234/2","approvals":[{"type":"Code-Review","value":"+1","by":{"username":"someone"}}]},"patchSets":[{"number":1,"revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ref":"refs/changes/34/1234/1"},{"number":2,"revision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","ref":"refs/changes/34/1234/2","approvals":[{"type":"Code-Review","value":"+1","by":{"username":"someone"}}]}]}
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
# 同一个用例表跑两个 shell：env.zsh 和 env.bash 必须行为一致
# （命令名、退出码、报错文字都一样；只有实现语法不同）
for SHELL_NAME in zsh bash; do
    if ! command -v "$SHELL_NAME" >/dev/null 2>&1; then
        echo "== env.$SHELL_NAME：跳过（没装 $SHELL_NAME）=="
        continue
    fi
    echo "== env.$SHELL_NAME：cnp/cdd 的用法报错 =="
    mkdir -p "$WS/kernel/common/.git" "$WS/device/emui/generic_a15/.git"

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
