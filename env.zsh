# 迁移自 mytool/android/wsw_env.sh（原 wsw-androidrc）。纯 zsh，由 ~/.zshrc 里的 wtool 块 source。
#
# WTOOL_PROJECT_DIR 由 wtool 块导出 = $HOME/.wtool/wtool-work-dir/links/tools/git-repo-sh-tools，
# 指向本项目根。单独 source（不经 wtool 块）时给出默认值，保证可用。
[[ -n "$WTOOL_PROJECT_DIR" ]] || WTOOL_PROJECT_DIR="$HOME/.wtool/wtool-work-dir/links/tools/git-repo-sh-tools"
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

# 内部：gerrit 上的提交编号 -> 它属于哪个项目（gerrit project 名）。
# 复用 ggcp 那套服务器解析（环境变量 / client.conf / ~/.wtool/gerrit.conf / 猜 remote）
# 和 _gr_query_info（ggcp 的查询阶段也走它，不复制第二份 ssh/JSON 代码）。
_cdd_project_from_change () {
    local number=$1 line
    if ! _gerrit_resolve >/dev/null 2>&1; then
        echo "cdd: 按提交编号跳转得先知道 gerrit 服务器在哪：" >&2
        echo "     export WTOOL_GERRIT_HOST=user@host:29418" >&2
        echo "     或写 <repo 根>/.gerrit/client.conf（host=/port=/user=/sshkey=）" >&2
        return 1
    fi
    local errfile
    errfile=$(mktemp "${TMPDIR:-/tmp}/cdd-query.XXXXXX") || return 1
    if ! line=$(_gr_query_info ${number} '' 2>${errfile}); then
        local msg
        msg=$(_gr_first_line "$(cat ${errfile} 2>/dev/null)")
        [[ -z ${msg} ]] && msg="查询 change ${number} 失败"
        echo "cdd: ${msg}" >&2
        rm -f ${errfile}
        return 1
    fi
    rm -f ${errfile}
    print -r -- ${line} | cut -f5
}

# 内部：`cdd -N` / `cdd N` 的落点 —— 查编号所属项目，再找本地清单里的路径。
# 两种情况分开报：清单里有但没检出 / 清单里根本没有这个项目。
_cdd_cd_to_change () {
    local change=$1 css_dir=$2 proj proj_rel
    if ! proj=$(_cdd_project_from_change ${change}); then
        return 1
    fi
    if [[ -z ${proj} ]]; then
        echo "cdd: change ${change} 查不到它属于哪个项目" >&2
        return 1
    fi
    if proj_rel=$(_repo_project_relpath ${proj}); then
        if [[ -d ${css_dir}/${proj_rel} ]]; then
            cd ${css_dir}/${proj_rel} && return 0
            return 1
        fi
        echo "cdd: change ${change} 属于项目 ${proj}，但本地还没检出（清单路径 ${proj_rel}）" >&2
        echo "     先 repo sync ${proj_rel}" >&2
        return 1
    fi
    echo "cdd: change ${change} 属于项目 ${proj}，但当前工作区的清单里没有它" >&2
    return 1
}

