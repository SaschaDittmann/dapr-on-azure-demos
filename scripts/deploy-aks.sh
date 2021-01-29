#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
export LC_CTYPE=C

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

usage() { echo "Usage: $0 -s <subscriptionId> -g <resourceGroupName> -l <resourceGroupLocation> -k <aksClusterName> -r <containerRegistryName> -v <kubernetesVersion> -d <dnsPrefix> -n <vnetName> -p <servicePrincipalName>" 1>&2; exit 1; }

declare subscriptionId=""
declare resourceGroupName="dapr"
declare resourceGroupLocation="northeurope"
declare aksClusterName="dapr-aks"
declare containerRegistryName="dapracr$(head -c32 < /dev/urandom | base64 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"
declare kubernetesVersion="1.18.14"
declare dnsPrefix="dapr-demos"
declare vnetName="dapr-vnet"
declare servicePrincipalName="http://dapr-spn"
declare vmSize="Standard_DS2_v2"
declare nodepoolName="agentpool"

# Initialize parameters specified from command line
while getopts ":s:g:l:k:r:v:d:n:p:h" arg; do
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
		k)
			aksClusterName=${OPTARG}
			;;
		r)
			containerRegistryName=${OPTARG}
			;;
		v)
			kubernetesVersion=${OPTARG}
			;;
		d)
			dnsPrefix=${OPTARG}
			;;
		n)
			vnetName=${OPTARG}
			;;
		p)
			servicePrincipalName=${OPTARG}
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

if [[ -z "$aksClusterName" ]]; then
	echo "This script will create an Azure Kubernetes Service cluster "
	echo "Enter a name for the AKS cluster:"
	read aksClusterName
	[[ "${aksClusterName:?}" ]]
fi

if [[ -z "$containerRegistryName" ]]; then
	echo "This script will create an Azure Container Registry "
	echo "This service is used to store private docker images "
	echo "Enter a name for the ACR:"
	read containerRegistryName
	[[ "${containerRegistryName:?}" ]]
fi

if [[ -z "$kubernetesVersion" ]]; then
	echo "Which version of Kubernetes should be used for the AKS cluster "
	echo "Enter a Kubernetes version:"
	read kubernetesVersion
	[[ "${kubernetesVersion:?}" ]]
fi

if [[ -z "$vnetName" ]]; then
	echo "This script will create a Virtual Network for the AKS "
	echo "Enter a name for the Virtual Network:"
	read vnetName
	[[ "${vnetName:?}" ]]
fi

if [[ -z "$servicePrincipalName" ]]; then
	echo "This scripts creates a Service Principal to control the inter-service access "
	echo "The name of a Service Principal is in the format of an URI, e.g. http://kubeflow-spn "
	echo "Enter a name for the Service Principal:"
	read servicePrincipalName
	[[ "${servicePrincipalName:?}" ]]
fi

if [ -z "$subscriptionId" ] || [ -z "$resourceGroupName" ] || [ -z "$aksClusterName" ] || [ -z "$containerRegistryName" ] || [ -z "$vnetName" ] || [ -z "$servicePrincipalName" ]; then
	echo "Either one of subscriptionId, resourceGroupName, aksClusterName, containerRegistryName, vnetName, servicePrincipalName is empty"
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

if [ -f "logs/spn.json" ]; then
    echo "Loading Service Principal from file..."
	spnResult=$(cat logs/spn.json)
