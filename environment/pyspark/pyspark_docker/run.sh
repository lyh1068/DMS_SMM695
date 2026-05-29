#!/usr/bin/env bash
set -e
docker compose up -d
echo "Jupyter: http://localhost:8888/?token=pyspark"
