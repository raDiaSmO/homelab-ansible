# Ansible control node. Self-contained: nothing outside this directory is copied
# in, and playbooks and ansible.cfg are bind-mounted at run time.
FROM ubuntu:26.04

# Must match the `ansible` user on the VM host, whose SSH key is bind-mounted in.
ARG UID=1001
ARG GID=1001

# Version specifier, not a bare version: pins the minor series, allows patch fixes.
# The series has to support the base image's Python -- Ubuntu 26.04 ships 3.14,
# which needs 2.20 or newer. Nothing enforces this at build time, since
# requires_python has no upper bound, so pip installs an unsupported pairing
# silently and it surfaces later as obscure runtime errors. Check when bumping FROM.
ARG ANSIBLE_CORE_VERSION="~=2.21.0"

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/opt/ansible/bin:$PATH \
    ANSIBLE_CONFIG=/home/ansible/ansible/ansible.cfg

# ansible-core from pip rather than the distro `ansible` package, which is frozen
# at release and pulls in every collection that exists. ansible-core alone suffices
# because the playbooks use only ansible.builtin; when that stops being true, add
# an ansible/requirements.yml with an ansible-galaxy step and point the build
# context back at the repo root.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        openssh-client \
        python3 \
        python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/ansible \
    && /opt/ansible/bin/pip install --no-cache-dir "ansible-core${ANSIBLE_CORE_VERSION}" \
    && groupadd -g "${GID}" ansible \
    && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash ansible

USER ansible
WORKDIR /home/ansible/ansible

# A long-lived shell target for `docker exec`, so it needs a foreground process;
# `bash` here would read EOF and exit.
CMD ["sleep", "infinity"]
