#!/bin/bash

set -o errexit
set -o pipefail
# set -o xtrace

# set output color
NC='\033[0m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'

log::err() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')][${RED}ERROR${NC}] %b\n" "$@"
}

log::info() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')][INFO] %b\n" "$@"
}

log::warning() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')][${YELLOW}WARNING${NC}] \033[0m%b\n" "$@"
}

check_file() {
  if [[ ! -r  ${1} ]]; then
    log::err "can not find ${1}"
    exit 1
  fi
}

# get x509v3 subject alternative name from the old certificate
cert::get_subject_alt_name() {
  local cert=${1}.crt
  check_file "${cert}"
  local alt_name
  alt_name=$(openssl x509 -text -noout -in "${cert}" | grep -A1 'Alternative' | tail -n1 | sed 's/[[:space:]]*Address//g')
  printf "%s\n" "${alt_name}"
}

# get subject from the old certificate
cert::get_subj() {
  local cert=${1}.crt
  check_file "${cert}"
  local subj
  subj=$(openssl x509 -text -noout -in "${cert}"  | grep "Subject:" | sed 's/Subject:/\//g;s/\,/\//;s/[[:space:]]//g')
  printf "%s\n" "${subj}"
}

cert::backup_file() {
  local file=${1}
  if [[ ! -e ${file}.old-$(date +%Y%m%d) ]]; then
    cp -rp "${file}" "${file}.old-$(date +%Y%m%d)"
    log::info "backup ${file} to ${file}.old-$(date +%Y%m%d)"
  else
    log::warning "does not backup, ${file}.old-$(date +%Y%m%d) already exists"
  fi
}

# generate certificate whit client, server or peer
# Args:
#   $1 (the name of certificate)
#   $2 (the type of certificate, must be one of client, server, peer)
#   $3 (the subject of certificates)
#   $4 (the validity of certificates) (days)
#   $5 (the name of ca)
#   $6 (the x509v3 subject alternative name of certificate when the type of certificate is server or peer)
cert::gen_cert() {
  local cert_name=${1}
  local cert_type=${2}
  local subj=${3}
  local cert_days=${4}
  local ca_name=${5}
  local alt_name=${6}
  local ca_cert=${ca_name}.crt
  local ca_key=${ca_name}.key
  local cert=${cert_name}.crt
  local key=${cert_name}.key
  local csr=${cert_name}.csr
  local csr_conf='distinguished_name = dn\n[dn]\n[v3_ext]\nkeyUsage = critical, digitalSignature, keyEncipherment\n'

  check_file "${ca_cert}"
  check_file "${ca_key}"
  check_file "${cert}"
  check_file "${key}"

  case "${cert_type}" in
    client)
      # gen csr
      openssl req -new  -key "${key}" -subj "${subj}" -reqexts v3_ext \
        -config <(printf "%bextendedKeyUsage = clientAuth\n" "${csr_conf}") \
        -out "${csr}" > /dev/null 2>&1
      # gen cert
      openssl x509 -in "${csr}" -req -CA "${ca_cert}" -CAkey "${ca_key}" -CAcreateserial -extensions v3_ext \
        -extfile <(printf "%bextendedKeyUsage = clientAuth\n" "${csr_conf}") \
        -days "${cert_days}" -out "${cert}" > /dev/null 2>&1
    ;;
    server)
      # gen csr
      openssl req -new  -key "${key}" -subj "${subj}" -reqexts v3_ext \
        -config <(printf "%bextendedKeyUsage = serverAuth\nsubjectAltName = %b\n" "${csr_conf}" "${alt_name}") \
        -out "${csr}" > /dev/null 2>&1
      # gen cert
      openssl x509 -in "${csr}" -req -CA "${ca_cert}" -CAkey "${ca_key}" -CAcreateserial -extensions v3_ext \
        -extfile <(printf "%bextendedKeyUsage = serverAuth\nsubjectAltName = %b\n" "${csr_conf}" "${alt_name}") \
        -days "${cert_days}" -out "${cert}" > /dev/null 2>&1
    ;;
    peer)
      # gen csr
      openssl req -new  -key "${key}" -subj "${subj}" -reqexts v3_ext \
        -config <(printf "%bextendedKeyUsage = serverAuth, clientAuth\nsubjectAltName = %b\n" "${csr_conf}" "${alt_name}") \
        -out "${csr}" > /dev/null 2>&1
      # gen cert
      openssl x509 -in "${csr}" -req -CA "${ca_cert}" -CAkey "${ca_key}" -CAcreateserial -extensions v3_ext \
        -extfile <(printf "%bextendedKeyUsage = serverAuth, clientAuth\nsubjectAltName = %b\n" "${csr_conf}" "${alt_name}") \
        -days "${cert_days}" -out "${cert}" > /dev/null 2>&1
    ;;
    *)
      log::err "unknow, unsupported certs type: ${YELLOW}${cert_type}${NC}, supported type: client, server, peer"
      exit 1
  esac

  log::info "${GREEN}generated ${BLUE}${cert}${NC}"
  rm -f "${csr}"
}

