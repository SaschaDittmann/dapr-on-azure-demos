#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
export LC_CTYPE=C

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

usage() { echo "Usage: $0 -s <subscriptionId> -g <resourceGroupName> -l <resourceGroupLocation> -n <cosmosdbAccountName>" 1>&2; exit 1; }

declare subscriptionId=""
declare resourceGroupName="dapr"
declare resourceGroupLocation="northeurope"
declare cosmosdbAccountName="dapr-cosmosdb-$(head -c32 < /dev/urandom | base64 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"

# Initialize parameters specified from command line
while getopts ":s:g:l:n:h" arg; do
	case "${arg}" in
		s)
			subscriptionId=${OPTARG}
			;;
		g)
			resourceGroupName=${OPTARG}
			;;
		l)
			resourceGroupLocation=${OPTARG}
			;;
		n)
			cosmosdbAccountName=${OPTARG}
			;;
		h)
			usage
			;;
		?) 
			echo "Unknown option ${arg}"
			;;
		esac
done
shift $((OPTIND-1))

#Prompt for parameters is some required parameters are missing
if [[ -z "$subscriptionId" ]]; then
	echo "Your subscription ID can be looked up with the CLI using: az account show --out json "
	echo "Enter your subscription ID:"
	read subscriptionId
	[[ "${subscriptionId:?}" ]]
fi

if [[ -z "$resourceGroupName" ]]; then
	echo "This script will look for an existing resource group, otherwise a new one will be created "
	echo "You can create new resource groups with the CLI using: az group create "
	echo "Enter a resource group name"
	read resourceGroupName
	[[ "${resourceGroupName:?}" ]]
fi

if [[ -z "$resourceGroupLocation" ]]; then
	echo "If creating a *new* resource group, you need to set a location "
	echo "You can lookup locations with the CLI using: az account list-locations "
	echo "Enter resource group location:"
	read resourceGroupLocation
fi

if [[ -z "$cosmosdbAccountName" ]]; then
	echo "This script will create an Azure CosmosDB Account "
	echo "Enter a name for the cosmos db account:"
	read cosmosdbAccountName
	[[ "${cosmosdbAccountName:?}" ]]
fi

if [ -z "$subscriptionId" ] || [ -z "$resourceGroupName" ] || [ -z "$cosmosdbAccountName" ]; then
	echo "Either one of subscriptionId, resourceGroupName, cosmosdbAccountName is empty"
	usage
fi

#login to azure using your credentials
az account show 1> /dev/null

if [ $? != 0 ];
then
	az login
fi

#set the default subscription id
az account set --subscription $subscriptionId

set +e

#Check for existing RG
az group show --name $resourceGroupName 1> /dev/null

if [ $? != 0 ]; then
	echo "Resource group with name" $resourceGroupName "could not be found. Creating new resource group.."
	set -e
	(
		set -x
		az group create --name $resourceGroupName --location $resourceGroupLocation 1> /dev/null
	)
	else
	echo "Using existing resource group..."
fi

mkdir -p logs

if [ -f "logs/cosmosdb.json" ]; then
	echo "Loading Azure Cosmos DB Account from file..."
	cosmosdbAccountResult=$(cat logs/cosmosdb.json)
	cosmosdbAccountName=$(jq -r '.name' logs/cosmosdb.json)
else
	echo "Creating Azure Cosmos DB Account ($cosmosdbAccountName)..."
	cosmosdbAccountResult=$(az cosmosdb create -n "$cosmosdbAccountName" -g "$resourceGroupName" --locations regionName=$resourceGroupLocation failoverPriority=0 isZoneRedundant=False)
	if [ $? != 0 ];
	then
		echo "Creating the Azure Storage Account failed. Aborting..."
		exit 1
	fi
	echo $cosmosdbAccountResult | tee logs/cosmosdb.json > /dev/null
fi

echo "Getting Azure Cosmos DB keys..."
az cosmosdb keys list -n "$cosmosdbAccountName" -g "$resourceGroupName" > logs/cosmosdb-keys.json
cosmosdbUrl=$(jq -r '.documentEndpoint' logs/cosmosdb.json)
cosmosdbMasterKey=$(jq -r '.primaryMasterKey' logs/cosmosdb-keys.json)
kubectl create secret generic azure-cosmosdb --from-literal="url=$cosmosdbUrl" --from-literal="masterKey=$cosmosdbMasterKey"

echo "Creating Azure Cosmos DB containers..."
az cosmosdb sql database create -n "statestore" -g "$resourceGroupName" -a "$cosmosdbAccountName"
az cosmosdb sql container create -n "states" -g "$resourceGroupName" -a "$cosmosdbAccountName" -d "statestore" \
	--partition-key-path '/id' --throughput "400"

echo "Azure Cosmos DB has been successfully deployed"
