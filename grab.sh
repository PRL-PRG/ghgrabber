#!/bin/bash

function usage {
    echo "Usage: grab.sh [OPTION]... [REPO]..."
    echo "Download specified GitHub repositories and extract specific information.       "
    echo 
    echo "Mandatory arguments to long options are mandatory for short options too.       "
    echo "  -s, --simple-output             turns off prefix-based directory structure   "
    echo "                                  in the output dir                            "
    echo "  -m, --modules=MODULES           specify a comma-separated list of modules to "
    echo "                                  run, each module extract different type of   "
    echo "                                  data:                                        "
    echo "                                    commit_metadata                            "
    echo "                                    commit_file_modification_info              "
    echo "                                    commit_file_modification_hashes            "
    echo "                                    commit_comments                            "
    echo "                                    commit_parents                             "
    echo "                                    commit_repositories                        "
    echo "                                    repository_info                            "
    echo "                                    submodule_history                          "
    echo "                                    submodule_museum                           "
    echo "  -f, --repo-list=REPO_LIST       list of repositories to download, one        "
    echo "                                  repository per line in the form:             "
    echo "                                    USER/PROJECT                               "
    echo "  -p, --processes:                number of parallel processes to use          "
    echo "  -o, --output-dir:               output directory for extracted data          "
    echo "                                                                               "
    echo "Repo list can either be provided by -f or by specyfing the repos as arguments. "
    echo "If both are provided, repos specified via file take precedence.                "
    echo "                                                                               " 
    echo "Requires GNU parallel.                                                         "
}

# Parse options
options=$(getopt -u \
    -o sm:f:p:o:h \
    --long simple-output-dirs,modules:,repo-list:,processes:,output-dir:,help \
    -n $0 -- "$@")

if [ $? != 0 ] 
then 
    echo "Argh! Parsing went pear-shaped!" >&2
    exit 1 
fi

# Defaults
export SIMPLE_OUTPUT=false
export GHGRABBER_HOME="$(pwd)"
export OUTPUT_DIR="${GHGRABBER_HOME}/data"
export PROCESSES=1
declare -A MODULES
export MODULES
MODULES[commit_metadata]=1
MODULES[commit_file_modification_info]=1
MODULES[commit_file_modification_hashes]=1
MODULES[commit_comments]=1
MODULES[commit_parents]=1
MODULES[commit_repositories]=1
MODULES[repository_info]=1
MODULES[submodule_history]=1
MODULES[submodule_museum]=1


# Analyze results of parsing options
set -- $options 
while true  
do
    echo $1
    case "$1" in 
        -s|--simple-output) 
            SIMPLE_OUTPUT=true 
            shift 1;;
        -m|--modules)
            unset MODULES
            declare -A MODULES
            export MODULES
            IFS="," read -r -a modules <<< "$2"
            for module in "${modules[@]}"
            do
                MODULES["$module"]=1
            done
            shift 2;; 
        -f|--repo-list) 
            REPOS_LIST="$2"
            if [ ! -f "$REPOS_LIST" ]
            then
                echo "'$REPOS_LIST' is not a file." >&2
                exit 4
            fi
            shift 2;; 
        -p|--processes) 
            processes="$2"
            shift 2;; 
        -o|--output-dir) 
            OUTPUT_DIR="$2"
            if expr "$OUTPUT_DIR" : "^/" >/dev/null 
            then 
                :
            else 
                OUTPUT_DIR="$GHGRABBER_HOME/$OUTPUT_DIR"
            fi
            shift 2;; 
        -h|--help) 
            usage
            exit 2;; 
        --) 
            shift
            break;; 
        *) 
            echo "Ack! She cannae take it anymore, captain!" >&2
            exit 3;;
    esac 
done

echo SIMPLE_OUTPUT=$SIMPLE_OUTPUT
echo OUTPUT_DIR=$OUTPUT_DIR
echo MODULES=${MODULES[@]}
echo REPOS_LIST=$REPOS_LIST
echo PROCESSES=$PROCESSES

