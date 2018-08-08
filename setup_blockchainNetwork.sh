#!/bin/bash

if [ -d "${PWD}/configFiles" ]; then
    KUBECONFIG_FOLDER=${PWD}/configFiles
else
    echo "Configuration files are not found."
    exit
fi


# Creating Persistant Volume
echo -e "\nCreating volume"
if [ "$(oc get pvc | grep shared-pvc | awk '{print $2}')" != "Bound" ]; then
    echo "The Persistant Volume does not seem to exist or is not bound"
    echo "Creating Persistant Volume"

    if [ "$1" == "--paid" ]; then
        echo "You passed argument --paid. Make sure you have an IBM Cloud Kubernetes - Standard tier. Else, remove --paid option"
        echo "Running: oc create -f ${KUBECONFIG_FOLDER}/createVolume-paid.yaml"
        oc create -f ${KUBECONFIG_FOLDER}/createVolume-paid.yaml
        sleep 5
    else
        echo "Running: oc create -f ${KUBECONFIG_FOLDER}/createVolume.yaml"
        oc create -f ${KUBECONFIG_FOLDER}/createVolume.yaml
        sleep 5
    fi

    if [ "oc get pvc | grep shared-pvc | awk '{print $3}'" != "shared-pv" ]; then
        echo "Success creating Persistant Volume"
    else
        echo "Failed to create Persistant Volume"
    fi
else
    echo "The Persistant Volume exists, not creating again"
fi

# Copy the required files(configtx.yaml, cruypto-config.yaml, sample chaincode etc.) into volume
echo -e "\nCreating Copy artifacts job."
echo "Running: oc create -f ${KUBECONFIG_FOLDER}/copyArtifactsJob.yaml"
oc create -f ${KUBECONFIG_FOLDER}/copyArtifactsJob.yaml

pod=$(oc get pods --selector=job-name=copyartifacts --output=jsonpath={.items..metadata.name})

podSTATUS=$(oc get pods --selector=job-name=copyartifacts --output=jsonpath={.items..phase})

while [ "${podSTATUS}" != "Running" ]; do
    echo "Wating for container of copy artifact pod to run. Current status of ${pod} is ${podSTATUS}"
    sleep 5;
    if [ "${podSTATUS}" == "Error" ]; then
        echo "There is an error in copyartifacts job. Please check logs."
        exit 1
    fi
    podSTATUS=$(oc get pods --selector=job-name=copyartifacts --output=jsonpath={.items..phase})
done

echo -e "${pod} is now ${podSTATUS}"
echo -e "\nStarting to copy artifacts in persistent volume."

#fix for this script to work on icp and ICS
oc cp ./artifacts $pod:/shared/

