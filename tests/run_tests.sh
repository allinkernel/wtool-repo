#!/bin/sh
# run_tests.sh —— tools/repo 的测试
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
done

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
