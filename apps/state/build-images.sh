#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
export LC_CTYPE=C

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

usage() { echo "Usage: $0 -s <subscriptionId>" 1>&2; exit 1; }

declare subscriptionId=""
declare resourceGroupName=$(jq -r '.resourceGroup' ../../scripts/logs/acr.json)
declare acrName=$(jq -r '.name' ../../scripts/logs/acr.json)
declare acrServer=$(jq -r '.loginServer' ../../scripts/logs/acr.json)

# Initialize parameters specified from command line
while getopts ":s:g:l:n:h" arg; do
	case "${arg}" in
		s)
			subscriptionId=${OPTARG}
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

if [ -z "$subscriptionId" ] || [ -z "$resourceGroupName" ] || [ -z "$acrServer" ]; then
	echo "Either one of subscriptionId, resourceGroupName, acrName is empty"
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

cd src/WebShopApi
dotnet publish -c Release
cd ../..
az acr build -t $acrServer/shop:latest -r $acrName ./src/WebShopApi

az acr build -t $acrServer/buyer:latest -r $acrName ./src/buyer
