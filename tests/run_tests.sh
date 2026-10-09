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
        # change 1 patchset 1：加 ps1.txt
        printf 'ps1\n' > ps1.txt
        git add -A
        git commit -qm 'lab: change one (ps1)'
        PS1=$(git rev-parse HEAD)
        # change 1 patchset 2：同一个 change 的新版本（ps1.txt 一样 + 多一个 ps2.txt）
        git reset -q --hard "$BASE"
        printf 'ps1\n' > ps1.txt
        printf 'ps2\n' > ps2.txt
        git add -A
        git commit -qm 'lab: change one (ps2)'
        PS2=$(git rev-parse HEAD)
        # change 2：另一个提交（加 two.txt）
        git reset -q --hard "$BASE"
        printf 'two\n' > two.txt
        git add -A
        git commit -qm 'lab: change two'
        TWO=$(git rev-parse HEAD)
        # 把三个"patchset 提交"推到"gerrit 服务器"（本地裸仓）上
        git push -q origin "$BASE":refs/heads/main
        git push -q origin \
            "$PS1":refs/changes/01/1/1 \
            "$PS2":refs/changes/01/1/2 \
            "$TWO":refs/changes/02/2/1
        printf '%s %s %s %s\n' "$BASE" "$PS1" "$PS2" "$TWO" > "$GGCP_ROOT/shas"
    )
    read -r GGCP_BASE_SHA GGCP_PS1_SHA GGCP_PS2_SHA GGCP_TWO_SHA < "$GGCP_ROOT/shas"

    # 工作区：清单 + client.conf + 项目目录（真 git 仓，remote 叫 polygerrit）
    cat > "$GGCP_WS/.repo/manifests/default.xml" <<'X'
<?xml version="1.0"?>
<manifest>
    <remote name="polygerrit" fetch="ssh://t@127.0.0.1:29418/" />
    <default revision="main" remote="polygerrit" />
    <project path="mylib" name="platform/mylib" />
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

    # 桩 _gerrit_ssh 喂的 JSON（最后一行是 gerrit 固定的 stats）
    _stats='{"type":"stats","rowCount":1,"runTimeMilliseconds":1,"moreChanges":false}'
    # change 1 有**两个 patchset**（真的 gerrit 也是这样：`change:1` 一次回全部 patchset）
    cat > "$GGCP_JSON/change-1.json" <<X
{"number":1,"project":"platform/mylib","branch":"main","subject":"lab: change one","url":"http://g.example.com/c/platform/mylib/+/1","currentPatchSet":{"number":1,"revision":"$GGCP_PS1_SHA","ref":"refs/changes/01/1/1"},"patchSets":[{"number":1,"revision":"$GGCP_PS1_SHA","ref":"refs/changes/01/1/1"},{"number":2,"revision":"$GGCP_PS2_SHA","ref":"refs/changes/01/1/2"}]}
$_stats
X
    cat > "$GGCP_JSON/change-2.json" <<X
{"number":2,"project":"platform/mylib","branch":"main","subject":"lab: change two","url":"http://g.example.com/c/platform/mylib/+/2","currentPatchSet":{"number":1,"revision":"$GGCP_TWO_SHA","ref":"refs/changes/02/2/1"},"patchSets":[{"number":1,"revision":"$GGCP_TWO_SHA","ref":"refs/changes/02/2/1"}]}
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
        I1111111111111111111111111111111111111111) cat "$GGCP_JSON/change-1.json" ;;
        9001|9002|9003) cat "$GGCP_JSON/cdd-\${c#change:}.json" ;;
        *)    cat "$GGCP_JSON/empty.json" ;;
    esac
}
X
    GGCP_OK=1
fi

# 每条用例都从同一个起点开始：detached 回到 base，并且清掉上一次的现场
ggcp_reset () {
    git -C "$GGCP_WORK" cherry-pick --abort >/dev/null 2>&1 || true
    git -C "$GGCP_WORK" checkout -q -f "$GGCP_BASE_SHA" 2>/dev/null || true
    git -C "$GGCP_WORK" clean -qfd
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
            out=$(script -qec "env -u NO_COLOR $SHELL_NAME $T/p.script" /dev/null 2>&1 | tr -d '\r') || rc=$?
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

        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1"
        chk "ggcp 1：退出码 0" "$rc" "0"
        chk "ggcp 1：正常路径只打三行（正在下载/正在打补丁/打补丁成功）" \
            "$out" "正在下载1
正在打补丁1
打补丁成功"
        chk "ggcp 1：真的 cherry-pick 上来了" \
            "$(git -C "$GGCP_WORK" log --oneline -1 --format=%s)" "lab: change one (ps1)"
        chk "ggcp 1：新文件在" "$(cat "$GGCP_WORK/ps1.txt" 2>/dev/null)" "ps1"

        # 同一个命令放到真 pty 里跑：成功那行必须**带 ANSI 色码**（上面管道里那条是纯文本）
        if command -v script >/dev/null 2>&1; then
            ggcp_reset
            pty_eval "source $GGCP_ROOT/stub.sh
                cd $GGCP_WORK
                ggcp 1"
            chk "真 pty 里 ggcp 1：退出码 0" "$rc" "0"
            case $out in
                *"$ESC[32m打补丁成功$ESC[0m"*) ok "真 pty 里 ggcp 的成功行带绿色码" ;;
                *) bad "真 pty 里 ggcp 没上色：[$out]" ;;
            esac
            ggcp_reset
        fi

        # 多编号 + 链接 + 混用：一次打三个（ps1 那个已经打过了，所以再来一次会红）
        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1 2"
        chk "ggcp 1 2（空格分隔）：退出码 0" "$rc" "0"
        case $out in
            *"正在下载1
