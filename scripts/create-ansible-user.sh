#!/usr/bin/env bash
# Creates the dedicated `ansible` account on the homelab VM and its automation SSH
# key. Idempotent; safe to re-run.
#
#   sudo ./scripts/create-ansible-user.sh [managed-host ...]
#
# Hosts passed as arguments are added to the account's known_hosts, which the
# container needs because it mounts ~/.ssh read-only and cannot record host keys
# itself. Pass each host exactly as the inventory addresses it -- ssh-keyscan files
# the key under the name it was given, so scanning `desktop` does nothing for an
# inventory entry of `192.168.1.20`.
set -euo pipefail

# Fixed IDs, matching the UID/GID build args in docker/ansible/compose.yaml. The
# SSH key is bind-mounted into the container; a mismatch makes it unreadable.
ANSIBLE_USER=ansible
ANSIBLE_UID=1001
ANSIBLE_GID=1001
ANSIBLE_HOME=/home/${ANSIBLE_USER}
SSH_DIR=${ANSIBLE_HOME}/.ssh
KEY=${SSH_DIR}/id_ed25519

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "error: must run as root (try: sudo $0)" >&2
        exit 1
    fi
}

# The numeric IDs are checked, not just the name: an account that already exists
# under the right name but the wrong UID satisfies a name-only check and then fails
# much later, as an unreadable key inside the container.
create_account() {
    local existing_gid existing_uid

    existing_gid=$(getent group "${ANSIBLE_USER}" | cut -d: -f3 || true)
    if [[ -z ${existing_gid} ]]; then
        groupadd -g "${ANSIBLE_GID}" "${ANSIBLE_USER}"
    elif [[ ${existing_gid} -ne ${ANSIBLE_GID} ]]; then
        echo "error: group ${ANSIBLE_USER} has gid ${existing_gid}, expected ${ANSIBLE_GID}" >&2
        echo "       fix the group, or change ANSIBLE_GID here and the GID build" >&2
        echo "       arg in docker/ansible/compose.yaml together" >&2
        exit 1
    fi

    existing_uid=$(id -u "${ANSIBLE_USER}" 2>/dev/null || true)
    if [[ -z ${existing_uid} ]]; then
        useradd -m -u "${ANSIBLE_UID}" -g "${ANSIBLE_GID}" \
            -s /bin/bash "${ANSIBLE_USER}"
    elif [[ ${existing_uid} -ne ${ANSIBLE_UID} ]]; then
        echo "error: user ${ANSIBLE_USER} has uid ${existing_uid}, expected ${ANSIBLE_UID}" >&2
        echo "       fix the account, or change ANSIBLE_UID here and the UID build" >&2
        echo "       arg in docker/ansible/compose.yaml together" >&2
        exit 1
    fi

    # Root-equivalent on this host: the Docker socket can mount the filesystem.
    # A convenience boundary, not a privilege boundary.
    if getent group docker >/dev/null; then
        usermod -aG docker "${ANSIBLE_USER}"
    else
        echo "warning: no docker group; run scripts/install-docker.sh first" >&2
    fi
}

create_ssh_key() {
    install -d -m 0700 -o "${ANSIBLE_USER}" -g "${ANSIBLE_USER}" "${SSH_DIR}"

    if [[ ! -f ${KEY} ]]; then
        # No passphrase: playbooks run unattended. The key never leaves this VM and
        # is mounted read-only into the container.
        runuser -u "${ANSIBLE_USER}" -- \
            ssh-keygen -t ed25519 -N '' -C "${ANSIBLE_USER}@$(hostname)" -f "${KEY}"
    fi
}

scan_host_keys() {
    local known_hosts=${SSH_DIR}/known_hosts
    local host scanned

    [[ -f ${known_hosts} ]] || : >"${known_hosts}"

    for host in "$@"; do
        if ssh-keygen -F "${host}" -f "${known_hosts}" >/dev/null 2>&1; then
            echo "known_hosts: ${host} already present"
            continue
        fi
        # An unreachable host must not abort the run under `set -e`.
        if ! scanned=$(ssh-keyscan -H "${host}" 2>/dev/null) || [[ -z ${scanned} ]]; then
            echo "warning: ${host} unreachable; add it to known_hosts later" >&2
            continue
        fi
        printf '%s\n' "${scanned}" >>"${known_hosts}"
        echo "known_hosts: added ${host}"
    done

    chown "${ANSIBLE_USER}:${ANSIBLE_USER}" "${known_hosts}"
    chmod 0644 "${known_hosts}"
}

print_next_steps() {
    # The address the VM actually egresses from, used to scope the key below. From
    # the default route rather than `hostname -I`, which by now also lists docker0's
    # 172.17.0.1 -- scoping the key to an address the VM never connects from
    # surfaces later as a rejected key, far from its cause. Parsed by keyword so it
    # holds for on-link routes too, and falls back to a placeholder rather than
    # emitting a clause that locks nothing.
    local ip
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}' || true)
    ip=${ip:-<this-vm-ip>}

    cat <<EOF

Account ${ANSIBLE_USER} ready (uid ${ANSIBLE_UID}).

Automation public key -- add this whole line to the managed host's
authorized_keys. The key has no passphrase, so the prefix is what limits it:
sshd on the managed host refuses it from any source but this VM, and the three
no-* options strip forwarding that Ansible never uses. Widen the from= to a
CIDR if the VM's address is not reserved, or the first DHCP lease breaks it.

from="${ip}",no-agent-forwarding,no-port-forwarding,no-X11-forwarding $(cat "${KEY}.pub")

Remaining manual steps:
  1. Become ${ANSIBLE_USER} and clone both repos side by side:
       sudo -u ${ANSIBLE_USER} -i
       cd ${ANSIBLE_HOME} && git clone <homelab-ansible> && git clone <homelab-base-configs>
  2. cd ${ANSIBLE_HOME}/homelab-ansible/docker/ansible && docker compose up -d --build

Optional, only to save typing: adding your desktop's public key to
${SSH_DIR}/authorized_keys gets you 'ssh ${ANSIBLE_USER}@$(hostname)' in one hop
rather than 'sudo -u ${ANSIBLE_USER} -i' each time. Nothing above needs it.
sudo needs a terminal, so copy the key across first and place it from here:
piping into 'ssh -t' fails with "no tty present", and 'ssh -tt' mangles the key
through the pty.

  # on your desktop
  scp ~/.ssh/id_ed25519.pub ${SUDO_USER:-<you>}@$(hostname):/tmp/pc.pub

  # back here
  sudo tee -a ${SSH_DIR}/authorized_keys < /tmp/pc.pub
  sudo chown ${ANSIBLE_USER}:${ANSIBLE_USER} ${SSH_DIR}/authorized_keys
  sudo chmod 0600 ${SSH_DIR}/authorized_keys
  rm /tmp/pc.pub
EOF
}

main() {
    require_root
    create_account
    create_ssh_key
    scan_host_keys "$@"
    print_next_steps
}

main "$@"
