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

# Install the python dependencies we need for airflow
apt-get update
apt-get install -y --no-install-recommends python3.7 python3-virtualenv virtualenv python3-pip

# Run the scap deployment script to build the venv
PIP_ALLOW_INDEX=yes SCAP_REV_PATH=/src/search-airflow PYTHON=/usr/bin/python3.7 /src/search-airflow/scap/scripts/virtualenv.sh

# Create the various places airflow wants to write to (todo: adduser? permissions?)
mkdir -p $AIRFLOW_HOME /var/run/airflow /var/log/airflow

# Symlink the dags/plugins to default airflow locations
ln -s /src/wikimedia-discovery-analytics/airflow/dags $AIRFLOW_HOME/dags
ln -s /src/wikimedia-discovery-analytics/airflow/plugins $AIRFLOW_HOME/plugins
