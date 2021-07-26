#!/bin/bash

set -o errexit
set -o pipefail
# set -o xtrace

log::err() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%N%z')]: \033[31mERROR: \033[0m$@\n"
}

log::info() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%N%z')]: \033[32mINFO: \033[0m$@\n"
}

log::warning() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%N%z')]: \033[33mWARNING: \033[0m$@\n"
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
  local alt_name=$(openssl x509 -text -noout -in ${cert} | grep -A1 'Alternative' | tail -n1 | sed 's/[[:space:]]*Address//g')
  printf "${alt_name}\n"
}

# get subject from the old certificate
cert::get_subj() {
  local cert=${1}.crt
  check_file "${cert}"
  local subj=$(openssl x509 -text -noout -in ${cert}  | grep "Subject:" | sed 's/Subject:/\//g;s/\,/\//;s/[[:space:]]//g')
  printf "${subj}\n"
}

cert::backup_file() {
  local file=${1}
  if [[ ! -e ${file}.old-$(date +%Y%m%d) ]]; then
    cp -rp ${file} ${file}.old-$(date +%Y%m%d)
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
#   $5 (the x509v3 subject alternative name of certificate when the type of certificate is server or peer)
cert::gen_cert() {
  local cert_name=${1}
  local cert_type=${2}
  local subj=${3}
  local cert_days=${4}
  local alt_name=${5}
  local cert=${cert_name}.crt
  local key=${cert_name}.key
  local csr=${cert_name}.csr
  local csr_conf="distinguished_name = dn\n[dn]\n[v3_ext]\nkeyUsage = critical, digitalSignature, keyEncipherment\n"

  check_file "${key}"
  check_file "${cert}"

  # backup certificate when certificate not in ${kubeconf_arr[@]}
  # kubeconf_arr=("controller-manager.crt" "scheduler.crt" "admin.crt" "kubelet.crt")
  # if [[ ! "${kubeconf_arr[@]}" =~ "${cert##*/}" ]]; then
  #   cert::backup_file "${cert}"
  # fi

  case "${cert_type}" in
    client)
      openssl req -new  -key ${key} -subj "${subj}" -reqexts v3_ext \
        -config <(printf "${csr_conf} extendedKeyUsage = clientAuth\n") -out ${csr}
      openssl x509 -in ${csr} -req -CA ${CA_CERT} -CAkey ${CA_KEY} -CAcreateserial -extensions v3_ext \
        -extfile <(printf "${csr_conf} extendedKeyUsage = clientAuth\n") -days ${cert_days} -out ${cert}
      log::info "generated ${cert}"
    ;;
    server)
      openssl req -new  -key ${key} -subj "${subj}" -reqexts v3_ext \
        -config <(printf "${csr_conf} extendedKeyUsage = serverAuth\nsubjectAltName = ${alt_name}\n") -out ${csr}
      openssl x509 -in ${csr} -req -CA ${CA_CERT} -CAkey ${CA_KEY} -CAcreateserial -extensions v3_ext \
        -extfile <(printf "${csr_conf} extendedKeyUsage = serverAuth\nsubjectAltName = ${alt_name}\n") -days ${cert_days} -out ${cert}
      log::info "generated ${cert}"
    ;;
    peer)
      openssl req -new  -key ${key} -subj "${subj}" -reqexts v3_ext \
        -config <(printf "${csr_conf} extendedKeyUsage = serverAuth, clientAuth\nsubjectAltName = ${alt_name}\n") -out ${csr}
      openssl x509 -in ${csr} -req -CA ${CA_CERT} -CAkey ${CA_KEY} -CAcreateserial -extensions v3_ext \
        -extfile <(printf "${csr_conf} extendedKeyUsage = serverAuth, clientAuth\nsubjectAltName = ${alt_name}\n") -days ${cert_days} -out ${cert}
      log::info "generated ${cert}"
    ;;
    *)
      log::err "unknow, unsupported etcd certs type: ${cert_type}, supported type: client, server, peer"
      exit 1
  esac

  rm -f ${csr}
}

