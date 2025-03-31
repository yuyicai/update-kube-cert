#!/usr/bin/env bash

# MIT License
#
# The full license can be found at:
# https://github.com/yuyicai/update-kube-cert/blob/master/LICENSE

# more information about the kubernetes certificates can be found at:
# https://kubernetes.io/docs/setup/best-practices/certificates/

# renew certificates to 10 years for existing cluster
#  bash update-kubeadm-cert.sh --cri containerd
# generate 100 years CA before kubeadm init cluster (only used for new clusters)
#  bash update-kubeadm-cert.sh --action gen-ca
# check the expiration of the certificates without updating them
#  bash update-kubeadm-cert.sh --action check

# GitHub: https://github.com/yuyicai/update-kube-cert

# version of the script
VERSION="v2.0.0"

set -o errexit
set -o pipefail
# set -o xtrace

# loglevel: debug, info
LOG_LEVEL=${LOG_LEVEL:-"info"}

# set cri: docker, containerd
# cri is used to determine the command used to restart the control-plane pod
# when cri is docker, use `docker restart` to restart the control-plane pod
# when cri is containerd, use `crictl stopp` to restart the control-plane pod (kill the pod, and kubelet will recreate the pod)
KUBE_CRI=${KUBE_CRI:-"containerd"}

# set default certificate expiration days
KUBE_CERT_DAYS=${KUBE_CERT_DAYS:-3650}

# set default CA expiration days
KUBE_CA_DAYS=${KUBE_CA_DAYS:-36500}

# ----------------------------- Certificates Path Begin -----------------------------
# set default kubernetes path
KUBE_PATH=${KUBE_PATH:-"/etc/kubernetes"}
KUBE_PKI_PATH=${KUBE_PATH}/pki

# master certificates path
# api-server
KUBE_CERT_CA=${KUBE_PKI_PATH}/ca
KUBE_CERT_APISERVER=${KUBE_PKI_PATH}/apiserver
KUBE_CERT_APISERVER_KUBELET_CLIENT=${KUBE_PKI_PATH}/apiserver-kubelet-client
# kubeconfig
KUBE_CONF_CONTROLLER_MANAGER=${KUBE_PATH}/controller-manager
KUBE_CONF_SCHEDULER=${KUBE_PATH}/scheduler
KUBE_CONF_ADMIN=${KUBE_PATH}/admin
# super-admin.conf, add on v1.29.0
# https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.29.md#no-really-you-must-read-this-before-you-upgrade
KUBE_CONF_SUPER_ADMIN=${KUBE_PATH}/super-admin
KUBE_CONF_KUBELET=${KUBE_PATH}/kubelet
# front-proxy
KUBE_FRONT_PROXY_CA=${KUBE_PKI_PATH}/front-proxy-ca
KUBE_FRONT_PROXY_CLIENT=${KUBE_PKI_PATH}/front-proxy-client

# etcd certificates path
KUBE_ETCD_CERT_CA=${KUBE_PKI_PATH}/etcd/ca
KUBE_ETCD_CERT_SERVER=${KUBE_PKI_PATH}/etcd/server
KUBE_ETCD_CERT_PEER=${KUBE_PKI_PATH}/etcd/peer
KUBE_ETCD_CERT_HEALTHCHECK_CLIENT=${KUBE_PKI_PATH}/etcd/healthcheck-client
KUBE_ETCD_CERT_APISERVER_ETCD_CLIENT=${KUBE_PKI_PATH}/apiserver-etcd-client

KUBE_ETCD_CERT_LIST=("${KUBE_ETCD_CERT_CA}" "${KUBE_ETCD_CERT_SERVER}" "${KUBE_ETCD_CERT_PEER}" "${KUBE_ETCD_CERT_HEALTHCHECK_CLIENT}" "${KUBE_ETCD_CERT_APISERVER_ETCD_CLIENT}")

KUBE_MASTER_CERT_LIST=("${KUBE_CERT_CA}" "${KUBE_CERT_APISERVER}" "${KUBE_CERT_APISERVER_KUBELET_CLIENT}" "${KUBE_FRONT_PROXY_CA}" "${KUBE_FRONT_PROXY_CLIENT}")

