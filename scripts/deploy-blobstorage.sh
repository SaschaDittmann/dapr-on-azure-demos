#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
export LC_CTYPE=C

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

usage() { echo "Usage: $0 -s <subscriptionId> -g <resourceGroupName> -l <resourceGroupLocation> -n <storageAccountName>" 1>&2; exit 1; }

declare subscriptionId=""
declare resourceGroupName="dapr"
declare resourceGroupLocation="northeurope"
declare storageAccountName="daprstore$(head -c32 < /dev/urandom | base64 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"
declare storageAccountSku="Standard_LRS"

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
			storageAccountName=${OPTARG}
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

if [[ -z "$storageAccountName" ]]; then
	echo "This script will create an Azure Storage Account "
	echo "Enter a name for the Storage account:"
	read storageAccountName
	[[ "${storageAccountName:?}" ]]
fi

if [ -z "$subscriptionId" ] || [ -z "$resourceGroupName" ] || [ -z "$storageAccountName" ]; then
	echo "Either one of subscriptionId, resourceGroupName, storageAccountName is empty"
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

if [ -f "logs/storageaccount.json" ]; then
	echo "Loading Azure Storage Account from file..."
	storageAccountResult=$(cat logs/storageaccount.json)
	storageAccountName=$(jq -r '.name' logs/storageaccount.json)
else
	echo "Creating Azure Storage Account ($storageAccountName)..."
	storageAccountResult=$(az storage account create -n "$storageAccountName" -g "$resourceGroupName" --sku "$storageAccountSku" -l "$resourceGroupLocation")
	if [ $? != 0 ];
	then
		echo "Creating the Azure Storage Account failed. Aborting..."
		exit 1
	fi
	echo $storageAccountResult | tee logs/storageaccount.json > /dev/null
fi

echo "Getting Azure Storage Account keys..."
az storage account keys list -n "$storageAccountName" -g "$resourceGroupName" > logs/storageaccount-keys.json
storageAccountKey=$(jq -r '.[0].value' logs/storageaccount-keys.json)
kubectl create secret generic azure-storageaccount --from-literal="storageaccountname=$storageAccountName" --from-literal="storageaccountkey=$storageAccountKey"

echo "Creating Azure Storage Account containers..."
az storage container create -n "statestore" -g "$resourceGroupName" --account-name "$storageAccountName" --account-key "$storageAccountKey"
az storage container create -n "pubsub" -g "$resourceGroupName" --account-name "$storageAccountName" --account-key "$storageAccountKey"

echo "Azure Storage Account has been successfully deployed"
