#!/bin/bash

if [ -n "$1" ]
then

    time ./grab.sh \
        --repo-list="repos/repos.list.${1}" \
        --output-dir="data_${1}" \
        --processes=6
fi