KUBE_MASTER_CONF_LIST=("${KUBE_CONF_CONTROLLER_MANAGER}" "${KUBE_CONF_SCHEDULER}" "${KUBE_CONF_ADMIN}")
# if super-admin.conf is existed, add it to the list
if [[ -f "${KUBE_CONF_SUPER_ADMIN}.conf" ]]; then
  KUBE_MASTER_CONF_LIST+=("${KUBE_CONF_SUPER_ADMIN}")
fi
# add kubelet.conf to the list if needed
# kubelet.conf does not need to update for K8s v1.17+
# https://github.com/kubernetes/kubeadm/issues/1753

# if the kubelet.conf contains kubelet-client-current.pem, it does not need to update
IS_KUBELET_NEED_RESTART="false"
if [[ -f "${KUBE_CONF_KUBELET}.conf" ]]; then
  grep -q kubelet-client-current.pem "${KUBE_CONF_KUBELET}.conf" 2>/dev/null || KUBE_MASTER_CONF_LIST+=("${KUBE_CONF_KUBELET}") && IS_KUBELET_NEED_RESTART="true"
fi

# ----------------------------- Certificates Path End -----------------------------

# Determines if the kubelet, apiserver, controller-manager, scheduler, etcd should be restarted after update certificates
# Set to false if you want to restart manually
KUBE_RESTART_SERVICES=true

# is need restart control-plane manually
IS_NEED_RESTART_CONTROL_PLANE_MANUALLY=false

# set output color
COLOR_NC='\033[0m'
COLOR_RED='\033[31m'
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_BLUE='\033[34m'
COLOR_PURPLE='\033[35m'

# loglevel color
LOG_INFO_COLOR="${COLOR_GREEN}"
LOG_WARNING_COLOR="${COLOR_YELLOW}"
LOG_ERROR_COLOR="${COLOR_RED}"
LOG_DEBUG_COLOR="${COLOR_PURPLE}"

log_err() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')] ${LOG_ERROR_COLOR}[ERROR]${COLOR_NC} %b\n" "$@"
}

log_info() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')] ${LOG_INFO_COLOR}[INFO]${COLOR_NC} %b\n" "$@"
}

log_warning() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')] ${LOG_WARNING_COLOR}[WARNING]${COLOR_NC} %b\n" "$@"
}

log_debug() {
  if [[ "${LOG_LEVEL}" == "debug" ]]; then
    printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')] ${LOG_DEBUG_COLOR}[DEBUG]${COLOR_NC} %b\n" "$@"
  fi
}

# get x509v3 subject alternative name from the old certificate
# like: DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:some.domain.com, IP:x.x.x.x
cert_get_subject_alt_name() {
  local cert_file_path=${1}.crt
  local alt_name
  alt_name=$(openssl x509 -text -noout -in "${cert_file_path}" | grep -A1 'Alternative' | tail -n1 | sed 's/[[:space:]]*Address//g' | sed 's/^[[:space:]]*//')
  printf "%s\n" "${alt_name}"

}

# get subject from the old certificate
# like: /CN=kube-apiserver
cert_get_subj() {
  local cert_file_path=${1}.crt
  local subj
  subj=$(openssl x509 -text -noout -in "${cert_file_path}" | grep "Subject:" | sed 's/Subject:/\//g;s/\,/\//;s/[[:space:]]//g')
  printf "%s\n" "${subj}"
}

