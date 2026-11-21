# homelab-ansible

Ansible control node, running as a container on the `homelab` VM and used to push
configuration to other machines on the network.

No secrets live in this repository. Inventory and the config files pushed by `copy`
tasks are kept in a separate private repo, `homelab-base-configs`, cloned alongside
this one. SSH keys live on the VM and are bind-mounted read-only into the container.

```
homelab-ansible/
├── ansible/
│   ├── ansible.cfg              # inventory path + always prompt for sudo
│   └── playbooks/
│       ├── ubuntu-baseline.yml  # desktop baseline (Ubuntu 24.04)
│       └── install-beats.yml    # elastic beats agents
├── docker/ansible/              # Dockerfile + compose.yaml for the control node
└── scripts/                     # one-time VM setup, plus beats dashboard loading
```

Both repos sit side by side under `/home/ansible` on the VM. `compose.yaml` finds
the private one by relative path and by name, so they must stay siblings: Docker
does not fail on a missing bind source, it creates an empty directory, so the
container starts normally and playbooks only fail later on an inventory that isn't
there.

## VM setup

One time, on a fresh Ubuntu Server VM. Both scripts are idempotent.

```bash
git clone <homelab-ansible> /tmp/homelab-ansible
sudo /tmp/homelab-ansible/scripts/install-docker.sh
sudo /tmp/homelab-ansible/scripts/create-ansible-user.sh <managed-host> ...
```

`create-ansible-user.sh` creates the `ansible` account (uid 1001, in the `docker`
group), generates its ed25519 automation key, and records the host keys of the
hosts passed to it. Pass each host exactly as the inventory addresses it —
`ssh-keyscan` files a key under the name it was given, and the container cannot
fix a mismatch later because `known_hosts` is mounted read-only.

Then follow the steps the script prints, which carry the exact commands: authorise
the automation key on each managed host, add your own public key to the `ansible`
account, and clone both repos side by side before building. Keep the
`from="<vm-ip>"` prefix on the automation key — it has no passphrase, so that
prefix is what stops a stolen copy being usable from anywhere else.

```bash
cd /home/ansible/homelab-ansible/docker/ansible
docker compose up -d --build
```

## Running a playbook

```bash
ssh ansible@homelab
docker exec -it ansible bash
ansible-playbook playbooks/ubuntu-baseline.yml
```

`ansible.cfg` supplies the inventory path and always prompts for the sudo password,
so neither `-i` nor `-K` is needed; SSH authentication uses the mounted key.
Playbooks and inventory are mounted live, so only a Dockerfile change needs a
rebuild (`docker compose up -d --build`).

## Notes

A host added after setup needs its key recorded on the VM, since the container's
`known_hosts` is read-only:

```bash
ssh-keyscan -H <host> >> /home/ansible/.ssh/known_hosts
```

Two overrides for `ubuntu-baseline.yml` — skip the GNOME tasks on a host without a
graphical session, or pin the VirtualBox repo when Oracle has not published one for
the host's release yet:

```bash
ansible-playbook playbooks/ubuntu-baseline.yml --skip-tags desktop
ansible-playbook playbooks/ubuntu-baseline.yml -e virtualbox_codename=noble
```

`beats_version` in `install-beats.yml` must match your Elastic stack.

Each of these is explained where it is defined; the playbooks carry the reasoning.

## License

MIT — see [LICENSE](LICENSE). These playbooks change system state: they purge
packages, disable services, and rewrite config. Read one before pointing it at a
machine you care about.
