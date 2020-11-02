#!/bin/bash
#
# Provision airflow inside bigtop 1.4 using debian-9
#
# Install the things we need, unfortunately we can't actually initialize
# anything inside hadoop as that doesn't exist yet. Hadoop doesn't get setup
# until we have real fqdn's for live containers.
#

set -e
set -x

# people.debian.org is https only, but https isn't installed by default
apt-get update
apt-get install -y --no-install-recommends apt-transport-https ca-certificates
# Provides python 3.7
echo "deb https://people.debian.org/~paravoid/python-all $(lsb_release -sc) main" \
 | sudo tee /etc/apt/sources.list.d/python-all.list

# python dependencies we need for airflow
airflow_deps="python3.7 python3-virtualenv virtualenv python3-pip"
# python packages installed to prod that we expect already exist
other_deps="python3-requests"

apt-get update
apt-get install -y --no-install-recommends $airflow_deps $other_deps


# Run the scap deployment script to build the airflow venv
PIP_ALLOW_INDEX=yes SCAP_REV_PATH=/src/search-airflow PYTHON=/usr/bin/python3.7 /src/search-airflow/scap/scripts/virtualenv.sh

# Run the other scap deployment srcipt to build venvs for individual tasks
PIP_ALLOW_INDEX=yes SCAP_REV_PATH=/src/wikimedia-discovery-analytics /src/wikimedia-discovery-analytics/scap/scripts/build_deployment_virtualenvs.sh

# Mimicing production, the deployment is owned by one user (in this case root), and the runtime is a second user
useradd analytics-search

# TODO: Should have been exported from Dockerfile?
export AIRFLOW_HOME=/etc/airflow

# Create the various places airflow wants to write to (todo: adduser? permissions?)
mkdir -p $AIRFLOW_HOME /var/{log,lib}/airflow
chown -R analytics-search:analytics-search $AIRFLOW_HOME /var/{log,lib}/airflow
chown -R root:analytics-search /etc/airflow

# Prepare the sqlite database so the daemons are ready to start.
sudo -u analytics-search airflow initdb

# Import production airflow variables
SCAP_REV_PATH=/src/wikimedia-discovery-analytics /src/wikimedia-discovery-analytics/scap/scripts/import_airflow_variables.sh
# Import integration overrides (by tieing to exact implementation details, the script only looks in $SCAP_REV_PATH/airflow/config).
SCAP_REV_PATH=/etc /src/wikimedia-discovery-analytics/scap/scripts/import_airflow_variables.sh

# Bigtop ships with spark 2.2, but we use 2.4 in prod. Additionally I couldn't
# get hive-site.xml to ship properly with 2.2 with deploy-mode cluster and the
# app shipping extra files via --files. The relevant code in 2.4 has been
# rewritten and works out of the box. We still include bigtop spark to let it
# write all the configuration files. Not ideal, but "works".
tar -C /opt -xf /tmp/spark-2.4.4-bin-hadoop2.6.tgz
rm /tmp/spark-2.4.4-bin-hadoop2.6.tgz
mv /opt/spark-2.4.4-bin-hadoop2.6/conf /opt/spark-2.4.4-bin-hadoop2.6/conf.dist
ln -s /etc/spark/conf /opt/spark-2.4.4-bin-hadoop2.6/conf

# Configure airflow to use spark in deploy-mode cluster, mimicing prod and required for how our
# python environments are utilized.
# The cli integration requires us to set conn_type, even though the spark hook doesn't use it.
sudo -u analytics-search airflow connections --delete --conn_id spark_default
# TODO: Probably wrong version of hadoop for spark, should we use the no-hadoop ver?
sudo -u analytics-search airflow connections --add --conn_id spark_default --conn_type unreferenced --conn_host yarn --conn_extra '{"queue": "default", "deploy-mode": "cluster", "spark-home": "/opt/spark-2.4.4-bin-hadoop2.6"}'

# Turn on the airflow webserver on boot. The default use case is test
# invocations, not scheduling, so we do not enable the scheduler by default.
systemctl enable airflow-webserver
