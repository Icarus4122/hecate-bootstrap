# Privilege Escalation — {{TARGET}}

## Current Access

| Field    | Value |
|----------|-------|
| User     |       |
| Shell    |       |
| OS       |       |
| Arch     |       |
| Kernel   |       |

## Linux

- [ ] sudo -l
- [ ] SUID/SGID binaries
- [ ] Capabilities
- [ ] Cron jobs
- [ ] Writable paths / scripts
- [ ] Kernel exploits
- [ ] Docker / LXC breakout
- [ ] NFS no_root_squash

```bash
# Quick enum
id; sudo -l; find / -perm -4000 -type f 2>/dev/null
cat /etc/crontab; ls -la /etc/cron.*
```

## Windows

- [ ] whoami /priv
- [ ] Service misconfigurations
- [ ] Unquoted service paths
- [ ] AlwaysInstallElevated
- [ ] Stored credentials
- [ ] Token impersonation
- [ ] Kernel exploits
- [ ] UAC bypass

```cmd
whoami /priv
whoami /groups
systeminfo
```

## Escalation Path

```
→
```

## Notes
