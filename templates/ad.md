# Active Directory — {{DOMAIN}}

## Domain Info

| Field  | Value       |
|--------|-------------|
| Domain | {{DOMAIN}}  |
| DC     |             |
| Forest |             |
| Functional Level |   |

## Enumeration

- [ ] Domain users / groups
- [ ] Domain admins
- [ ] SPNs (Kerberoast targets)
- [ ] AS-REP roastable accounts
- [ ] GPP passwords
- [ ] ACL abuse paths (BloodHound)
- [ ] Delegation (constrained / unconstrained)
- [ ] Certificate templates (Certipy)

```bash
# BloodHound collection
bloodhound-python -u USER -p PASS -d {{DOMAIN}} -c all

# Kerberoast
impacket-GetUserSPNs {{DOMAIN}}/USER:PASS -dc-ip <dc> -request

# AS-REP roast
impacket-GetNPUsers {{DOMAIN}}/ -usersfile users.txt -dc-ip <dc>

# Certipy
certipy find -u USER@{{DOMAIN}} -p PASS -dc-ip <dc>
```

## Credentials

| Account | Type | Hash/Password | Source |
|---------|------|---------------|--------|
|         |      |               |        |

## Attack Path

```
→
```

## Notes
