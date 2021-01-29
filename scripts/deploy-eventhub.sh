#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
export LC_CTYPE=C

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

usage() { echo "Usage: $0 -s <subscriptionId> -g <resourceGroupName> -l <resourceGroupLocation> -n <eventhubNamespace>" 1>&2; exit 1; }

declare subscriptionId=""
declare resourceGroupName="dapr"
declare resourceGroupLocation="northeurope"
declare eventhubNamespace="dapr-eventhubs-$(head -c32 < /dev/urandom | base64 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"

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
			eventhubNamespace=${OPTARG}
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

if [[ -z "$eventhubNamespace" ]]; then
	echo "This script will create an Azure Event Hub Namespace "
	echo "Enter a name for the namespace:"
	read eventhubNamespace
	[[ "${eventhubNamespace:?}" ]]
fi

if [ -z "$subscriptionId" ] || [ -z "$resourceGroupName" ] || [ -z "$eventhubNamespace" ]; then
	echo "Either one of subscriptionId, resourceGroupName, eventhubNamespace is empty"
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

if [ -f "logs/eventhubnamespace.json" ]; then
	echo "Loading Azure Event Hub Namespace from file..."
	eventhubNamespaceResult=$(cat logs/eventhubnamespace.json)
	eventhubNamespace=$(jq -r '.name' logs/eventhubnamespace.json)
else
	echo "Creating Azure Event Hub Namespace ($eventhubNamespace)..."
	eventhubNamespaceResult=$(az eventhubs namespace create -n "$eventhubNamespace" -g "$resourceGroupName" -l "$resourceGroupLocation")
	if [ $? != 0 ];
	then
		echo "Creating the Azure Event Hub Namespace failed. Aborting..."
		exit 1
	fi
	echo $eventhubNamespaceResult | tee logs/eventhubnamespace.json > /dev/null
fi

az eventhubs eventhub create -n "pubsub" -g "$resourceGroupName" --namespace-name "$eventhubNamespace"
az eventhubs eventhub consumer-group create -n "node-subscriber" -g "$resourceGroupName" --namespace-name "$eventhubNamespace" --eventhub-name "pubsub"
az eventhubs eventhub consumer-group create -n "python-subscriber" -g "$resourceGroupName" --namespace-name "$eventhubNamespace" --eventhub-name "pubsub"
az eventhubs eventhub authorization-rule create  -g "$resourceGroupName" --namespace-name "$eventhubNamespace" --eventhub-name "pubsub" -n dapr --rights Send Listen
az eventhubs eventhub authorization-rule keys list -g "$resourceGroupName" -n dapr --namespace-name "$eventhubNamespace" --eventhub-name "pubsub" > logs/eventhubnamespace-keys.json

connectionString=$(jq -r '.primaryConnectionString' logs/eventhubnamespace-keys.json)
kubectl create secret generic azure-eventhub --from-literal="connectionString=$connectionString"

echo "Azure Event Hubs have been successfully deployed"
