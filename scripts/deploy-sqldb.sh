#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
export LC_CTYPE=C

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

usage() { echo "Usage: $0 -s <subscriptionId> -g <resourceGroupName> -l <resourceGroupLocation> -n <sqlServerName>" 1>&2; exit 1; }

declare subscriptionId=""
declare resourceGroupName="dapr"
declare resourceGroupLocation="northeurope"
declare sqlServerName="dapr-sqlserver-$(head -c32 < /dev/urandom | base64 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"
declare sqlServerAdminName="dapr"
declare sqlServerAdminPassword=$(head -c32 < /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)

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
			sqlServerName=${OPTARG}
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

if [[ -z "$sqlServerName" ]]; then
	echo "This script will create an Azure SQL Database Logical Server "
	echo "Enter a name for the SQL Logical Server:"
	read sqlServerName
	[[ "${sqlServerName:?}" ]]
fi

if [ -z "$subscriptionId" ] || [ -z "$resourceGroupName" ] || [ -z "$sqlServerName" ]; then
	echo "Either one of subscriptionId, resourceGroupName, sqlServerName is empty"
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

if [ -f "logs/sqlserver.json" ]; then
	echo "Loading Azure SQL Database Logical Server from file..."
	sqlServerResults=$(cat logs/sqlserver.json)
	sqlServerName=$(jq -r '.name' logs/sqlserver.json)
	sqlServerAdminPassword=$(cat logs/sqlserver-password.txt)
else
	echo "Creating Azure SQL Database Logical Server ($sqlServerName)..."
	sqlServerResults=$(az sql server create -n "$sqlServerName" -g "$resourceGroupName" -l "$resourceGroupLocation" -u "$sqlServerAdminName" -p "$sqlServerAdminPassword")
	if [ $? != 0 ];
	then
		echo "Creating the Azure SQL Database Logical Server failed. Aborting..."
		exit 1
	fi
	echo $sqlServerResults | tee logs/sqlserver.json > /dev/null
	echo $sqlServerAdminPassword | tee logs/sqlserver-password.txt > /dev/null
fi

echo "Storing Azure SQL Databases Connection String..."
fullyQualifiedDomainName=$(jq -r '.fullyQualifiedDomainName' logs/sqlserver.json)
connectionString="server=$fullyQualifiedDomainName;user id=$sqlServerAdminName;password=$sqlServerAdminPassword;port=1433;database=statestore;"
kubectl create secret generic azure-sqldb --from-literal="connectionString=$connectionString"

echo "Creating Azure SQL Databases..."
az sql db create -n 'statestore' -g "$resourceGroupName" -s "$sqlServerName" -e 'Basic'

echo "Setting Firewall Rules..."
az sql server firewall-rule create -n 'AllowAllWindowsAzureIps' -g "$resourceGroupName" -s "$sqlServerName" \
	--start-ip-address '0.0.0.0' --end-ip-address '0.0.0.0'

echo "Azure SQL Database has been successfully deployed"
