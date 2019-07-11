#!/bin/bash

# Create target index on elasticsearch
docker exec es01 curl -s -XDELETE localhost:9200/integration?pretty
docker exec es01 curl -s -H 'Content-Type: application/json' -XPUT localhost:9200/integration?pretty -d '{"settings":{"index":{"number_of_shards":1,"number_of_replicas":0}},"mappings":{"page":{"properties":{"popularity_score":{"type":"float"}}}}}'
docker exec es01 curl -s -XPUT -H 'Content-Type: application/json' http://es01:9200/integration/page/hi?pretty -d '{"popularity_score":1.0}'

# Create glent template on elasticsearch
docker exec es01 curl -s -XPUT -H 'Content-Type: application/json' http://es01:9200/_template/glent -d '{
  "index_patterns": ["glent_*"],
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "mappings": {
    "_doc": {
      "properties": {
        "query": {"type": "text"},
        "dym": {"type": "text"},
        "q1q2LevenDist": {"type": "short"},
        "wikiid": {"type": "keyword"},
        "queryhitsTotal": {"type": "integer"},
        "suggCount": {"type": "integer"}
      }
    }
  }
}'

# Test standard bulk daemon pipeline
docker exec mjolnir01 apt install -y kafkacat
echo '{"_index":"integration","_id":"hi","_source":{"popularity_score": 4.2}}' | docker exec -i mjolnir01 kafkacat -P -b kafka01:9092 -t mjolnir_bulk
# Check stats
docker exec es01 curl -s http://mjolnir01:9170/ | grep bulk_action

# Upload test file to swift
docker cp /tmp/esbulk/10k.suggestions.ndjson.gz swift01:/tmp/
docker exec swift01 swift -A http://swift01:8080/auth/v2.0 -U test:tester -K testing upload --object-name v2/suggs.ndjson.gz search_glent /tmp/10k.suggestions.ndjson.gz 

# Ask mjolnir to download from swift and upload the suggestions
echo '{"container":"search_glent", "object_prefix": "v1"}' | docker exec -i mjolnir01 kafkacat -P -b kafka01:9092 -t mjolnir_swift