# generate certificate whit client, server or peer
# Args:
#   $1 (the path of certificate, without suffix.
#       example: /etc/kubernetes/pki/apiserver)
#   $2 (the type of certificate, must be one of 'client', 'server', 'peer')
#   $3 (the subject of certificate)
#   $4 (the validity of certificate) (days)
#   $5 (the path of ca, without suffix.
#       example: /etc/kubernetes/pki/ca)
#   $6 (the x509v3 subject alternative name of certificate.
#       This option is required when the type of certificate is 'server' or 'peer'.
#       example: "DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:some.domain.com, IP:10.96.0.1, IP:10.0.0.185")
cert_gen_cert() {
  local cert_file_path=${1}.crt
  local key_file_path=${1}.key
  local csr_file_path=${1}.csr
  local cert_type=${2}
  local subj=${3}
  local cert_days=${4}
  local ca_cert_file_path=${5}.crt
  local ca_key_file_path=${5}.key
  local alt_name=${6}
  local cert_name=${cert_file_path##*/}
  local common_csr_conf='distinguished_name = dn\n[dn]\n[v3_ext]\nkeyUsage = critical, digitalSignature, keyEncipherment\nbasicConstraints = critical, CA:FALSE\n'
  # check x509v3 subject alternative name when the type of certificate is 'server' or 'peer'
  if [[ "${cert_type}" == "server" || "${cert_type}" == "peer" ]]; then
    if [[ -z "${alt_name}" ]]; then
      log_err "x509v3 subject alternative name is required when the type of certificate is 'server' or 'peer'"
      exit 1
    fi
    log_debug "[${cert_name}] x509v3 subject alternative name: ${alt_name}"
  fi
  log_debug "[${cert_name}] subject: ${subj}"

  # set the extended key usage for the certificate with different types
  case "${cert_type}" in
  client)
    csr_conf=$(printf "%bextendedKeyUsage = clientAuth\n" "${common_csr_conf}")
    ;;
  server)
    csr_conf=$(printf "%bextendedKeyUsage = serverAuth\nsubjectAltName = %b\n" "${common_csr_conf}" "${alt_name}")
    ;;
  peer)
    csr_conf=$(printf "%bextendedKeyUsage = serverAuth, clientAuth\nsubjectAltName = %b\n" "${common_csr_conf}" "${alt_name}")
    ;;
  *)
    log_err "unknown, unsupported certs type: ${COLOR_YELLOW}${cert_type}${COLOR_NC}, supported type: client, server, peer"
    exit 1
    ;;
  esac

  # gen csr
  log_debug "[${cert_name}] generate csr"
  if ! openssl req -new -key "${key_file_path}" -subj "${subj}" -reqexts v3_ext \
    -config <(printf "%b" "${csr_conf}") \
    -out "${csr_file_path}" >/dev/null 2>&1; then
    log_err "Failed to generate CSR: ${csr_file_path}"
    exit 1
  fi
  # gen cert
  log_debug "[${cert_name}] generate cert"
  if ! openssl x509 -in "${csr_file_path}" -req \
    -CA "${ca_cert_file_path}" -CAkey "${ca_key_file_path}" -CAcreateserial -extensions v3_ext \
    -extfile <(printf "%b" "${csr_conf}") \
    -days "${cert_days}" -out "${cert_file_path}" >/dev/null 2>&1; then
    log_err "Failed to generate certificate: ${cert_file_path}"
    exit 1
  fi
  log_debug "[${cert_name}] remove csr"
  # remove csr
  rm -f "${csr_file_path}"
}

cert_update_kubeconf() {
  local cert_path_without_suffix=${1}
  local kubeconf_file_path=${cert_path_without_suffix}.conf
  local cert_file_path=${cert_path_without_suffix}.crt
  local key_file_path=${cert_path_without_suffix}.key
  local subj
  local cert_base64

  # get the key file from the old kubeconf
  grep "client-key-data" "${kubeconf_file_path}" | awk '{print$2}' | base64 -d >"${key_file_path}"
  # get the old certificate file from the old kubeconf
  grep "client-certificate-data" "${kubeconf_file_path}" | awk '{print$2}' | base64 -d >"${cert_file_path}"
  # get subject from the old certificate
  subj=$(cert_get_subj "${cert_path_without_suffix}")
  # generate new certificate
  cert_gen_cert "${cert_path_without_suffix}" "client" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_CERT_CA}"
  # convert the new certificate to base64 code
  cert_base64=$(base64 -w 0 "${cert_file_path}")

  # set new certificate base64 code to kubeconf
  sed -i 's/client-certificate-data:.*/client-certificate-data: '"${cert_base64}"'/g' "${kubeconf_file_path}"

  # remove certificate, key file after set kubeconf
  rm -f "${cert_file_path}"
  rm -f "${key_file_path}"
}

