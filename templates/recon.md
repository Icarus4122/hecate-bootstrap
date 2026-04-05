# Recon - {{TARGET}}

## Passive

- [ ] OSINT / public info
- [ ] DNS enumeration
- [ ] Subdomain discovery
- [ ] Certificate transparency

## Active

- [ ] TCP full port scan
- [ ] Top-1000 UDP scan
- [ ] Service version detection
- [ ] OS fingerprint
- [ ] SNMP walk
- [ ] SMB null session
- [ ] LDAP anonymous bind

## Commands

```bash
# TCP full
nmap -sC -sV -p- -oA scans/{{TARGET}}_full {{TARGET}}

# UDP top
nmap -sU --top-ports 50 -oA scans/{{TARGET}}_udp {{TARGET}}
```

## Findings


## Next Steps
