#!/bin/bash

# Usage:
# Author: Paul Donovan 
# Email: pauldonovan@rcsi.com
# 19-Oct-2018

usage() { echo "Usage: $0 [-s <45|90>] [-p <string>]" 1>&2; exit 1; }

while getopts ":s:p:" o; do
    case "${o}" in
        s)
            s=${OPTARG}
            ((s == 45 || s == 90)) || usage
            ;;
        p)
            p=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${s}" ] || [ -z "${p}" ]; then
    usage
fi

#echo "Started at $(date)"
#StartTime="Pipeline initiated at $(date)"

#trim_galore -o trim_galore_output/ --paired Reads/SRR5788497_1_10000-reads.fq Reads/SRR5788497_2_10000-reads.fq