cert_update_etcd_cert() {
  local subj
  local subject_alt_name
  local cert

  # generate new etcd server, peer certificate (extendedKeyUsage = serverAuth, clientAuth)
  # /etc/kubernetes/pki/etcd/server.crt
  # /etc/kubernetes/pki/etcd/peer.crt
  for cert in ${KUBE_ETCD_CERT_SERVER} ${KUBE_ETCD_CERT_PEER}; do
    log_debug "updating ${cert}.crt"
    subj=$(cert_get_subj "${cert}")
    subject_alt_name=$(cert_get_subject_alt_name "${cert}")
    cert_gen_cert "${cert}" "peer" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_ETCD_CERT_CA}" "${subject_alt_name}"
    log_info "updated ${COLOR_BLUE}${cert}.crt${COLOR_NC}"
  done

  # generate new etcd healthcheck-client, apiserver-etcd-client certificate (extendedKeyUsage = clientAuth)
  # /etc/kubernetes/pki/etcd/healthcheck-client.crt
  # /etc/kubernetes/pki/apiserver-etcd-client.crt
  for cert in ${KUBE_ETCD_CERT_HEALTHCHECK_CLIENT} ${KUBE_ETCD_CERT_APISERVER_ETCD_CLIENT}; do
    log_debug "updating ${cert}.crt"
    subj=$(cert_get_subj "${cert}")
    cert_gen_cert "${cert}" "client" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_ETCD_CERT_CA}"
    log_info "updated ${COLOR_BLUE}${cert}.crt${COLOR_NC}"
  done

  # restart etcd pod if needed
  # This will restart etcd if KUBE_RESTART_SERVICES is set to true
  restart_etcd
}

restart_etcd() {
  # restart etcd if needed
  if [[ "${KUBE_RESTART_SERVICES}" == "true" ]]; then
    log_debug "restarting etcd"
    set +e
    case ${KUBE_CRI} in
    "docker")
      docker ps 2>/dev/null | grep 'k8s_etcd' | awk '{print$1}' | xargs -r -I '{}' docker restart {} >/dev/null 2>&1
      ;;
    "containerd")
      crictl --runtime-endpoint unix:///run/containerd/containerd.sock pods  | grep 'etcd-' | awk '{print$1}' | xargs -r -I '{}' crictl --runtime-endpoint unix:///run/containerd/containerd.sock stopp {} >/dev/null 2>&1
      ;;
    esac
    is_etcd_restarted=$?
    set -e
    if [[ "${is_etcd_restarted}" != "0" ]]; then
      IS_NEED_RESTART_CONTROL_PLANE_MANUALLY=true
      log_warning "failed to restart etcd, please restart etcd manually"
   else
      log_info "restarted etcd"
    fi
  else
    IS_NEED_RESTART_CONTROL_PLANE_MANUALLY=true
    log_info "please restart etcd manually, KUBE_RESTART_SERVICES is set to false"
  fi
}

cert_update_master_cert() {
  local subj
  local subject_alt_name
  local conf

  # generate new apiserver server certificate (extendedKeyUsage = serverAuth)
  # /etc/kubernetes/pki/apiserver.crt
  subj=$(cert_get_subj "${KUBE_CERT_APISERVER}")
  log_debug "updating ${KUBE_CERT_APISERVER}.crt"
  subject_alt_name=$(cert_get_subject_alt_name "${KUBE_CERT_APISERVER}")
  cert_gen_cert "${KUBE_CERT_APISERVER}" "server" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_CERT_CA}" "${subject_alt_name}"
  log_info "updated ${COLOR_BLUE}${KUBE_CERT_APISERVER}.crt${COLOR_NC}"

  # generate new apiserver-kubelet-client certificate (extendedKeyUsage = clientAuth)
  # /etc/kubernetes/pki/apiserver-kubelet-client.crt
  log_debug "updating ${KUBE_CERT_APISERVER_KUBELET_CLIENT}.crt"
  subj=$(cert_get_subj "${KUBE_CERT_APISERVER_KUBELET_CLIENT}")
  cert_gen_cert "${KUBE_CERT_APISERVER_KUBELET_CLIENT}" "client" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_CERT_CA}"
  log_info "updated ${COLOR_BLUE}${KUBE_CERT_APISERVER_KUBELET_CLIENT}.crt${COLOR_NC}"

  # generate new kubeconf for controller-manager,scheduler and kubelet (extendedKeyUsage = clientAuth)
  # /etc/kubernetes/controller-manager.conf,scheduler.conf,admin.conf,kubelet.conf,super-admin.conf
  # Note: kubelet.conf does not need to update for K8s v1.17+ unless it contains kubelet-client-current.pem,
  #  it will be skipped in the KUBE_MASTER_CONF_LIST if it does not contain the kubelet-client-current.pem
  # Note: super-admin.conf was added in v1.29.0, it will be included in the KUBE_MASTER_CONF_LIST if it exists
  for conf in "${KUBE_MASTER_CONF_LIST[@]}"; do
    # update kubeconf
    log_debug "updating ${conf}.conf"
    cert_update_kubeconf "${conf}"
    log_info "updated ${COLOR_BLUE}${conf}.conf${COLOR_NC}"
  done

  # generate new front-proxy-client certificate (extendedKeyUsage = clientAuth)
  # /etc/kubernetes/pki/front-proxy-client
  log_debug "updating ${KUBE_FRONT_PROXY_CLIENT}.crt"
  subj=$(cert_get_subj "${KUBE_FRONT_PROXY_CLIENT}")
  cert_gen_cert "${KUBE_FRONT_PROXY_CLIENT}" "client" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_FRONT_PROXY_CA}"
  log_info "updated ${COLOR_BLUE}${KUBE_FRONT_PROXY_CLIENT}.crt${COLOR_NC}"

  # restart apiserver, controller-manager, scheduler and kubelet if needed
  restart_control_plane
}