else
	echo "Creating Service Principal..."
	spnResult=$(az ad sp create-for-rbac -n "$servicePrincipalName" --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName" --skip-assignment)
	if [ $? != 0 ];
	then
		echo "Creating the Service Principal failed. Aborting..."
		exit 1
	fi
	echo $spnResult | tee logs/spn.json > /dev/null
	sleep 30
fi
servicePrincipalClientId=$(echo $spnResult | jq -r .appId)
servicePrincipalClientSecret=$(echo $spnResult | jq -r .password)

if [ -f "logs/spn-role-assignment.json" ]; then
    echo "Loading Service Principal Contributor Assignment from file..."
	roleAssignmentResult=$(cat logs/spn-role-assignment.json)
else
	roleAssignmentResult=$(az role assignment create --assignee "$servicePrincipalName" --role "Contributor" -g "$resourceGroupName")
	if [ $? != 0 ]; then
		echo "Assigning the Contributor to the Service Principal failed. Aborting..."
		exit 1
	fi
	echo $roleAssignmentResult | tee logs/spn-role-assignment.json > /dev/null
fi

if [ -f "logs/vnet-subnet-default.json" ]; then
    echo "Loading Virtual Network from file..."
	subnetDefaultResult=$(cat logs/vnet-subnet-default.json)
else
	echo "Creating Virtual Network..."
	subnetDefaultResult=$(az network vnet create -g "$resourceGroupName" -n "$vnetName" -l "$resourceGroupLocation" \
		--address-prefix 10.0.0.0/8 --subnet-name "default" --subnet-prefix 10.240.0.0/16)
	if [ $? != 0 ]; then
		echo "Creating the Virtual Network failed. Aborting..."
		exit 1
	fi
	echo $subnetDefaultResult | tee logs/vnet-subnet-default.json > /dev/null
fi
subnetDefaultId=$(jq -r '.newVNet.subnets[0].id' logs/vnet-subnet-default.json)

if [ -f "logs/aks.json" ]; then
    echo "Loading Azure Kubernetes Service from file..."
	aksResult=$(cat logs/aks.json)
else
	#Start deployment
	echo "Creating Azure Kubernetes Service..."
	if [[ -z "$dnsPrefix" ]]; then
		aksResult=$(az aks create -g "$resourceGroupName" -n "$aksClusterName" -l "$resourceGroupLocation" \
			-s "$vmSize" -c 3 -k "$kubernetesVersion" \
			--service-principal "$servicePrincipalClientId" --client-secret "$servicePrincipalClientSecret" \
			--enable-cluster-autoscaler --min-count 1 --max-count 10 \
			--network-plugin "azure" \
			--vm-set-type "VirtualMachineScaleSets" --load-balancer-sku "standard" \
			--dns-service-ip "10.0.0.10" --docker-bridge-address "172.17.0.1/16" \
			--nodepool-name "$nodepoolName" --vnet-subnet-id "$subnetDefaultId" \
			--generate-ssh-keys)
	else
		aksResult=$(az aks create -g "$resourceGroupName" -n "$aksClusterName" -l "$resourceGroupLocation" \
			-s "$vmSize" -c 3 -k "$kubernetesVersion" -p "$dnsPrefix" \
			--service-principal "$servicePrincipalClientId" --client-secret "$servicePrincipalClientSecret" \
			--enable-cluster-autoscaler --min-count 1 --max-count 10 \
			--network-plugin "azure" \
			--vm-set-type "VirtualMachineScaleSets" --load-balancer-sku "standard" \
			--dns-service-ip "10.0.0.10" --docker-bridge-address "172.17.0.1/16" \
			--nodepool-name "$nodepoolName" --vnet-subnet-id "$subnetDefaultId" \
			--generate-ssh-keys)
	fi
	if [ $? != 0 ];
	then
		echo "Deploying the Azure Kubernetes Service failed. Aborting..."
		exit 1
	fi
	echo $aksResult | tee logs/aks.json > /dev/null
fi

if [ -f "logs/acr.json" ]; then
    echo "Loading Azure Container Registry from file..."
	acrResult=$(cat logs/acr.json)
	containerRegistryName=$(jq -r '.name' logs/acr.json)
else
	echo "Creating Azure Container Registry ($containerRegistryName)..."
	acrResult=$(az acr create -g "$resourceGroupName" -n "$containerRegistryName" -l "$resourceGroupLocation" \
		--sku Premium --admin-enabled)
	if [ $? != 0 ];
	then
		echo "Creating the Azure Container Registry failed. Aborting..."
		exit 1
	fi
	echo $acrResult | tee logs/acr.json > /dev/null
fi

if [ -f "logs/aks-attach-acr.json" ]; then
    echo "Loading Attached Azure Container Registry Result from file..."
	aksAttachAcrResult=$(cat logs/aks-attach-acr.json)
else
	echo "Attaching the Azure Container Registry the Azure Kubernetes Service..."
	aksAttachAcrResult=$(az aks update -g "$resourceGroupName" -n "$aksClusterName" --attach-acr "$containerRegistryName")
	if [ $? != 0 ];
	then
		echo "Attaching the Azure Container Registry failed. Aborting..."
		exit 1
	fi
	echo $aksAttachAcrResult | tee logs/aks-attach-acr.json > /dev/null
fi

echo "Configuring kubectl..."
az aks get-credentials -g "$resourceGroupName" -n "$aksClusterName"

if [ -f "logs/aks-enable-monitoring.json" ]; then
    echo "Loading AKS Monitoring from file..."
	aksEnableMonitoringResult=$(cat logs/aks-enable-monitoring.json)
else
	echo "Enabling monitoring of Azure Kubernetes Service (AKS)..."
	#az resource list --resource-type Microsoft.OperationalInsights/workspaces -o json
	workspaceId=$(az resource list --resource-type Microsoft.OperationalInsights/workspaces -o tsv  --query "[?location=='$resourceGroupLocation'].id")
	if [[ -z "$workspaceId" ]]; then
		echo "No Monitoring Workspace found. Skipping..."
	else
		aksEnableMonitoringResult=$(az aks enable-addons -a monitoring -g "$resourceGroupName" -n "$aksClusterName" --workspace-resource-id "$workspaceId")
		if [ $? != 0 ];
		then
			echo "Enable monitoring of Azure Kubernetes Service (AKS) failed. Aborting..."
			exit 1
		fi
		echo $aksEnableMonitoringResult | tee logs/aks-enable-monitoring.json > /dev/null
	fi
fi

echo "Azure Kubernetes Service has been successfully deployed"
