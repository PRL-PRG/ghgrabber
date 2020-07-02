#!/bin/bash

source functions.sh
source scraper.sh

ECHO_PREFIX=`basename $0`

function usage {
    echo "Usage: grab.sh [OPTION]..."
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
    echo "  -f, --repo-list=REPO_LIST       file containing a list of repositories to    "
    echo "                                  download, one repository per line in the     "
    echo "                                  form:                                        "
    echo "                                    USER/PROJECT                               "
    echo "  --single-repo-path=PATH         directory containing a git repository,       "
    echo "                                  use with --single-repo                       "
    echo "  --single-repo=USER/PROJECT      user and project names of a git repository,  "
    echo "                                  use with --single-repo-path                  "
    echo "  -p, --processes:                number of parallel processes to use          "
    echo "  -o, --output-dir:               output directory for extracted data          "
    echo "  --no-renames:                   do not detect renames                        "
    echo "  --only-master:                  analyze only the master branch of each git   "
    echo "                                  repository instead of all branches           "
    echo "                                                                               "
    echo "Requires GNU Parallel.                                                         "
}

# If no options, print usage and exit
if [ $# -eq 0 ]
then
    usage
    exit 6
fi

# Parse options
options=$(getopt -u \
    -o sm:f:p:o:h \
    --long no-sorting-dir,modules:,repo-list:,processes:,output-dir:,no-renames,single-repo:,single-repo-path:,only-master,help \
    -n $0 -- "$@")

if [ $? != 0 ] 
then 
    err_echo "Argh! Argument parsing went pear-shaped!"
    exit 1 
fi

# Defaults
export USE_SORTING_DIR=true
export GHGRABBER_HOME="$(pwd)"
export OUTPUT_DIR="${GHGRABBER_HOME}/data"
export PROCESSES=1
export MODULE_LIST="commit_metadata,commit_file_modification_info,commit_file_modification_hashes,commit_comments,commit_parents,commit_repositories,repository_info,submodule_history,submodule_museum"

SINGLE_REPO_USER=""
SINGLE_REPO_PROJECT=""
SINGLE_REPO_PATH=""

export RENAMES=""
export BRANCHES="--all"

# Analyze results of parsing options
set -- $options 
while true  
do
    case "$1" in 
        -s|--no-sorting-dir) 
            USE_SORTING_DIR=false
            shift 1;;
        -m|--modules)
            MODULE_LIST="$2"
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
                err_echo "'$REPOS_LIST' is not a file."
                exit 4
            fi
            shift 2;;
        --single-repo)
            SINGLE_REPO_USER=$(dirname "$2")
            SINGLE_REPO_PROJECT=$(basename "$2")
            shift 2;;
        --single-repo-path) 
            SINGLE_REPO_PATH="$2"
            if [ ! -d "$SINGLE_REPO_PATH" ]
            then
                err_echo "'$SINGLE_REPO_PATH' is not a directory."
                exit 15
            fi
            tmp_path=`pwd`
            cd "$SINGLE_REPO_PATH"
            if git status 1>/dev/null 2>/dev/null
            then
                :
            else
                err_echo "'$SINGLE_REPO_PATH' is not a git repository."
                exit 16 
            fi
            cd "$tmp_path"
            shift 2;; 
        -p|--processes) 
            PROCESSES="$2"
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
        --no-renames) 
            export RENAMES="--no-renames"    
            shift;;
        --only-master) 
            export BRANCHES=""    
            shift;;
        -h|--help) 
            usage
            exit 2;; 
        --) 
            shift
            break;; 
        *) 
            err_echo "Ack! She cannae take it anymore, captain!" 
            exit 3;;
    esac 
done

if [ -n "$REPOS_LIST" ] && [ -n "$SINGLE_REPO_PATH" ]
then
    err_echo "Cannot continue, provided both a list of repositories to download and a single repository to analyze."
    err_echo "Run the $0 with no arguments for usage information."
    exit 17
fi

if [ -n "$SINGLE_REPO_PATH" ]
then
    if [ -z "$SINGLE_REPO_USER" ] || [ -z "$SINGLE_REPO_PROJECT" ]
    then
        err_echo "Cannot continue, provided invalid single repository user or project name: ${SINGLE_REPO_USER}/${SINGLE_REPO_PROJECT}."
        err_echo "Provide the user and project names via commandline argument --single-repo=USER/PROJECT."
        err_echo "For example: --single-repo=PRL-PRG/ghgrabber."
        err_echo "The USER and PROJECT parts must be separated by a slash."
        err_echo "Run the $0 with no arguments for usage information."
        exit 18
    fi
fi

if [ -z "$REPOS_LIST" ] && [ -z "$SINGLE_REPO_PATH" ]
then
    err_echo "Cannot continue, provide a list of repositories to download or a single repository to analyze."
    err_echo "Run the $0 with no arguments for usage information."
    exit 7
fi

export SEQUENCE="$OUTPUT_DIR/sequence.val"
sequence_new "$SEQUENCE" 0

# Check dependencies
if which parallel
then
    :
else
    err_echo [[ GNU parallel missing. Cannot continue. ]]
    exit 5
fi

if [ -n "$SINGLE_REPO_PATH" ]
then
    err_echo [[ analyzing predownloaded repo from "'$SINGLE_REPO_PATH'" "(${SINGLE_REPO_USER}/${SINGLE_REPO_PROJECT})" to "'$OUTPUT_DIR'" ]]

    analyze_predownloaded_repository "$SINGLE_REPO_USER" "$SINGLE_REPO_PROJECT" "$SINGLE_REPO_PATH"
fi

if [ -n "$REPOS_LIST" ]
then
    timing_init "$OUTPUT_DIR/timing.csv"
    write_specification_certificate

    err_echo [[ downloading repos from "'$REPOS_LIST'" to "'$OUTPUT_DIR'" using $PROCESSES processes ]]
    err_echo [[ `< "$REPOS_LIST" wc -l` total repositories to download ]]

    err_echo [[ extracting the following $(echo MODULE_LIST | tr , ' ' | wc -w) modules: "$MODULE_LIST" ]]

    err_echo [[ started downloading on `date` ]]
    <"$REPOS_LIST" parallel -v -k --ungroup -j $PROCESSES download_and_analyze_repository 
    err_echo [[ finished downloading on `date` ]]

    err_echo [[ compress data ]]
    compress_data
    err_echo [[ done compressing data ]]

fi
