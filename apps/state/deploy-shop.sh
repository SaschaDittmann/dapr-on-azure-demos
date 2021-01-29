#!/bin/bash
declare acrName=$(jq -r '.name' ../../scripts/logs/acr.json)

sed "s/<myacr>/$acrName/g" shop.yaml | kubectl apply -f -
sed "s/<myacr>/$acrName/g" buyer.yaml | kubectl apply -f -
