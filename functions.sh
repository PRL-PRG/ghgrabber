#!/bin/bash

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
export -f timing_init

function timing_start  { date +%s%3N; } # miliseconds
export -f timing_start

function timing_end    { date +%s%3N; } # miliseconds
export -f timing_end

function timing_print  {
    local time="$1"

    local hours=$(printf "%02d" $((time/60/60/1000)))
    local minutes=$(printf "%02d" $(((time/60/1000)%60)))
    local seconds=$(printf "%02d" $(((time/1000)%60)))
    local miliseconds=$(printf "%03d" $((time%1000)))

    echo -n ${hours}:${minutes}:${seconds}.${miliseconds}
}
export -f timing_print

function timing_output { 
    echo "${2},\"${3}\"","\"${4}\"",${6},$(timing_print $((${6} - ${5}))),${7},${8},${9},${10} >> "${1}"
}
export -f timing_output 


# Misc. auxiliary functions.
function escape_quotes {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
export -f escape_quotes


function err_echo {
    if [ -n "$ECHO_PREFIX" ]
    then
       echo "[ $ECHO_PREFIX ]" $@ >&2 
    else
        echo $@ >&2
    fi
}
export -f err_echo

function use_first_if_available {
    [ -n "$1" ] && echo "$1" || echo "$2"
}
export -f use_first_if_available

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
export -f sequence_new

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
export -f sequence_current_value

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
export -f sequence_next_value

# Compress data into a tarball
function compress_data {
    cd "$OUTPUT_DIR/"
    tar -czf "../$(basename $OUTPUT_DIR/).tar.gz" *
    cd "$GHGRABBER_HOME"
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

# Tells us where the data came from. LEaves the information about how the data
# was collected.
function write_specification_certificate {
    prepare_specification_certificate > "$OUTPUT_DIR/spec_cert.conf"
}
