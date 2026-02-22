rs_cur () {
    repo sync --force-sync -d -c $(repo manifest | rg --pcre2 "(?<=path=\")${$(pwd)#$(css)/}[^\"]+(?=\")" | rg --pcre2 -o "(?<=name=\")[^\"]+?(?=\")" ) -j123 2>&1 |tee $(pwd)/rs_cur.log
}

rs () {
    tmp_xml=$(mktemp).xml
    repo manifest -o ${tmp_xml}
    # TODO:后续要把 repo manifest -Ro 实现，创造自己的repo仓
    repo sync -c -j$(grep 'processor' /proc/cpuinfo | wc -l) --force-sync --force-checkout -d -m ${tmp_xml}
}

cdd () {
    if [[ $# -lt 1 || $# -gt 1 ]]; then
        echo "Usage: cdd TARGET" >&2
        return -1
    fi
    # 如果有一个参数
    ## 首先判断参数是不是一个路径或者文件
    if [[ -e $1 ]]; then
        if [[ -f $1 ]]; then
            cd $(dirname $1)
            return 0
        elif [[ -d $1 ]]; then
            cd $1
            return 0
        fi
    fi
    ## 然后判断当前是否在repo仓库中，判断参数是否对应一个仓库名或者仓库对应的路径
    ## 是则直接跳到对应的仓库路径下，不是则return 1
    target=$1
    if [[ -n $(css) ]]; then
        p=$(repo manifest 2>/dev/null | grep "path=\"${target}\"")
        if [[ -n ${p} ]]; then
            cs; cd ${target}
            return 0
        fi
        n=$(repo manifest 2>/dev/null | grep "name=\"${target}\"")
        if [[ -n ${n} ]]; then
            p=$(repo manifest 2>/dev/null | grep "${target}" | sed -nE 's#.*path="([^"]+)".*$#\1#p')
            if [[ -n ${p} ]]; then
                cs; cd ${p}
                return 0
            else
                cs; cd ${n}
                return 0
            fi
        fi
    fi
    return -1
}
cur_dir=$(get_this_dir)
REPO_QUERY_PY="${cur_dir}/my_repo.py"

# 1. 根据路径拿名字
repo_mfst_get_name_from_path() {
    local rel=${$(ctt)#$(css)/}
    $REPO_QUERY_PY name_from_path "$rel" --root "$(css)"
}

# 2. 根据名字拿路径
repo_mfst_get_path_from_name() {
    $REPO_QUERY_PY path_from_name "$1" --root "$(css)"
}

# 3. 根据路径拿分支 (最核心的同步逻辑)
repo_mfst_get_branch_from_path() {
    local rel=${$(ctt)#$(css)/}
    $REPO_QUERY_PY branch_from_path "$rel" --root "$(css)"
}

# 4. 根据名字拿分支
repo_mfst_get_branch_from_name() {
    $REPO_QUERY_PY branch_from_name "$1" --root "$(css)"
}

# 5. 根据名字拿remote
repo_mfst_get_remote_from_name() {
    $REPO_QUERY_PY remote_from_name "$1" --root "$(css)"
}

# 6. 根据路径拿remote
repo_mfst_get_remote_from_path() {
    $REPO_QUERY_PY remote_from_path "$1" --root "$(css)"
}

cs ()
{
    dir=$(_up_to_have_dir .repo)
    if [[ $? -eq 0 ]]; then
        cd ${dir}
        return 0
    fi
    echo "not in repo dir!!!"
    return 1
}

css ()
{
    dir=$(_up_to_have_dir .repo)
    if [[ $? -eq 0 ]]; then
        echo ${dir}
        return 0
    fi
    echo "not in repo dir!!!"
    return 1
}

ct ()
{
    dir=$(_up_to_have_dir .git)
    if [[ $? -eq 0 ]]; then
        cd ${dir}
        return 0
    fi
    echo "not in git dir!!!"
    return 1
}

ctt ()
{
    dir=$(_up_to_have_dir .git)
    if [[ $? -eq 0 ]]; then
        echo ${dir}
        return 0
    fi
    echo "not in git dir!!!"
    return 1
}

cnp ()
{
    dir=${$(ctt)#$(css)/}
    if [[ $? -eq 0 ]]; then
        echo ${dir}
        return 0
    fi
    echo "not in repo dir!!!"
    return 1
}

cnn ()
{
    repo_path=$(cnp)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    echo $(repo_mfst_get_name_from_path ${repo_path})
    return 0
}

cnb ()
{
    repo_path=$(cnp)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    echo $(repo_mfst_get_branch_from_path ${repo_path})
    return 0
}

cnr ()
{
    repo_path=$(cnp)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    echo $(repo_mfst_get_remote_from_path ${repo_path})
    return 0
}

cm ()
{
    dir=$(_up_to_have_dir .repo)
    if [[ $? -eq 0 ]]; then
        cd ${dir}/.repo/manifests
        return 0
    fi
    return 1
}

cmm ()
{
    dir=$(_up_to_have_dir .repo)
    if [[ $? -eq 0 ]]; then
        echo ${dir}/.repo/manifests
        return 0
    fi
    return 1
}

alias gb > /dev/null 2>&1 && unalias gb || true
gb ()
{
    # 从project标签中拿到project指定的branch和remote
    ctt &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo "not in repo dir!!!"
        return 1
    fi
    repo_branch=$(cnb)
    repo_remote="$(cnr)"

    echo "git push ${repo_remote} HEAD:refs/for/${repo_branch}"
    echo "git push ${repo_remote} HEAD:${repo_branch}"
    echo "git pull ${repo_remote} ${repo_branch} --unshallow"
    echo "git pull ${repo_remote} ${repo_branch}"
    echo "git fetch ${repo_remote} ${repo_branch} --unshallow"
    echo "git fetch ${repo_remote} ${repo_branch}"
    echo "remote: ${repo_remote}"
    echo "branch: ${repo_branch}"
    git remote -v
}

gfun ()
{
    gb | awk 'NR==5 {print; exit}'
}

gpun ()
{
    gb | awk 'NR==3 {print; exit}'
}

# 直接推送到远端，注意如果是在公司需要gerrit审核，这里要改成第1行的命令
gbb ()
{
    if [[ -f ./gbb ]]; then
        zsh ./gbb
    else
        cmd=$(gb | head -2 | tail -1)
        echo "${cmd}"
        eval ${cmd}
    fi
}

