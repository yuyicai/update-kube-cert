#!/usr/bin/env bash

set -o errexit
set -o pipefail
# set -o xtrace

# loglevel, default: info, supported: debug, info
LOG_LEVEL=${LOG_LEVEL:-"debug"}

# set cri, default docker, supported: docker, containerd
# cri is used to determine the command used to restart the control-plane pod
# when cri is docker, use `docker restart` to restart the control-plane pod
# when cri is containerd, use `crictl stopp` to restart the control-plane pod (kill the pod, and kubelet will recreate the pod)
# Note: kubectl cannot restart static pods：https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#manual-certificate-renewal
KUBE_CRI=${KUBE_CRI:-"docker"}

# set default certificate expiration days
KUBE_CERT_DAYS=${KUBE_CERT_DAYS:-3650}

# cert update scope, etcd, master, all
KUBE_CERT_SCOPE=${KUBE_CERT_SCOPE:-"all"}

# action: update, check, init-ca, init-cert
KUBE_ACTION=${KUBE_ACTION:-"update"}

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

KUBE_ETCD_CERT_LIST=(
  "${KUBE_ETCD_CERT_CA}"
  "${KUBE_ETCD_CERT_SERVER}"
  "${KUBE_ETCD_CERT_PEER}"
  "${KUBE_ETCD_CERT_HEALTHCHECK_CLIENT}"
  "${KUBE_ETCD_CERT_APISERVER_ETCD_CLIENT}"
)

KUBE_MASTER_CERT_LIST=(
  "${KUBE_CERT_CA}"
  "${KUBE_CERT_APISERVER}"
  "${KUBE_CERT_APISERVER_KUBELET_CLIENT}"
  "${KUBE_FRONT_PROXY_CA}"
  "${KUBE_FRONT_PROXY_CLIENT}"
)

KUBE_MASTER_CONF_LIST=(
  "${KUBE_CONF_CONTROLLER_MANAGER}"
  "${KUBE_CONF_SCHEDULER}"
  "${KUBE_CONF_ADMIN}"
  "${KUBE_CONF_KUBELET}"
)
# ----------------------------- Certificates Path End -----------------------------

# restart kubelet, apiserver, controller-manager, scheduler, etcd after update certificates
KUBE_RESTART_SERVICES=true

# set output color
COLOR_NC='\033[0m'
COLOR_RED='\033[31m'
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_BLUE='\033[34m'
COLOR_PURPLE='\033[35m'

# loglevel color
LOG_INFO_COLOR="${COLOR_BLUE}"
LOG_WARNING_COLOR="${COLOR_YELLOW}"
LOG_ERROR_COLOR="${COLOR_RED}"
LOG_DEBUG_COLOR="${COLOR_PURPLE}"

log::err() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')] ${LOG_ERROR_COLOR}[ERROR]${COLOR_NC} %b\n" "$@"
}

log::info() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')] ${LOG_INFO_COLOR}[INFO]${COLOR_NC} %b\n" "$@"
}

log::warning() {
  printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')] ${LOG_WARNING_COLOR}[WARNING}]${COLOR_NC} \033[0m%b\n" "$@"
}

log::debug() {
  if [[ "${LOG_LEVEL}" == "debug" ]]; then
    printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')] ${LOG_DEBUG_COLOR}[DEBUG]${COLOR_NC} %b\n" "$@"
  fi
}

# get x509v3 subject alternative name from the old certificate
cert::get_subject_alt_name() {
  local cert_file_path=${1}.crt
  local alt_name

  alt_name=$(openssl x509 -text -noout -in "${cert_file_path}" | grep -A1 'Alternative' | tail -n1 | sed 's/[[:space:]]*Address//g' | sed 's/^[[:space:]]*//')
  printf "%s\n" "${alt_name}"

}

# get subject from the old certificate
cert::get_subj() {
  local cert_file_path=${1}.crt
  local subj

  subj=$(openssl x509 -text -noout -in "${cert_file_path}" | grep "Subject:" | sed 's/Subject:/\//g;s/\,/\//;s/[[:space:]]//g')
  printf "%s\n" "${subj}"
}

