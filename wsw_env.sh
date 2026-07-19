export WSW_ANDROID_DIR=$(get_this_dir)

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

cnp ()
{
    local dir ctt_dir css_dir
    {
        ctt_dir=$(ctt) &&
        css_dir=$(css)
    } || {
        echo "${funcstack[1]}: not in git dir!!!" >&2
        return 1
    }
    dir=${${ctt_dir}##${css_dir}/}
    {
        ${WSW_ANDROID_DIR}/my_repo.py name_from_path ${dir} --root ${css_dir} &>/dev/null;
    } || {
        echo "${funcstack[1]}: ${WSW_ANDROID_DIR}/my_repo.py: no project with path:'${dir}' in your manifests!!!" >&2
        return 1
    }
    echo ${dir}
    return 0
}

cnn() {
    local cnp_dir css_dir
    {
        css_dir=$(css) &&
        cnp_dir=$(cnp)
    } || {
        echo "${funcstack[1]}: not in git dir!!!" >&2
        return 1
    }
    {
        ${WSW_ANDROID_DIR}/my_repo.py name_from_path ${cnp_dir} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: ${WSW_ANDROID_DIR}/my_repo.py: no project with path:'${cnp_dir}' in your manifests!!!" >&2
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
        ${WSW_ANDROID_DIR}/my_repo.py name_from_path ${repo_path} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: ${WSW_ANDROID_DIR}/my_repo.py: no project with path:'${repo_path}' in your manifests!!!" >&2
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
        ${WSW_ANDROID_DIR}/my_repo.py path_from_name ${repo_name} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: ${WSW_ANDROID_DIR}/my_repo.py: no project with name:'${repo_name}' in your manifests!!!" >&2
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
        ${WSW_ANDROID_DIR}/my_repo.py branch_from_path ${repo_path} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: ${WSW_ANDROID_DIR}/my_repo.py: no project with path:'${repo_path}' in your manifests!!!" >&2
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
        ${WSW_ANDROID_DIR}/my_repo.py branch_from_name ${repo_name} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: ${WSW_ANDROID_DIR}/my_repo.py: no project with name:'${repo_name}' in your manifests!!!" >&2
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
        ${WSW_ANDROID_DIR}/my_repo.py remote_from_name ${repo_name} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: ${WSW_ANDROID_DIR}/my_repo.py: no project with name:'${repo_name}' in your manifests!!!" >&2
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
        ${WSW_ANDROID_DIR}/my_repo.py remote_from_path ${repo_path} --root ${css_dir}
    } || {
        echo "${funcstack[1]}: ${WSW_ANDROID_DIR}/my_repo.py: no project with path:'${repo_path}' in your manifests!!!" >&2
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

# only used by zsh
cdd () {
    if [[ $# -ne 1 ]]; then
        echo "Usage: cdd TARGET" >&2
        return 1
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
    # for now, target might be a a repo name or path
    # use repo manifest parser to transform it to abs path
    local repo_path repo_name css_dir repo_abs_path
    {
        css_dir=$(css) &&
        { repo_path=$(repo_mfst_get_path_from_name ${target}) ||
            { repo_name=$(repo_mfst_get_name_from_path ${target}) && repo_path=${target}; }
        }
    } && {
        repo_abs_path=${css_dir}/${repo_path}
        [[ -d ${repo_abs_path} ]] && cd ${repo_abs_path} && return 0;
    }
    echo "${funcstack[1]}: not in repo dir!!!" >&2
    return -1
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
