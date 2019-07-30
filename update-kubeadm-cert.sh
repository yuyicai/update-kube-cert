#!/bin/bash

set -o errexit
set -o pipefail
# set -o xtrace

log_err() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%N%z')]: \033[31mERROR: \033[0m$@\n"
}

log_info() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%N%z')]: \033[32mINFO: \033[0m$@\n"
}

log_warning() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%N%z')]: \033[33mWARNING: \033[0m$@\n"
}

check_file() {
  if [[ ! -r  $1 ]]; then
    log_err "can not find $1"
    exit 1
  fi
}

# get the x509v3 subject alternative name from the old certificate
get_subject_alt_name() {
  local cert=${PKI_PATH}/$1.crt
  check_file "${cert}"
  local alt_name=$(openssl x509 -ext subjectAltName -noout -in ${cert} | tail -n1 | sed 's/ *Address//g')
  printf "${alt_name}\n"
}

# Args:
#   $1 (the name of certificate)
#   $2 (the type of certificate, must be one of client, server, peer)
#   $3 (the subject of certificates)
#   $4 (the subject of certificates)
#   $5 (the x509v3 subject alternative name of certificate when the type of certificate is server or peer)
gen_cert() {
  local cert_name=${1}
  local cert_type=${2}
  local subj=${3}
  local cert_days=${4}
  local alt_name=${5}
  local cert=${PKI_PATH}/${cert_name}.crt
  local key=${PKI_PATH}/${cert_name}.key
  local csr=${PKI_PATH}/${cert_name}.csr
  local csr_conf="distinguished_name = dn\n[dn]\n[v3_ext]\nkeyUsage = critical, digitalSignature, keyEncipherment\n"

  if [[ "${cert_name}" == "controller-manager" || "${cert_name}" == "scheduler" || "${cert_name}" == "admin" ]]; then
    check_file "${key}"
  else
    check_file "${key}"
    check_file "${cert}"
    if [[ ! -f ${cert}.old-$(date +%Y%m%d) ]]; then
      cp -p ${cert} ${cert}.old-$(date +%Y%m%d)
      log_info "backup ${cert} to ${cert}.old-$(date +%Y%m%d)"
    else
      log_info "does not backup, ${cert}.old-$(date +%Y%m%d) already exists"
    fi
  fi

  case "${cert_type}" in
    client)
      openssl req -new  -key ${key} -subj "${subj}" -reqexts v3_ext \
        -config <(printf "${csr_conf} extendedKeyUsage = clientAuth\n") -out ${csr}
      openssl x509 -in ${csr} -req -CA ${CA_CERT} -CAkey ${CA_KEY} -CAcreateserial -extensions v3_ext \
        -extfile <(printf "${csr_conf} extendedKeyUsage = clientAuth\n") -days ${cert_days} -out ${cert}
      log_info "generated ${cert}"
    ;;
    server)
      openssl req -new  -key ${key} -subj "${subj}" -reqexts v3_ext \
        -config <(printf "${csr_conf} extendedKeyUsage = serverAuth\nsubjectAltName = ${alt_name}\n") -out ${csr}
      openssl x509 -in ${csr} -req -CA ${CA_CERT} -CAkey ${CA_KEY} -CAcreateserial -extensions v3_ext \
        -extfile <(printf "${csr_conf} extendedKeyUsage = serverAuth\nsubjectAltName = ${alt_name}\n") -days ${cert_days} -out ${cert}
      log_info "generated ${cert}"
    ;;
    peer)
      openssl req -new  -key ${key} -subj "${subj}" -reqexts v3_ext \
        -config <(printf "${csr_conf} extendedKeyUsage = serverAuth, clientAuth\nsubjectAltName = ${alt_name}\n") -out ${csr}
      openssl x509 -in ${csr} -req -CA ${CA_CERT} -CAkey ${CA_KEY} -CAcreateserial -extensions v3_ext \
        -extfile <(printf "${csr_conf} extendedKeyUsage = serverAuth, clientAuth\nsubjectAltName = ${alt_name}\n") -days ${cert_days} -out ${cert}
      log_info "generated ${cert}"
    ;;
    *)
      log_err "unknow, unsupported etcd certs type: ${cert_type}, supported type: client, server, peer"
      exit 1
  esac

  rm -f ${csr}
}

gen_kubeconf() {
  local cert_name=$1
  local kubeconf_file=${KUBE_PATH}/${cert_name}.conf
  local cert=${PKI_PATH}/${cert_name}.crt
  local key=${PKI_PATH}/${cert_name}.key
  local subj="/CN=system:kube-${cert_name}"

  if [[ ${cert_name} == "admin" ]]; then
    subj="/O=system:masters/CN=kubernetes-admin"
    if [[ ! -r ${kubeconf_file} ]]; then
    log_warning "can not find admin_conf, does not generate admin certificate for kubectl"
    return
    fi
  fi

  # generate  certificate
  check_file ${kubeconf_file}
  # get the key from old kubeconf
  grep "client-key-data" ${kubeconf_file} | awk {'print$2'} | base64 -d > ${key}
  gen_cert "${cert_name}" "client" "${subj}" "${CAER_DAYS}"
  local cert_base64=$(base64 -w 0 ${cert})
  if [[ ! -f ${kubeconf_file}.old-$(date +%Y%m%d) ]]; then
    cp -p ${kubeconf_file} ${kubeconf_file}.old-$(date +%Y%m%d)
    log_info "backup ${kubeconf_file} to ${kubeconf_file}.old-$(date +%Y%m%d)"
  else
    log_info "does not backup, ${kubeconf_file}.old-$(date +%Y%m%d) already exists"
  fi
  sed -i 's/client-certificate-data:.*/client-certificate-data: '${cert_base64}'/g' ${kubeconf_file}
  log_info "generated new ${kubeconf_file}"
  rm -f ${cert}
  rm -f ${key}

  if [[ ${cert_name} == "admin" ]]; then
    mkdir -p ~/.kube
    cp -fp ${kubeconf_file} ~/.kube/config
    log_info "copy the admin.conf to ~/.kube/config for kubectl"
  fi
}