# Timing helper functions
function timing_init   {
    if [ -e "$1" ]
    then
        err_echo [[ timing init file at $1 already exists, letting it be ]]
    else 
        err_echo [[ timing init file created at $1 ]]
        echo '"id","user","repo","timestamp","elapsed time","status","commits","files","size"' > "$1"; 
    fi
}
function timing_start  { date +%s%3N; } # miliseconds
function timing_end    { date +%s%3N; } # miliseconds
function timing_print  {
    local time="$1"

    local hours=$(printf "%02d" $((time/60/60/1000)))
    local minutes=$(printf "%02d" $(((time/60/1000)%60)))
    local seconds=$(printf "%02d" $(((time/1000)%60)))
    local miliseconds=$(printf "%03d" $((time%1000)))

    echo -n ${hours}:${minutes}:${seconds}.${miliseconds}
}
function timing_output { 
    echo "${2},\"${3}\"","\"${4}\"",${6},$(timing_print $((${6} - ${5}))),${7},${8},${9},${10} >> "${1}"
}

# Function writing a specification certificate. It will be attached to data and
# will make it easier to figure out where and when the data came from.

function prepare_specification_certificate {
    echo date=$(date)
    echo user=$(whoami)
    echo hostname=$(hostname)
    echo ghgrabber_ver=$(git log -n 1 --format=%H)
    echo repos_list=$REPOS_LIST
    echo output_dir=$OUTPUT_DIR
    echo processes=$PROCESSES
}
function write_specification_certificate {
    prepare_specification_certificate > "$OUTPUT_DIR/spec_cert.conf"
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
    dir=`dirname "$1"`
    mkdir -p "$dir"

    if [ -d "$dir" ]
    then
        :
    else
        echo "Cannot create '$1', because the directory cannot be created:" >&2
        cho "  - not creating a new sequence" >&2
        echo "  - not safe to continue, must terminate" >&2
        echo "  - attempting to terminate" >&2
        exit 404       
    fi

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
    #export REPOS_LIST=`use_first_if_available "$1" "repos.list"`
    #export OUTPUT_DIR=`use_first_if_available "$2" "data"`
    #export GHGRABBER_HOME="$(pwd)"
    
    #PROCESSES=`use_first_if_available "$3" 1`
    ECHO_PREFIX=main


    export SEQUENCE="$OUTPUT_DIR/sequence.val"
    sequence_new "$SEQUENCE" 0
}
function prepare_directories {
    mkdir -p "$OUTPUT_DIR/commit_metadata/$1"
    #mkdir -p "$OUTPUT_DIR/commit_files/$1"
    mkdir -p "$OUTPUT_DIR/commit_file_hashes/$1"
    mkdir -p "$OUTPUT_DIR/commit_comments/$1"
    mkdir -p "$OUTPUT_DIR/commit_parents/$1"
    #mkdir -p "$OUTPUT_DIR/commit_repositories/$1"
    #mkdir -p "$OUTPUT_DIR/repository_info/$1"
    #mkdir -p "$OUTPUT_DIR/submodule_history/$1"
    mkdir -p "$OUTPUT_DIR/submodule_museum/$1/$2"
}

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

