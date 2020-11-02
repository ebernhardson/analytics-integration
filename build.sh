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

fetch-spark24() {
    # Bigtop comes with spark 2.2, but we need 2.4. Perhaps this should be attached via git-fat?
    # For now simply grab it from the internet
    SPARK_VERSION="2.4.4"
    SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop2.6.tgz"
    SPARK_TGZ_SHA512="793d68d633640c7dd4517e9b467cf40eb67fc45eb33208a4a4143cdf7b30900bd02de7b8289d5dab211e669cc3c08f48306449ee4b7183de93975a1ac5c24333"
    if [ -f "artifacts/${SPARK_TGZ}" ]; then
        echo "Spark archive alreadys available"
    else
        echo "Spark archive not available, retrieving..."
        # sha512sum --check only works if we are in the download directory
        mkdir /tmp/$$
        pushd /tmp/$$
        wget -O "${SPARK_TGZ}" "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"
        echo "${SPARK_TGZ_SHA512}  ${SPARK_TGZ}" > "${SPARK_TGZ}.sha512"
        if sha512sum -c "${SPARK_TGZ}.sha512"; then
            echo "Retrieved $SPARK_TGZ"
            popd
            mv "/tmp/$$/${SPARK_TGZ}" "artifacts/${SPARK_TGZ}"
            rm -rf "/tmp/$$"
        else
            echo "ERROR: Downloaded spark archive doesn't match expected sha512"
            rm -rf /tmp/$$
            exit 1
        fi
    fi
}

bigtop() {
    # docker-hadoop.sh uses paths relative to current working directory
    (
        cd $BIGTOP;
        ./docker-hadoop.sh -C $BIGTOP_CONFIG "$@"
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
        docker-compose -p $PROVISION_ID "$@"
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
    # Download spark if not already done
    fetch-spark24
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

reload-airflow-vars() {
    # TODO: Same routine is in provision_airflow_on_bigtop.sh. Choose
    # a location.
    for SCAP_REV_PATH in /src/wikimedia-discovery-analytics /etc; do
        echo "Reloading from $SCAP_REV_PATH"
        bigtop --exec 0 \
            env SCAP_REV_PATH=${SCAP_REV_PATH} \
            /src/wikimedia-discovery-analytics/scap/scripts/import_airflow_variables.sh
    done
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
    --airflow-test)
        shift
        bigtop --exec 0 sudo -u analytics-search airflow test "$@"
        exit $?
        ;;
    --exec)
        shift
        bigtop --exec 0 "$@"
        exit $?
        ;;
    --yarn-logs)
        bigtop --exec 0 env HADOOP_USER_NAME=hdfs yarn logs -applicationId $2
        shift; shift;;
    --reload-airflow-vars)
        reload-airflow-vars
        shift;;
    *)
        echo "Unknown argument: '$1'" 1>&2
        usage;;
    esac
done

