#!/usr/bin/env bash
# Loads the stock Kibana dashboards for each installed beat. Run once per stack
# version, on a host that can reach Kibana, after install-beats.yml.
#
#   sudo ./scripts/beats-setup-dashboards.sh
#
# Each beat reads its own /etc/<beat>/<beat>.yml for the Kibana endpoint and
# credentials, so there is nothing to pass in here. Those configs are 0600
# root-owned, hence the root check.
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "error: must run as root (try: sudo $0)" >&2
    exit 1
fi

# Candidates, not the operative list: a host running three of the four should not
# die on a missing binary, and this drifting from install-beats.yml costs nothing.
candidates=(filebeat metricbeat packetbeat auditbeat)

beats=()
for beat in "${candidates[@]}"; do
    if command -v "${beat}" >/dev/null 2>&1; then
        beats+=("${beat}")
    fi
done

if [[ ${#beats[@]} -eq 0 ]]; then
    echo "error: none of ${candidates[*]} are installed; run install-beats.yml first" >&2
    exit 1
fi

for beat in "${beats[@]}"; do
    # Stop on the first failure: the usual cause is Kibana being unreachable or
    # rejecting the credentials, which the remaining beats would only hit again.
    if ! "${beat}" setup --dashboards; then
        echo "error: ${beat} setup --dashboards failed" >&2
        exit 1
    fi
done

echo "Dashboards loaded for: ${beats[*]}"
