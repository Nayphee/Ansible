#!/usr/bin/env python3

## Execute from root ansible directory
## ansible-playbook -i dynamic_inventory.py site.yml
## Where site.yml contains all playbooks
## host file for all hosts lives in /metadata/hosts_metadata.yml

import json
import yaml

META_FILE = "hosts.yml"

with open(META_FILE) as f:
    data = yaml.safe_load(f)

inventory = {
    "_meta": {"hostvars": {}}
}

for host in data["hosts"]:
    name = host["name"]
    env = host["env"]
    roles = host.get("roles", [])
    
    # Group by environment
    inventory.setdefault(env, {"hosts": []})
    inventory[env]["hosts"].append(name)

    # Group by role
    for role in roles:
        inventory.setdefault(role, {"hosts": []})
        inventory[role]["hosts"].append(name)

    # Host vars
    host_vars = {
        "ansible_host": host["ip"],
        "environment": env,
        "roles": roles,
     }

    if host.get("local", False):
        host_vars["ansible_connection"] = "local"

    inventory["_meta"]["hostvars"][name] = host_vars

print(json.dumps(inventory))
