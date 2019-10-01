#!/bin/sh
REGION=eastus
RND=$RANDOM
sourced=0

# Check if file is being sourced.  It should be to set the variables 
if [ -n "$ZSH_EVAL_CONTEXT" ]; then 
    case $ZSH_EVAL_CONTEXT in *:file) sourced=1;; esac
elif [ -n "$KSH_VERSION" ]; then
    [ "$(cd $(dirname -- $0) && pwd -P)/$(basename -- $0)" != "$(cd $(dirname -- ${.sh.file}) && pwd -P)/$(basename -- ${.sh.file})" ] && sourced=1
elif [ -n "$BASH_VERSION" ]; then
    (return 0 2>/dev/null) && sourced=1 
else # All other shells: examine $0 for known shell binary filenames
    # Detects `sh` and `dash`; add additional shell filenames as needed.
    case ${0##*/} in sh|dash) sourced=1;; esac
fi

usage() {
    echo "`basename $0`"
    echo "   Usage: "
    echo "     [-g <group>] resource group to use. Defaults are supplied if not provided"
    echo "     [-n <db name>] name of the DB.  Defaults are supplied if not provided"
    exit 1
}

# Catch any help requests
for arg in "$@"; do
  case "$arg" in
    --help| -h)
        usage
        ;;
  esac
done

while getopts g:n: option
do
    case "${option}"
    in
        g) RG=${OPTARG};;
        n) DBNAME=${OPTARG};;
        *) usage;;
        : ) usage;;
    esac
done
shift "$(($OPTIND -1))"

if [ -z $RG ]; then
    RG=todo-$RND
fi

if [ -z $DBNAME ]; then
    DBNAME=$RG-db
fi

if ! ((sourced)); then
    read -r -d '' SCRIPT_SOURCED <<EOF
WARNING: This script is not being sourced so Maven environment variables won't be set.  Is this ok [y/n]?
EOF
    read -p "$SCRIPT_SOURCED" SOURCED_ANSWER
    if ! [[ $SOURCED_ANSWER =~ [yY](es)* ]]; then
        echo "Okey Dokey will exit and let you think about it"
        exit 0
    fi
fi

# Check if what we need is available
command -v jq >/dev/null 2>&1 || { echo >&2 "ERROR: Script requires jq but it's not installed.  Aborting."; exit 1; }
command -v az >/dev/null 2>&1 || { echo >&2 "ERROR: Script requires az but it's not installed.  Aborting."; exit 1; }
set -x
    az group show -n $RG
    if [ $? -ne 0 ]; then
        az group create -n $RG -l eastus
    fi
    COSMOS=$( az cosmosdb show -g $RG -n $DBNAME -o json )
    if [ $? -ne 0 ]; then 
        COSMOS=$( az cosmosdb create --kind GlobalDocumentDB -g $RG -n $DBNAME -o json )
    fi

    KEYS=$( az cosmosdb keys list -g $RG -n $DBNAME -o json )
set +x
export COSMOSDB_URI=$( echo $COSMOS | jq -r '.documentEndpoint' )
export COSMOSDB_KEY=$( echo $KEYS | jq -r '.primaryMasterKey' )
export COSMOSDB_DBNAME=$DBNAME