# generate certificate whit client, server or peer
# Args:
#   $1 (the path of certificate, without suffix, example: /etc/kubernetes/pki/apiserver)
#   $2 (the type of certificate, must be one of client, server, peer)
#   $3 (the subject of certificate)
#   $4 (the validity of certificate) (days)
#   $5 (the path of ca, without suffix, example: /etc/kubernetes/pki/ca)
#   $6 (the x509v3 subject alternative name of certificate when the type of certificate is server or peer)
cert::gen_cert() {
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
  local common_csr_conf='distinguished_name = dn\n[dn]\n[v3_ext]\nkeyUsage = critical, digitalSignature, keyEncipherment\n'

  if [[ "${cert_type}" == "server" || "${cert_type}" == "peer" ]]; then
    if [[ -z "${alt_name}" ]]; then
      log::err "x509v3 subject alternative name is required when the type of certificate is server or peer"
      exit 1
    fi
    log::debug "[${cert_name}] x509v3 subject alternative name: ${alt_name}"
  fi

  log::debug "[${cert_name}] subject: ${subj}"

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
    log::err "unknown, unsupported certs type: ${COLOR_YELLOW}${cert_type}${COLOR_NC}, supported type: client, server, peer"
    exit 1
    ;;
  esac

  # gen csr
  log::debug "[${cert_name}] generate csr"
  openssl req -new -key "${key_file_path}" -subj "${subj}" -reqexts v3_ext \
    -config <(printf "%b" "${csr_conf}") \
    -out "${csr_file_path}" >/dev/null 2>&1
  # gen cert
  log::debug "[${cert_name}] generate cert"
  openssl x509 -in "${csr_file_path}" -req -CA "${ca_cert_file_path}" -CAkey "${ca_key_file_path}" -CAcreateserial -extensions v3_ext \
    -extfile <(printf "%b" "${csr_conf}") \
    -days "${cert_days}" -out "${cert_file_path}" >/dev/null 2>&1

  log::debug "[${cert_name}] remove csr"
  rm -f "${csr_file_path}"
}

cert::update_kubeconf() {
  local cert_path_without_suffix=${1}
  local kubeconf_file_path=${cert_path_without_suffix}.conf
  local cert_file_path=${cert_path_without_suffix}.crt
  local key_file_path=${cert_path_without_suffix}.key
  local subj
  local cert_base64

  # get the key from the old kubeconf
  grep "client-key-data" "${kubeconf_file_path}" | awk '{print$2}' | base64 -d >"${key_file_path}"
  # get the old certificate from the old kubeconf
  grep "client-certificate-data" "${kubeconf_file_path}" | awk '{print$2}' | base64 -d >"${cert_file_path}"
  # get subject from the old certificate
  subj=$(cert::get_subj "${cert_path_without_suffix}")
  cert::gen_cert "${cert_path_without_suffix}" "client" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_CERT_CA}"
  # get certificate base64 code
  cert_base64=$(base64 -w 0 "${cert_file_path}")

  # set certificate base64 code to kubeconf
  sed -i 's/client-certificate-data:.*/client-certificate-data: '"${cert_base64}"'/g' "${kubeconf_file_path}"

  rm -f "${cert_file_path}"
  rm -f "${key_file_path}"
}

cert::update_etcd_cert() {
  local subj
  local subject_alt_name
  local cert

  # generate etcd server,peer certificate
  # /etc/kubernetes/pki/etcd/server
  # /etc/kubernetes/pki/etcd/peer
  for cert in ${KUBE_ETCD_CERT_SERVER} ${KUBE_ETCD_CERT_PEER}; do
    subj=$(cert::get_subj "${cert}")
    subject_alt_name=$(cert::get_subject_alt_name "${cert}")
    cert::gen_cert "${cert}" "peer" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_ETCD_CERT_CA}" "${subject_alt_name}"
    log::info "updated ${COLOR_BLUE}${cert}.conf${COLOR_NC}"
  done

  # generate etcd healthcheck-client,apiserver-etcd-client certificate
  # /etc/kubernetes/pki/etcd/healthcheck-client
  # /etc/kubernetes/pki/apiserver-etcd-client
  for cert in ${KUBE_ETCD_CERT_HEALTHCHECK_CLIENT} ${KUBE_ETCD_CERT_APISERVER_ETCD_CLIENT}; do
    subj=$(cert::get_subj "${cert}")
    cert::gen_cert "${cert}" "client" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_ETCD_CERT_CA}"
    log::info "updated ${COLOR_BLUE}${cert}.conf${COLOR_NC}"
  done

  # restart etcd
  if [[ "${KUBE_RESTART_SERVICES}" == "true" ]]; then
    set +e
    case ${KUBE_CRI} in
    "docker")
      docker ps | awk '/k8s_etcd/{print$1}' | xargs -r -I '{}' docker restart {} >/dev/null 2>&1
      ;;
    "containerd")
      crictl ps | awk '/etcd-/{print$(NF-1)}' | xargs -r -I '{}' crictl stopp {} >/dev/null 2>&1
      ;;
    esac
    is_etcd_restarted=$?
    set -e
    if [[ "${is_etcd_restarted}" != "0" ]]; then
      log::warning "failed to restart etcd with ${KUBE_CRI}, please restart etcd manually"
    else
      log::info "restarted etcd with ${KUBE_CRI}"
    fi
  fi
}