restart_control_plane() {
  # restart control-plane pods if needed
  if [[ "${KUBE_RESTART_SERVICES}" == "true" ]]; then
    for item in "apiserver" "controller-manager" "scheduler"; do
      log_debug "restarting control-plane pod: ${item}"
      set +e
      case ${KUBE_CRI} in
      "docker")
        docker ps 2>/dev/null | awk "k8s_kube-${item}" | awk '{print$1}' | xargs -r -I '{}' docker restart {} >/dev/null 2>&1
        ;;
      "containerd")
        crictl --runtime-endpoint unix:///run/containerd/containerd.sock pods | grep "kube-${item}-" | awk '{print $1}' | xargs -r -I '{}' crictl --runtime-endpoint unix:///run/containerd/containerd.sock stopp {} >/dev/null 2>&1
        ;;
      esac
      is_control_plane_restarted=$?
      set -e
      if [[ "${is_control_plane_restarted}" != "0" ]]; then
        IS_NEED_RESTART_CONTROL_PLANE_MANUALLY=true
        log_warning "failed to restart ${item}, please restart ${item} manually"
      else
        log_info "restarted control-plane pod: ${item}"
      fi
    done

    if [[ "${IS_KUBELET_NEED_RESTART}" == "true" ]]; then
      set +e
      systemctl restart kubelet
      is_kubelet_restarted=$?
      set -e
      if [[ "${is_kubelet_restarted}" != "0" ]]; then
        log_warning "failed to restart kubelet, please restart kubelet manually
        systemctl restart kubelet"
      else
        log_info "restarted kubelet"
      fi
    fi
  else
    IS_NEED_RESTART_CONTROL_PLANE_MANUALLY=true
    log_info "please restart control-plane pods manually, KUBE_RESTART_SERVICES is set to false"
  fi
}

# get certificate expires date
cert_get_cert_expires_date() {
  local cert_file_path=${1}.crt
  local cert_expires

  cert_expires=$(openssl x509 -text -noout -in "${cert_file_path}" 2>/dev/null | awk -F ": " '/Not After/{print$2}')
  printf "%s\n" "${cert_expires}"
}

# get kubeconfig expires date
cert_get_kubeconfig_expires_date() {
  local config_file_path=${1}.conf
  local cert_content
  local cert_expires

  cert_content=$(grep "client-certificate-data" "${config_file_path}" 2>/dev/null | awk '{print$2}' | base64 -d)
  cert_expires=$(openssl x509 -text -noout -in <(printf "%s" "${cert_content}") 2>/dev/null | awk -F ": " '/Not After/{print$2}')
  printf "%s\n" "${cert_expires}"
}

