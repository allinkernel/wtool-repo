# 迁移自 mytool/android/wsw_env.sh（原 wsw-androidrc）。纯 zsh，由 ~/.zshrc 里的 wtool 块 source。
#
# WTOOL_PROJECT_DIR 由 wtool 块导出 = $HOME/.wtool/links/tools/repo，指向本项目根。
# 单独 source（不经 wtool 块）时给出默认值，保证可用。
[[ -n "$WTOOL_PROJECT_DIR" ]] || WTOOL_PROJECT_DIR="$HOME/.wtool/links/tools/repo"
export WTOOL_REPO_TOOL="$WTOOL_PROJECT_DIR/my_repo.py"
# 解析 gerrit query JSON 的小工具（ggcp / gchk / gq 用）
export WTOOL_GERRIT_TOOL="$WTOOL_PROJECT_DIR/gerrit_query.py"

# ---------------------------------------------------------------------------
# 定位：向上找 .repo / .git
# ---------------------------------------------------------------------------
# _up_to_have_dir 原本定义在 mytool/zsh/wsw-zshrc/wsw.zsh 里；
# 本项目迁移为独立项目后需要自包含，故内联一份（仅 zsh，用了 ${cur_dir:h}）。
_up_to_have_dir ()
{
    target_dir=$1
    cur_dir=${PWD}
    while [[ ! -e ${cur_dir}/${target_dir} ]]; do
        cur_dir=${cur_dir:h}
        [[ ${cur_dir} == / ]] && return 1
    done
    echo ${cur_dir}
    return 0
}

cs ()
{
    local dir
    dir=$(_up_to_have_dir .repo)
    if [[ $? -eq 0 ]]; then
        cd ${dir}
        return 0
    else
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    fi
}

css ()
{
    local dir
    dir=$(_up_to_have_dir .repo)
    if [[ $? -eq 0 ]]; then
        echo ${dir}
        return 0
    else
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    fi
}

ct ()
{
    local dir
    dir=$(_up_to_have_dir .git)
    if [[ $? -eq 0 ]]; then
        cd ${dir}
        return 0
    else
        echo "${funcstack[1]}: not in git dir!!!" >&2
        return 1
    fi
}

ctt ()
{
    local dir
    dir=$(_up_to_have_dir .git)
    if [[ $? -eq 0 ]]; then
        echo ${dir}
        return 0
    else
        echo "${funcstack[1]}: not in git dir!!!" >&2
        return 1
    fi
}

