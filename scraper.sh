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

# Functions for retrieving specific bits of information form one repository.
function retrieve_commit_metadata {
    err_echo [[ retrieving commit metadata ]]
    git log --pretty=format:'%H%n%ae%n%at%n%ce%n%ct%n%D%n🐹%n%n' --all | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/metadata.awk"
}
export -f retrieve_commit_metadata

function retrieve_commit_file_modification_info {
    err_echo [[ retrieving commit file modification info ]]
    git log --pretty=format:-----%H:::  --numstat --all -M -C | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/numstat.awk"
}
export -f retrieve_commit_file_modification_info

function retrieve_commit_file_modification_hashes {
    err_echo [[ retrieving commit file modification hashes ]]
    git log --format="%n%n%H" --raw --no-abbrev --all -M -C -m | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/raw.awk"
}
export -f retrieve_commit_file_modification_hashes

function retrieve_commit_comments {
    err_echo [[ retrieving commit messages ]]
    git log --pretty=format:"🐹 %H%n%B"  --all | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/comment.awk"
}
export -f retrieve_commit_comments

function retrieve_commit_parents {
    err_echo [[ retrieving commit parents ]]
    git log --pretty=format:"%H %P" --all | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/parents.awk"
}
export -f retrieve_commit_parents

function retrieve_commit_repositories {
    err_echo [[ retrieving commit repositories ]]
    echo '"hash","id"'
    git log --pretty=format:"\"%H\",$1" --all
}
export -f retrieve_commit_repositories

function retrieve_repository_info {
    err_echo [[ retrieving repository info ]]
    echo '"id","user","project"'
    echo "${3},\"${1}\",\"${2}\""
}
export -f retrieve_repository_info

function retrieve_submodule_history {
    err_echo [[ retrieving submodule history ]]
    git log --format="%n%n%H" --full-history --no-abbrev --raw --all -M -C -m -- .gitmodules | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -v OFS=, -v header=1 -f "${GHGRABBER_HOME}/awk/submodules.awk" 
}
export -f retrieve_submodule_history

function make_submodule_museum {
    err_echo [[ creating submodule museum ]]
    git log --format="%n%n%H" --full-history --no-abbrev --raw --all -M -C -m -- .gitmodules | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/submodules.awk" | \
    while read commit file
    do
        echo commit: $commit
        echo file: $file
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
    repo="$2"

    mkdir -p "$OUTPUT_DIR/commit_metadata/$sorting_dir"
    #mkdir -p "$OUTPUT_DIR/commit_files/$sorting_dir"
    mkdir -p "$OUTPUT_DIR/commit_file_hashes/$sorting_dir"
    mkdir -p "$OUTPUT_DIR/commit_comments/$sorting_dir"
    mkdir -p "$OUTPUT_DIR/commit_parents/$sorting_dir"
    #mkdir -p "$OUTPUT_DIR/commit_repositories/$sorting_dir"
    #mkdir -p "$OUTPUT_DIR/repository_info/$sorting_dir"
    #mkdir -p "$OUTPUT_DIR/submodule_history/$sorting_dir"
    mkdir -p "$OUTPUT_DIR/submodule_museum/$1/$2"
}
export -f prepare_directories

function retrieve_data {
    sorting_dir="$1"
    filename="$2"
    user="$2"
    project="$3"
    

    retrieve_commit_metadata                 > "$OUTPUT_DIR/commit_metadata/$sorting_dir/${filename}"
    #retrieve_commit_file_modification_info   > "$OUTPUT_DIR/commit_files/$sorting_dir/${filename}"
    retrieve_commit_file_modification_hashes > "$OUTPUT_DIR/commit_file_hashes/$sorting_dir/${filename}"
    retrieve_commit_comments                 > "$OUTPUT_DIR/commit_comments/$sorting_dir/${filename}"
    retrieve_commit_parents                  > "$OUTPUT_DIR/commit_parents/$sorting_dir/${filename}"
    #retrieve_commit_repositories $i          > "$OUTPUT_DIR/commit_repositories/$sorting_dir/${filename}"
    #retrieve_repository_info $user $repo $i  > "$OUTPUT_DIR/repository_info/$sorting_dir/${filename}"
    #retrieve_submodule_history               > "$OUTPUT_DIR/submodule_history/$sorting_dir/${filename}"

    make_submodule_museum "$OUTPUT_DIR/submodule_museum/$sorting_dir/${user}_${project}/"
}
export -f retrieve_data

function retrieve_repository_stats {
    local filename="${1}_${2}.csv"
    local sorting_dir="$(expr substr ${1} 1 3)"
    local number_of_files=$(< "$OUTPUT_DIR/commit_file_hashes/$sorting_dir/${filename}" wc -l 2>/dev/null || )
    local number_of_commits=$(< "$OUTPUT_DIR/commit_metadata/$sorting_dir/${filename}" wc -l 2>/dev/null )
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

#     retrieve_commit_metadata                 > "$OUTPUT_DIR/commit_metadata/$sorting_dir/${filename}"
#     #retrieve_commit_file_modification_info   > "$OUTPUT_DIR/commit_files/$sorting_dir/${filename}"
#     retrieve_commit_file_modification_hashes > "$OUTPUT_DIR/commit_file_hashes/$sorting_dir/${filename}"
#     retrieve_commit_comments                 > "$OUTPUT_DIR/commit_comments/$sorting_dir/${filename}"
#     retrieve_commit_parents                  > "$OUTPUT_DIR/commit_parents/$sorting_dir/${filename}"
#     #retrieve_commit_repositories $i          > "$OUTPUT_DIR/commit_repositories/$sorting_dir/${filename}"
#     #retrieve_repository_info $user $repo $i  > "$OUTPUT_DIR/repository_info/$sorting_dir/${filename}"
#     #retrieve_submodule_history               > "$OUTPUT_DIR/submodule_history/$sorting_dir/${filename}"
#     make_submodule_museum "$OUTPUT_DIR/submodule_museum/$sorting_dir/${user}_${project}/"

    number_of_files=$(< "$OUTPUT_DIR/commit_file_hashes/$sorting_dir/${filename}" wc -l)
    number_of_commits=$(< "$OUTPUT_DIR/commit_metadata/$sorting_dir/${filename}" wc -l)
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

function retrieve_repository_stats {
    local filename="${1}_${2}.csv"
    local sorting_dir="$(expr substr ${1} 1 3)"
    local number_of_files=$(< "$OUTPUT_DIR/commit_file_hashes/$sorting_dir/${filename}" wc -l 2>/dev/null || )
    local number_of_commits=$(< "$OUTPUT_DIR/commit_metadata/$sorting_dir/${filename}" wc -l 2>/dev/null )
    local repository_size=$(du -s . | cut -f 1)
    echo -n "${number_of_files},${number_of_commits},${repository_size}"
}
export -f retrieve_repository_stats

# Pre-process arguments and start processing a single repository.
function download_and_analyze_repository {

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

    err_echo [[ done with status $? ]]
    return 0
}
export -f download_and_analyze_repository
