#!/bin/sh

set -e

DISCOLYTICS=/src/wikimedia-discovery-analytics
REFINERY=/src/analytics-refinery
HADOOP_CLUSTER_NAME="bigtop"

header() {
    echo
    echo
    echo "********************"
    echo
    echo $*
    echo
    echo "********************"
    echo
}

create_table() {
    # The various scripts often reference the exact location
    # to store data in the analytics-hadoop cluster. We need
    # to replace those locations with our test cluster, 
    extra_args=""
    if [ -z "$2" ]; then
        hql_raw_path=$1
    else
        extra_args="--database $1"
        hql_raw_path=$2
    fi
    hql=/tmp/create_table_hql_$$
    cat $hql_raw_path \
        | sed "s/hdfs:\/\/analytics-hadoop//g" \
        | sed 's/CREATE EXTERNAL TABLE/CREATE TABLE/' \
        >> $hql

    header Create table from $hql_raw_path
    cat $hql
    hive $extra_args -f $hql
    rm $hql
}

provision_spark() {
    # Spark doesn't come fully setup as we need it, also note that
    # running bigtop provision will break this. Maybe we should
    # modify bigtop provision and make it run this as post-provision?
    header "Configuring spark"
    ln -sf /etc/hive/conf/hive-site.xml /etc/spark/conf/
    DEFAULTS=/etc/spark/conf/spark-defaults.conf
    if ! grep -q hive-site.xml $DEFAULTS; then
        echo "spark.sql.catalogImplementation hive" >> $DEFAULTS
        # --deploy-mode cluster builds a spark conf to ship, but doesn't include
        # hive-site.xml, so include it to make hive work from spark.
        echo "spark.yarn.dist.files /etc/spark/conf/hive-site.xml" >> $DEFAULTS
    fi
}

purge_existing() {
    header "Dropping existing data"
    cat <<EOD | hive
        DROP DATABASE IF EXISTS wmf CASCADE;
        DROP DATABASE IF EXISTS wmf CASCADE;
        DROP DATABASE IF EXISTS discovery CASCADE;
        DROP DATABASE IF EXISTS mjolnir CASCADE;
        DROP DATABASE IF EXISTS glent CASCADE;
        DROP DATABASE IF EXISTS event CASCADE;
        DROP DATABASE IF EXISTS canonical_data CASCADE;
EOD

    header "Purging hdfs:///wmf"
    hdfs dfs -rm -r -f /wmf
}

create_databases() {
    header "Creating necessary databases"
    cat <<EOD | hive
        CREATE DATABASE wmf;
        CREATE DATABASE discovery;
        CREATE DATABASE mjolnir;
        CREATE DATABASE glent;
        CREATE DATABASE event;
        CREATE DATABASE canonical_data;
EOD
}

provision_tables() {
    # Tables we create from this repo. The database to use is embedded
    # in the files already
    find $DISCOLYTICS/hive -name "create_*.hql" | while read hql_path; do
      create_table $hql_path
    done

    # Tables we reference from analytics/refinery. These need the --database flag
    # provided to hive when running
    create_table wmf $REFINERY/hive/webrequest/create_webrequest_table.hql
}

populate_tables() {
    # Fill tables with data
    find $DISCOLYTICS/hive/integration -name "populate_*.hql" | while read hql_path; do
        header Running HQL at $hql_path
        hive -f $hql_path
    done

    find $DISCOLYTICS/hive/integration -name "populate_*.py" | while read pyspark_path; do
        header Running pyspark at $pyspark_path
        # The default client deploy mode doesn't seem to respect
        # --py-files, so we are setting PYTHONPATH directly
        PYTHONPATH=$DISCOLYTICS/spark/ spark-submit $pyspark_path
    done
}

start_airflow() {
    header "Starting airflow"
    /src/search-airflow/venv/bin/airflow initdb
    systemctl enable airflow-scheduler
    systemctl start airflow-scheduler
    systemctl enable airflow-webserver
    systemctl start airflow-webserver
}

# Root doesn't have write permissions, because hdfs permissions
# are wholly unrelated. Tell the system we are the hdfs user.
export HADOOP_USER_NAME=hdfs

# We expect python3.7 in the airflow support code, which is also
# used in the scripts to populate hive with test data. We set this
# here, instead of in spark defaults, as python3.7 also has to be
# explicitly requested in prod.
export PYSPARK_PYTHON=python3.7

# Having individual functions makes testing easier
provision_spark
purge_existing
create_databases
provision_tables
populate_tables
start_airflow

header "Provisioning of hive state complete!"
