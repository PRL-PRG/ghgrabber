#!/bin/bash
# Install before using: csvtool, wget

repository_ids_file=
projects_file='/data/dejavu/join/projects.csv'
destination_dir='/tmp/grabber/'

options=$(getopt -o r:p:o: --long repositories:,projects:,output-dir:,help -- "$@")
problem=false
show_usage=false

[ $? -eq 0 ] || { 
    usage
    exit 1
}

eval set -- "$options"
while true; do
    case "$1" in
    --repositories|-r) 
        repository_ids_file="$2"
        [ -f "$repository_ids_file" ] || { 
            echo -e "[\e[36m$0\e[0m] Repository IDs file does not exist or is not a file: $repository_ids_file" >&2
            problem=true
        }
        shift;;
    --projects|-p) 
        projects_file="$2"
        [ -f "$projects_file" ] || { 
            echo -e "[\e[36m$0\e[0m] Projects file does not exist or is not a file: $projects_file" >&2
            problem=true
        }
        shift;;
    --output-dir|-o) 
        destination_dir="$2"
        [ -d "$destination_dir" ] || { 
            echo -e "[\e[36m$0\e[0m] Destination directory does not exist or is not a directory: $destination_dir" >&2 
            problem=true
        }
        shift;;
    --home|-h) 
        home="$2"
        [ -d "$home" ] || { 
            echo -e "[\e[36m$0\e[0m] Destination directory does not exist or is not a directory: $destination_dir" >&2
            problem=true
        }
        shift;;
    --help) show_usage=true;;
    --)     shift; break;;
    esac
    shift
done

"$show_usage" && {
 
    echo "Usage: $0 [OPTION]... [FILE]..."                                                                       >&2
    echo                                                                                                         >&2
    echo "Mandatory arguments to long options are mandatory for short options too."                              >&2
    echo                                                                                                         >&2
    echo "Options:"                                                                                              >&2
    echo "  -r, --repositories=FILE  a file containing a list of project IDs, specifies which projects to"       >&2
    echo "                           download files from [MANDATORY]"                                            >&2
    echo "  -o, --output-dir=DIR     a directory where files are going to be downloaded [default: /tmp/grabber]" >&2
    echo "  -p, --projects=CSV       a CSV file containing the following columns: project ID, username, and"     >&2
    echo "                           project name [default: /data/dejavu/join/projects.csv]"                     >&2
    echo "  --help                   usage information"                                                          >&2
    exit 1  
}

[ -z "$repository_ids_file" ] && {
    echo -e "[\e[36m$0\e[0m] Must specify a list of repositories to download files from." >&2
    problem=true
}

$problem && {
    exit 2
}

[ -z "$home" ] && {
    home=$(mktemp -d "/tmp/grabber.XXXXX")
}

files=( "$@" )
#pattern_file="${home}/patterns"
view_file="${home}/view"
repos_file="${home}/repos"
log_file="${home}/log"

echo -e "[\e[36m$0\e[0m] finding projects with specified IDs in \e[31m${projects_file}\e[0m" >&2

# XXX Probably could do this better with csvtool.
#cat "$repository_ids_file" | while read line
#do 
#    echo '^'${line}','
#done > "$pattern_file"
#
#<"$projects_file" grep -f "$pattern_file" >"$view_file"

awk -v repository_ids="$repository_ids_file" '
    BEGIN {
        FS=","; 
        while((getline id < repository_ids) > 0) {
            ids[id]=1
        }
    } 
    ($1 in ids) {
        print
    }' <"$projects_file" >"$view_file"

n_found=$(< "$view_file" wc -l)
n_searched=$(< "$repository_ids_file" wc -l)
echo -e "[\e[36m$0\e[0m] I found $n_found projects" \
  "for the $n_searched project IDs you gave me"  \
  "(see "$view_file" for details)." >&2

function record_time {
    date '+%s%3N' # miliseconds    
}

function timing_print  {
    local time="$1"

    local hours=$(printf "%02d" $((time/60/60/1000)))
    local minutes=$(printf "%02d" $(((time/60/1000)%60)))
    local seconds=$(printf "%02d" $(((time/1000)%60)))
    local miliseconds=$(printf "%03d" $((time%1000)))

    echo -n ${hours}:${minutes}:${seconds}.${miliseconds}
}

# runtime variables
prefix_length=80

function glue {
    echo "printf ' %.0s' {$1..$prefix_length}" | bash
}	

echo -e "[\e[36m$0\e[0m] starting downloads" >&2
all_start_time=`record_time`
csvtool format '%(2)/%(3)\n' "$view_file" | while read repo
do
    prefix="[\e[36m$0\e[0m] [\e[94m${repo}\e[0m] "
    my_prefix_length=$(expr length "$prefix")
    if ((my_prefix_length > prefix_length))
    then
        prefix_length=$my_prefix_length
    fi    

    start_time=`record_time`
    echo -e "[\e[36m$0\e[0m] [\e[94m${repo}\e[0m] $(glue $my_prefix_length)starting download" >&2

    for file in "${files[@]}"
    do
        prefix_folder="${repo:0:2}"
        path_dir="${destination_dir}/${prefix_folder}/${repo}"
        path="${path_dir}/${file}"
        repo_address="https://github.com/${repo}/blob/master/${file}"

	echo -ne "${prefix}$(glue $my_prefix_length)  * \e[33m${repo_address}\e[0m" >&2 #-> \e[33m${path}\e[0m" >&2

        mkdir -p "$path_dir"
        wget "$repo_address" -O "$path" 2>>"$log_file"

        case $? in
	    0) echo -e "...\e[32mOK\e[0m" >&2;;
	    1) echo -e "...\e[31mFAIL\e[0m" >&2;;
	    2) echo -e "...\e[31mFAIL\e[0m (parse error)";;
            3) echo -e "...\e[31mFAIL\e[0m (file I/O error)" >&2;;
            4) echo -e "...\e[31mFAIL\e[0m (network failure)" >&2;;
            5) echo -e "...\e[31mFAIL\e[0m (SSL verification failure)" >&2;;
            6) echo -e "...\e[31mFAIL\e[0m (username/password authentication failure)" >&2;;
            7) echo -e "...\e[31mFAIL\e[0m (protocol error)" >&2;;
            8) echo -e "...\e[31mFAIL\e[0m (server issued error response)" >&2;;
            *) echo -e "...\e[31mFAIL\e[0m (unknown error)" >&2;;
        esac        
    done

    elapsed_time=$(timing_print $(($(record_time) - start_time)))
    echo -e "[\e[36m$0\e[0m] [\e[94m${repo}\e[0m] $(glue $my_prefix_length)finished download in \e[34m${elapsed_time}\e[0m" >&2
done

all_elapsed_time=$(timing_print $(($(record_time) - all_start_time)))
echo -e "[\e[36m$0\e[0m] finished all in \e[34m${all_elapsed_time}\e[0m" >&2
#echo -e "[\e[36m$0\e[0m] downloaded files: \e[32m${successes}\e[0m, errors: \e[31m${failures}\e[0m" >&2
echo -e "[\e[36m$0\e[0m] data downloaded to \e[94m${destination_dir}\e[0m" >&2
echo -e "[\e[36m$0\e[0m] error details available at \e[31m${log_file}\e[0m" >&2


