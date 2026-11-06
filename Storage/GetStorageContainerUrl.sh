#!/bin/sh
# Print a one-hour container SAS URL using the signed-in Azure CLI account.
# Usage: sh GetStorageContainerUrl.sh ACCOUNT CONTAINER
set -eu

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    printf '%s\n' 'Usage: sh GetStorageContainerUrl.sh ACCOUNT CONTAINER' >&2
    exit 1
fi
account=$1
container=$2

for dependency in az python3; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf 'Error: %s is required.\n' "$dependency" >&2
        exit 1
    fi
done

validity=$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone

now = datetime.now(timezone.utc)
print(
    (now - timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%MZ"),
    (now + timedelta(hours=1)).strftime("%Y-%m-%dT%H:%MZ"),
)
PY
)
read -r start expiry <<EOF
$validity
EOF

suffix=$(az cloud show --query suffixes.storageEndpoint --output tsv)
if [ -z "$suffix" ]; then
    printf '%s\n' 'Error: the active Azure cloud has no storage endpoint suffix.' >&2
    exit 1
fi

if ! sas=$(az storage container generate-sas \
    --account-name "$account" \
    --name "$container" \
    --auth-mode login \
    --as-user \
    --permissions rl \
    --start "$start" \
    --expiry "$expiry" \
    --https-only \
    --output tsv); then
    printf '%s\n' \
        'Error: could not generate the SAS. Run az login and check container Read/List access and account-level user delegation key permissions.' >&2
    exit 1
fi
if [ -z "$sas" ]; then
    printf '%s\n' 'Error: Azure CLI returned an empty SAS token.' >&2
    exit 1
fi

printf 'https://%s.blob.%s/%s?%s\n' "$account" "$suffix" "$container" "$sas"
