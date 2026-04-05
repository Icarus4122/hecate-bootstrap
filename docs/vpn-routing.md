# VPN Routing

VPN runs on the **host**.  Two container access strategies:

## Host-Network Mode (Simple)

```bash
sudo openvpn --config /path/to/htb.ovpn
labctl up --hostnet
```

Containers share all host interfaces including tun0.
Zero routing config required.

## Bridge Mode + Forwarding (Default)

Default `labctl up` uses Docker bridge.  Containers reach the internet
via Docker NAT.  For VPN targets:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 172.17.0.0/16 -o tun0 -j MASQUERADE
```

Persist:
```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-lab.conf
sudo netfilter-persistent save
```

## Quick Reference

| Mode | VPN Access | Isolation | Setup Complexity |
|------|-----------|-----------|-----------------|
| `--hostnet` | Direct tun0 | None | Zero |
| Bridge (default) | Host NAT | Yes | IP forward + masquerade |