cert::update_master_cert() {
  local subj
  local subject_alt_name
  local conf

  # generate apiserver server certificate
  # /etc/kubernetes/pki/apiserver
  subj=$(cert::get_subj "${KUBE_CERT_APISERVER}")
  subject_alt_name=$(cert::get_subject_alt_name "${KUBE_CERT_APISERVER}")
  cert::gen_cert "${KUBE_CERT_APISERVER}" "server" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_CERT_CA}" "${subject_alt_name}"
  log::info "updated ${COLOR_BLUE}${KUBE_CERT_APISERVER}.crt${COLOR_NC}"

  # generate apiserver-kubelet-client certificate
  # /etc/kubernetes/pki/apiserver-kubelet-client
  subj=$(cert::get_subj "${KUBE_CERT_APISERVER_KUBELET_CLIENT}")
  cert::gen_cert "${KUBE_CERT_APISERVER_KUBELET_CLIENT}" "client" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_CERT_CA}"
  log::info "updated ${COLOR_BLUE}${KUBE_CERT_APISERVER_KUBELET_CLIENT}.crt${COLOR_NC}"

  # generate kubeconf for controller-manager,scheduler and kubelet
  # /etc/kubernetes/controller-manager,scheduler,admin,kubelet.conf
  for conf in "${KUBE_MASTER_CONF_LIST[@]}"; do

    # kubelet.conf does not need to update for K8s v1.17+
    # https://github.com/kubernetes/kubeadm/issues/1753
    if [[ ${conf##*/} == "kubelet" ]]; then
      set +e
      grep kubelet-client-current.pem /etc/kubernetes/kubelet.conf >/dev/null 2>&1
      kubelet_cert_auto_update=$?
      set -e
      if [[ "$kubelet_cert_auto_update" == "0" ]]; then
        log::info "does not need to update kubelet.conf for K8s v1.17+"
        continue
      fi
    fi

    # update kubeconf
    cert::update_kubeconf "${conf}"
    log::info "updated ${COLOR_BLUE}${conf}.conf${COLOR_NC}"

    # copy admin.conf to ${HOME}/.kube/config
    if [[ ${conf##*/} == "admin" ]]; then
      local kubectl_config=${HOME}/.kube/config
      if [[ -f ${kubectl_config} ]]; then
        local kubectl_config_backup
        kubectl_config_backup=${HOME}/.kube/config.old-$(date +%Y%m%d)
        if [[ ! -f ${kubectl_config_backup} ]]; then
          cp -fp "${kubectl_config}" "${kubectl_config_backup}"
          log::info "backup ${kubectl_config} to ${kubectl_config_backup}"
        fi
        cp -fp "${conf}.conf" "${HOME}/.kube/config"
        log::info "copy the admin.conf to ${HOME}/.kube/config"
      else
        log::warning "can not find ${kubectl_config}"
      fi
    fi
  done

  # generate front-proxy-client certificate
  # /etc/kubernetes/pki/front-proxy-client
  subj=$(cert::get_subj "${KUBE_FRONT_PROXY_CLIENT}")
  cert::gen_cert "${KUBE_FRONT_PROXY_CLIENT}" "client" "${subj}" "${KUBE_CERT_DAYS}" "${KUBE_FRONT_PROXY_CA}"
  log::info "updated ${COLOR_BLUE}${KUBE_FRONT_PROXY_CLIENT}.crt${COLOR_NC}"

  # restart apiserver, controller-manager, scheduler and kubelet
  if [[ "${KUBE_RESTART_SERVICES}" == "true" ]]; then
    for item in "apiserver" "controller-manager" "scheduler"; do
      set +e
      case ${KUBE_CRI} in
      "docker")
        docker ps | awk '/k8s_kube-'${item}'/{print$1}' | xargs -r -I '{}' docker restart {} >/dev/null 2>&1 || true
        ;;
      "containerd")
        crictl ps | awk '/kube-'${item}'-/{print $(NF-1)}' | xargs -r -I '{}' crictl stopp {} >/dev/null 2>&1 || true
        ;;
      esac
      is_control_plane_restarted=$?
      set -e
      if [[ "${is_control_plane_restarted}" != "0" ]]; then
        log::warning "failed to restart ${item} with ${KUBE_CRI}, please restart ${item} manually"
      else
        log::info "restarted ${item} with ${KUBE_CRI}"
      fi
    done
    set +e
    systemctl restart kubelet
    is_kubelet_restarted=$?
    set -e
    if [[ "${is_kubelet_restarted}" != "0" ]]; then
      log::warning "failed to restart kubelet, please restart kubelet manually"
    else
      log::info "restarted kubelet"
    fi
  fi
}

cert::update() {
  # update certificates by different scope
  case ${KUBE_CERT_SCOPE} in
  "etcd")
    # update etcd certificates only, does not include master certificates
    cert::update_etcd_cert
    ;;
  "master")
    # update master certificates and kubeconf only, does not include etcd
    cert::update_master_cert
    ;;
  "all")
    # update all certificates, including etcd and master

    # update etcd certificates
    cert::update_etcd_cert
    # update master certificates and kubeconf
    cert::update_master_cert
    ;;
  *)
    log::err "unknown, unsupported cert type: ${KUBE_CERT_SCOPE}, supported type: \"all\", \"master\""
    exit 1
    ;;
  esac
}

