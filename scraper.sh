#!/bin/bash

# Function for downloading the contents of one repository.
function download_repo_contents {
    err_echo [[ downloading repo contents ]]
    local destination=$(mktemp --directory)
    GIT_TERMINAL_PROMPT=0 git clone "https://github.com/$1/$2.git" "$destination"
    
    if [ $? -ne 0 ] 
    then
        rmdir "$destination"
        return $?   
    fi

    echo "$destination"
    return 0
}
export -f download_repo_contents

function printable_options {
    local string=""

    if echo "$@" | fgrep -q "branches"
    then
        if [ -n "$BRANCHES" ]
        then
            string="${string}all branches"
        else
            string="${string}master branch"
        fi
    fi

    if echo "$@" | fgrep -q "renames"
    then
        if [ -n "${string}" ]
        then
            string="${string}, "
        fi

        if [ -z "$RENAMES" ]
        then
            string="${string}follow renames"
        else
            string="${string}do not follow renames"
        fi
    fi

    if [ -n "${string}" ]
    then
        echo -n "(${string})"
    fi
}
export -f printable_options

# Functions for retrieving specific bits of information form one repository.
function retrieve_commit_metadata {
    err_echo [[ retrieving commit metadata `printable_options branches` ]]
    git log --pretty=format:'%H%n%ae%n%at%n%ce%n%ct%n%D%n🐹%n%n' $BRANCHES | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/metadata.awk"
}
export -f retrieve_commit_metadata

function retrieve_commit_file_modification_info {
    err_echo [[ retrieving commit file modification info `printable_options branches renames` ]]
    git log --format="%n%n%H"  --numstat --raw $BRANCHES -M -C $RENAMES | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/numstat.awk"
}
export -f retrieve_commit_file_modification_info

function retrieve_commit_file_modification_hashes {
    err_echo [[ retrieving commit file modification hashes `printable_options branches renames` ]]
    git log --format="%n%n%H" --raw --no-abbrev $BRANCHES -M -C -m $RENAMES | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/raw.awk"
}
export -f retrieve_commit_file_modification_hashes

function retrieve_commit_comments {
    err_echo [[ retrieving commit messages `printable_options branches` ]]
    git log --pretty=format:"🐹 %H%n%B"  $BRANCHES | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/comment.awk"
}
export -f retrieve_commit_comments

function retrieve_commit_parents {
    err_echo [[ retrieving commit parents `printable_options branches` ]]
    git log --pretty=format:"%H %P" $BRANCHES | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/parents.awk"
}
export -f retrieve_commit_parents

function retrieve_commit_repositories {
    err_echo [[ retrieving commit repositories `printable_options branches` ]]
    echo '"hash","id"'
    git log --pretty=format:"\"%H\",$1" $BRANCHES
}
export -f retrieve_commit_repositories

function retrieve_repository_info {
    err_echo [[ retrieving repository info ]]
    echo '"id","user","project"'
    echo "${3},\"${1}\",\"${2}\""
}
export -f retrieve_repository_info

function retrieve_submodule_history {
    err_echo [[ retrieving submodule history `printable_options branches` ]]
    git log --format="%n%n%H" --full-history --no-abbrev --raw $BRANCHES -M -C -m -- .gitmodules | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -v OFS=, -v header=1 -f "${GHGRABBER_HOME}/awk/submodules.awk" 
}
export -f retrieve_submodule_history

function make_submodule_museum {
    err_echo [[ creating submodule museum `printable_options branches` ]]
    git log --format="%n%n%H" --full-history --no-abbrev --raw $BRANCHES -M -C -m -- .gitmodules | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/submodules.awk" | \
    while read commit file
    do
        #echo commit: $commit
        #echo file: $file
        if [ "$file" == 0000000000000000000000000000000000000000 ]
        then
            echo "" > "$1/$commit"
        else
            filename="$1/$commit"
            while [ -e "$filename" ]
            do
                filename="${filename}_"
            done            
            git cat-file -p "$file" > "$filename"
        fi
    done
}
export -f make_submodule_museum

