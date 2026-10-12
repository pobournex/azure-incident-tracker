#!/usr/bin/env bash
# Open or close a temporary SSH rule for YOUR current public IP, only while you need it.
# The IP is looked up at run time and never stored in the repo, GitHub variables or Terraform.
#
# Usage:  ./scripts/ssh-window.sh open
#         ./scripts/ssh-window.sh close
set -euo pipefail

RG="${APP_RG:-rg-incident-demo}"
RULE="allow-ssh-admin-temp"
ACTION="${1:-}"

case "$ACTION" in
  open)
    MY_IP="$(curl -fsS https://api.ipify.org)"
    for nsg in $(az network nsg list --resource-group "$RG" --query "[].name" -o tsv); do
      az network nsg rule create --resource-group "$RG" --nsg-name "$nsg" --name "$RULE" \
        --priority 300 --direction Inbound --access Allow --protocol Tcp \
        --destination-port-ranges 22 --source-address-prefixes "$MY_IP/32" -o none
    done
    echo "SSH open from your current IP on every NSG in $RG. Run '$0 close' when finished."
    ;;
  close)
    for nsg in $(az network nsg list --resource-group "$RG" --query "[].name" -o tsv); do
      az network nsg rule delete --resource-group "$RG" --nsg-name "$nsg" --name "$RULE" -o none || true
    done
    echo "Temporary SSH rule removed."
    ;;
  *)
    echo "Usage: $0 open|close" >&2
    exit 1
    ;;
esac