cert::update_kubeconf() {
  local cert_name=${1}
  local kubeconf_file=${cert_name}.conf
  local cert=${cert_name}.crt
  local key=${cert_name}.key

  # generate  certificate
  check_file ${kubeconf_file}
  # get the key from the old kubeconf
  grep "client-key-data" ${kubeconf_file} | awk {'print$2'} | base64 -d > ${key}
  # get the old certificate from the old kubeconf
  grep "client-certificate-data" ${kubeconf_file} | awk {'print$2'} | base64 -d > ${cert}
  # get subject from the old certificate
  local subj=$(cert::get_subj ${cert_name})
  cert::gen_cert "${cert_name}" "client" "${subj}" "${CAER_DAYS}"
  # get certificate base64 code
  local cert_base64=$(base64 -w 0 ${cert})

  # backup kubeconf
  # cert::backup_file "${kubeconf_file}"

  # set certificate base64 code to kubeconf
  sed -i 's/client-certificate-data:.*/client-certificate-data: '${cert_base64}'/g' ${kubeconf_file}

  log::info "generated new ${kubeconf_file}"
  rm -f ${cert}
  rm -f ${key}

  # set config for kubectl
  if [[ ${cert_name##*/} == "admin" ]]; then
    mkdir -p ${HOME}/.kube
    local config=${HOME}/.kube/config
    local config_backup=${HOME}/.kube/config.old-$(date +%Y%m%d)
    if [[ -f ${config} ]] && [[ ! -f ${config_backup} ]]; then
      cp -fp ${config} ${config_backup}
      log::info "backup ${config} to ${config_backup}"
    fi
    cp -fp ${kubeconf_file} ${HOME}/.kube/config
    log::info "copy the admin.conf to ${HOME}/.kube/config for kubectl"
  fi
}

cert::update_etcd_cert() {
  PKI_PATH=${KUBE_PATH}/pki/etcd
  CA_CERT=${PKI_PATH}/ca.crt
  CA_KEY=${PKI_PATH}/ca.key

  check_file "${CA_CERT}"
  check_file "${CA_KEY}"

  # generate etcd server certificate
  # /etc/kubernetes/pki/etcd/server
  CART_NAME=${PKI_PATH}/server
  subject_alt_name=$(cert::get_subject_alt_name ${CART_NAME})
  cert::gen_cert "${CART_NAME}" "peer" "/CN=etcd-server" "${CAER_DAYS}" "${subject_alt_name}"

  # generate etcd peer certificate
  # /etc/kubernetes/pki/etcd/peer
  CART_NAME=${PKI_PATH}/peer
  subject_alt_name=$(cert::get_subject_alt_name ${CART_NAME})
  cert::gen_cert "${CART_NAME}" "peer" "/CN=etcd-peer" "${CAER_DAYS}" "${subject_alt_name}"

  # generate etcd healthcheck-client certificate
  # /etc/kubernetes/pki/etcd/healthcheck-client
  CART_NAME=${PKI_PATH}/healthcheck-client
  cert::gen_cert "${CART_NAME}" "client" "/O=system:masters/CN=kube-etcd-healthcheck-client" "${CAER_DAYS}"

  # generate apiserver-etcd-client certificate
  # /etc/kubernetes/pki/apiserver-etcd-client
  check_file "${CA_CERT}"
  check_file "${CA_KEY}"
  PKI_PATH=${KUBE_PATH}/pki
  CART_NAME=${PKI_PATH}/apiserver-etcd-client
  cert::gen_cert "${CART_NAME}" "client" "/O=system:masters/CN=kube-apiserver-etcd-client" "${CAER_DAYS}"

  # restart etcd
  docker ps | awk '/k8s_etcd/{print$1}' | xargs -r -I '{}' docker restart {} || true
  log::info "restarted etcd"
}

cert::update_master_cert() {
  PKI_PATH=${KUBE_PATH}/pki
  CA_CERT=${PKI_PATH}/ca.crt
  CA_KEY=${PKI_PATH}/ca.key

  check_file "${CA_CERT}"
  check_file "${CA_KEY}"

  # generate apiserver server certificate
  # /etc/kubernetes/pki/apiserver
  CART_NAME=${PKI_PATH}/apiserver
  subject_alt_name=$(cert::get_subject_alt_name ${CART_NAME})
  cert::gen_cert "${CART_NAME}" "server" "/CN=kube-apiserver" "${CAER_DAYS}" "${subject_alt_name}"

  # generate apiserver-kubelet-client certificate
  # /etc/kubernetes/pki/apiserver-kubelet-client
  CART_NAME=${PKI_PATH}/apiserver-kubelet-client
  cert::gen_cert "${CART_NAME}" "client" "/O=system:masters/CN=kube-apiserver-kubelet-client" "${CAER_DAYS}"

  # generate kubeconf for controller-manager,scheduler,kubectl and kubelet
  # /etc/kubernetes/controller-manager,scheduler,admin,kubelet.conf
  cert::update_kubeconf "${KUBE_PATH}/controller-manager"
  cert::update_kubeconf "${KUBE_PATH}/scheduler"
  cert::update_kubeconf "${KUBE_PATH}/admin"
  # check kubelet.conf
  # https://github.com/kubernetes/kubeadm/issues/1753
  set +e
  grep kubelet-client-current.pem /etc/kubernetes/kubelet.conf > /dev/null 2>&1
  kubelet_cert_auto_update=$?
  set -e
  if [[ "$kubelet_cert_auto_update" == "0" ]]; then
    log::warning "does not need to update kubelet.conf"
  else
    cert::update_kubeconf "${KUBE_PATH}/kubelet"
  fi

  # generate front-proxy-client certificate
  # use front-proxy-client ca
  CA_CERT=${PKI_PATH}/front-proxy-ca.crt
  CA_KEY=${PKI_PATH}/front-proxy-ca.key
  check_file "${CA_CERT}"
  check_file "${CA_KEY}"
  CART_NAME=${PKI_PATH}/front-proxy-client
  cert::gen_cert "${CART_NAME}" "client" "/CN=front-proxy-client" "${CAER_DAYS}"

  # restart apiserve, controller-manager, scheduler and kubelet
  docker ps | awk '/k8s_kube-apiserver/{print$1}' | xargs -r -I '{}' docker restart {} || true
  log::info "restarted kube-apiserver"
  docker ps | awk '/k8s_kube-controller-manager/{print$1}' | xargs -r -I '{}' docker restart {} || true
  log::info "restarted kube-controller-manager"
  docker ps | awk '/k8s_kube-scheduler/{print$1}' | xargs -r -I '{}' docker restart {} || true
  log::info "restarted kube-scheduler"
  systemctl restart kubelet
  log::info "restarted kubelet"
}

main() {
  local node_tpye=$1
  
  KUBE_PATH=/etc/kubernetes
  CAER_DAYS=3650

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