# get certificate expires date
cert::get_cert_expires_date() {
  local cert_file_path=${1}.crt
  local cert_expires

  cert_expires=$(openssl x509 -text -noout -in "${cert_file_path}" | awk -F ": " '/Not After/{print$2}')
  printf "%s\n" "${cert_expires}"
}

# get kubeconfig expires date
cert::get_kubeconfig_expires_date() {
  local config_file_path=${1}.conf
  local cert_content
  local cert_expires

  cert_content=$(grep "client-certificate-data" "${config_file_path}" | awk '{print$2}' | base64 -d)
  cert_expires=$(openssl x509 -text -noout -in <(printf "%s" "${cert_content}") | awk -F ": " '/Not After/{print$2}')
  printf "%s\n" "${cert_expires}"
}

# check etcd certificates expires information
cert::check_etcd_certs_expires() {
  local cert
  local name

  for cert in "${KUBE_ETCD_CERT_LIST[@]}"; do
    name=${cert##*/}
    printf "| %-33s | %-27s|\n" "etcd/${name}.crt" "$(cert::get_cert_expires_date "${cert}")"
  done
}

# check master certificates expires information
cert::check_master_certs_expires() {
  local cert
  local conf
  local name

  for cert in "${KUBE_MASTER_CERT_LIST[@]}"; do
    name=${cert##*/}
    printf "| %-33s | %-27s|\n" "${name}.crt" "$(cert::get_cert_expires_date "${cert}")"
  done

  for conf in "${KUBE_MASTER_CONF_LIST[@]}"; do
    name=${conf##*/}
    printf "| %-33s | %-27s|\n" "${name}.config" "$(cert::get_kubeconfig_expires_date "${conf}")"
  done
}

# check all certificates expires
cert::check_expires() {
  printf "|%b|%b|\n" "-----------------------------------" "----------------------------"
  printf "| %-33s | %-27s|\n" "CERTIFICATE" "EXPIRES"
  printf "|%b|%b|\n" "-----------------------------------" "----------------------------"

  case ${KUBE_CERT_SCOPE} in
  "etcd")
    cert::check_etcd_certs_expires
    ;;
  "master")
    cert::check_master_certs_expires
    ;;
  "all")
    cert::check_master_certs_expires
    cert::check_etcd_certs_expires
    ;;
  *)
    log::err "unknown, unsupported cert type: ${KUBE_CERT_SCOPE}, supported type: \"all\", \"master\""
    exit 1
    ;;
  esac
  printf "|%b|%b|\n" "-----------------------------------" "----------------------------"
}

# backup kubernetes files, copy $KUBE_PATH to $KUBE_PATH.old-$(date +%Y%m%d)
cert::backup_kube_file() {
  local file=${KUBE_PATH}
  log::info "backup ${file} to ${file}.old-$(date +%Y%m%d)"
  if [[ ! -e ${file}.old-$(date +%Y%m%d) ]]; then
    cp -rp "${file}" "${file}.old-$(date +%Y%m%d)"
  else
    log::debug "does not need to backup ${file}, because ${file}.old-$(date +%Y%m%d) already exists"
  fi
}

