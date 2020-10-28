#!/bin/bash
set -e


init-git-submodules() {
    # Simplify first run by initializing the appropriate submodules
    # if a canary file is not already in place.
    if [ ! -f src/bigtop/LICENSE ]; then
        git submodule update --init --recursive
        for repo in search-airflow wikimedia-discovery-analytics; do
            (cd src/$repo && git fat init && git fat pull)
        done
    fi
}

fix-bigtop14-spark() {
    # The puppet shipped with bigtop 1.4.0 sets the wrong SPARK_MASTER_URL
    # because scope['deploy::roles'] returns nil, the appropriate scope var
    # is scope['spark::deploy::roles'].
    # This is an evil hack, ideally this will be fixed upstream.
    templates="${BIGTOP_SRC}/bigtop-deploy/puppet/modules/spark/templates"
    if ! grep -q spark::deploy::roles $templates/spark-env.sh; then
        echo "WARNING: Adjusting bigtop spark templates to reference spark::deploy::roles"
        sed -i "s/'deploy::roles'/'spark::deploy::roles'/" $templates/spark-env.sh $templates/spark-defaults.conf
    fi
}

bigtop() {
    # docker-hadoop.sh uses paths relative to current working directory
    (
        cd $BIGTOP;
        ./docker-hadoop.sh -C $BIGTOP_CONFIG $*
    )
}

bigtop-docker() {
    PROVISION_ID="$(cat $BIGTOP/.provision_id)"
    if [ -z "$PROVISION_ID" ]; then
        echo "Bigtop cluster not provisioned"
        exit 1
    fi
    (
        cd $BIGTOP;
        docker-compose -p $PROVISION_ID $*
    )
}

usage() {
    echo "Usage: $PROG arg"
    echo
    echo "Argument:"
    echo "    -c --create"
    echo "    -u --up"
    echo "    -d --down"
    echo "       --destroy"
    echo "    -h --help"
    echo
    exit 1
}

create() {
    # Start hadoop
    bigtop --create 1
    instance=$(bigtop-docker ps -q)
    if [ -z "$instance" ]; then
        echo "No bigtop after create?"
        exit 1
    fi
    # TODO: Gate on actual creation? For now we only work with
    # a full init from scratch each time.
    bigtop --exec 0 /usr/local/bin/init-hive-state.sh
}

down() {
    # EXPERIMENTAL. Doesn't come back up right.
    bigtop-docker down
}

up() {
    # EXPERIMENTAL. Doesn't come back up right.
    bigtop-docker up
}

destroy() {
    bigtop --destroy
}

PROG=$(basename "$0")
cd "$(dirname "$0")"

BIGTOP="$PWD/etc/bigtop"
BIGTOP_SRC="$PWD/src/bigtop"
BIGTOP_CONFIG="$BIGTOP/config.yaml"
export BIGTOP_PUPPET_DIR="${BIGTOP_SRC}/bigtop-deploy/puppet"

if [ -e etc/defaults ]; then
    . etc/defaults
fi

if [ $# -eq 0 ]; then
    usage
fi

# First-run setup
init-git-submodules
fix-bigtop14-spark

while [ $# -gt 0 ]; do
    case "$1" in
    -c|--create)
        create
        shift;;
    --destroy)
        destroy
        shift;;
    -u|--up)
        up
        shift;;
    -d|--down)
        down
        shift;;
    -h|--help)
        usage
        shift;;
    *)
        echo "Unknown argument: '$1'" 1>&2
        usage;;
    esac
done