echo "Waiting for 10 more seconds for copying artifacts to avoid any network delay"
sleep 10
JOBSTATUS=$(oc get jobs |grep "copyartifacts" |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for copyartifacts job to complete"
    sleep 1;
    PODSTATUS=$(oc get pods | grep "copyartifacts" | awk '{print $3}')
        if [ "${PODSTATUS}" == "Error" ]; then
            echo "There is an error in copyartifacts job. Please check logs."
            exit 1
        fi
    JOBSTATUS=$(oc get jobs |grep "copyartifacts" |awk '{print $3}')
done
echo "Copy artifacts job completed"


# Generate Network artifacts using configtx.yaml and crypto-config.yaml
echo -e "\nGenerating the required artifacts for Blockchain network"
echo "Running: oc create -f ${KUBECONFIG_FOLDER}/generateArtifactsJob.yaml"
oc create -f ${KUBECONFIG_FOLDER}/generateArtifactsJob.yaml

JOBSTATUS=$(oc get jobs |grep utils|awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for generateArtifacts job to complete"
    sleep 1;
    # UTILSLEFT=$(oc get pods | grep utils | awk '{print $2}')
    UTILSSTATUS=$(oc get pods | grep "utils" | awk '{print $3}')
    if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in utils job. Please check logs."
            exit 1
    fi
    # UTILSLEFT=$(oc get pods | grep utils | awk '{print $2}')
    JOBSTATUS=$(oc get jobs |grep utils|awk '{print $3}')
done


# Create services for all peers, ca, orderer
echo -e "\nCreating Services for blockchain network"
echo "Running: oc create -f ${KUBECONFIG_FOLDER}/blockchain-services.yaml"
oc create -f ${KUBECONFIG_FOLDER}/blockchain-services.yaml


# Create peers, ca, orderer using Kubernetes Deployments
echo -e "\nCreating new Deployment to create four peers in network"
echo "Running: oc create -f ${KUBECONFIG_FOLDER}/peersDeployment.yaml"
oc create -f ${KUBECONFIG_FOLDER}/peersDeployment.yaml

echo "Checking if all deployments are ready"

NUMPENDING=$(oc get deployments | grep blockchain | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
while [ "${NUMPENDING}" != "0" ]; do
    echo "Waiting on pending deployments. Deployments pending = ${NUMPENDING}"
    NUMPENDING=$(oc get deployments | grep blockchain | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
    sleep 1
done

echo "Waiting for 15 seconds for peers and orderer to settle"
sleep 15


# Generate channel artifacts using configtx.yaml and then create channel
echo -e "\nCreating channel transaction artifact and a channel"
echo "Running: oc create -f ${KUBECONFIG_FOLDER}/create_channel.yaml"
oc create -f ${KUBECONFIG_FOLDER}/create_channel.yaml

JOBSTATUS=$(oc get jobs |grep createchannel |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for createchannel job to be completed"
    sleep 1;
    if [ "$(oc get pods | grep createchannel | awk '{print $3}')" == "Error" ]; then
        echo "Create Channel Failed"
        exit 1
    fi
    JOBSTATUS=$(oc get jobs |grep createchannel |awk '{print $3}')
done
echo "Create Channel Completed Successfully"


# Join all peers on a channel
echo -e "\nCreating joinchannel job"
echo "Running: oc create -f ${KUBECONFIG_FOLDER}/join_channel.yaml"
oc create -f ${KUBECONFIG_FOLDER}/join_channel.yaml

JOBSTATUS=$(oc get jobs |grep joinchannel |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for joinchannel job to be completed"
    sleep 1;
    if [ "$(oc get pods | grep joinchannel | awk '{print $3}')" == "Error" ]; then
        echo "Join Channel Failed"
        exit 1
    fi
    JOBSTATUS=$(oc get jobs |grep joinchannel |awk '{print $3}')
done
echo "Join Channel Completed Successfully"


# Install chaincode on each peer
echo -e "\nCreating installchaincode job"
echo "Running: oc create -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml"
oc create -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml

JOBSTATUS=$(oc get jobs |grep chaincodeinstall |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for chaincodeinstall job to be completed"
    sleep 1;
    if [ "$(oc get pods | grep chaincodeinstall | awk '{print $3}')" == "Error" ]; then
        echo "Chaincode Install Failed"
        exit 1
    fi
    JOBSTATUS=$(oc get jobs |grep chaincodeinstall |awk '{print $3}')
done
echo "Chaincode Install Completed Successfully"


# Instantiate chaincode on channel
echo -e "\nCreating chaincodeinstantiate job"
echo "Running: oc create -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml"
oc create -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml

JOBSTATUS=$(oc get jobs |grep chaincodeinstantiate |awk '{print $3}')
while [ "${JOBSTATUS}" != "1" ]; do
    echo "Waiting for chaincodeinstantiate job to be completed"
    sleep 1;
    if [ "$(oc get pods | grep chaincodeinstantiate | awk '{print $3}')" == "Error" ]; then
        echo "Chaincode Instantiation Failed"
        exit 1
    fi
    JOBSTATUS=$(oc get jobs |grep chaincodeinstantiate |awk '{print $3}')
done
echo "Chaincode Instantiation Completed Successfully"

sleep 15
echo -e "\nNetwork Setup Completed !!"