# 内部：`..` / `...` / `....` 这种"整个 token 都是点"的参数 -> 往上跳的层数。
# N 个点 = 往上 N-1 层（跟 zsh 里 `cd ...` 的规矩一样）。**不是点参数就返回 1**
# （含别的字符 / 只有 1 个点 / 空），什么都不打印 —— 调用方照常往下走别的路。
_cdd_dots_up () {
    local token=$1
    [[ ${token} == *[!.]* ]] && return 1
    (( ${#token} >= 2 )) || return 1
    print -r -- $(( ${#token} - 1 ))
}

# only used by zsh
cdd () {
    if [[ $# -ne 1 ]]; then
        echo "Usage: cdd TARGET" >&2
        echo "  TARGET 可以是：清单里的项目名（allinkernel/wtool-doc.git 也行）、" >&2
        echo "                 相对 repo 根或当前目录的路径、现存的文件/目录、" >&2
        echo "                 gerrit 提交编号（-N；纯数字也认，但会先当现存目录）、" >&2
        echo "                 或者一串点（.. / ... / ....，往上跳\"点数-1\"层）" >&2
        return 2
    fi
    local target=$1
    # 一串点（`..` = 上一层，`...` = 上两层，…… N 个点 = 往上 N-1 层）：
    # 这是 zsh 里 `cd ...` 那个习惯（zsh 自己没有，是 oh-my-zsh 的 global alias
    # 给的，只到 6 个点）。这里**不限点数**，bash 也照样能用，而且**不用站在
    # repo 工作区里**（到不了 `/` 以下的任何清单逻辑）。放在最前面判 —— `..`
    # 本身就是个真目录，不先判就会被下面"现存目录"那条抢走；顺带也压住
    # "真有个叫 `...` 的目录"这种情形（点参数就是往上跳，不做路径解析）。
    # 点太多、跳过根了？`cd` 自己会停在 `/`，不算错（退出码 0，不打东西）。
    local dots_up up_path i
    if dots_up=$(_cdd_dots_up ${target}); then
        up_path=..
        for (( i = 1; i < dots_up; i++ )); do
            up_path+=/..
        done
        cd ${up_path} || return 1
        return 0
    fi
    # `-N`：明确表示"这是 gerrit 提交编号，不是目录"（纯数字还留着，但它会先被
    # 上面"现存目录"那条抢走）。去 gerrit 查它属于哪个项目，再跳到本地清单里
    # 那个项目的目录。
    if [[ ${target} == -<-> ]]; then
        local change=${target#-} css_dir
        if ! css_dir=$(css 2>/dev/null); then
            echo "cdd: 当前目录不在 repo 工作区里（一路往上都找不到 .repo）" >&2
            echo "     按提交编号跳转得先站在 repo 工作区里" >&2
            return 1
        fi
        _cdd_cd_to_change ${change} ${css_dir}
        return $?
    fi
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
    # 纯数字 = gerrit 提交编号（ggcp 用的那个）：去 gerrit 查它属于哪个仓库，
    # 然后跳到那个仓库的本地目录。`-N` 是显式写法（见上面），纯数字是兼容老写法。
    if [[ ${target} == <-> ]]; then
        _cdd_cd_to_change ${target} ${css_dir}
        return $?
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

# gpun [<深度>]
#   把 `gb` 打印的那条 `git pull <remote> <branch> --unshallow` **真的跑掉**
#   （`gb` 只打印、`gbb` 只挑 push 那条；这条专管 shallow 仓补历史）。
#   gpun -30 / gpun --depth=30 表示把 --unshallow 换成 --depth=30（只拉 30 层，不补全）。
#   挑不到那条命令（gb 没给 / gb 自己失败）就报错返回 1 —— 不静默当成功；
#   gb 的整段输出不刷给用户，只回显真正要跑的那一条。
gpun ()
{
    local me=${funcstack[1]}
    local depth='' depth_set=0 usage_bad='' out cmd rc
    if [[ $# -gt 1 ]]; then
        usage_bad="参数太多（$# 个）"
    else
        case "${1-}" in
            '') ;;
            --depth=*) depth=${1#--depth=}; depth_set=1 ;;
            -[0-9]*) depth=${1#-}; depth_set=1 ;;
            *) usage_bad="参数不认：${1}" ;;
        esac
    fi
    if [[ -z ${usage_bad} && ${depth_set} -eq 1 ]]; then
        case ${depth} in
            *[!0-9]*) usage_bad="深度要是正整数（>= 1）：'${depth}'" ;;
            *[!0]*) ;;
            *) usage_bad="深度要是正整数（>= 1）：'${depth}'" ;;
        esac
    fi
    if [[ -n ${usage_bad} ]]; then
        echo "${me}: ${usage_bad}" >&2
        echo "Usage: gpun [<深度> | --depth=<深度>]" >&2
        echo "  gpun              # 跑 gb 给出的那条 git pull <remote> <branch> --unshallow" >&2
        echo "  gpun -30          # 同上，但把 --unshallow 换成 --depth=30" >&2
        echo "  gpun --depth=30   # 同上（等价写法）" >&2
        return 2
    fi

    if ! out=$(gb); then
        echo "${me}: 拿不到 gb 的输出，没法确定要跑哪条 pull 命令" >&2
        return 1
    fi
    cmd=$(print -r -- "${out}" | grep -E '^git pull .*[[:space:]]--unshallow$' | head -n 1)
    if [[ -z ${cmd} ]]; then
        echo "${me}: gb 没给出 'git pull <remote> <branch> --unshallow' 那条命令" >&2
        echo "      先单独跑一次 gb 看看它打印了什么" >&2
        return 1
    fi
    if [[ -n ${depth} ]]; then
        cmd="${cmd%--unshallow}--depth=${depth}"
    fi

    echo "${me}: 执行 ${cmd}"
    if eval "${cmd}"; then rc=0; else rc=$?; fi
    if [[ ${rc} -ne 0 ]]; then
        echo "${me}: 上面这条 pull 失败（退出码 ${rc}）" >&2
    fi
    return ${rc}
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
#   认：1234 / 1234/2 / 两种 gerrit 链接 / I<40 位十六进制>（Change-Id）
#   Change-Id 不是编号：这时 _GERRIT_CHANGEID 非空、_GERRIT_CHANGE 也等于它
#   （`change:<Change-Id>` 在 gerrit query 里是合法的），调用方看到
#   _GERRIT_CHANGEID 非空就知道"这是 Change-Id，要展开成多个提交"。
_gerrit_parse_change_arg () {
    local raw=$1 ps=$2 orig=$1
    typeset -g _GERRIT_CHANGE _GERRIT_PS _GERRIT_CHANGEID
    _GERRIT_CHANGEID=
    local re_cid='^I[0-9a-fA-F]{40}$'
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
    elif [[ ${raw} =~ ${re_cid} ]]; then
        _GERRIT_CHANGE=${raw}
        _GERRIT_CHANGEID=${raw}
    else
        _GERRIT_CHANGE=${raw%%[/,]*}
        if [[ -z ${ps} && ${raw} == *[/,]* ]]; then
            ps=${raw#*[/,]}
        fi
    fi
    if [[ -n ${_GERRIT_CHANGEID} ]]; then
        if [[ -n ${ps} ]]; then
            echo "ggcp: Change-Id '${orig}' 不能指定 patchset（它对应很多个提交）" >&2
            echo "      要看清单个 patchset 请用编号，例如 ggcp 1234/2" >&2
            return 2
        fi
        _GERRIT_PS=
        return 0
    fi
    if [[ ! ${_GERRIT_CHANGE} == <-> ]]; then
        echo "ggcp: '${orig}' 里看不出 change 编号。" >&2
        echo "      用法: ggcp <change> [patchset]，例如 ggcp 1234 / ggcp 1234 2" >&2
        echo "           也认 https://gerrit.company.com/c/proj/+/1234/2 和老式 #/c/1234/2" >&2
        echo "           还可以给 Change-Id：ggcp I1111111111111111111111111111111111111111" >&2
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
# `</dev/null` 是必须的：ssh 会把 stdin 吞掉（转发给远端命令），而 ggcp 按
# Change-Id 打补丁时要**用 stdin 逐个问用户** —— 不挡的话问题刚打完就问不到答案了。
_gerrit_query_change () {
    local change=$1
    _gerrit_ssh gerrit query --format=JSON --patch-sets --current-patch-set "change:${change}" < /dev/null
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

# 内部：查一个 change + patchset，成功时 stdout 打一行 TSV：
#   number  patchset  revision  ref  project  branch  url  subject
# 失败时返回 1，原因放在 _GR_QUERY_ERR（ggcp 和 cdd 共用这一份查询逻辑）。
_gr_query_info () {
    local change=$1 wanted=$2 json line
    typeset -g _GR_QUERY_ERR
    _GR_QUERY_ERR=
    if ! _gerrit_query_capture ${change}; then
        _GR_QUERY_ERR="连 ${_GERRIT_USER}@${_GERRIT_HOST}:${_GERRIT_PORT} 查询 change ${change} 失败"
        print -r -- "${_GR_QUERY_ERR}" >&2
        return 1
    fi
    json=${_GERRIT_JSON}
    if [[ -z ${json//[[:space:]]/} ]]; then
        _GR_QUERY_ERR="gerrit 上查不到 change ${change}（编号对不对？有没有权限？）"
        print -r -- "${_GR_QUERY_ERR}" >&2
        return 1
    fi
    local -a args
    args=(patchset ${change})
    [[ -n ${wanted} ]] && args+=(${wanted})
    if ! line=$(print -r -- ${json} | python3 ${WTOOL_GERRIT_TOOL} ${args} 2>&1); then
        _GR_QUERY_ERR=$(print -r -- ${line} | head -n 1)
        if [[ ${_GR_QUERY_ERR} == *没有匹配* ]]; then
            _GR_QUERY_ERR="gerrit 上查不到 change ${change}（编号对不对？有没有权限？）"
        fi
        [[ -z ${_GR_QUERY_ERR} ]] && \
            _GR_QUERY_ERR="gerrit 上查不到 change ${change} 的 patchset ${wanted}"
        print -r -- "${_GR_QUERY_ERR}" >&2
        return 1
    fi
    print -r -- ${line}
    return 0
}

# 内部：多行输出取第一行非空内容（表格里一格只能放一行）。
_gr_first_line () {
    print -r -- "$1" | awk 'NF { print; exit }'
}

# 内部：结果表里显示的短 commit id（12 位；空的就是 `-`）。
_gr_short_sha () {
    local sha=$1
    [[ -z ${sha} ]] && { print -r -- '-'; return 0; }
    print -r -- ${sha} | cut -c1-12
}

# 内部：把一个仓库的所有提交标记成同一个失败原因（项目不在清单 / 目录没检出 / 工作树脏…）。
_gr_repo_fail_all () {
    local project=$1 spec=$2 out=$3 reason=$4
    local number pset revision ref p branch url rel
    while IFS=$'\t' read -r number pset revision ref p branch url rel; do
        [[ -z ${pset} ]] && pset='-'
        print -r -- "${project}"$'\t'"${rel:--}"$'\t'"$(_gr_short_sha "${revision}")"$'\t'"${pset}"$'\t'"${reason}" >> ${out}
    done < ${spec}
}


# ---------------------------------------------------------------------------
# ggcp —— 把 gerrit 上的提交抓回本地并 cherry-pick
#
# 所有入口最后都**坍缩成"按编号打补丁"这一件事**：
#   编号          ggcp 1234
#   编号列表      ggcp 1,2,3（英文逗号）/ ggcp 1 2 3（空格）/ 混用 ggcp 1,2 3
#   gerrit 链接   ggcp https://host/#/c/1234  或  https://host/c/proj/+/1234
#   Change-Id     ggcp I1111…（去 gerrit 查它的**所有**提交，打表后逐个问）
#
# 两阶段执行：
#   阶段 1  每个补丁一条 gerrit 查询，**全部并行**（查询结果各自落到临时文件）；
#   阶段 2  按项目分组：**同仓库串行**（按用户给的顺序）、**不同仓库并行**。
# 每个仓库全部结束后才把它的行写进缓冲；最后按项目路径排序合并成**一张表**。
# git fetch / cherry-pick 的原始输出一律吞掉，只把关键错误放进"结果说明"列。
# ---------------------------------------------------------------------------

# 颜色：**只有自动两条** —— 设了 NO_COLOR 就不上色；否则 stdout 是 tty 才上色。
# 没有"强制开关"这种变量（用户口径：不给用户加看不懂的旋钮）。
# （ggcp 的结果表不上色：ANSI 码会破坏中文对齐；这两个函数留给别的调用方。）
_gr_color_on () {
    [[ -n ${NO_COLOR:-} ]] && return 1
    [[ -t 1 ]]
}

_gr_green () {
    if _gr_color_on; then
        print -r -- $'\033[32m'"$1"$'\033[0m'
    else
        print -r -- "$1"
    fi
}

_gr_red () {
    if _gr_color_on; then
        print -r -- $'\033[31m'"$1"$'\033[0m'
    else
        print -r -- "$1"
    fi
}

_gr_ggcp_usage () {
    echo "Usage: ggcp [-y|-n] [-p <patchset>] <编号|链接|Change-Id> ..." >&2
    echo "  ggcp 1234               # 一个编号（当前 patchset）" >&2
    echo "  ggcp 1,2,3              # 英文逗号分隔的编号列表" >&2
    echo "  ggcp 1 2 3              # 空格分隔的编号列表（两种可以混用）" >&2
    echo "  ggcp https://gerrit.company.com/#/c/1234     # 直接从链接里取编号" >&2
    echo "  ggcp https://gerrit.company.com/c/proj/+/1234" >&2
    echo "  ggcp I1111111111111111111111111111111111111111" >&2
    echo "       # 按 Change-Id：查 gerrit 上它的所有提交，打表后逐个问" >&2
    echo "  -p <n>   打第 n 个 patchset（默认当前 patchset；也可以写成 1234/2）" >&2
    echo "  -y       全都打，不再问（Change-Id 那条路默认逐个问）" >&2
    echo "  -n       全都跳过，不问" >&2
}

# 把 ggcp 的参数**坍缩成"按编号打补丁"这一件事**：
#   数字 / 逗号列表 / 空格列表 / 链接 / 1234/2  -> _GGCP_ITEMS（"编号|patchset"）
#   Change-Id                                   -> _GGCP_IDS（稍后去 gerrit 展开）
_gr_collect_args () {
    typeset -ga _GGCP_ITEMS _GGCP_IDS
    _GGCP_ITEMS=()
    _GGCP_IDS=()
    local a tok re_cid='^I[0-9a-fA-F]{40}$'
    for a in "$@"; do
        # 逗号列表：1,2,3 -> 三个 token（空格列表由调用方的 $@ 天然拆开）
        for tok in ${(s:,:)a}; do
            [[ -z ${tok} ]] && continue
            if [[ ${tok} =~ ${re_cid} ]]; then
                _GGCP_IDS+=(${tok})
                continue
            fi
            if [[ ${tok} == http*://* ]]; then
                _gerrit_parse_change_arg ${tok} || return 2
                _GGCP_ITEMS+=("${_GERRIT_CHANGE}|${_GERRIT_PS}")
                continue
            fi
            if [[ ${tok} == <->/<-> ]]; then
                _GGCP_ITEMS+=("${tok%%/*}|${tok#*/}")
                continue
            fi
            if [[ ${tok} == <-> ]]; then
                _GGCP_ITEMS+=("${tok}|")
                continue
            fi
            echo "ggcp: '${tok}' 不是提交编号、gerrit 链接或 Change-Id" >&2
            _gr_ggcp_usage
            return 2
        done
    done
    return 0
}

# 问一句：返回 0 = 打，1 = 跳过，2 = 不再问了（剩下的都跳过）
_gr_ask () {
    local prompt=$1 ans
    printf '%s' "${prompt}"
    if ! IFS= read -r ans; then
        print -r -- ""
        return 1
    fi
    # 答案是从管道/文件喂进来的时候（`printf 'y\n' | ggcp …`），终端不会回显那一下回车，
    # 这里自己补一个换行 —— 不然问题和后面的输出会粘成一行，日志没法看
    [[ -t 0 ]] || print -r -- ""
    case ${ans} in
        [yY]|[yY][eE][sS]) return 0 ;;
        [qQ])              return 2 ;;
        *)                 return 1 ;;
    esac
}

# 查询阶段的**一条**任务：查 gerrit，再算本地清单路径，打一行 8 列 TSV：
#   number  patchset  revision  ref  project  branch  url  relpath
# relpath 拿不到就写 `-`（后面按项目分组，失败原因由执行阶段给）。
_gr_query_one () {
    local change=$1 wanted=$2 line project rel
    line=$(_gr_query_info ${change} ${wanted}) || return 1
    project=$(print -r -- ${line} | cut -f5)
    rel=$(_repo_project_relpath ${project} 2>/dev/null) || rel='-'
    [[ -z ${rel} ]] && rel='-'
    print -r -- "$(print -r -- ${line} | cut -f1-7)"$'\t'"${rel}"
}

# 执行阶段的**一个仓库**：spec 里每一行是一个提交（按用户给的顺序，**串行**）。
# 结果全部写进 out（5 列 TSV：项目名 项目路径 提交id patchset 结果说明），
# 本函数**不直接打印** —— 交给父进程按仓库聚拢后合并成一张表。
_gr_repo_batch () {
    local project=$1 spec=$2 out=$3
    local number pset revision ref p branch url rel root dir remote
    local fetch_out cherry_out fetched porcelain files abort_out after reason rc
    : > ${out}

    root=$(css 2>/dev/null) || root=''
    IFS=$'\t' read -r number pset revision ref p branch url rel < ${spec} || true
    if [[ -z ${root} ]]; then
        _gr_repo_fail_all ${project} ${spec} ${out} '当前目录不在 repo 工作区里'
        return 1
    fi
    if [[ -z ${rel} || ${rel} == '-' ]]; then
        _gr_repo_fail_all ${project} ${spec} ${out} "本地清单里没有项目 ${project}"
        return 1
    fi
    dir=${root}/${rel}
    if [[ ! -d ${dir} ]]; then
        _gr_repo_fail_all ${project} ${spec} ${out} "项目目录不存在：${rel}（先 repo sync ${rel}）"
        return 1
    fi
    cd ${dir} || {
        _gr_repo_fail_all ${project} ${spec} ${out} "进不了项目目录：${dir}"
        return 1
    }
    if ! remote=$(_gerrit_project_remote); then
        _gr_repo_fail_all ${project} ${spec} ${out} "找不到可用的 git remote"
        return 1
    fi
    # 有本地改动时不动工作树：cherry-pick 的冲突/回滚都会和它搅在一起，
    # 后面就说不清"工作树干净"到底干不干净。
    if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
        _gr_repo_fail_all ${project} ${spec} ${out} '工作树有本地改动（先 stash/commit）'
        return 1
    fi

    while IFS=$'\t' read -r number pset revision ref p branch url rel; do
        [[ -n ${ref} ]] || ref=${revision}
        [[ -z ${pset} ]] && pset='-'
        if [[ -z ${revision} ]]; then
            reason='gerrit 没给出 commit id'
            print -r -- "${project}"$'\t'"${rel:--}"$'\t-'$'\t'"${pset}"$'\t'"${reason}" >> ${out}
            continue
        fi

        fetch_out=$(GIT_SSH_COMMAND=$(_gerrit_git_ssh_command) git fetch ${remote} ${ref} < /dev/null 2>&1)
        rc=$?
        if (( rc != 0 )); then
            reason="下载失败：$(_gr_first_line "${fetch_out}")"
            [[ ${reason} == '下载失败：' ]] && reason='下载失败'
            print -r -- "${project}"$'\t'"${rel:--}"$'\t'"$(_gr_short_sha ${revision})"$'\t'"${pset}"$'\t'"${reason}" >> ${out}
            continue
        fi

        # 核对：ref 里写的 patchset 和 gerrit 报的 commit 必须是同一个，
        # 不然就是 ref 拼错了，这时候宁可不 cherry-pick。
        fetched=$(git rev-parse FETCH_HEAD 2>/dev/null)
        if [[ ${fetched} != ${revision} ]]; then
            reason="抓到的 commit（${fetched}）和 gerrit 说的（${revision}）不一致"
            print -r -- "${project}"$'\t'"${rel:--}"$'\t'"$(_gr_short_sha ${revision})"$'\t'"${pset}"$'\t'"${reason}" >> ${out}
            continue
        fi

        cherry_out=$(GIT_SSH_COMMAND=$(_gerrit_git_ssh_command) git cherry-pick ${revision} < /dev/null 2>&1)
        rc=$?
        if (( rc == 0 )); then
            reason='成功'
        else
            porcelain=$(git status --porcelain --untracked-files=no)
            if [[ -n ${porcelain} ]]; then
                # 有文件就是冲突：把 git status 里的路径原样列出来（一行一格）
                files=$(print -r -- ${porcelain} | cut -c4- | tr '\n' ' ')
                files=${files% }
                reason="${files} 文件冲突"
            else
                # status 为空 = 没有冲突文件：最常见的是这个补丁已经在了/已合入，
                # cherry-pick 变成一个空提交（CHERRY_PICK_HEAD 还在）。
                reason='此提交本地已经有了（可能已合入）'
            fi
            # ⚠️ 必须收干净：留着冲突态会把用户的 git 卡在 cherry-pick 中间。
            # 只用 --abort（回到 cherry-pick 之前），**绝不** reset --hard。
            if git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
                if ! abort_out=$(git cherry-pick --abort < /dev/null 2>&1); then
                    git cherry-pick --quit < /dev/null >/dev/null 2>&1 || true
                    [[ -n ${abort_out} ]] && \
                        reason="${reason}（清理：$(_gr_first_line "${abort_out}")）"
                fi
            fi
            after=$(git status --porcelain --untracked-files=no)
            if [[ -n ${after} ]]; then
                reason="${reason}（工作树没清干净，请手工处理）"
            fi
        fi
        reason=${reason//$'\n'/ }
        reason=${reason//$'\t'/ }
        print -r -- "${project}"$'\t'"${rel:--}"$'\t'"$(_gr_short_sha ${revision})"$'\t'"${pset}"$'\t'"${reason}" >> ${out}
    done < ${spec}
    return 0
}

# 打印"总述 + 一张表"。返回 0 = 全部成功；1 = 至少有失败。
_gr_result_table () {
    local rows=$1 repos=$2 total=$3 ok fail
    ok=$(awk -F '\t' '$5 == "成功" { n++ } END { print n + 0 }' ${rows})
    fail=$(( total - ok ))
    print -r -- "${repos} 个仓库 / ${total} 笔提交 / 成功 ${ok} / 失败 ${fail}"
    if ! python3 ${WTOOL_GERRIT_TOOL} result-table < ${rows}; then
        # python 那边出问题时别把结果吞掉：退回原始 TSV（至少信息还在）
        cat ${rows}
    fi
    (( fail == 0 ))
}

# 还没进入"补丁结果"就失败时（gerrit 没配置 / Change-Id 展开失败）也打一张表：
# 每个用户给的条目一行，结果说明统一写失败原因。返回 1。
_gr_fail_table () {
    local reason=$1 rows item number patchset cid total=0
    rows=$(mktemp "${TMPDIR:-/tmp}/ggcp-fail.XXXXXX") || return 1
    for item in ${_GGCP_ITEMS}; do
        number=${item%%|*}
        patchset=${item#*|}
        [[ -z ${patchset} ]] && patchset='-'
        print -r -- '-'$'\t-'$'\t-'$'\t'"${patchset}"$'\t'"查询失败：${reason}" >> ${rows}
        total=$(( total + 1 ))
    done
    for cid in ${_GGCP_IDS}; do
        print -r -- '-'$'\t-'$'\t-'$'\t-'$'\t'"查询失败：${reason}" >> ${rows}
        total=$(( total + 1 ))
    done
    _gr_result_table ${rows} 0 ${total}
    rm -f ${rows}
    return 1
}

# Change-Id -> 去 gerrit 查它的**所有提交**（同一 Change-Id 可能横跨多个分支 /
# 多个 change，每个还有多个 patchset），打一张表（编号/patchset/仓库/路径/提交链接），
# 然后挨个问"给这个仓库打这个补丁吗？"。答应的条目追加进 _GGCP_ITEMS。
_gr_expand_changeids () {
    local assume=$1 cid json rows line project rel mapfile
    local -a all_rows=()
    for cid in ${_GGCP_IDS}; do
        if ! _gerrit_query_capture ${cid}; then
            echo "ggcp: 连 ${_GERRIT_USER}@${_GERRIT_HOST}:${_GERRIT_PORT} 查询失败" >&2
            return 1
        fi
        json=${_GERRIT_JSON}
        if [[ -z ${json//[[:space:]]/} ]]; then
            echo "ggcp: Change-Id ${cid} 在 gerrit 上查不到对应的提交（是不是别的服务器上的？）" >&2
            return 1
        fi
        if ! rows=$(print -r -- ${json} | python3 ${WTOOL_GERRIT_TOOL} commits 2>&1); then
            # 查询成功但一条 change 都没有时，gerrit query 只回一行 stats
            echo "ggcp: Change-Id ${cid} 在 gerrit 上查不到对应的提交" >&2
            print -r -- ${rows} >&2
            return 1
        fi
        all_rows+=(${(f)rows})
    done
    if (( ${#all_rows} == 0 )); then
        echo "ggcp: 这些 Change-Id 在 gerrit 上没有任何提交" >&2
        return 1
    fi

    # 每行：编号 patchset 仓库 revision ref 提交链接 分支
    mapfile=$(mktemp "${TMPDIR:-/tmp}/ggcp-paths.XXXXXX") || return 1
    local seen="|" root
    root=$(css 2>/dev/null)
    for line in ${all_rows}; do
        local -a f
        IFS=$'\t' read -rA f <<< ${line}
        project=${f[3]}
        [[ -z ${project} ]] && continue
        [[ ${seen} == *"|${project}|"* ]] && continue
        seen+="${project}|"
        if rel=$(_repo_project_relpath ${project}) && [[ -d ${root}/${rel} ]]; then
            print -r -- "${project}"$'\t'${rel} >> ${mapfile}
        elif [[ -n ${rel} ]]; then
            print -r -- "${project}"$'\t'"(目录不存在)" >> ${mapfile}
        else
            print -r -- "${project}"$'\t'"(不在本地清单里)" >> ${mapfile}
        fi
    done

    # 注意用 print -rl：print 会把多个参数**打在同一行**，这里要的是一行一条
    print -rl -- ${all_rows} | python3 ${WTOOL_GERRIT_TOOL} table --path-map ${mapfile} \
        || print -rl -- ${all_rows}
    rm -f ${mapfile}

    local number patchset revision ref url branch answer
    for line in ${all_rows}; do
        IFS=$'\t' read -r number patchset project revision ref url branch <<< ${line}
        if [[ ${assume} == yes ]]; then
            answer=0
        elif [[ ${assume} == no ]]; then
            answer=1
        else
            _gr_ask "给仓库 ${project} 打补丁 ${number} (patchset ${patchset}) 吗？[y/N/q] "
            answer=$?
            if (( answer == 2 )); then
                echo "ggcp: 不再问了，剩下的都跳过" >&2
                break
            fi
        fi
        (( answer == 0 )) && _GGCP_ITEMS+=("${number}|${patchset}")
    done
    return 0
}

# ggcp <编号|链接|Change-Id> ...
#   把 gerrit 上的提交抓回本地，cd 到它在清单里对应的项目目录，fetch 之后 cherry-pick。
#   多个编号可以写成 1,2,3 或 1 2 3（等价，可混用）；链接里自动取编号；
#   Change-Id 会先在 gerrit 上展开成它的所有提交，打表后逐个询问。
#   -p <n> 指定 patchset（默认当前那个）；-y 全打不问；-n 全跳过。
ggcp () {
    local assume= ps_all= item number patchset rc=0 revision ref branch url
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)      assume=yes; shift ;;
            -n|--no)       assume=no;  shift ;;
            -p|--patchset) ps_all=$2; shift 2 ;;
            --patchset=*)  ps_all=${1#*=}; shift ;;
            -h|--help)     _gr_ggcp_usage; return 0 ;;
            --)            shift; break ;;
            -*)            echo "ggcp: 不认识的选项 '$1'" >&2; _gr_ggcp_usage; return 2 ;;
            *)             break ;;
        esac
    done
    if [[ $# -lt 1 ]]; then
        _gr_ggcp_usage
        return 2
    fi
    if [[ -n ${ps_all} && ! ${ps_all} == <-> ]]; then
        echo "ggcp: patchset '${ps_all}' 不是数字" >&2
        return 2
    fi

    _gr_collect_args "$@" || return $?
    if (( ${#_GGCP_ITEMS} == 0 && ${#_GGCP_IDS} == 0 )); then
        _gr_ggcp_usage
        return 2
    fi
    if ! _gerrit_resolve; then
        _gr_fail_table '不知道 gerrit 服务器在哪'
        return 1
    fi

    # Change-Id 那条路：先在 gerrit 上展开成"编号 + patchset"，问过之后
    # 追进 _GGCP_ITEMS —— 于是所有入口都坍缩成"按编号打补丁"。
    if (( ${#_GGCP_IDS} )); then
        if ! _gr_expand_changeids ${assume}; then
            _gr_fail_table 'Change-Id 展开失败'
            return 1
        fi
    fi

    if (( ${#_GGCP_ITEMS} == 0 )); then
        print -r -- "ggcp: 没有要打的补丁"
        return 0
    fi

    local work
    work=$(mktemp -d "${TMPDIR:-/tmp}/ggcp.XXXXXX") || {
        echo "ggcp: 建不了临时目录" >&2
        return 1
    }
    local -a qpids rpids
    local item_count=0 i gid g=0 project rel gidx sortkey

    # ---- 阶段 1：每个补丁一条查询，全部并行（结果各写各的文件，互不穿插）----
    for item in ${_GGCP_ITEMS}; do
        number=${item%%|*}
        patchset=${item#*|}
        [[ -n ${ps_all} ]] && patchset=${ps_all}
        item_count=$(( item_count + 1 ))
        i=${item_count}
        printf '%s\t%s\n' "${number}" "${patchset}" > "${work}/req.${i}"
        ( _gr_query_one "${number}" "${patchset}" > "${work}/out.${i}" 2> "${work}/err.${i}" ) < /dev/null &
        qpids+=($!)
    done
    for i in ${qpids}; do
        wait ${i} 2>/dev/null || true
    done

    # ---- 阶段 2：按项目分组（同一个项目 = 同一个仓库，串行；项目之间并行）----
    : > "${work}/seen"
    : > "${work}/groups"
    for (( i = 1; i <= item_count; i++ )); do
        [[ -s "${work}/out.${i}" ]] || continue
        IFS=$'\t' read -r number patchset revision ref project branch url rel < "${work}/out.${i}"
        [[ -z ${project} ]] && project='-'
        if ! grep -Fxq -- "${project}" "${work}/seen"; then
            g=$(( g + 1 ))
            print -r -- "${project}" >> "${work}/seen"
            print -r -- "${g}"$'\t'"${project}" >> "${work}/groups"
        fi
        gid=$(awk -F '\t' -v p="${project}" '$2 == p { print $1; exit }' "${work}/groups")
        cat "${work}/out.${i}" >> "${work}/g.${gid}.spec"
    done

    # 仓库之间按本地路径排序（稳定、可读；路径拿不到就按项目名）
    : > "${work}/order"
    while IFS=$'\t' read -r gidx project; do
        rel=$(cut -f8 "${work}/g.${gidx}.spec" | head -n 1)
        if [[ -z ${rel} || ${rel} == '-' ]]; then
            sortkey=${project}
        else
            sortkey=${rel}
        fi
        print -r -- "${sortkey}"$'\t'"${gidx}"$'\t'"${project}" >> "${work}/order"
    done < "${work}/groups"
    LC_ALL=C sort -t $'\t' -k1,1 "${work}/order" > "${work}/order.sorted"

    # 每个仓库一个后台任务：仓库内部串行，仓库之间并行
    while IFS=$'\t' read -r sortkey gid project; do
        ( _gr_repo_batch "${project}" "${work}/g.${gid}.spec" "${work}/rows.${gid}" ) < /dev/null &
        rpids+=($!)
    done < "${work}/order.sorted"
    for i in ${rpids}; do
        wait ${i} 2>/dev/null || true
    done

    # 各仓库都结束后才合并结果：先按仓库分组，查询失败的排在最后
    : > "${work}/rows.all"
    while IFS=$'\t' read -r sortkey gid project; do
        [[ -f "${work}/rows.${gid}" ]] && cat "${work}/rows.${gid}" >> "${work}/rows.all"
    done < "${work}/order.sorted"
    local reason
    for (( i = 1; i <= item_count; i++ )); do
        [[ -s "${work}/out.${i}" ]] && continue
        IFS=$'\t' read -r number patchset < "${work}/req.${i}"
        [[ -z ${patchset} ]] && patchset='-'
        reason=$(_gr_first_line "$(cat "${work}/err.${i}" 2>/dev/null)")
        [[ -z ${reason} ]] && reason='查询失败'
        reason=${reason//$'\t'/ }
        print -r -- '-'$'\t-'$'\t-'$'\t'"${patchset}"$'\t'"查询失败：${reason}" >> "${work}/rows.all"
    done

    _gr_result_table "${work}/rows.all" "${g}" "${item_count}"
    rc=$?
    rm -rf "${work}"
    return ${rc}
}

# ggco <分支|tag|commit>
#   把远端的一个 ref 抓下来，然后**直接切过去**（ggcp 是抓下来 cherry-pick，这条不动提交历史）。
#   远端用和 ggcp 同一套：polygerrit -> 清单里声明的 remote -> 第一条 remote。
#   本地已经有同名分支时**不 reset 它**：切过去比一下，和刚 fetch 的对不上就报出来。
ggco () {
    if [[ $# -ne 1 || $1 == -* ]]; then
        echo "Usage: ggco <分支|tag|commit>" >&2
        echo "  ggco main         # 切到远端 main（本地没有就建跟踪分支）" >&2
        echo "  ggco v1.2.3       # 切到 tag（detached HEAD）" >&2
        echo "  ggco 1a2b3c4      # 切到某个 commit（远端得允许按 SHA 取）" >&2
        return 2
    fi
    local ref=$1
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "ggco: 当前目录不是 git 仓库" >&2
        return 1
    fi

    local dirty
    dirty=$(git status --porcelain --untracked-files=no 2>/dev/null)
    if [[ -n ${dirty} ]]; then
        echo "ggco: 工作树有本地改动，先 git stash 或 git commit（本命令不覆盖本地改动）：" >&2
        print -r -- ${dirty} >&2
        return 1
    fi

    local remote
    if ! remote=$(_gerrit_project_remote); then
        echo "ggco: 在 $(pwd) 里找不到可用的 git remote。现有的：" >&2
        git remote -v >&2
        return 1
    fi

    local want
    if ! git fetch ${remote} ${ref}; then
        echo "ggco: 远端没有这个 ref（或取不到）：${remote} ${ref}" >&2
        echo "      看看远端有什么：git ls-remote --heads --tags ${remote}" >&2
        return 1
    fi
    if ! want=$(git rev-parse --verify 'FETCH_HEAD^{commit}' 2>/dev/null); then
        echo "ggco: ${remote} 的 ${ref} 取下来不是 commit，切不过去" >&2
        return 1
    fi

    local head branch
    if git show-ref --verify --quiet "refs/heads/${ref}"; then
        git checkout ${ref} || return 1
        head=$(git rev-parse HEAD)
        if [[ ${head} != ${want} ]]; then
            echo "ggco: 本地分支 ${ref} 停在 ${head}，不是刚 fetch 的 ${want}" >&2
            echo "      本命令不 reset 本地分支；要更新就自己 git merge --ff-only FETCH_HEAD" >&2
            return 1
        fi
    else
        if ! git checkout ${ref}; then
            echo "ggco: git checkout ${ref} 失败（远端有这个 ref 吗？本地有同名文件挡着？）" >&2
            return 1
        fi
        head=$(git rev-parse HEAD)
    fi

    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    [[ ${branch} == HEAD ]] && branch=detached
    echo "ggco: $(pwd) 现在在 ${branch} @ $(git rev-parse --short HEAD)（来自 ${remote} ${ref}）"
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
    # Change-Id 直接查出来的可能是好几个 change，这时不给编号（取第一个）
    local -a cargs
    cargs=(check)
    [[ -z ${_GERRIT_CHANGEID} ]] && cargs+=(${change})
    print -r -- ${json} | python3 ${WTOOL_GERRIT_TOOL} ${cargs}
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
