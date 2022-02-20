#!/bin/sh
ueberzug layer --parser bash 0< <(
    declare -Ap add_command=([action]="add" [identifier]="example0" [path]=$1 [x]=$2 [y]=$3 [height]=$4)
    while [ 1 ]; do
        sleep 1
    done
)

