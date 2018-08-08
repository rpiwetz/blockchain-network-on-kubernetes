
KUBECONFIG_FOLDER=${PWD}/configFiles

oc delete -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml
oc delete -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml

oc delete -f ${KUBECONFIG_FOLDER}/join_channel.yaml
oc delete -f ${KUBECONFIG_FOLDER}/create_channel.yaml

oc delete -f ${KUBECONFIG_FOLDER}/peersDeployment.yaml
oc delete -f ${KUBECONFIG_FOLDER}/blockchain-services.yaml

oc delete -f ${KUBECONFIG_FOLDER}/generateArtifactsJob.yaml
oc delete -f ${KUBECONFIG_FOLDER}/copyArtifactsJob.yaml

oc delete -f ${KUBECONFIG_FOLDER}/createVolume.yaml

sleep 15

echo -e "\npv:"
oc get pv
echo -e "\npvc:"
oc get pvc
echo -e "\njobs:"
oc get jobs
echo -e "\ndeployments:"
oc get deployments
echo -e "\nservices:"
oc get services
echo -e "\npods:"
oc get pods

echo -e "\nNetwork Deleted!!\n"

