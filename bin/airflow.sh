#!/bin/bash

# Running as any other user will cause permission issues
if [ "$(whoami)" != "analytics-search" ]; then
    echo "Can only run as analytics-search!"
    exit 1
fi

# Gives appropriate write permissions in hdfs
export HADOOP_USER_NAME=hdfs
# Should already be in env from Dockerfile, but lets be sure.
export AIRFLOW_HOME="${AIRFLOW_HOME:-/etc/airflow}"

# skein is a library used by custom airflow plugins to submit
# jobs to the yarn cluster.
export SKEIN_CONFIG="/var/run/airflow/skein"
source "/src/search-airflow/venv/bin/activate"
airflow "$@"

