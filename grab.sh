#!/bin/bash

source functions.sh
source scraper.sh

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
    echo "  -f, --repo-list=REPO_LIST       list of repositories to download, one        "
    echo "                                  repository per line in the form:             "
    echo "                                    USER/PROJECT                               "
    echo "  -p, --processes:                number of parallel processes to use          "
    echo "  -o, --output-dir:               output directory for extracted data          "
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

ECHO_PREFIX=main
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