正在打补丁1
打补丁成功
正在下载2
正在打补丁2
打补丁成功"*) ok "ggcp 1 2：两段各三行，顺序对" ;;
            *) bad "ggcp 1 2 的输出不对：[$out]" ;;
        esac
        chk "ggcp 1 2：两个补丁都进来了" \
            "$(git -C "$GGCP_WORK" log --oneline --format=%s | head -2 | tr '\n' '/')" \
            "lab: change two/lab: change one (ps1)/"

        # 打第二遍：同一份补丁再来一次 -> 空提交 -> 红
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 1"
        chk "重复打同一个补丁：退出码 1" "$rc" "1"
        chk "重复打：有且只有一行红的「打补丁失败」" \
            "$(printf '%s\n' "$out" | grep -c '^打补丁失败$')" "1"
        ggcp_reset

        # 链接：老式 #/c/1234 和新式 /c/proj/+/1234
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 'https://g.example.com/#/c/2'"
        chk "ggcp <老式链接>：退出码 0" "$rc" "0"
        chk "ggcp <老式链接>：打的是 2 号" "$out" "正在下载2
正在打补丁2
打补丁成功"
        ggcp_reset
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 'https://g.example.com/c/platform/mylib/+/1/1'"
        chk "ggcp <新式链接>：退出码 0" "$rc" "0"
        case $out in
            *"正在下载1"*) ok "ggcp <新式链接>：编号从链接里取" ;;
            *) bad "ggcp <新式链接> 没取到编号：[$out]" ;;
        esac
        ggcp_reset

        # 查不到 / 项目不在工作区：都要红 + 非 0
        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            ggcp 9"
        chk "change 查不到：退出码 1" "$rc" "1"
        case $out in
            *"打补丁失败"*) ok "change 查不到也打红行" ;;
            *) bad "change 查不到没打红行：[$out]" ;;
        esac

        # Change-Id：表格 + 逐个询问（-y / -n / 交互三种）
        ggcp_reset
        srun "printf 'y\nn\n' | {
                source $GGCP_ROOT/stub.sh
                cd $GGCP_WORK
                ggcp I1111111111111111111111111111111111111111
            }"
        chk "Change-Id 逐个问：退出码 0" "$rc" "0"
        case $out in
            *"编号  patchset  仓库"*) ok "Change-Id：打了表（编号/patchset/仓库/路径/提交链接）" ;;
            *) bad "Change-Id 没打表：[$out]" ;;
        esac
        chk "Change-Id：表里两个 patchset 各一行（看提交链接列）" \
            "$(printf '%s\n' "$out" | grep -c 'g.example.com/c/platform/mylib/+/1/')" "2"
        case $out in
            *"路径"*"mylib"*) ok "Change-Id：表里有本地路径" ;;
            *) bad "Change-Id 表里没路径：[$out]" ;;
        esac
        chk "Change-Id：逐个问了两次（y/n 各一次）" \
            "$(printf '%s\n' "$out" | grep -o '打补丁 1 (patchset' | wc -l | tr -d ' ')" "2"
        case $out in
            *"给仓库 platform/mylib 打补丁 1 (patchset 1) 吗？"*) ok "询问里点明了仓库/编号/patchset" ;;
            *) bad "询问文案看不明白：[$out]" ;;
        esac
        chk "Change-Id：答 y 的那个真打了（答 n 的没打）" \
            "$(git -C "$GGCP_WORK" log --oneline --format=%s | head -1)" "lab: change one (ps1)"
        case $out in
            *"打补丁成功"*) ok "Change-Id：答应的那条出绿行" ;;
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
        chk "ggcp -y：退出码 0（两个 patchset 都打）" "$rc" "0"
        chk "ggcp -y：不再问、两行绿" \
            "$(printf '%s\n' "$out" | grep -c '^打补丁成功$')" "2"
        chk "ggcp -y：两个 patchset 的文件都在" \
            "$(cat "$GGCP_WORK/ps1.txt" "$GGCP_WORK/ps2.txt" 2>/dev/null | tr '\n' '/')" "ps1/ps2/"
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
    fi

    # ---- cdd <gerrit 编号>：坍缩成 cdd <仓库名> ----
    if [ "$GGCP_OK" != 1 ]; then
        echo "  （没装 git，cdd <编号> 这几条跳过）"
    else
        echo "== env.$SHELL_NAME：cdd <gerrit 编号> =="

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd 9001 >/dev/null 2>&1 && pwd"
        chk "cdd 9001：跳到 gerrit 说的那个仓库" "$out" "$GGCP_WORK"

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd 9002"
        chk "cdd 9002（仓库不在工作区）：退出码 1" "$rc" "1"
        chk "cdd 9002：打的正是那句话" \
            "$out" "cdd: 9002 对应的仓库名 gone/project 在当前 repo 工作区不存在"

        srun "source $GGCP_ROOT/stub.sh
            cd $GGCP_WORK
            cdd 9003"
        chk "cdd 9003（清单里没这个项目）：退出码 1" "$rc" "1"
        case $out in
            *"cdd: 9003 对应的仓库名 nope/nope 在当前 repo 工作区不存在"*)
                ok "cdd 9003：同一句话（外加一句提示）" ;;
            *) bad "cdd 9003 的报错不对：[$out]" ;;
        esac

        # 原有两条路不许被抢：现存目录 / 项目名，优先级都在"数字去 gerrit"前面
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
