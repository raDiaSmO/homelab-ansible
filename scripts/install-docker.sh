#!/usr/bin/env bash
# Installs Docker CE on the homelab VM. Idempotent; safe to re-run.
#
#   sudo ./scripts/install-docker.sh
#
# Docker does not always publish packages for a brand new Ubuntu release. If the
# apt update below 404s, point it at the previous LTS codename:
#
#   sudo DOCKER_CODENAME=noble ./scripts/install-docker.sh
set -euo pipefail

KEYRING=/etc/apt/keyrings/docker.asc
SOURCES=/etc/apt/sources.list.d/docker.list

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "error: must run as root (try: sudo $0)" >&2
        exit 1
    fi
}

# ca-certificates and curl fetch the signing key over HTTPS, so they have to land
# before the Docker repository is added, not alongside it.
install_prerequisites() {
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl
}

add_docker_repository() {
    local codename
    codename=${DOCKER_CODENAME:-$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")}

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${KEYRING}"
    chmod a+r "${KEYRING}"

    printf 'deb [arch=%s signed-by=%s] https://download.docker.com/linux/ubuntu %s stable\n' \
        "$(dpkg --print-architecture)" "${KEYRING}" "${codename}" >"${SOURCES}"
}

update_system() {
    apt-get update
    apt-get upgrade -y
    apt-get autoremove -y
}

install_docker() {
    # buildx is required by `docker compose build` on current Docker releases.
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    systemctl enable --now docker
}

main() {
    require_root
    install_prerequisites
    add_docker_repository
    update_system
    install_docker
    echo "Docker installed. Next: sudo ./scripts/create-ansible-user.sh"
}

main "$@"