update_etcd_cert() {
  check_file "${CA_CERT}"
  check_file "${CA_KEY}"

  # generate etcd server certificate
  CART_NAME=server
  subject_alt_name=$(get_subject_alt_name ${CART_NAME})
  gen_cert "${CART_NAME}" "peer" "/CN=etcd-server" "${CAER_DAYS}" "${subject_alt_name}"

  # generate etcd peer certificate
  CART_NAME=peer
  subject_alt_name=$(get_subject_alt_name ${CART_NAME})
  gen_cert "${CART_NAME}" "peer" "/CN=etcd-peer" "${CAER_DAYS}" "${subject_alt_name}"

  # generate etcd healthcheck-client certificate
  CART_NAME=healthcheck-client
  gen_cert "${CART_NAME}" "client" "/O=system:masters/CN=kube-etcd-healthcheck-client" "${CAER_DAYS}"
}

update_master_cert() {
  check_file "${CA_CERT}"
  check_file "${CA_KEY}"

  # generate apiserver server certificate
  CART_NAME=apiserver
  subject_alt_name=$(get_subject_alt_name ${CART_NAME})
  gen_cert "${CART_NAME}" "server" "/CN=kube-apiserver" "${CAER_DAYS}" "${subject_alt_name}"

  # generate apiserver-kubelet-client certificate
  CART_NAME=apiserver-kubelet-client
  gen_cert "${CART_NAME}" "client" "/O=system:masters/CN=kube-apiserver-kubelet-client" "${CAER_DAYS}"

  # generate kubeconf for controller-manager、scheduler and kubectl
  gen_kubeconf "controller-manager"
  gen_kubeconf "scheduler"
  gen_kubeconf "admin"

  # generate front-proxy-client certificate
  # use front-proxy-client ca
  CA_CERT=${PKI_PATH}/front-proxy-ca.crt
  CA_KEY=${PKI_PATH}/front-proxy-ca.key
  check_file "${CA_CERT}"
  check_file "${CA_KEY}"
  CART_NAME=front-proxy-client
  gen_cert "${CART_NAME}" "client" "/CN=front-proxy-client" "${CAER_DAYS}"

  # generate apiserver-etcd-client certificate
  # use etcd ca
  CA_CERT=${PKI_PATH}/etcd/ca.crt
  CA_KEY=${PKI_PATH}/etcd/ca.key
  check_file "${CA_CERT}"
  check_file "${CA_KEY}"
  CART_NAME=apiserver-etcd-client
  gen_cert "${CART_NAME}" "client" "/O=system:masters/CN=kube-apiserver-etcd-client" "${CAER_DAYS}"
}

main() {
  local node_tpye=$1
  
  KUBE_PATH=/etc/kubernetes
  PKI_PATH=/etc/kubernetes/pki

  if [[ ${node_tpye} == "etcd" ]]; then
      PKI_PATH=${PKI_PATH}/etcd
  fi

  CAER_DAYS=3650
  CA_CERT=${PKI_PATH}/ca.crt
  CA_KEY=${PKI_PATH}/ca.key

  case ${node_tpye} in
    etcd)
      update_etcd_cert
      docker ps | grep etcd| awk '{print $1}' | xargs -r -I '{}' docker restart {} || true
      log_info "restarted etcd"
    ;;
    master)
      update_master_cert
      docker ps | grep kube-apiserver | awk '{print $1}' | xargs -I '{}' docker restart {} || true
      log_info "restarted kube-apiserver"
      sleep 5
      docker ps | grep kube-controller-manager | awk '{print $1}' | xargs -r -I '{}' docker restart {} || true
      log_info "restarted kube-controller-manager"
      sleep 1
      docker ps | grep kube-scheduler | awk '{print $1}' | xargs -r -I '{}' docker restart {} || true
      log_info "restarted kube-scheduler"
    ;;
    *)
      update_master_cert
  
      PKI_PATH=${PKI_PATH}/etcd
      CA_CERT=${PKI_PATH}/ca.crt
      CA_KEY=${PKI_PATH}/ca.key
      update_etcd_cert

      docker ps | grep etcd| awk '{print $1}' | xargs -r -I '{}' docker restart {} || true
      log_info "restarted etcd"
      sleep 5
      docker ps | grep kube-apiserver | awk '{print $1}' | xargs -I '{}' docker restart {} || true
      log_info "restarted kube-apiserver"
      sleep 5
      docker ps | grep kube-controller-manager | awk '{print $1}' | xargs -r -I '{}' docker restart {} || true
      log_info "restarted kube-controller-manager"
      sleep 1
      docker ps | grep kube-scheduler | awk '{print $1}' | xargs -r -I '{}' docker restart {} || true
      log_info "restarted kube-scheduler"
    esac
}

main "$@"
