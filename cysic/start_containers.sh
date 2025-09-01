#!/bin/bash

NUM_CONTAINERS=$(ls containers | wc -l)
echo "Starting $NUM_CONTAINERS of containers..."

for i in $(seq 11 $NUM_CONTAINERS); do
  CONFIG_FOLDER="containers/verifier$i"
  if [ -d "$CONFIG_FOLDER" ]; then
    docker-compose -p verifier$i -f "$CONFIG_FOLDER/docker-compose.yml" up -d
    echo "The verifier$i container is running"
  else
    echo "Folder $CONFIG_FOLDER not found, skip..."
  fi
done