# cnp：报告"当前目录"在清单里的**相对路径**（老名字沿用，实际输出 path）。
# 它不接受参数 —— 以前多传了参数会被静默忽略，"我在公司敲了 cnp <路径> 没反应"
# 就是这么来的。现在明确报错并告诉你该用 cdd。
cnp ()
{
    if [[ $# -ne 0 ]]; then
        echo "cnp: 不接受参数（它报告当前目录属于哪个项目）" >&2
        echo "     cnp                -> 打印当前项目在清单里的路径" >&2
        echo "     cdd ${1}   -> 按路径/项目名跳转" >&2
        return 2
    fi
    local dir ctt_dir css_dir
    {
        ctt_dir=$(ctt) &&
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: 当前目录不在 repo 工作区的某个 git 仓库里（试试 cdd <项目名>）" >&2
        return 1
    }
    dir=${${ctt_dir}##${css_dir}/}
    {
        python3 $WTOOL_REPO_TOOL name_from_path ${dir} --root ${css_dir} &>/dev/null;
    } || {
        echo "${funcstack[1]}: 清单里没有 path='${dir}' 的项目" >&2
        return 1
    }
    echo ${dir}
    return 0
}

cnn() {
    if [[ $# -ne 0 ]]; then
        echo "cnn: 不接受参数（它打印当前项目的清单名字）" >&2
        return 2
    fi
    local cnp_dir css_dir
    {
        css_dir=$(css) &&
        cnp_dir=$(cnp)
    } || {
        echo "${funcstack[1]}: 当前目录不在 repo 工作区的某个 git 仓库里" >&2
        return 1
    }
    {
        python3 $WTOOL_REPO_TOOL name_from_path ${cnp_dir} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: 清单里没有 path='${cnp_dir}' 的项目" >&2
        return 1
    }
    return 0
}

# 1. 根据路径拿名字
repo_mfst_get_name_from_path() {
    local repo_path=$1
    local css_dir
    {
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    }
    {
        python3 $WTOOL_REPO_TOOL name_from_path ${repo_path} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: $WTOOL_REPO_TOOL: no project with path:'${repo_path}' in your manifests!!!" >&2
        return 1
    }
    return 0
}


# 2. 根据名字拿路径
repo_mfst_get_path_from_name() {
    local repo_name=$1
    local css_dir
    {
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    }
    {
        python3 $WTOOL_REPO_TOOL path_from_name ${repo_name} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: $WTOOL_REPO_TOOL: no project with name:'${repo_name}' in your manifests!!!" >&2
        return 1
    }
    return 0
}

# 3. 根据路径拿分支
repo_mfst_get_branch_from_path() {
    local repo_path=$1
    local css_dir
    {
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    }
    {
        python3 $WTOOL_REPO_TOOL branch_from_path ${repo_path} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: $WTOOL_REPO_TOOL: no project with path:'${repo_path}' in your manifests!!!" >&2
        return 1
    }
    return 0
}

# 4. 根据名字拿分支
repo_mfst_get_branch_from_name() {
    local repo_name=$1
    local css_dir
    {
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    }
    {
        python3 $WTOOL_REPO_TOOL branch_from_name ${repo_name} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: $WTOOL_REPO_TOOL: no project with name:'${repo_name}' in your manifests!!!" >&2
        return 1
    }
    return 0
}

# 5. 根据名字拿remote
repo_mfst_get_remote_from_name() {
    local repo_name=$1
    local css_dir
    {
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    }
    {
        python3 $WTOOL_REPO_TOOL remote_from_name ${repo_name} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: $WTOOL_REPO_TOOL: no project with name:'${repo_name}' in your manifests!!!" >&2
        return 1
    }
    return 0
}

# 6. 根据路径拿remote
repo_mfst_get_remote_from_path() {
    local repo_path=$1
    local css_dir
    {
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    }
    {
        python3 $WTOOL_REPO_TOOL remote_from_path ${repo_path} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: $WTOOL_REPO_TOOL: no project with path:'${repo_path}' in your manifests!!!" >&2
        return 1
    }
    return 0
}

# 7. 根据名字拿 clone URL（gerrit 场景常用）
repo_mfst_get_url_from_name() {
    local repo_name=$1
    local css_dir
    {
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: not in repo dir!!!" >&2
        return 1
    }
    {
        $WTOOL_REPO_TOOL url_from_name ${repo_name} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: $WTOOL_REPO_TOOL: no project with name:'${repo_name}' in your manifests!!!" >&2
        return 1
    }
    return 0
}

cnb ()
{
    local repo_path
    {
        repo_path=$(cnp)
    } || {
        echo "${funcstack[1]}: not in git dir!!!" >&2
        return 1
    }
    {
        echo $(repo_mfst_get_branch_from_path ${repo_path})
    } || {
        echo "${funcstack[1]}: param wrong !!!" >&2
    }
}

cnr ()
{
    local repo_path
    {
        repo_path=$(cnp)
    } || {
        echo "${funcstack[1]}: not in git dir!!!" >&2
        return 1
    }
    {
        echo $(repo_mfst_get_remote_from_path ${repo_path})
    } || {
        echo "${funcstack[1]}: param wrong !!!" >&2
    }
}

cm ()
{
    dir=$(_up_to_have_dir .repo)
    if [[ $? -eq 0 ]]; then
        cd ${dir}/.repo/manifests
        return 0
    fi
    echo "${funcstack[1]}: not in repo dir!!!" >&2
    return 1
}

cmm ()
{
    dir=$(_up_to_have_dir .repo)
    if [[ $? -eq 0 ]]; then
        echo ${dir}/.repo/manifests
        return 0
    fi
    echo "${funcstack[1]}: not in repo dir!!!" >&2
    return 1
}

# 内部：项目名/路径 -> 清单里的相对路径（失败返回 1，不打印）
_repo_project_relpath () {
    local target=$1 css_dir repo_path
    css_dir=$(css 2>/dev/null) || return 1
    if repo_path=$($WTOOL_REPO_TOOL path_from_name ${target} --root ${css_dir} 2>/dev/null); then
        print -r -- ${repo_path}
        return 0
    fi
    if [[ -d ${css_dir}/${target} ]] && \
       $WTOOL_REPO_TOOL name_from_path ${target} --root ${css_dir} >/dev/null 2>&1; then
        print -r -- ${target}
        return 0
    fi
    return 1
}

# only used by zsh
cdd () {
    if [[ $# -ne 1 ]]; then
        echo "Usage: cdd TARGET" >&2
        echo "  TARGET 可以是：清单里的项目名（allinkernel/wtool.git 也行）、" >&2
        echo "                 相对 repo 根或当前目录的路径、现存的文件/目录" >&2
        return 2
    fi
    local target=$1
    if [[ -e $target ]]; then
        if [[ -f $target ]]; then
            cd ${target:h}
            return 0
        elif [[ -d $target ]]; then
            cd $target
            return 0
        fi
    fi

    local css_dir repo_rel repo_abs
    if ! css_dir=$(css 2>/dev/null); then
        echo "cdd: 当前目录不在 repo 工作区里（一路往上都找不到 .repo）" >&2
        echo "     想按名字跳转得先站在 repo 工作区里" >&2
        return 1
    fi
    if repo_rel=$(_repo_project_relpath ${target}); then
        repo_abs=${css_dir}/${repo_rel}
        if [[ -d ${repo_abs} ]]; then
            cd ${repo_abs} && return 0
        fi
        echo "cdd: 项目 '${repo_rel}' 已在清单里，但目录还不存在：" >&2
        echo "     ${repo_abs}" >&2
        echo "     先 repo sync ${repo_rel}" >&2
        return 1
    fi
    echo "cdd: 清单里没有 '${target}' 这个项目名或路径" >&2
    echo "     看看都有什么：$WTOOL_REPO_TOOL list --root ${css_dir}" >&2
    return 1
}


alias gb > /dev/null 2>&1 && unalias gb || true
gb ()
{
    {
        ctt_dir=$(ctt) &&
        repo_branch=$(cnb) &&
        repo_remote=$(cnr)
    } || {
        echo "${funcstack[1]}: not in project dir!!!" >&2
        return 1
    }
    echo "git push ${repo_remote} HEAD:refs/for/${repo_branch}"
    echo "git push ${repo_remote} HEAD:${repo_branch}"
    echo "git pull ${repo_remote} ${repo_branch} --unshallow"
    echo "git pull ${repo_remote} ${repo_branch}"
    echo "git fetch ${repo_remote} ${repo_branch} --unshallow"
    echo "git fetch ${repo_remote} ${repo_branch}"
    echo "remote: ${repo_remote}"
    echo "branch: ${repo_branch}"
    if git remote 2>/dev/null | grep -qx polygerrit; then
        echo "polygerrit: git push polygerrit HEAD:refs/for/${repo_branch}   # 送检（+2 后才进 main）"
    fi
    git remote -v
    return $?
}

# 直接推送到远端，注意如果是在公司需要gerrit审核，need_to_review需要设置成0
# `need_to_review` means need to push HEAD to refs/for/BRANCH nor BRANCH
gbb ()
{
    local ctt_dir cmd need_to_review=1
    if ! ctt_dir=$(ctt); then
        echo "${funcstack[1]}: not in project dir!!!" >&2
        return 1
    fi

    if [[ -f ${ctt_dir}/gbb ]]; then
        zsh ${ctt_dir}/gbb
        return 0
    fi
    cmd=$(gb) || { echo "${funcstack[1]}: not in project dir!!!" >&2; return 1; }
    if [[ ${need_to_review} -eq 0 ]]; then
        cmd=$(grep -P 'git push .*?HEAD:(refs/for/)' <(echo ${cmd}))
    else
        cmd=$(grep -P 'git push .*?HEAD:(?!refs/for/)' <(echo ${cmd}))
    fi
    echo ${cmd}
    eval ${cmd}
    return $?
}

# ---------------------------------------------------------------------------
# Gerrit
#
# 三件事：
#   ggcp  <change> [patchset]  把 gerrit 上的一个提交（指定 patchset）抓回本地并 cherry-pick
#   gchk  <change>             看它有没有 +2 / 有没有 merged（决定能不能推 main）
#   gpush [remote]             把当前 HEAD 推到 refs/for/<清单里声明的分支>
#
# 服务器地址按这个顺序找（先命中先用）：
#   1. 环境变量  WTOOL_GERRIT_HOST / _PORT / _USER / _SSH_KEY
#   2. 配置文件  $WTOOL_GERRIT_CONF、<repo 根>/.gerrit/client.conf、~/.wtool/gerrit.conf
#   3. 自动猜    当前 git remote / 清单 remote 里带 "29418" 或 "gerrit" 的那条
# 配置文件就是几行 shell 变量：
#   host=gerrit.company.com
#   port=29418
#   user=mindul
#   sshkey=~/.ssh/id_rsa
# ---------------------------------------------------------------------------

_gerrit_conf_files () {
    local root
    [[ -n ${WTOOL_GERRIT_CONF} ]] && print -r -- ${WTOOL_GERRIT_CONF}
    if root=$(css 2>/dev/null); then
        print -r -- ${root}/.gerrit/client.conf
    fi
    print -r -- ${HOME}/.wtool/gerrit.conf
}

_gerrit_conf_get () {
    local key=$1 f v
    for f in ${(f)"$(_gerrit_conf_files)"}; do
        [[ -r ${f} ]] || continue
        v=$( . ${f} >/dev/null 2>&1; eval "print -r -- \"\${${key}}\"" )
        if [[ -n ${v} ]]; then
            print -r -- ${v}
            return 0
        fi
    done
    return 1
}

# 从 URL 里拆出 host/port/user：ssh://user@host:29418/path 或 user@host:path
_gerrit_parse_url () {
    local url=$1 rest
    case ${url} in
        ssh://*)
            rest=${url#ssh://}
            rest=${rest%%/*}
            ;;
        *://*)
            # http(s):// 的 remote 不当 gerrit ssh 端点用
            return 1
            ;;
        *@*:*)
            rest=${url%%:*}
            ;;
        *)
            return 1
            ;;
    esac
    [[ -z ${_GERRIT_USER} && ${rest} == *@* ]] && _GERRIT_USER=${rest%%@*}
    rest=${rest#*@}
    if [[ ${rest} == *:* ]]; then
        [[ -z ${_GERRIT_PORT} ]] && _GERRIT_PORT=${rest##*:}
        rest=${rest%%:*}
    fi
    [[ -z ${_GERRIT_HOST} ]] && _GERRIT_HOST=${rest}
    [[ -n ${_GERRIT_HOST} ]]
}

_gerrit_guess_from_remotes () {
    local r url
    if git rev-parse --git-dir >/dev/null 2>&1; then
        for r in ${(f)"$(git remote 2>/dev/null)"}; do
            url=$(git remote get-url ${r} 2>/dev/null) || continue
            case ${url} in
                *29418*|*gerrit*) print -r -- ${url}; return 0 ;;
            esac
        done
    fi
    local css_dir
    if css_dir=$(css 2>/dev/null); then
        for url in ${(f)"$(python3 $WTOOL_REPO_TOOL list --root ${css_dir} 2>/dev/null | awk -F'\t' '{print $5}')"}; do
            case ${url} in
                *29418*|*gerrit*) print -r -- ${url}; return 0 ;;
            esac
        done
    fi
    return 1
}

# 填好 _GERRIT_HOST/_PORT/_USER/_KEY；失败返回 1
_gerrit_resolve () {
    typeset -g _GERRIT_HOST _GERRIT_PORT _GERRIT_USER _GERRIT_KEY
    local url
    _GERRIT_HOST=${WTOOL_GERRIT_HOST:-}
    _GERRIT_PORT=${WTOOL_GERRIT_PORT:-}
    _GERRIT_USER=${WTOOL_GERRIT_USER:-}
    _GERRIT_KEY=${WTOOL_GERRIT_SSH_KEY:-}

    [[ -z ${_GERRIT_HOST} ]] && _GERRIT_HOST=$(_gerrit_conf_get host)
    [[ -z ${_GERRIT_PORT} ]] && _GERRIT_PORT=$(_gerrit_conf_get port)
    [[ -z ${_GERRIT_USER} ]] && _GERRIT_USER=$(_gerrit_conf_get user)
    [[ -z ${_GERRIT_KEY}  ]] && _GERRIT_KEY=$(_gerrit_conf_get sshkey)

    # host 允许写成 user@host:port
    if [[ ${_GERRIT_HOST} == *@* ]]; then
        [[ -z ${_GERRIT_USER} ]] && _GERRIT_USER=${_GERRIT_HOST%%@*}
        _GERRIT_HOST=${_GERRIT_HOST#*@}
    fi
    if [[ ${_GERRIT_HOST} == *:* ]]; then
        [[ -z ${_GERRIT_PORT} ]] && _GERRIT_PORT=${_GERRIT_HOST##*:}
        _GERRIT_HOST=${_GERRIT_HOST%%:*}
    fi

    if [[ -z ${_GERRIT_HOST} ]]; then
        if url=$(_gerrit_guess_from_remotes); then
            _gerrit_parse_url ${url}
        fi
    fi

    if [[ -z ${_GERRIT_HOST} ]]; then
        echo "ggcp: 不知道 gerrit 服务器在哪。请任选一种方式告诉它：" >&2
        echo "  export WTOOL_GERRIT_HOST=user@gerrit.company.com:29418" >&2
        echo "  或写 ~/.wtool/gerrit.conf（host=/port=/user=/sshkey=）" >&2
        echo "  或在 repo 根下放 .gerrit/client.conf" >&2
        return 1
    fi
    [[ -z ${_GERRIT_PORT} ]] && _GERRIT_PORT=29418
    [[ -z ${_GERRIT_USER} ]] && _GERRIT_USER=${USER}
    return 0
}

# 跑一条 gerrit ssh 命令（stdin/stdout 透传）
_gerrit_ssh () {
    local -a opts
    # LogLevel=ERROR：known_hosts 写不进去时 ssh 会往 stderr 抱怨一句，
    # 那句话会把 ggcp/gchk 的 JSON 流搅脏，这里直接压掉
    opts=(-p ${_GERRIT_PORT}
          -o StrictHostKeyChecking=accept-new
          -o LogLevel=ERROR
          -o ConnectTimeout=10)
    if [[ -n ${_GERRIT_KEY} ]]; then
        opts+=(-i ${_GERRIT_KEY} -o IdentitiesOnly=yes)
    fi
    ssh ${opts} "${_GERRIT_USER}@${_GERRIT_HOST}" "$@"
}

# 给 git 用：让 git fetch/push 也走同一把 key
_gerrit_git_ssh_command () {
    local cmd="ssh -p ${_GERRIT_PORT} -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR"
    [[ -n ${_GERRIT_KEY} ]] && cmd+=" -i ${_GERRIT_KEY} -o IdentitiesOnly=yes"
    print -r -- ${cmd}
}

# ggcp 用哪条 remote 抓：优先 polygerrit（本地送检用的镜像），
# 否则用清单里声明的 remote（公司树里就是它）
_gerrit_project_remote () {
    local r
    if git remote 2>/dev/null | grep -qx polygerrit; then
        print -r -- polygerrit
        return 0
    fi
    r=$(cnr 2>/dev/null)
    if [[ -n ${r} ]] && git remote 2>/dev/null | grep -qx ${r}; then
        print -r -- ${r}
        return 0
    fi
    r=$(git remote 2>/dev/null | head -1)
    [[ -n ${r} ]] && print -r -- ${r} && return 0
    return 1
}

# 内部：把 <change> 或 URL 拆成 "编号 [patchset]"
_gerrit_parse_change_arg () {
    local raw=$1 ps=$2 orig=$1
    typeset -g _GERRIT_CHANGE _GERRIT_PS
    if [[ ${raw} == http*://* ]]; then
        raw=${raw%%\?*}
        # 老式链接把 change 号放在 # 后面：https://host/#/c/1234/2
        # 所以先认 #/c/，再考虑"#之后是评论锚点"的一般情况
        if [[ ${raw} == *#/c/* ]]; then
            raw=/${raw#*\#/c/}
        else
            raw=${raw%%#*}
        fi
        raw=${raw%/}
        if [[ ${raw} =~ '/([0-9]+)/([0-9]+)$' ]]; then
            _GERRIT_CHANGE=${match[1]}
            [[ -z ${ps} ]] && ps=${match[2]}
        elif [[ ${raw} =~ '/([0-9]+)$' ]]; then
            _GERRIT_CHANGE=${match[1]}
        fi
    else
        _GERRIT_CHANGE=${raw%%[/,]*}
        if [[ -z ${ps} && ${raw} == *[/,]* ]]; then
            ps=${raw#*[/,]}
        fi
    fi
    if [[ ! ${_GERRIT_CHANGE} == <-> ]]; then
        echo "ggcp: '${orig}' 里看不出 change 编号。" >&2
        echo "      用法: ggcp <change> [patchset]，例如 ggcp 1234 / ggcp 1234 2" >&2
        echo "           也认 https://gerrit.company.com/c/proj/+/1234/2 这种链接" >&2
        return 2
    fi
    if [[ -n ${ps} && ! ${ps} == <-> ]]; then
        echo "ggcp: patchset '${ps}' 不是数字" >&2
        return 2
    fi
    _GERRIT_PS=${ps}
    return 0
}

# 内部：抓一个 change 的 JSON（stdout）
_gerrit_query_change () {
    local change=$1
    _gerrit_ssh gerrit query --format=JSON --patch-sets --current-patch-set "change:${change}"
}

# 内部：抓 JSON 到 $_GERRIT_JSON。
# 关键点：ssh 的 stderr 不能混进 JSON（known_hosts 之类的一句话就能把它搅脏），
# 所以这里把 stderr 单独落文件，只有失败时才回显。
_gerrit_query_capture () {
    local change=$1 tmperr rc
    tmperr=$(mktemp "${TMPDIR:-/tmp}/wtool-gerrit.XXXXXX") || return 1
    typeset -g _GERRIT_JSON
    _GERRIT_JSON=$(_gerrit_query_change ${change} 2>${tmperr})
    rc=$?
    (( rc != 0 )) && cat ${tmperr} >&2
    rm -f ${tmperr}
    return ${rc}
}

# ggcp <change> [patchset]
#   把 gerrit 上第 <change> 号提交的第 <patchset> 个版本抓回本地，
#   cd 到它在清单里对应的项目目录，fetch 之后 cherry-pick。
#   不给 patchset 就用当前（最新）那个。
ggcp () {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ggcp <change> [patchset]" >&2
        echo "  ggcp 1234        # 当前 patchset" >&2
        echo "  ggcp 1234 1      # 第 1 个 patchset" >&2
        echo "  ggcp https://gerrit.company.com/c/proj/+/1234/2" >&2
        return 2
    fi
    _gerrit_parse_change_arg "$1" "$2" || return $?
    local change=${_GERRIT_CHANGE} wanted=${_GERRIT_PS}
    _gerrit_resolve || return 1

    local json line
    if ! _gerrit_query_capture ${change}; then
        echo "ggcp: 连 ${_GERRIT_USER}@${_GERRIT_HOST}:${_GERRIT_PORT} 查询失败" >&2
        return 1
    fi
    json=${_GERRIT_JSON}
    if [[ -z ${json//[[:space:]]/} ]]; then
        echo "ggcp: change ${change} 查不到（编号对不对？有没有权限？）" >&2
        return 1
    fi

    local -a args
    args=(patchset ${change})
    [[ -n ${wanted} ]] && args+=(${wanted})
    if ! line=$(print -r -- ${json} | python3 ${WTOOL_GERRIT_TOOL} ${args} 2>&1); then
        print -r -- ${line} >&2
        return 1
    fi

    local number pset revision ref project branch url subject
    IFS=$'\t' read -r number pset revision ref project branch url subject <<< ${line}
    [[ -z ${ref} ]] && ref=${revision}

    local dir
    if ! dir=$(cdd_path ${project}); then
        echo "ggcp: change ${change} 属于项目 '${project}'，但清单里找不到它" >&2
        echo "      （本地清单和 gerrit 上的是同一份吗？）" >&2
        return 1
    fi
    if [[ ! -d ${dir} ]]; then
        echo "ggcp: 项目 '${project}' 的目录还不存在：${dir}" >&2
        echo "      先 repo sync ${project}" >&2
        return 1
    fi

    cd ${dir} || return 1
    local remote
    if ! remote=$(_gerrit_project_remote); then
        echo "ggcp: 在 $(pwd) 里找不到可用的 git remote" >&2
        return 1
    fi

    echo "ggcp: change ${number} patchset ${pset} -> ${project} (${branch})"
    echo "      commit ${revision}"
    echo "      URL    ${url}"
    GIT_SSH_COMMAND=$(_gerrit_git_ssh_command) git fetch ${remote} ${ref} || return 1
    # fetch 回来核对一下：ref 里写的 patchset 和 gerrit 报的 commit 必须是同一个，
    # 不然就是我把 ref 拼错了，这时候宁可不 cherry-pick
    local fetched
    fetched=$(git rev-parse FETCH_HEAD 2>/dev/null)
    if [[ ${fetched} != ${revision} ]]; then
        echo "ggcp: 抓到的 commit（${fetched}）和 gerrit 说的（${revision}）对不上，" >&2
        echo "      这次不 cherry-pick。用 gq ${number} 看看 patchset 列表" >&2
        return 1
    fi
    if ! GIT_SSH_COMMAND=$(_gerrit_git_ssh_command) git cherry-pick ${revision}; then
        if [[ -f $(git rev-parse --git-path CHERRY_PICK_HEAD 2>/dev/null) ]]; then
            echo "ggcp: cherry-pick 冲突了。解决后 git cherry-pick --continue，" >&2
            echo "      或者 git cherry-pick --abort 整个放弃" >&2
        else
            echo "ggcp: cherry-pick 没跑起来（工作区有没提交的改动？先 commit 或 git stash）" >&2
        fi
        return 1
    fi
    echo "ggcp: 已 cherry-pick 到 $(pwd) 的 $(git rev-parse --abbrev-ref HEAD) 分支"
    return 0
}

# 项目名/路径 -> 绝对路径（不 cd）
cdd_path () {
    local target=$1 css_dir repo_path
    if ! css_dir=$(css 2>/dev/null); then
        echo "cdd_path: 当前目录不在 repo 工作区里" >&2
        return 1
    fi
    if repo_path=$($WTOOL_REPO_TOOL path_from_name ${target} --root ${css_dir} 2>/dev/null); then
        print -r -- ${css_dir}/${repo_path}
        return 0
    fi
    if [[ -e ${css_dir}/${target} ]]; then
        print -r -- ${css_dir}/${target}
        return 0
    fi
    echo "cdd_path: 清单里没有 '${target}'" >&2
    return 1
}

# gchk <change>：能不能推 main？—— 看 +2 和 merged
# 退出码 0 = 已 merged（此时必然有 +2），1 = 还没，2 = 查不到
gchk () {
    if [[ $# -ne 1 ]]; then
        echo "Usage: gchk <change>" >&2
        return 2
    fi
    _gerrit_parse_change_arg "$1" || return $?
    local change=${_GERRIT_CHANGE}
    _gerrit_resolve || return 2
    local json
    if ! _gerrit_query_capture ${change}; then
        echo "gchk: 查询失败" >&2
        return 2
    fi
    json=${_GERRIT_JSON}
    print -r -- ${json} | python3 ${WTOOL_GERRIT_TOOL} check ${change}
    return $?
}

# gq <change>：把 change 的摘要列出来（raw JSON 用 gq -r）
gq () {
    local raw=0
    [[ $1 == -r || $1 == --raw ]] && { raw=1; shift }
    if [[ $# -lt 1 ]]; then
        echo "Usage: gq <change>" >&2
        return 2
    fi
    _gerrit_parse_change_arg "$1" || return $?
    _gerrit_resolve || return 2
    local json
    json=$(_gerrit_query_change ${_GERRIT_CHANGE}) || return 1
    if [[ ${raw} -eq 1 ]]; then
        print -r -- ${json}
    else
        print -r -- ${json} | python3 ${WTOOL_GERRIT_TOOL} list
    fi
}

# gpush [remote] [额外参数...]：推当前 HEAD 去送检
gpush () {
    local remote=polygerrit branch
    if [[ $# -gt 0 && $1 != -* ]]; then
        remote=$1
        shift
    fi
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "gpush: 当前目录不是 git 仓库" >&2
        return 1
    fi
    if ! branch=$(cnb); then
        echo "gpush: 取不到清单里声明的分支（cnb 失败）" >&2
        return 1
    fi
    if ! git remote 2>/dev/null | grep -qx ${remote}; then
        echo "gpush: 这个仓库没有 remote '${remote}'。现有的：" >&2
        git remote -v >&2
        return 1
    fi
    _gerrit_resolve >/dev/null 2>&1
    echo "gpush: git push ${remote} HEAD:refs/for/${branch} $*"
    GIT_SSH_COMMAND=$(_gerrit_git_ssh_command) git push ${remote} "HEAD:refs/for/${branch}" "$@"
}

# ---------------------------------------------------------------------------
# repo / 构建
# ---------------------------------------------------------------------------
rs () {
    tmp_xml=$(mktemp).xml
    repo manifest -o ${tmp_xml}
    # TODO:后续要把 repo manifest -Ro 实现，创造自己的repo仓
    repo sync -c -j$(grep 'processor' /proc/cpuinfo | wc -l) --force-sync --force-checkout -d -m ${tmp_xml}
}

wninja() {
    # this only for zsh
    if [[ -z $ZSH_VERSION ]]; then
        return
    fi
    cs
    # 局部作用域定义变量，防止污染全局
    local ninja_bin prebuilt_ninja
    prebuilt_ninja="$(css)/prebuilts/build-tools/linux-x86/bin/ninja"
    if [[ -f "$prebuilt_ninja" ]]; then
        ninja_bin="$prebuilt_ninja"
    else
        ninja_bin="ninja" # 回退到系统路径
    fi
    combined_configs=(out/combined-*.ninja(N))
    build_configs=(out/build.ninja(N))
    nested_configs=(out/*/*/build.ninja(N))

    if (( $#combined_configs > 0 )); then
        "$ninja_bin" -f "$combined_configs[1]" "$@"
    elif (( $#build_configs > 0 )); then
        "$ninja_bin" -f "$build_configs[1]" "$@"
    elif (( $#nested_configs > 0 )); then
        "$ninja_bin" -f "$nested_configs[1]" "$@"
    else
        echo "Error: No ninja build file found."
        return 1
    fi
}
rscur () {
# repo sync all repo project in current rel-path
    local count cur_dir all_sub_dir cnn_dir _answer _cmd
    css_dir=$(css 2>/dev/null) || { echo "${funcstack[1]}: not in repo dir!!!" >&2; return 1; }
    if cnn_dir=$(cnn 2>/dev/null) ; then
        _cmd="repo sync -c ${cnn_dir}"
    else
        cur_dir="${${PWD}##${css_dir}/}"
        echo ${cur_dir}
        all_sub_dir=(${(f)"$(repo list | sort | rg -o --pcre2 "^${cur_dir}/(?<=${cur_dir}/)[^ ]+")"})
        echo ${all_sub_dir}
        all_sub_dir=(${all_sub_dir//${cur_dir}\//})
        count=${#all_sub_dir}
        all_sub_dir=${(j: :)${all_sub_dir}}
        if [[ ${all_sub_dir} == "" ]]; then
            echo "${funcstack[1]}: TODO: repo list has no such dir before download it!!!" >&2
            return 1
        fi
        _cmd="repo sync --force-sync -d -c ${all_sub_dir} -j$(nproc)"
    fi
    echo '==>'"${_cmd}"
    printf "total ${count} repos in ${cur_dir}, execute it? ({ENTER/Y/y}/{N/n/*}) "
    read answer
    [[ -z "${answer}" ]] || [[ "${answer}" =~ ^(Y|y)?$ ]] && eval "${_cmd}"

    unset cur_dir _answer _cmd
}
