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
    echo "  -p, --processes:                number of parallel processes to use          "
    echo "  -o, --output-dir:               output directory for extracted data          "
    echo "  --no-renames:                   do not detect renames                        "
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
    --long no-sorting-dir,modules:,repo-list:,processes:,output-dir:,no-renames,help \
    -n $0 -- "$@")

if [ $? != 0 ] 
then 
    err_echo "Argh! Parsing went pear-shaped!"
    exit 1 
fi

# Defaults
export USE_SORTING_DIR=true
export GHGRABBER_HOME="$(pwd)"
export OUTPUT_DIR="${GHGRABBER_HOME}/data"
export PROCESSES=1
export MODULE_LIST="commit_metadata,commit_file_modification_info,commit_file_modification_hashes,commit_comments,commit_parents,commit_repositories,repository_info,submodule_history,submodule_museum"

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

if [ -z "$REPOS_LIST" ]
then
    err_echo "Cannot continue, provide a list of repositories to download."
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
