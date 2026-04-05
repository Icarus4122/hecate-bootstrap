# Services — {{TARGET}}

## SMB (445)

```bash
smbclient -N -L //{{TARGET}}
netexec smb {{TARGET}} -u '' -p ''
```

- [ ] Null session
- [ ] Shares enumerated
- [ ] Interesting files

## HTTP/HTTPS (80/443)

See: [web.md](web.md)

## SSH (22)

- [ ] Banner grabbed
- [ ] Key exchange algorithms noted
- [ ] Brute force (if in scope)

## DNS (53)

```bash
dig axfr @{{TARGET}} {{DOMAIN}}
```

- [ ] Zone transfer
- [ ] Reverse lookups

## LDAP (389/636)

```bash
ldapsearch -x -H ldap://{{TARGET}} -b '' -s base
```

- [ ] Anonymous bind
- [ ] Base DN identified

## Other

| Port | Service | Notes |
|------|---------|-------|
|      |         |       |
