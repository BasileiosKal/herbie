#!/usr/bin/env bash
set -e -x

RHOST="uwplse.org"
RHOSTDIR="/var/www/herbie/reports"

upload () {
    DIR=$1
    B=$(git rev-parse --abbrev-ref HEAD)
    C=$(git rev-parse HEAD | sed 's/\(..........\).*/\1/')
    RDIR="$(date +%s):$(hostname):$B:$C"
    rsync --verbose --recursive "$1" --exclude reports/ "$RHOST:$RHOSTDIR/$RDIR"
    ssh "$RHOST" chmod a+rx "$RHOSTDIR/$RDIR" -R
}

index () {
    rsync -v --include 'results.json' --include '/*/' --exclude '*' -r uwplse.org:/var/www/herbie/reports/ graphs/reports/
    racket herbie/reports/make-index.rkt
    rsync --verbose --recursive "index.html" "herbie/reports/index.css" "$RHOST:$RHOSTDIR/"
    ssh "$RHOST" chgrp uwplse "$RHOSTDIR/index.html"
    rm index.html
}

help () {
    echo "USAGE: publish.sh upload <dir>\t\t\tUpload the directory <dir>"
    echo "       publish.sh index\t\t\t\tRegenerate the report index"
}

CMD="$1"

if [[ $CMD = "upload" ]]; then
    DIR="$2"
    if [[ -z $DIR ]]; then
        echo "Please pass a directory to upload"
        echo
        help
        exit 1
    elif [[ ! -d $DIR ]]; then
        echo "Directory $DIR does not exist"
        exit 2
    else
        upload "$DIR"
    fi
else
    index
fi

