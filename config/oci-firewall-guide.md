# Opening the right ports (two layers, again)

IceVPN-Reality needs ports open in **TWO separate places**. Miss either and it
fails. Same trap as the Outline build.

Default ports:
- SSH: `22/tcp`
- VLESS/REALITY: `443/tcp` (blends with normal HTTPS)
- Panel: the random port the installer printed (open to YOUR ip only)

## Layer 1: The OS firewall (bootstrap.sh does this)

`bootstrap.sh` runs `ufw` and opens only SSH and 443. It deliberately does NOT
open the panel port to the world at the OS layer. That is on purpose.

## Layer 2: The cloud provider firewall (you do this by hand)

Oracle Cloud (and most providers) firewall traffic OUTSIDE the VM. On OCI this is
the **Security List** on your subnet AND possibly a **Network Security Group** on
the VM. Both must allow the ports.

### Oracle Cloud Console

1. **Networking > Virtual Cloud Networks** > your VCN > **Subnets** > your subnet
   > **Security Lists** > **Add Ingress Rules**.

2. Add:

| Source CIDR | Protocol | Dest Port | Purpose |
|-------------|----------|-----------|---------|
| your-ip/32 | TCP | 22 | SSH (lock down) |
| 0.0.0.0/0 | TCP | 443 | VLESS/REALITY (clients connect) |
| your-ip/32 | TCP | PANEL_PORT | Panel admin (YOUR ip only) |

3. If the VM is in a **Network Security Group**, add the same rules there too.

### Why the panel port is YOUR ip only

The 3x-ui panel is your control room. If it is open to the world, anyone who
finds it can try to log in or attack it. Keep it locked to your own IP. You
access it through an SSH tunnel if you are on a changing IP:

```
ssh -L  localport:localhost:PANELPORT user@YOUR_VPS_IP
```

Then open http://localhost:localport/PATH locally.

### Why 443 and not a random port

443 is the HTTPS port. Running REALITY there makes your traffic look like normal
web traffic to anyone watching the port, which is the whole point. Do not move it
unless 443 is already taken by a real website on that box.

## Test

From a device on cellular data:
1. Import the VLESS link into the client, connect.
2. Load https://ipinfo.io, confirm the IP is your VPS.
3. https://dnsleaktest.com, confirm no leak.

Connects but no pages load -> almost always Layer 2 (cloud firewall) or the
target site choice. Will not connect at all -> port or Xray not running.