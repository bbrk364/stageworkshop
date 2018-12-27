#!/usr/bin/env bash

# stageworkshop_pe kill && stageworkshop_w1 && stageworkshop_pe
# TODO:80 prompt for choice when more than one cluster
# TODO:90 scp?

. scripts/global.vars.sh

if [[ -e ${RELEASE} && "${1}" != 'quiet' ]]; then
  echo -e "Sourced lib.shell-convenience.sh, release: $(jq -r '.FullSemVer' ${RELEASE})\n \
    \tPrismCentralStable=${PC_STABLE_VERSION}\n \
    \t   PrismCentralDev=${PC_DEV_VERSION}"

  if [[ -z ${PC_VERSION} ]]; then
    export PC_VERSION="${PC_DEV_VERSION}"
  fi
fi

alias stageworkshop_pe-chrome='stageworkshop_chrome PE'
alias stageworkshop_pc-chrome='stageworkshop_chrome PC'
alias         stageworkshop_w='./stage_workshop.sh -f example_pocs.txt -w '

function stageworkshop_auth() {
  . scripts/global.vars.sh
  stageworkshop_ssh 'AUTH' "${1}"
}

function stageworkshop_cache_start() {
  local  _hold
  local  _host
  local _hosts
  local  _file
  local  _bits=( \
  #https://github.com/mlavi/stageworkshop/archive/master.zip \
  #http://download.nutanix.com/downloads/pc/one-click-pc-deployment/5.10.0.1/euphrates-5.10.0.1-stable-prism_central.tar \
  #   http://10.59.103.143:8000/autodc-2.0.qcow2 \
  #   http://download.nutanix.com/calm/CentOS-7-x86_64-GenericCloud-1801-01.qcow2 \
  )

  if [[ ! -d cache ]]; then
    mkdir cache
  fi
  pushd cache || true

  stageworkshop_cache_stop

  echo "Setting up http://localhost:${HTTP_CACHE_PORT}/ on cache directory..."
  python -m SimpleHTTPServer ${HTTP_CACHE_PORT} || python -m http.server ${HTTP_CACHE_PORT} &

  echo "Populate cache files..."
  for _file in "${_bits[@]}"; do
    if [[ -e ${_file##*/} ]]; then
      echo "Cached: ${_file##*/}"
    else
      curl --remote-name --location --continue-at - ${_file}
    fi
  done

  stageworkshop_cluster ''

  echo "Setting up remote SSH tunnels on local and remote port ${HTTP_CACHE_PORT}..."
  #acli -o json host.list | jq -r .data[].hypervisorAddress
  _hosts=$(SSHPASS=${PE_PASSWORD} \
    sshpass -e ssh ${SSH_OPTS} -n ${NTNX_USER}@${PE_HOST} \
    'source /etc/profile.d/nutanix_env.sh ; ncli host list | grep Controller')
   _hold=$(echo "${_hosts}" | awk -F': ' '{print $2}')

  # shellcheck disable=2206
  _hosts=(${_hold// / }) # zero index

  for _host in "${_hosts[@]}"; do
    echo "SSH tunnel for _host=$_host"
    #ServerAliveInterval 120
    SSHPASS=${PE_PASSWORD} sshpass -e ssh ${SSH_OPTS} -nNT \
      -R ${HTTP_CACHE_PORT}:localhost:${HTTP_CACHE_PORT} ${NTNX_USER}@${_host} &
  done

  popd || true
  echo -e "\nTo turn service and tunnel off: stageworkshop_cache_stop"

  ps -efww | grep ssh
  unset NTNX_USER PE_HOST PE_PASSWORD SSHPASS
  stageworkshop_chrome http://localhost:${HTTP_CACHE_PORT}
}

function stageworkshop_cache_stop() {
  echo "Killing service and tunnel:${HTTP_CACHE_PORT}..."
  pkill -f ${HTTP_CACHE_PORT}
}

function stageworkshop_chrome() {
  stageworkshop_cluster ''
  local   _url="${1}"

  case "${1}" in
    PC | pc)
      # shellcheck disable=2153
      _url=https://${PC_HOST}:9440
      ;;
    PE | pe)
      _url=https://${PE_HOST}:9440
      ;;
  esac
  unset NTNX_USER PE_HOST PE_PASSWORD PC_HOST SSHPASS

  if [[ `uname -s` == "Darwin" ]]; then
    open -a 'Google Chrome' ${_url}
  fi
}

function stageworkshop_cluster() {
  local   _cluster
  local    _fields
  local  _filespec
  export NTNX_USER=nutanix

  if [[ -n ${1} || ${1} == '' ]]; then
    _filespec=~/Documents/github.com/mlavi/stageworkshop/example_pocs.txt
  else
    _filespec="${1}"
    echo "INFO: Using cluster file: |${1}| ${_filespec}"
  fi

  echo -e "\nAssumptions:
    - Last uncommented cluster in: ${_filespec}
    -     ssh user authentication: ${NTNX_USER}
    -     Accept self-signed cert: *.nutanix.local\n"

  _cluster=$(grep --invert-match --regexp '^#' "${_filespec}" | tail --lines=1)
  # shellcheck disable=2206
   _fields=(${_cluster//|/ })

  export     PE_HOST=${_fields[0]}
  export PE_PASSWORD=${_fields[1]}
  export    MY_EMAIL=${_fields[2]}
  echo "INFO|stageworkshop_cluster|PE_HOST=${PE_HOST} PE_PASSWORD=${PE_PASSWORD} NTNX_USER=${NTNX_USER}"

  . scripts/global.vars.sh
}

function stageworkshop_pe() {
  stageworkshop_ssh 'PE' "${1}"
}

function stageworkshop_pc() {
  stageworkshop_ssh 'PC' "${1}"
}

function stageworkshop_ssh() {
  stageworkshop_cluster ''

  local  _command
  local     _host
  local _password=${PE_PASSWORD}
  local     _user=${NTNX_USER}

  case "${1}" in
    PC | pc)
      echo 'pkill -f calm ; tail -f calm*log'
      echo "PC_VERSION=${PC_VERSION} MY_EMAIL=${MY_EMAIL} PE_PASSWORD='${_password}' ./calm.sh 'PC'"
          _host=${PC_HOST}
      _password='nutanix/4u'
      ;;
    PE | pe)
      _host=${PE_HOST}

      cat << EOF
OPTIONAL: cd stageworkshop-master
   CHECK: wget http://${HTTP_CACHE_HOST}:${HTTP_CACHE_PORT} -q -O-

pkill -f calm ; tail -f calm*log
EOF

      echo 'rm -rf master.zip calm*.log stageworkshop-master/ && \'
      echo '  curl --remote-name --location https://raw.githubusercontent.com/mlavi/stageworkshop/master/bootstrap.sh \'
      echo '  && SOURCE=${_} 'MY_EMAIL=${MY_EMAIL} PE_PASSWORD=${_password}' sh ${_##*/} \'
      echo '  && tail -f ~/calm*.log'
      echo -e "cd stageworkshop-master/scripts/ && \ \n PE_HOST=${PE_HOST} PE_PASSWORD='${_password}' PC_VERSION=${PC_DEV_VERSION} MY_EMAIL=${MY_EMAIL} ./calm.sh 'PE'"
      ;;
    AUTH | auth | ldap)
          _host=${AUTH_HOST}
      _password='nutanix/4u'
          _user=root
  esac
  #echo "INFO|stageworkshop_ssh|PE_HOST=${PE_HOST} PE_PASSWORD=${PE_PASSWORD} NTNX_USER=${NTNX_USER}"

  case "${2}" in
    log | logs)
      _command='date; echo; tail -f calm*log'
      ;;
    calm | inflight)
      _command='ps -efww | grep calm'
      ;;
    kill | stop)
      _command='ps -efww | grep calm ; pkill -f calm; ps -efww | grep calm'
      ;;
    *)
      _command="${2}"
      ;;
  esac

  echo -e "INFO: ${_host} $ ${_command}\n"
  SSHPASS="${_password}" sshpass -e ssh -q \
    -o StrictHostKeyChecking=no \
    -o GlobalKnownHostsFile=/dev/null \
    -o UserKnownHostsFile=/dev/null \
    ${_user}@"${_host}" "${_command}"

  unset NTNX_USER PE_HOST PE_PASSWORD PC_HOST SSHPASS
}
