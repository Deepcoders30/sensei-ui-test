#!/bin/bash

while getopts p: flag; do
  case "${flag}" in
  p) profile=${OPTARG} ;;
  ?)
    echo "INVALID OPTION - ${OPTARG}" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [-p] start|stop|build|restart|tidy|cleanup" >&2
    exit 1
    ;;
  esac
done

DEPLOYMENT_PROFILE="${profile:-local}"
ACTION=${@:$OPTIND:1}

function export_from_file() {
  set -o allexport
  # shellcheck disable=SC1090
  source "$1"
  set +o allexport
}

function repeat() {
  local start=1
  local end=${1:-80}
  local str="${2:-=}"
  # shellcheck disable=SC2155
  local range=$(seq $start $end)
  # shellcheck disable=SC2034
  for i in $range; do echo -n "${str}"; done
  echo
}

function update_docker_environment() {
  DOCKER_TEMPLATE_DIR="./templates/docker"

  export ENV_FILE=".${DEPLOYMENT_PROFILE}.env"
  export DOCKER_COMPOSE_FILE=docker-compose."${DEPLOYMENT_PROFILE}".yml

  export_from_file ".$(basename $(pwd)).env"
  export_from_file ./profiles/default/.env
  export_from_file ".$(basename $(pwd)).env"
#  export_from_file ./profiles/"${DEPLOYMENT_PROFILE}"/.env
  update_grpc_server_hostname

  generate_file_header "${ENV_FILE}"
  envsubst <"${DOCKER_TEMPLATE_DIR}"/.env >>"${ENV_FILE}"
  export_from_file "${ENV_FILE}"
}

function generate_docker_config() {
  generate_file_header "${DOCKER_COMPOSE_FILE}"
  envsubst <"${DOCKER_TEMPLATE_DIR}"/docker-compose.yml >>"${DOCKER_COMPOSE_FILE}"
}

function generate_file_header() {
  message="#  WARNING: AUTO-GENERATED CONFIG FOR ${APP_NAME} ${DEPLOYMENT_PROFILE} ENVIRONMENT BY deploy.sh. DO NOT TOUCH!!!  #"
  message_size=$(echo -n "${message}" | wc -c)

  {
    repeat "${message_size}" '#'
    echo "${message}"
    repeat "${message_size}" '#'
    echo ""
  } >"${1}"
}

function update_grpc_server_hostname() {
  if [ "$(uname)" == "Darwin" ]; then
    export GRPC_SERVER_HOSTNAME="host.docker.internal"
  elif [ "$(uname)" == "Linux" ]; then
    export GRPC_SERVER_HOSTNAME="172.17.0.1"
  elif [ "$(uname)" == "MINGW32_NT" ]; then
    export GRPC_SERVER_HOSTNAME="host.docker.internal"
  elif [ "$(uname)" == "MINGW64_NT" ]; then
    export GRPC_SERVER_HOSTNAME="host.docker.internal"
  fi
}

function create_logs_dir() {
  mkdir -p ${LOGS_DIR_HOST}
  chown -R ${USER_ID}:${GROUP_ID} ${LOGS_DIR_HOST}
}

function print_stage_message() {
  stage="$(echo $1 | cut -c1 | tr [a-z] [A-Z])$(echo $1 | cut -c2-)"

  [ -z "${stage}" ] && stage="All"
  echo "[ ${stage} ] Deploying ${APP_NAME}:${VERSION}"
}

function start() {
  update_docker_environment

  repeat 40 "="
  echo "APP_NAME := ${APP_NAME}"
  echo "VERSION := ${VERSION}"
  echo "DEPLOYMENT_PROFILE := ${DEPLOYMENT_PROFILE}"
  repeat 40 "="

  print_stage_message "${ACTION}"
  if [[ "${ACTION}" == "tidy" ]]; then
    generate_docker_config
    create_logs_dir
  elif [[ "${ACTION}" == "build" ]]; then
    docker compose -f "${DOCKER_COMPOSE_FILE}" build --no-cache
  elif [[ "${ACTION}" == "start" ]]; then
    docker compose -f "${DOCKER_COMPOSE_FILE}" up -d
  elif [[ "${ACTION}" == "stop" ]]; then
    if [ "$(docker ps -a | grep ${APP_NAME})" ]; then
      docker compose -f "${DOCKER_COMPOSE_FILE}" down ${APP_NAME}
    fi
  elif [[ "${ACTION}" == "restart" ]]; then
    if [ "$(docker ps -a | grep ${APP_NAME})" ]; then
      docker rm -f ${APP_NAME}
    fi
    [ "$(docker images -q "${APP_NAME}:${VERSION}")" ] && docker rmi "${APP_NAME}:${VERSION}"
    generate_docker_config
    docker compose -f "${DOCKER_COMPOSE_FILE}" build --no-cache
    docker compose -f "${DOCKER_COMPOSE_FILE}" up -d
  elif [[ "${ACTION}" == "cleanup" ]]; then
    [ -e ${ENV_FILE} ] && rm ${ENV_FILE}
    [ -e ${DOCKER_COMPOSE_FILE} ] && rm ${DOCKER_COMPOSE_FILE}
    if [ "$(docker ps -a | grep ${APP_NAME})" ]; then
      docker rm -f ${APP_NAME}
    fi
    [ "$(docker images -q "${APP_NAME}:${VERSION}")" ] && docker rmi "${APP_NAME}:${VERSION}"
  else
    generate_docker_config
    docker compose -f "${DOCKER_COMPOSE_FILE}" build --no-cache
    docker compose -f "${DOCKER_COMPOSE_FILE}" up -d
  fi
}

start