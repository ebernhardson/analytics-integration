#!/usr/bin/env spark-submit
import sys
from pyspark.sql import SparkSession

def read_jvm_stdin(jvm):
    sys_in = getattr(jvm.java.lang.System, 'in')
    # TODO: Why \A?
    scanner = jvm.java.util.Scanner(sys_in).useDelimiter('\\\\A')
    return scanner.next() if scanner.hasNext() else ""

if len(sys.argv) != 2:
    print('Usage: hql.py [query|-]')
    sys.exit(1)

spark = SparkSession.builder.enableHiveSupport().getOrCreate()

hql = sys.argv[1]
if hql == '-':
    # Fun thing, jvm owns the real stdin and doesnt pass thru
    hql = read_jvm_stdin(spark._jvm)

hql = hql.strip().rstrip(';')
if ';' in hql:
    print('WARNING: hql.py only supports a single statement')

print('*'*40)
print('')
print(spark.conf._jconf.getAll().toString())
print('')
print('*'*40)

spark.sql(hql).show()