cert::update_kubeconf() {
  local cert_name=${1}
  local kubeconf_file=${cert_name}.conf
  local cert=${cert_name}.crt
  local key=${cert_name}.key
  local subj
  local cert_base64

  # generate  certificate
  check_file "${kubeconf_file}"
  # get the key from the old kubeconf
  grep "client-key-data" "${kubeconf_file}" | awk '{print$2}' | base64 -d > "${key}"
  # get the old certificate from the old kubeconf
  grep "client-certificate-data" "${kubeconf_file}" | awk '{print$2}' | base64 -d > "${cert}"
  # get subject from the old certificate
  subj=$(cert::get_subj "${cert_name}")
  cert::gen_cert "${cert_name}" "client" "${subj}" "${CAER_DAYS}" "${CERT_CA}"
  # get certificate base64 code
  cert_base64=$(base64 -w 0 "${cert}")

  # set certificate base64 code to kubeconf
  sed -i 's/client-certificate-data:.*/client-certificate-data: '"${cert_base64}"'/g' "${kubeconf_file}"

  log::info "generated new ${kubeconf_file}"
  rm -f "${cert}"
  rm -f "${key}"

  # copy admin.conf to ${HOME}/.kube/config
  if [[ ${cert_name##*/} == "admin" ]]; then
    mkdir -p "${HOME}/.kube"
    local config=${HOME}/.kube/config
    local config_backup
    config_backup=${HOME}/.kube/config.old-$(date +%Y%m%d)
    if [[ -f ${config} ]] && [[ ! -f ${config_backup} ]]; then
      cp -fp "${config}" "${config_backup}"
      log::info "backup ${config} to ${config_backup}"
    fi
    cp -fp "${kubeconf_file}" "${HOME}/.kube/config"
    log::info "copy the admin.conf to ${HOME}/.kube/config"
  fi
}

cert::update_etcd_cert() {
  local subj
  local subject_alt_name

  # generate etcd server certificate
  # /etc/kubernetes/pki/etcd/server
  subj=$(cert::get_subj "${ETCD_CERT_SERVER}")
  subject_alt_name=$(cert::get_subject_alt_name "${ETCD_CERT_SERVER}")
  cert::gen_cert "${ETCD_CERT_SERVER}" "peer" "${subj}" "${CAER_DAYS}" "${ETCD_CERT_CA}" "${subject_alt_name}"

  # generate etcd peer certificate
  # /etc/kubernetes/pki/etcd/peer
  subj=$(cert::get_subj "${ETCD_CERT_PEER}")
  subject_alt_name=$(cert::get_subject_alt_name "${ETCD_CERT_PEER}")
  cert::gen_cert "${ETCD_CERT_PEER}" "peer" "${subj}" "${CAER_DAYS}" "${ETCD_CERT_CA}" "${subject_alt_name}"

  # generate etcd healthcheck-client certificate
  # /etc/kubernetes/pki/etcd/healthcheck-client
  subj=$(cert::get_subj "${ETCD_CERT_HEALTHCHECK_CLIENT}")
  cert::gen_cert "${ETCD_CERT_HEALTHCHECK_CLIENT}" "client" "${subj}" "${CAER_DAYS}" "${ETCD_CERT_CA}"

  # generate apiserver-etcd-client certificate
  # /etc/kubernetes/pki/apiserver-etcd-client
  subj=$(cert::get_subj "${ETCD_CERT_APISERVER_ETCD_CLIENT}")
  cert::gen_cert "${ETCD_CERT_APISERVER_ETCD_CLIENT}" "client" "${subj}" "${CAER_DAYS}" "${ETCD_CERT_CA}"

  # restart etcd
  docker ps | awk '/k8s_etcd/{print$1}' | xargs -r -I '{}' docker restart {} > /dev/null 2>&1 || true
  log::info "restarted etcd"
}

cert::update_master_cert() {
  local subj
  local subject_alt_name

  # generate apiserver server certificate
  # /etc/kubernetes/pki/apiserver
  subj=$(cert::get_subj "${CERT_APISERVER}")
  subject_alt_name=$(cert::get_subject_alt_name "${CERT_APISERVER}")
  cert::gen_cert "${CERT_APISERVER}" "server" "${subj}" "${CAER_DAYS}" "${CERT_CA}" "${subject_alt_name}"

  # generate apiserver-kubelet-client certificate
  # /etc/kubernetes/pki/apiserver-kubelet-client
  subj=$(cert::get_subj "${CERT_APISERVER_KUBELET_CLIENT}")
  cert::gen_cert "${CERT_APISERVER_KUBELET_CLIENT}" "client" "${subj}" "${CAER_DAYS}" "${CERT_CA}"

  # generate kubeconf for controller-manager,scheduler,kubectl and kubelet
  # /etc/kubernetes/controller-manager,scheduler,admin,kubelet.conf
  cert::update_kubeconf "${CONF_CONTROLLER_MANAGER}"
  cert::update_kubeconf "${CONF_SCHEDULER}"
  cert::update_kubeconf "${CONF_ADMIN}"
  # check kubelet.conf
  # https://github.com/kubernetes/kubeadm/issues/1753
  set +e
  grep kubelet-client-current.pem /etc/kubernetes/kubelet.conf > /dev/null 2>&1
  kubelet_cert_auto_update=$?
  set -e
  if [[ "$kubelet_cert_auto_update" == "0" ]]; then
    log::info "does not need to update kubelet.conf"
  else
    cert::update_kubeconf "${CONF_KUBELET}"
  fi

  # generate front-proxy-client certificate
  # /etc/kubernetes/pki/front-proxy-client
  subj=$(cert::get_subj "${FRONT_PROXY_CLIENT}")
  cert::gen_cert "${FRONT_PROXY_CLIENT}" "client" "${subj}" "${CAER_DAYS}" "${FRONT_PROXY_CA}"

  # restart apiserve, controller-manager, scheduler and kubelet
  docker ps | awk '/k8s_kube-apiserver/{print$1}' | xargs -r -I '{}' docker restart {} > /dev/null 2>&1 || true
  log::info "restarted kube-apiserver"
  docker ps | awk '/k8s_kube-controller-manager/{print$1}' | xargs -r -I '{}' docker restart {} > /dev/null 2>&1 || true
  log::info "restarted kube-controller-manager"
  docker ps | awk '/k8s_kube-scheduler/{print$1}' | xargs -r -I '{}' docker restart {} > /dev/null 2>&1 || true
  log::info "restarted kube-scheduler"
  systemctl restart kubelet
  log::info "restarted kubelet"
}

main() {
  local node_tpye=$1
  
  CAER_DAYS=3650

  KUBE_PATH=/etc/kubernetes
  PKI_PATH=${KUBE_PATH}/pki

  # master certificates path
  # apiserver
  CERT_CA=${PKI_PATH}/ca
  CERT_APISERVER=${PKI_PATH}/apiserver
  CERT_APISERVER_KUBELET_CLIENT=${PKI_PATH}/apiserver-kubelet-client
  CONF_CONTROLLER_MANAGER=${KUBE_PATH}/controller-manager
  CONF_SCHEDULER=${KUBE_PATH}/scheduler
  CONF_ADMIN=${KUBE_PATH}/admin
  CONF_KUBELET=${KUBE_PATH}/kubelet
  # front-proxy
  FRONT_PROXY_CA=${PKI_PATH}/front-proxy-ca
  FRONT_PROXY_CLIENT=${PKI_PATH}/front-proxy-client

  # etcd certificates path
  ETCD_CERT_CA=${PKI_PATH}/etcd/ca
  ETCD_CERT_SERVER=${PKI_PATH}/etcd/server
  ETCD_CERT_PEER=${PKI_PATH}/etcd/peer
  ETCD_CERT_HEALTHCHECK_CLIENT=${PKI_PATH}/etcd/healthcheck-client
  ETCD_CERT_APISERVER_ETCD_CLIENT=${PKI_PATH}/apiserver-etcd-client

  case ${node_tpye} in
    # etcd)
	  # # update etcd certificates
    #   cert::update_etcd_cert
    # ;;
    master)
      # backup $KUBE_PATH to $KUBE_PATH.old-$(date +%Y%m%d)
      cert::backup_file "${KUBE_PATH}"
	    # update master certificates and kubeconf
      cert::update_master_cert
    ;;
    all)
      # backup $KUBE_PATH to $KUBE_PATH.old-$(date +%Y%m%d)
      cert::backup_file "${KUBE_PATH}"
      # update etcd certificates
      cert::update_etcd_cert
      # update master certificates and kubeconf
      cert::update_master_cert
    ;;
    *)
      log::err "unknow, unsupported certs type: ${node_tpye}, supported type: all, master"
      printf "Documentation: https://github.com/yuyicai/update-kube-cert
  example:
    '\033[32m./update-kubeadm-cert.sh all\033[0m' update all etcd certificates, master certificates and kubeconf
      /etc/kubernetes
      ├── admin.conf
      ├── controller-manager.conf
      ├── scheduler.conf
      ├── kubelet.conf
      └── pki
          ├── apiserver.crt
          ├── apiserver-etcd-client.crt
          ├── apiserver-kubelet-client.crt
          ├── front-proxy-client.crt
          └── etcd
              ├── healthcheck-client.crt
              ├── peer.crt
              └── server.crt

    '\033[32m./update-kubeadm-cert.sh master\033[0m' update only master certificates and kubeconf
      /etc/kubernetes
      ├── admin.conf
      ├── controller-manager.conf
      ├── scheduler.conf
      ├── kubelet.conf
      └── pki
          ├── apiserver.crt
          ├── apiserver-kubelet-client.crt
          └── front-proxy-client.crt
"
      exit 1
    esac
}

main "$@"
