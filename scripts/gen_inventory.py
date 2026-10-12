#!/usr/bin/env python3
"""Turn `terraform output -json vms` into an Ansible YAML inventory.

Usage:
    terraform -chdir=terraform output -json vms | python3 scripts/gen_inventory.py > ansible/inventory/hosts.yml
"""
import json
import sys

ADMIN_USER = "azureuser"


def main() -> int:
    vms = json.load(sys.stdin)
    if not vms:
        print("no VMs in terraform output", file=sys.stderr)
        return 1

    tiers: dict[str, list[str]] = {}
    lines = ["---", "all:", "  vars:", f"    ansible_user: {ADMIN_USER}", "  children:"]

    for name, vm in sorted(vms.items()):
        tiers.setdefault(vm["tier"], []).append(name)

    for tier, names in sorted(tiers.items()):
        lines.append(f"    {tier}:")
        lines.append("      hosts:")
        for name in names:
            vm = vms[name]
            # Connect over the public IP when there is one, otherwise the private IP.
            host = vm.get("public_ip") or vm["private_ip"]
            # Host names get a -vm suffix so they never collide with the tier group names.
            lines.append(f"        {name}-vm:")
            lines.append(f"          ansible_host: {host}")
            lines.append(f"          private_ip: {vm['private_ip']}")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