# Functions for retrieving specific bits of information form one repository.
function retrieve_commit_metadata {
    err_echo [[ retrieving commit metadata ]]
    git log --pretty=format:'%H%n%ae%n%at%n%ce%n%ct%n%D%n🐹%n%n' --all | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/metadata.awk"
}
function retrieve_commit_file_modification_info {
    err_echo [[ retrieving commit file modification info ]]
    git log --pretty=format:-----%H:::  --numstat --all -M -C | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/numstat.awk"
}
function retrieve_commit_file_modification_hashes {
    err_echo [[ retrieving commit file modification hashes ]]
    git log --format="%n%n%H" --raw --no-abbrev --all -M -C -m | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/raw.awk"
}
function retrieve_commit_comments {
    err_echo [[ retrieving commit messages ]]
    git log --pretty=format:"🐹 %H%n%B"  --all | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/comment.awk"
}
function retrieve_commit_parents {
    err_echo [[ retrieving commit parents ]]
    git log --pretty=format:"%H %P" --all | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -f "${GHGRABBER_HOME}/awk/parents.awk"
}
function retrieve_commit_repositories {
    err_echo [[ retrieving commit repositories ]]
    echo '"hash","id"'
    git log --pretty=format:"\"%H\",$1" --all
}
function retrieve_repository_info {
    err_echo [[ retrieving repository info ]]
    echo '"id","user","project"'
    echo "${3},\"${1}\",\"${2}\""
}
function retrieve_submodule_history {
    err_echo [[ retrieving submodule history ]]
    git log --format="%n%n%H" --full-history --no-abbrev --raw --all -M -C -m -- .gitmodules | \
    tail -n +3 | \
    AWKPATH="${GHGRABBER_HOME}/awk" awk -v OFS=, -v header=1 -f "${GHGRABBER_HOME}/awk/submodules.awk" 
}

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

    local sorting_dir="$(expr substr $user 1 3)"
    prepare_directories "${sorting_dir}" "${user}_${repo}"

    retrieve_commit_metadata                 > "$OUTPUT_DIR/commit_metadata/$sorting_dir/${filename}"
    #retrieve_commit_file_modification_info   > "$OUTPUT_DIR/commit_files/$sorting_dir/${filename}"
    retrieve_commit_file_modification_hashes > "$OUTPUT_DIR/commit_file_hashes/$sorting_dir/${filename}"
    retrieve_commit_comments                 > "$OUTPUT_DIR/commit_comments/$sorting_dir/${filename}"
    retrieve_commit_parents                  > "$OUTPUT_DIR/commit_parents/$sorting_dir/${filename}"
    #retrieve_commit_repositories $i          > "$OUTPUT_DIR/commit_repositories/$sorting_dir/${filename}"
    #retrieve_repository_info $user $repo $i  > "$OUTPUT_DIR/repository_info/$sorting_dir/${filename}"
    #retrieve_submodule_history               > "$OUTPUT_DIR/submodule_history/$sorting_dir/${filename}"

    make_submodule_museum "$OUTPUT_DIR/submodule_museum/$sorting_dir/${user}_${repo}/"

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

function retrieve_repository_stats {
    local filename="${1}_${2}.csv"
    local sorting_dir="$(expr substr ${1} 1 3)"
    local number_of_files=$(< "$OUTPUT_DIR/commit_file_hashes/$sorting_dir/${filename}" wc -l 2>/dev/null || )
    local number_of_commits=$(< "$OUTPUT_DIR/commit_metadata/$sorting_dir/${filename}" wc -l 2>/dev/null )
    local repository_size=$(du -s . | cut -f 1)
    echo -n "${number_of_files},${number_of_commits},${repository_size}"
}

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

# Compress data into a tarball
function compress_data {
    cd "$OUTPUT_DIR/"
    tar -czf "../$(basename $OUTPUT_DIR/).tar.gz" *
    cd "$GHGRABBER_HOME"
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
export -f prepare_directories
export -f download_repo_contents
export -f retrieve_commit_metadata
export -f retrieve_commit_file_modification_info
export -f retrieve_commit_file_modification_hashes
export -f retrieve_commit_comments
export -f retrieve_commit_parents
export -f retrieve_commit_repositories
export -f retrieve_repository_info
export -f retrieve_submodule_history
export -f make_submodule_museum
export -f process_repository
export -f retrieve_repository_stats
export -f download_and_analyze_repository
export -f sequence_new
export -f sequence_current_value
export -f sequence_next_value

# Check dependencies
if which parallel
then
    :
else
    err_echo [[ GNU parallel missing. Cannot continue. ]]
    exit 5
fi

# Main.
#prepare_globals "$@"
prepare_directories
timing_init "$OUTPUT_DIR/timing.csv"

write_specification_certificate

err_echo [[ downloading repos from "'$REPOS_LIST'" to "'$OUTPUT_DIR'" using $PROCESSES processes ]]
err_echo [[ `< "$REPOS_LIST" wc -l` total repositories to download ]]

err_echo [[ started downloading on `date` ]]

<"$REPOS_LIST" parallel -v -k --ungroup -j $PROCESSES download_and_analyze_repository 

err_echo [[ finished downloading on `date` ]]

err_echo [[ compress data ]]

compress_data

err_echo [[ done compressing data ]]
