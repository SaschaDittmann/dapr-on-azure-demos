
#!/bin/bash
declare acrName=$(jq -r '.name' ../../scripts/logs/acr.json)

sed "s/<myacr>/$acrName/g" myactorservice.yaml | kubectl apply -f -
sed "s/<myacr>/$acrName/g" myactorclient.yaml | kubectl apply -f -
