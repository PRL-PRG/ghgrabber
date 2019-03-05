#!/bin/bash

# Timing helper functions
function timing_init   { 
    echo "\"$1\",\"$2\",\"time\",\"status\"" > "$3"; 
}
function timing_start  { date +%s; }
function timing_end    { date +%s; }
function timing_print  {
    local time="$1"

    local hours=$((time/60/60))
    local minutes=$(((time/60)%60))
    local seconds=$((time%60))

    local sec_extra_zero=`((seconds > 9)) && echo -n "" || echo -n 0`
    local min_extra_zero=`((minutes > 9)) && echo -n "" || echo -n 0`

    echo ${hours}:${min_extra_zero}${minutes}:${sec_extra_zero}${seconds}
}
function timing_output { 
    echo "\"${1}\"","\"${2}\"",$(timing_print $((${4} - ${3}))),${5} \
        >> "$6"
}

# Misc. auxiliary functions.
function escape_quotes {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
function err_echo {
    if [ -n "$ECHO_PREFIX" ]
    then
       echo "[ $ECHO_PREFIX ]" $@ >&2 
    else
        echo $@ >&2
    fi
}
function use_first_if_available {
    [ -n "$1" ] && echo "$1" || echo "$2"
}

# Sequence control.
function sequence_new {
    if [ -z "$2" ]
    then
        value=0
    else
        value="$2"
    fi

    if [ -e "$1" ]
    then
        echo "File '$1' already exists:" >&2
        echo "  - not creating a new sequence" >&2
        echo "  - not resetting current value" >&2
        echo "  - current value is '$(cat $1)'" >&2
        return 1
    else
        echo -n "$value" > "$1" 
        return 0
    fi
}
function sequence_current_value {
    if [ -e "$1" ]
    then
        cat "$1"
        return $?
    else
        echo "File '$1' does not exist" >&2
        echo "  - returning 0, but this is a fake value" >&2
        echo -n 0
        return 1
    fi
}
function sequence_next_value {
    current_value=$(sequence_current_value "$1")
   
    if [ $? -ne 0 ]
    then
        return $?
    fi

    next_value=$(( $current_value + 1 ))

    if [ -z "$next_value" ]
    then
        echo "Sequence value is weird" >&2
        echo "  - new value is supposed to be '$next_value'" >&2
        echo "  - old value was read as '$next_value'" >&2
        echo "  - returning 0, but this is a fake value" >&2
        echo -n 0
        return 1
    fi

    echo -n $next_value
    echo -n $next_value > "$1" 
    return $?
}

# Toplevel functions that set up the scraper.
function prepare_globals {
    export REPOS_LIST=`use_first_if_available "$1" "repos.list"`
    export OUTPUT_DIR=`use_first_if_available "$2" "data"`
    export GHGRABBER_HOME="$(pwd)"
    
    PROCESSES=`use_first_if_available "$3" 1`
    ECHO_PREFIX=main

    if expr "$OUTPUT_DIR" : "^/" >/dev/null 
    then 
        :
    else 
        OUTPUT_DIR="$GHGRABBER_HOME/$OUTPUT_DIR"
    fi

    export SEQUENCE="$OUTPUT_DIR/sequence.val"
    sequence_new "$SEQUENCE" 0
}
function prepare_directories {
    mkdir -p "$OUTPUT_DIR/commit_metadata"
    #mkdir -p "$OUTPUT_DIR/commit_files"
    mkdir -p "$OUTPUT_DIR/commit_file_hashes"
    mkdir -p "$OUTPUT_DIR/commit_comments"
    mkdir -p "$OUTPUT_DIR/commit_parents"
    mkdir -p "$OUTPUT_DIR/commit_repositories"
    mkdir -p "$OUTPUT_DIR/repository_info"
}

# Function for downloading the contents of one repository.
function download_repo_contents {
    err_echo [[ downloading repo contents ]]
    local destination=$(mktemp --directory)
    GIT_TERMINAL_PROMPT=0 git clone "https://github.com/$1/$2.git" "$destination"
    
    if [ $? -ne 0 ] 
    then
        return $?   
    fi

    echo "$destination"
    return 0
}

# Functions for retrieving specific bits of information form one repository.
function retrieve_commit_metadata {
    err_echo [[ retrieving commit metadata ]]
    echo '"hash","author name","author email","author timestamp","committer name","committer email","committer timestamp","tag"'
    git log --pretty=format:'"%H","%an","%ae","%at","%cn","%ce","%ct","%s","%D"' --all 
}
function retrieve_commit_file_modification_info {
    err_echo [[ retrieving commit file modification info ]]
    echo '"hash","added lines","deleted lines","file"'
    git log --pretty=format:-----%H:::  --numstat --all | \
        awk -f "${GHGRABBER_HOME}/awk/numstat.awk"
}
function retrieve_commit_file_modification_hashes {
    err_echo [[ retrieving commit file modification hashes ]]
    echo '"hash","source file hash","current file hash","status code","file"'
    git log --format="%n%n%h" --raw --abbrev=40 --all | \
        awk -f "${GHGRABBER_HOME}/awk/raw.awk"
}
function retrieve_commit_comments {
    err_echo [[ retrieving commit messages ]]
    echo '"hash","topic","message"'
    git log --pretty=format:"-----%H:::%s:::%B"  --all | \
        awk -f "${GHGRABBER_HOME}/awk/comment.awk"
}
function retrieve_commit_parents {
    err_echo [[ retrieving commit parents ]]
    echo '"child","parent"'
    git log --pretty=format:"%H %P" | \
        awk '{for(i=2; i<=NF; i++) print "\""$1"\",\""$i"\""}'
}
function retrieve_commit_repositories {
    err_echo [[ retrieving commit repositories ]]
    echo '"hash","id"'
    git log --pretty=format:"\"%H\",$1"
}
function retrieve_repository_info {
    err_echo [[ retrieving repository info ]]
    echo '"id","user","project"'
    echo "${3},\"${1}\",\"${2}\""
}

# Scrape one repository using the functions above.
function process_repository {
    local user="$1"
    local repo="$2"
    local i="$3"

    local filename="${user}_${repo}.csv"

    local repository_path="$(download_repo_contents $user $repo)"
    if [ -z "$repository_path" ]
    then
        err_echo [[ did not retreive repository for $user/$repo, exiting ]]
        return 1
    fi

    cd "${repository_path}"

    retrieve_commit_metadata                 > "$OUTPUT_DIR/commit_metadata/${filename}"
    #retrieve_commit_file_modification_info   > "$OUTPUT_DIR/commit_files/${filename}"
    retrieve_commit_file_modification_hashes > "$OUTPUT_DIR/commit_file_hashes/${filename}"
    retrieve_commit_comments                 > "$OUTPUT_DIR/commit_comments/${filename}"
    retrieve_commit_parents                  > "$OUTPUT_DIR/commit_parents/${filename}"
    retrieve_commit_repositories $i          > "$OUTPUT_DIR/commit_repositories/${filename}"
    retrieve_repository_info $user $repo $i  > "$OUTPUT_DIR/repository_info/${filename}"

    cd "$GHGRABBER_HOME"

    if [ -n ${repository_path} ]
    then
        if expr ${repository_path} : '/tmp/tmp\...........' >/dev/null
        then
            echo "Removing '${repository_path}'"
            rm -rf "${repository_path}"
        fi
    fi
}

# Pre-process arguments and start processing a single repository.
function download_and_analyze_repository {
    local processed=$(sem --id ghgrabber_sequence sequence_next_value "$SEQUENCE")
    local info="$1"

    ECHO_PREFIX="task ${processed}: $info"

    if [ -e "STOP" ]
    then
        echo [[ detected STOP file, stopping ]]
        exit 1
    fi

    err_echo [[ processing $processed: $info "(pid=$$)" ]]

    user=$(echo $info | cut -f1 -d/)
    repo=$(echo $info | cut -f2 -d/)
    
    local start_time=$(timing_start)
    process_repository "$user" "$repo" "$processed"
    local status=$?
    local end_time=$(timing_end)

    sem --id ghgrabber_timing \
    timing_output "$user" "$repo" "$start_time" "$end_time" "$status" "$OUTPUT_DIR/timing.csv" 

    err_echo [[ done with status $? ]]
    return 0
}

# Export all the functions that parallel needs.
export -f timing_init
export -f timing_start
export -f timing_end
export -f timing_print
export -f timing_output 
export -f escape_quotes
export -f err_echo
export -f use_first_if_available
export -f prepare_globals
export -f prepare_directories
export -f download_repo_contents
export -f retrieve_commit_metadata
export -f retrieve_commit_file_modification_info
export -f retrieve_commit_file_modification_hashes
export -f retrieve_commit_comments
export -f retrieve_commit_parents
export -f retrieve_commit_repositories
export -f retrieve_repository_info
export -f process_repository
export -f download_and_analyze_repository
export -f sequence_new
export -f sequence_current_value
export -f sequence_next_value

# Main.
prepare_globals "$@"
prepare_directories
timing_init "user" "repo" "$OUTPUT_DIR/timing.csv"

echo [[ downloading repos from "'$REPOS_LIST'" to "'$OUTPUT_DIR'" using $PROCESSES processes ]]
echo [[ `< "$REPOS_LIST" wc -l` total repositories to download ]]

#<"$REPOS_LIST" parallel -v -k --ungroup --halt soon,fail=1 -j $PROCESSES download_and_analyze_repository 
<"$REPOS_LIST" parallel -v -k --ungroup -j $PROCESSES download_and_analyze_repository 