check_file() {
  local file=${1}
  if [[ ! -r ${file} ]]; then
    log::err "can not find ${file}"
    exit 1
  fi
}

cert::check_etcd_files_existed() {
  local cert
  local conf
  for cert in "${KUBE_ETCD_CERT_LIST[@]}"; do
    check_file "${cert}.crt"
    check_file "${cert}.key"
  done
}

cert::check_master_files_existed() {
  local cert
  local conf
  for cert in "${KUBE_MASTER_CERT_LIST[@]}"; do
    check_file "${cert}.crt"
    check_file "${cert}.key"
  done
  for conf in "${KUBE_MASTER_CONF_LIST[@]}"; do
    check_file "${conf}.conf"
  done
}

# make sure the certificates are existed
cert::check_files_existed() {
  case ${KUBE_CERT_SCOPE} in
  etcd)
    cert::check_etcd_files_existed
    ;;
  master)
    cert::check_master_files_existed
    ;;
  all)
    cert::check_master_files_existed
    cert::check_etcd_files_existed
    ;;
  *)
    log::err "unknown, unsupported cert type: ${KUBE_CERT_SCOPE}, supported type: \"all\", \"master\""
    exit 1
    ;;
  esac
}

# update, check, init-ca, init-cert action switch by ${KUBE_ACTION}
cert::action() {
  case ${KUBE_ACTION} in
  "update")
    # make sure the certificates are existed
    cert::check_files_existed
    # backup kubernetes files, copy $KUBE_PATH to $KUBE_PATH.old-$(date +%Y%m%d)
    cert::backup_kube_file
    cert::update
    cert::check_expires
    ;;
  "check")
    cert::check_expires
    ;;
  "init-ca")
    cert::init_ca
    ;;
  "init-cert")
    # init cert does not need to restart services
    KUBE_RESTART_SERVICES=false
    cert::update
    cert::check_expires
    ;;
  *)
    log::err "unknown, unsupported action: ${KUBE_ACTION}, supported action: update, check, init-ca, init-cert"
    exit 1
    ;;
  esac
}

help() {
  printf "%b\n" "
  Usage: bash update-kubeadm-cert.sh [OPTIONS]
  Options:
    -a, --action <update|check|init-ca|init-cert>
                  Set the action type. (default: update)
                    update: update the certificates.
                    check: check the expiration of the certificates.
                    init-ca: create the ca certificates before kubeadm init cluster.
                    init-cert: update the certificates before kubeadm init cluster.
    -c, --cri <docker|containerd>
                  Set the cri type, in order to restart control-plane and etcd service. (default: docker)
    -s, --scope <all|master|etcd>
                  Set the scope of the certificate updated. (default: all)
    -h, --help    Show this help message and exit.
  "
}

main() {
  # read the options
  ARGS=$(getopt -n update-kubeadm-cert.sh -a -o a:c:s:h --long action:,cri:,scope:,only-check,help -- "$@")
  eval set -- "$ARGS"
  # extract options and their arguments into variables.
  while true; do
    case "$1" in
    -a | --action)
      # Set the action to perform.
      case "$2" in
      "update" | "check" | "init-ca" | "init-cert")
        KUBE_ACTION=$2
        shift 2
        ;;
      *)
        echo 'Unsupported action '"$2"'. Valid options are "update", "check", "init-ca", "init-cert".'
        exit 1
        ;;
      esac
      ;;
    -h | --help)
      help
      exit 0
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
    -s | --scope)
      # Set the scope of the certificate update.
      case "$2" in
      "all" | "master" | "etcd")
        KUBE_CERT_SCOPE=$2
        shift 2
        ;;
      *)
        echo 'Unsupported cert scope '"$2"'. Valid options are "docker", "containerd".'
        exit 1
        ;;
      esac
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

  # update, check, init-ca, init-cert action switch by ${KUBE_ACTION}
  cert::action

  if [[ "${KUBE_ACTION}" == "update" || "${KUBE_ACTION}" == "init-cert" ]]; then
    log::info "${COLOR_GREEN}DONE!!!${COLOR_NC}enjoy it"
  fi
}

# call the main function with all command-line arguments
main "$@"
