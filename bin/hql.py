#!/usr/bin/env spark-submit
import sys
from pyspark.sql import SparkSession

if len(sys.argv) != 2:
    print('Usage: hql.py [query]')
    sys.exit(1)

spark = SparkSession.builder.enableHiveSupport().getOrCreate()

hql = sys.argv[1].strip().rstrip(';')
if ';' in hql:
    print('WARNING: hql.py only supports a single statement')

# TODO: This truncates lots of info, there are settings that can change
# that. But this script is only really to smoketest the connection between
# spark and hive, so additional functionality has been avoided.
spark.sql(hql).show()

