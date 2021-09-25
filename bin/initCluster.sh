#!/bin/bash

# This script will set up the infrastructure to deploy an OKD 4.X cluster
# Follow the documentation at https://upstreamwithoutapaddle.com/home-lab/lab-intro/

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

function createInstallConfig() {
cat << EOF > ${OKD_LAB_PATH}/install-config-upi.yaml
apiVersion: v1
baseDomain: ${CLUSTER_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
networking:
  networkType: OpenShiftSDN
  clusterNetwork:
  - cidr: 10.100.0.0/14 
    hostPrefix: 23 
  serviceNetwork: 
  - 172.30.0.0/16
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 3
platform:
  none: {}
pullSecret: '${PULL_SECRET}'
sshKey: ${SSH_KEY}
additionalTrustBundle: |
${NEXUS_CERT}
imageContentSources:
- mirrors:
  - nexus.${LAB_DOMAIN}:5001/${OKD_RELEASE}
  source: quay.io/openshift/okd
- mirrors:
  - nexus.${LAB_DOMAIN}:5001/${OKD_RELEASE}
  source: quay.io/openshift/okd-content
EOF
}

CONFIG_FILE=$1
CLUSTER_NAME=$(yq e .cluster-sub-domain ${CONFIG_FILE})
SUB_DOMAIN=$(yq e .cluster-name ${CONFIG_FILE})
CLUSTER_DOMAIN="${SUB_DOMAIN}.${LAB_DOMAIN}"
OKD_RELEASE=$(oc version --client=true | cut -d" " -f3)
SSH_KEY=$(cat ${OKD_LAB_PATH}/id_rsa.pub)
PULL_SECRET=$(cat ${OKD_LAB_PATH}/pull_secret.json)
NEXUS_CERT=$(openssl s_client -showcerts -connect nexus.${LAB_DOMAIN}:5001 </dev/null 2>/dev/null|openssl x509 -outform PEM | while read line; do echo "  $line"; done)

# Create and deploy ignition files
rm -rf ${OKD_LAB_PATH}/ipxe-work-dir
rm -rf ${OKD_LAB_PATH}/okd-install-dir
mkdir ${OKD_LAB_PATH}/okd-install-dir
mkdir -p ${OKD_LAB_PATH}/ipxe-work-dir/ignition
createInstallConfig
cp ${OKD_LAB_PATH}/install-config-upi.yaml ${OKD_LAB_PATH}/okd-install-dir/install-config.yaml
openshift-install --dir=${OKD_LAB_PATH}/okd-install-dir create ignition-configs
cp ${OKD_LAB_PATH}/okd-install-dir/*.ign ${OKD_LAB_PATH}/ipxe-work-dir/

${OKD_LAB_PATH}/bin/deployOkdNodes.sh ${CONFIG_FILE}
