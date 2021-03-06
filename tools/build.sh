#!/usr/bin/env bash
set -e
pushd . > /dev/null
cd $(dirname ${BASH_SOURCE[0]})
SCRIPT_DIR=$(pwd)
GIT_REPO_URL=$(git config --get remote.origin.url | sed 's/:/\//' | sed 's/\.git//' | sed 's/git@/https\:\/\//')
GIT_ROOT_DIR=$(git rev-parse --show-toplevel)
popd > /dev/null

DOCKERREGISTRY_USER="ueisele"

PUSH=false
BUILD=false
DOCKERFILE_DIR=""

function usage () {
    echo "$0: $1" >&2
    echo
    echo "Usage: $0 [--build] [--push] [--user <name, e.g. ueisele>] <directory, e.g. ccloud-k8s-toolbox>"
    echo
    return 1
}

function parseCmd () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build)
                BUILD=true
                shift
                ;;
            --push)
                PUSH=true
                shift
                ;;
            --user)
                shift
                case "$1" in
                    ""|--*)
                        usage "Requires Docker registry user name"
                        return 1
                        ;;
                    *)
                        DOCKERREGISTRY_USER=$1
                        shift
                        ;;
                esac
                ;;
            -*)
                usage "Unknown option: $1"
                return $?
                ;;
            *)
                if [[ -n "$DOCKERFILE_DIR" ]]; then
                    usage "Cannot specify multiple directories: $1"
                    return $?
                fi
                DOCKERFILE_DIR="$1"
                shift
                ;;
        esac
    done
    if [ -z "${DOCKERFILE_DIR}" ]; then
        usage "Requires directory"
        return $?
    fi
    if [ ! -f "${SCRIPT_DIR}/${DOCKERFILE_DIR}/Dockerfile" ]; then 
        usage "Missing Dockerfile: ${DOCKERFILE_DIR}/Dockerfile"
    fi
    return 0
}

function resolveCommit () {
    pushd . > /dev/null
    cd $SCRIPT_DIR
    git rev-list --abbrev-commit --abbrev=7 -1 master ${DOCKERFILE_DIR}
    popd > /dev/null
}

function resolveBuildTimestamp() {
    local created=$(docker inspect --format "{{ index .Created }}" "${DOCKERREGISTRY_USER}/${DOCKERFILE_DIR}:latest")
    date --utc -d "${created}" +'%Y%m%dT%H%M%Z'
}

function resolveImageLabel () {
    local label=${1:-"Missing label name as first parameter!"}
    docker inspect \
        --format "{{ index .Config.Labels \"${label}\"}}" \
        "${DOCKERREGISTRY_USER}/${DOCKERFILE_DIR}:latest"
}

function resolveImageTags () {
    local version=$(resolveImageLabel "docker.image.version")
    local timestamp=$(resolveBuildTimestamp)
    local commit=$(resolveImageLabel "source.git.commit")
    echo "latest" "${version}" "${version}-${timestamp}-${commit}"
}

function build () {
    local commit=$(resolveCommit)
    local dockerfileDirAbsolutePath=${SCRIPT_DIR}/${DOCKERFILE_DIR}
    local dockerfileAbsolutePath=${SCRIPT_DIR}/${DOCKERFILE_DIR}/Dockerfile
    local dockerfileUrl=${GIT_REPO_URL}/blob/${commit}/$(realpath --relative-to=${GIT_ROOT_DIR} ${dockerfileAbsolutePath})
    local readmeAbsolutePath=${SCRIPT_DIR}/${DOCKERFILE_DIR}/README.adoc
    local readmeUrl=${GIT_REPO_URL}/blob/${commit}/$(realpath --relative-to=${GIT_ROOT_DIR} ${readmeAbsolutePath})
    docker build -t "${DOCKERREGISTRY_USER}/${DOCKERFILE_DIR}:latest" \
        -f ${dockerfileAbsolutePath} \
        --build-arg SOURCE_GIT_REPOSITORY=${GIT_REPO_URL} \
        --build-arg SOURCE_GIT_COMMIT=${commit} \
        --build-arg DOCKERFILE_URL=${dockerfileUrl} \
        --build-arg README_URL=${readmeUrl} \
        ${dockerfileDirAbsolutePath}
}

function tag () {
    for t in $(resolveImageTags); do
        docker tag "${DOCKERREGISTRY_USER}/${DOCKERFILE_DIR}:latest" "${DOCKERREGISTRY_USER}/${DOCKERFILE_DIR}:${t}"
    done
}

function push () {
    for t in $(resolveImageTags); do
        docker push "${DOCKERREGISTRY_USER}/${DOCKERFILE_DIR}:${t}"
    done
}

function main () {
    parseCmd "$@"
    local retval=$?
    if [ $retval != 0 ]; then
        exit $retval
    fi

    if [ "$BUILD" = true ]; then
        build
        tag
    fi
    if [ "$PUSH" = true ]; then
        push
    fi
}

main "$@"