function prepare_directories {
    sorting_dir="$1"
    repo_encoding="$2"

    [ ${MODULES[commit_metadata]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/commit_metadata/" "$sorting_dir")"

    [ ${MODULES[commit_file_modification_info]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/commit_files/" "$sorting_dir")"

    [ ${MODULES[commit_file_modification_hashes]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/commit_file_hashes/" "$sorting_dir")"

    [ ${MODULES[commit_comments]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/commit_comments/" "$sorting_dir")"

    [ ${MODULES[commit_parents]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/commit_parents/" "$sorting_dir")"

    [ ${MODULES[commit_repositories]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/commit_repositories/" "$sorting_dir")"

    [ ${MODULES[repository_info]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/repository_info/" "$sorting_dir")"

    [ ${MODULES[submodule_history]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/submodule_history/" "$sorting_dir")"

    [ ${MODULES[submodule_museum]+isset} ] && \
        mkdir -p "$(make_path "$OUTPUT_DIR/submodule_museum/" "$sorting_dir" "$repo_encoding")"
}
export -f prepare_directories

function make_path {
    local directory="$1"
    local sorting_dir="$2"
    shift 2
    local tail=$(IFS='/'; echo "$*")

    if $USE_SORTING_DIR
    then
        echo "${directory}/${sorting_dir}/${tail}"
    else
        echo "${directory}/${tail}"
    fi
}
export -f make_path

function retrieve_data {
    local sorting_dir="$1"
    local filename="$2"
    local user="$2"
    local project="$3"

    [ ${MODULES[commit_metadata]+isset} ] && \
        retrieve_commit_metadata > \
        "$(make_path "$OUTPUT_DIR/commit_metadata" "$sorting_dir" "$filename")"

    [ ${MODULES[commit_file_modification_info]+isset} ] && \
        retrieve_commit_file_modification_info > \
        "$(make_path "$OUTPUT_DIR/commit_files" "$sorting_dir" "$filename")"

    [ ${MODULES[commit_file_modification_hashes]+isset} ] && \
        retrieve_commit_file_modification_hashes > \
        "$(make_path "$OUTPUT_DIR/commit_file_hashes" "$sorting_dir" "$filename")"
    
    [ ${MODULES[commit_comments]+isset} ] && \
        retrieve_commit_comments > \
        "$(make_path "$OUTPUT_DIR/commit_comments" "$sorting_dir" "$filename")"

    [ ${MODULES[commit_parents]+isset} ] && \
        retrieve_commit_parents > \
        "$(make_path "$OUTPUT_DIR/commit_parents" "$sorting_dir" "$filename")"

    [ ${MODULES[commit_repositories]+isset} ] && \
        retrieve_commit_repositories $i > \
        "$(make_path "$OUTPUT_DIR/commit_repositories" "$sorting_dir" "$filename")"

    [ ${MODULES[repository_info]+isset} ] && \
        retrieve_repository_info $user $repo $i > \
        "$(make_path "$OUTPUT_DIR/repository_info" "$sorting_dir" "$filename")"

    [ ${MODULES[submodule_history]+isset} ] && \
        retrieve_submodule_history > \
        "$(make_path "$OUTPUT_DIR/submodule_history" "$sorting_dir" "$filename")"

    [ ${MODULES[submodule_museum]+isset} ] && \
        make_submodule_museum \
        "$(make_path "$OUTPUT_DIR/submodule_museum" "$sorting_dir" "${user}_${project}")"
}
export -f retrieve_data

function retrieve_repository_stats {
    local filename="${1}_${2}.csv"
    local sorting_dir="$(expr substr ${1} 1 3)"
    if [ -d "$OUTPUT_DIR/commit_file_hashes/" ]
    then 
        local number_of_files=$( \
            < "$(make_path "$OUTPUT_DIR/commit_file_hashes" "$sorting_dir" "$filename")" \
            wc -l 2>/dev/null )
    else
        local number_of_files=?
    fi

    if [ -d "$OUTPUT_DIR/commit_metadata/" ]
    then
        local number_of_commits=$( \
            < "$(make_path "$OUTPUT_DIR/commit_metadata" "$sorting_dir" "$filename")" \
            wc -l 2>/dev/null )
    else
        local number_of_commits=?
    fi
    local repository_size=$(du -s . | cut -f 1)
    echo -n "${number_of_files},${number_of_commits},${repository_size}"
}
export -f retrieve_repository_stats

# Scrape one repository using the functions above.
function process_repository {
    local user="$1"
    local project="$2"
    local i="$3"
    local sorting_dir="$(expr substr $user 1 3)"

    local filename="${user}_${project}.csv"

    local repository_path="$(download_repo_contents $user $project)"
    if [ -z "$repository_path" ]
    then
        err_echo [[ did not retreive repository for $user/$project, exiting ]]
        return 1
    fi

    cd "${repository_path}"
    prepare_directories "${sorting_dir}" "${user}_${project}"
    retrieve_data "${sorting_dir}" "${filename}" "${user}" "${project}"

    if [ -d "$OUTPUT_DIR/commit_file_hashes" ]
    then
        number_of_files=$(< "$(make_path "$OUTPUT_DIR/commit_file_hashes" "$sorting_dir" "$filename")" wc -l)
    else
        number_of_files=?
    fi

    if [ -d "$OUTPUT_DIR/commit_metadata" ]
    then
        number_of_commits=$(< "$(make_path "$OUTPUT_DIR/commit_metadata" "$sorting_dir" "$filename")" wc -l)
    else
        number_of_commits=?
    fi

    repository_size=$(du -s . | cut -f 1)

    cd "$GHGRABBER_HOME"

    if [ -n ${repository_path} ]
    then
        if expr ${repository_path} : '/tmp/tmp\...........' >/dev/null
        then
            echo "Removing '${repository_path}'"
            rm -rf "${repository_path}"
        fi
    fi
    return 0
}
export -f process_repository

# process a single repository that already lives in the filesystem,
# a simplification of the function above
function process_predownloaded_repository {
    local user="$1"
    local project="$2"
    local repository_path="$3"
    local sorting_dir="$(expr substr $user 1 3)"
    local filename="${user}_${project}.csv"

    cd "${repository_path}"
    prepare_directories "${sorting_dir}" "${user}_${project}"
    retrieve_data "${sorting_dir}" "${filename}" "${user}" "${project}"

    if [ -d "$OUTPUT_DIR/commit_file_hashes" ]
    then
        number_of_files=$(< "$(make_path "$OUTPUT_DIR/commit_file_hashes" "$sorting_dir" "$filename")" wc -l)
    else
        number_of_files=?
    fi

    if [ -d "$OUTPUT_DIR/commit_metadata" ]
    then
        number_of_commits=$(< "$(make_path "$OUTPUT_DIR/commit_metadata" "$sorting_dir" "$filename")" wc -l)
    else
        number_of_commits=?
    fi

    return 0
}
export -f process_predownloaded_repository 

# Pre-process arguments and start processing a single repository.
function download_and_analyze_repository {

    declare -A MODULES
    for module in `echo $MODULE_LIST | tr , ' '`
    do
        MODULES["$module"]=1
    done

    err_echo [[ starting new task ]]

    local processed=$(sem --id ghgrabber_sequence sequence_next_value "$SEQUENCE")
    local info="$1"

    ECHO_PREFIX="task ${processed}: $info"
    
    err_echo [[ processing $processed: $info "(pid=$$)" ]]

    if [ -e "STOP" ]
    then
        echo [[ detected STOP file, stopping ]]
        exit 1
    fi

    user=$(echo $info | cut -f1 -d/)
    repo=$(echo $info | cut -f2 -d/)

    number_of_files=0
    number_of_commits=0
    repository_size=0
    
    local start_time=$(timing_start)

    process_repository "$user" "$repo" "$processed"

    local status=$?
    local end_time=$(timing_end)

    sem --id ghgrabber_timing \
    timing_output "$OUTPUT_DIR/timing.csv" \
        "$processed" "$user" "$repo" \
        "$start_time" "$end_time" \
        "$status" \
        "$number_of_files" "$number_of_commits" "$repository_size" 

    err_echo [[ done with status $status ]]
    return 0
}
export -f download_and_analyze_repository

# pre-process arguments and start processing a single repository,
# that was already downloaded and lives on the filesystem,
# this is a simplification of the function above
function analyze_predownloaded_repository {
    local user="$1"
    local project="$2"
    local repository_path="$3"

    declare -A MODULES
    for module in `echo $MODULE_LIST | tr , ' '`
    do
        MODULES["$module"]=1
    done

    err_echo [[ starting new task ]]
    err_echo [[ processing "$user/$project" at "$repository_path" ]]

    process_predownloaded_repository "$user" "$project" "$repository_path"

    local status=$?
    err_echo [[ done with status $status ]]  
    return 0
}
export -f analyze_predownloaded_repository