# check etcd certificates expires information
cert_check_etcd_certs_expires() {
  local cert
  local name

  for cert in "${KUBE_ETCD_CERT_LIST[@]}"; do
    name=${cert##*/}
    [[ "${name}" == "apiserver-etcd-client" ]] || name="etcd/${name}"
    printf "| %-33s | %-27s|\n" "${name}.crt" "$(cert_get_cert_expires_date "${cert}")"
  done
}

split_line() {
  printf "|%b|%b|\n" "-----------------------------------" "----------------------------"
}

# check master certificates expires information
cert_check_master_certs_expires() {
  local cert
  local conf
  local name

  for cert in "${KUBE_MASTER_CERT_LIST[@]}"; do
    name=${cert##*/}
    printf "| %-33s | %-27s|\n" "${name}.crt" "$(cert_get_cert_expires_date "${cert}")"
  done

  split_line

  for conf in "${KUBE_MASTER_CONF_LIST[@]}"; do
    name=${conf##*/}
    printf "| %-33s | %-27s|\n" "${name}.conf" "$(cert_get_kubeconfig_expires_date "${conf}")"
  done
}

# check all certificates expires
cert_check_expires() {
  local cert
  local conf
  local name

  split_line
  printf "| %-33s | %-27s|\n" "CERTIFICATE" "EXPIRES"

  for cert in "${KUBE_MASTER_CERT_LIST[@]}"; do
    name=${cert##*/}
    printf "| %-33s | %-27s|\n" "${name}.crt" "$(cert_get_cert_expires_date "${cert}")"
  done

  split_line

  for conf in "${KUBE_MASTER_CONF_LIST[@]}"; do
    name=${conf##*/}
    printf "| %-33s | %-27s|\n" "${name}.conf" "$(cert_get_kubeconfig_expires_date "${conf}")"
  done

  split_line

  for cert in "${KUBE_ETCD_CERT_LIST[@]}"; do
    name=${cert##*/}
    [[ "${name}" == "apiserver-etcd-client" ]] || name="etcd/${name}"
    printf "| %-33s | %-27s|\n" "${name}.crt" "$(cert_get_cert_expires_date "${cert}")"
  done

  split_line
}

# backup kubernetes files, copy $KUBE_PATH to $KUBE_PATH.old-$(date +%Y-%m-%d_%H-%M-%S)
cert_backup_kube_file() {
  local file=${KUBE_PATH}
  local time_date
  time_date=$(date +'%Y-%m-%d_%H-%M-%S')
  log_info "backup ${file} to ${file}.old-${time_date}"
  cp -rp "${file}" "${file}.old-${time_date}"
}

check_file() {
  local file=${1}
  if [[ ! -f ${file} ]]; then
    log_err "file not found: ${file}"
    exit 1
  elif [[ ! -r ${file} || ! -w ${file} ]]; then
    log_err "insufficient permissions for ${file}"
    exit 1
  fi
}

# make sure the certificates are existed
cert_check_files_existed() {
  local cert
  local conf
  local cert_lists=("${KUBE_ETCD_CERT_LIST[@]}" "${KUBE_MASTER_CERT_LIST[@]}")

  # Check all certificate files
  for cert in "${cert_lists[@]}"; do
    check_file "${cert}.crt"
    check_file "${cert}.key"
  done

  # Check all kubeconfig files
  for conf in "${KUBE_MASTER_CONF_LIST[@]}"; do
    check_file "${conf}.conf"
  done
}

cert_gen_ca() {
  # make sure the directory exists
  if [[ ! -d "${KUBE_PKI_PATH}" ]]; then
    mkdir -p "${KUBE_PKI_PATH}"
    log_debug "created directory: ${KUBE_PKI_PATH}"
  fi
  # etcd
  if [[ ! -d "${KUBE_PKI_PATH}/etcd" ]]; then
    mkdir -p "${KUBE_PKI_PATH}/etcd"
    log_debug "created directory: ${KUBE_PKI_PATH}/etcd"
  fi

  local ca_list=("${KUBE_PKI_PATH}/ca" "${KUBE_PKI_PATH}/front-proxy-ca" "${KUBE_PKI_PATH}/etcd/ca")
  # Check if CA keys already exist
  for ca in "${ca_list[@]}"; do
    if [[ -f "${ca}.key" ]]; then
      log_err "${ca}.key already exists, make sure you want to regenerate the CA. please backup the existing ca certs, keys and remove them before regenerating the CA."
      exit 1
    fi
    if [[ -f "${ca}.crt" ]]; then
      log_err "${ca}.crt already exists, make sure you want to regenerate the CA. please backup the existing ca certs, keys and remove them before regenerating the CA."
      exit 1
    fi
  done

  csr_conf='distinguished_name = dn\n[dn]\n[ v3_ca_ext ]\nkeyUsage = critical, digitalSignature, keyEncipherment, keyCertSign\nbasicConstraints = critical, CA:true\n'

  # generate ca.crt
  log_info "generating k8s CA..."
  openssl genrsa -out "${KUBE_PKI_PATH}"/ca.key 2048 >/dev/null 2>&1
  log_debug "generated ${KUBE_PKI_PATH}/ca.key"
  openssl req -x509 -new -nodes -key "${KUBE_PKI_PATH}"/ca.key \
    -subj "/CN=kubernetes" \
    -config <(printf "%bsubjectAltName = DNS:kubernetes" "${csr_conf}") \
    -extensions v3_ca_ext \
    -days "${KUBE_CA_DAYS}" \
    -out "${KUBE_PKI_PATH}"/ca.crt >/dev/null 2>&1
  log_info "generated ${COLOR_BLUE}${KUBE_PKI_PATH}/ca.crt${COLOR_NC}"

  # generate front-proxy-ca.crt
  log_info "generating front-proxy CA..."
  openssl genrsa -out "${KUBE_PKI_PATH}"/front-proxy-ca.key 2048 >/dev/null 2>&1
  log_debug "generated ${KUBE_PKI_PATH}/front-proxy-ca.key"
  openssl req -x509 -new -nodes -key "${KUBE_PKI_PATH}"/front-proxy-ca.key \
    -subj "/CN=front-proxy-ca" \
    -config <(printf "%bsubjectAltName = DNS:front-proxy-ca" "${csr_conf}") \
    -extensions v3_ca_ext \
    -days "${KUBE_CA_DAYS}" \
    -out "${KUBE_PKI_PATH}"/front-proxy-ca.crt >/dev/null 2>&1
  log_info "generated ${COLOR_BLUE}${KUBE_PKI_PATH}/front-proxy-ca.crt${COLOR_NC}"

  # generate etcd/ca.crt
  log_info "generating etcd CA..."
  openssl genrsa -out "${KUBE_PKI_PATH}"/etcd/ca.key 2048 >/dev/null 2>&1
  log_debug "generated ${KUBE_PKI_PATH}/etcd/ca.key"
  openssl req -x509 -new -nodes -key "${KUBE_PKI_PATH}"/etcd/ca.key \
    -subj "/CN=etcd-ca" \
    -config <(printf "%bsubjectAltName = DNS:etcd-ca" "${csr_conf}") \
    -extensions v3_ca_ext \
    -days "${KUBE_CA_DAYS}" \
    -out "${KUBE_PKI_PATH}"/etcd/ca.crt >/dev/null 2>&1
  log_info "generated ${COLOR_BLUE}${KUBE_PKI_PATH}/etcd/ca.crt${COLOR_NC}"
}

help() {
  printf "%b\n" "
  Usage: bash update-kubeadm-cert.sh [OPTIONS]
  Version: ${VERSION}
  Example: 
    # renew certificates to 10 years for existing cluster
      bash update-kubeadm-cert.sh --cri containerd
    # generate 100 years CA before kubeadm init cluster (only used for new clusters)
      bash update-kubeadm-cert.sh --action gen-ca
    # check the expiration of the certificates without updating them
      bash update-kubeadm-cert.sh --action check
  Options:
    -c, --cri     <docker|containerd> (default: containerd)
                    Set the cri type, in order to restart control-plane and etcd service by different command, 'docker' or 'crictl'.
    -a, --action  <update|check|gen-ca> (default: update)
                    update: Update certificates 10 years for existing clusters
                    check: Only check the expiration of the certificates without updating them.
                    gen-ca: Generate 100 years CA before kubeadm init cluster. (only used for new clusters, not for existing clusters)
    --days        Set the number of days for certificate expiration. (default: 3650)
    -h, --help    Show this help message and exit.
  
  more info: https://github.com/yuyicai/update-kube-cert
  "
}

main() {
  local action="update" # default action

  # read the options
  ARGS=$(getopt -n update-kubeadm-cert.sh -a -o a:c:h --long action:,cri:,days:,help -- "$@")
  eval set -- "$ARGS"
  # extract options and their arguments into variables.
  while true; do
    case "$1" in
    -h | --help)
      help
      exit 0
      ;;
    -a | --action)
      # Set the action (update, check, gen-ca)
      case "$2" in
      "update" | "check" | "gen-ca")
        action=$2
        shift 2
        ;;
      *)
        echo 'Unsupported action '"$2"'. Valid options are "update", "check", "gen-ca".'
        exit 1
        ;;
      esac
      ;;
    -c | --cri)
      # Set the container runtime interface (KUBE_CRI) to use.
      case "$2" in
      "docker" | "containerd")
        KUBE_CRI=$2
        shift 2
        ;;
      *)
        echo 'Unsupported cri '"$2"'. Valid options are "docker", "containerd".'
        exit 1
        ;;
      esac
      ;;
    --days)
      # This option is deprecated, use KUBE_CERT_DAYS and KUBE_CA_DAYS instead
      # Set the number of days for certificate expiration
      if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
        KUBE_CERT_DAYS=$2
        shift 2
      else
        echo "Invalid value for --days. It should be a positive integer."
        exit 1
      fi
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid arguments '$1'"
      help
      exit 1
      ;;
    esac
  done

  # Only check the expiration of the certificates without updating them
  if [[ "${action}" == "check" ]]; then
    log_info "checking certificate expiration only..."
    cert_check_expires
    log_info "${COLOR_GREEN}DONE!!!${COLOR_NC}"
    exit 0
  fi

  # Generate 100 years CA before kubeadm init cluster (only used for new clusters)
  if [[ "${action}" == "gen-ca" ]]; then
    log_info "generating CA with ${KUBE_CA_DAYS} days expiration..."
    cert_gen_ca
    cert_check_expires
    log_info "${COLOR_GREEN}DONE!!!${COLOR_NC} generated CA for new cluster.
    # create new cluster after generating CA, you can use the following command:
      kubeadm init [options]
    # after running kubeadm init, update certificates for 100 yeas
      bash update-kubeadm-cert.sh --cri containerd --days 36500
    "
    exit 0
  fi

  # make sure the certificates are existed
  log_info "checking if all certificate files are existed..."
  cert_check_files_existed
  # backup kubernetes files
  cert_backup_kube_file
  # check expires before updating the certificates
  log_info "checking certificate expiration before update..."
  cert_check_expires

  # update certificates 10 years for existing clusters
  log_info "updating certificates with ${KUBE_CERT_DAYS} days expiration..."
  # update etcd certificates
  cert_update_etcd_cert
  # update master certificates and kubeconf
  cert_update_master_cert

  # check expires after updating the certificates
  log_info "checking certificate expiration after update..."
  cert_check_expires

  log_info "${COLOR_GREEN}DONE!!!${COLOR_NC}enjoy it"

  # printf cofy admin.conf manually info
  printf "\n%b\n\n\n" "please copy admin.conf to ${HOME}/.kube/config manually.
    # back old config
    cp $HOME/.kube/config $HOME/.kube/config_backup
    # copy new admin.conf to ${HOME}/.kube/config for kubectl manually
    ${LOG_WARNING_COLOR}cp -i ${KUBE_PATH}/admin.conf ${HOME}/.kube/config${COLOR_NC}"

  if [[ "${IS_NEED_RESTART_CONTROL_PLANE_MANUALLY}" == "true" ]]; then
    log_warning "please restart control-plane pods manually"
    printf "\n%b\n" "${LOG_WARNING_COLOR}you can use the following command to restart control-plane pods:${COLOR_NC}
    # make sure kubelet is running
        systemctl restart kubelet
    # move manifests to trigger kubelet to recreate the pods
        mv /etc/kubernetes/manifests /etc/kubernetes/manifests_backup
    # wait for 2 minutes, let kubelet remove the old pods
        sleep 120
    # restore manifests, kubelet will recreate the pods
        mv /etc/kubernetes/manifests_backup /etc/kubernetes/manifests
    # check the status of control-plane pods
        kubectl get pods -n kube-system -o wide"    
  fi
}

# call the main function with all command-line arguments
main "$@"
