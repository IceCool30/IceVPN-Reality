# IceVPN-Reality

A self-hosted VPN that resists detection. Built on **3x-ui + Xray-core +
VLESS + REALITY**, the current gold standard for getting past censorship and
deep packet inspection.

This is the harder, stronger sibling of the Outline build. Choose this one when
the goal is to look like normal HTTPS traffic and defeat a censor or DPI. If you
only need privacy from your ISP, the plain Outline build is simpler.

**Read `docs/what-this-beats.md` first.** It is precise about what REALITY
defeats and what it does not. Short version: it beats protocol/DPI detection,
it does NOT beat IP-reputation blocks like Netflix.

## What's in here

| Path | What it is |
|------|------------|
| `scripts/bootstrap.sh` | Harden the VPS, enable BBR, install 3x-ui non-interactively, fail-closed firewall. |
| `scripts/reality-setup.sh` | Generate keys/UUID/shortId and print the exact inbound settings. |
| `scripts/tier-manager.sh` | Drive the 3x-ui API to make free (capped) and paid (unlimited) users. |
| `scripts/test-connection.sh` | Check reachability and verify your target supports TLS 1.3 + h2. |
| `tests/test-tier-manager.sh` | Unit tests for the tier logic. `bash tests/test-tier-manager.sh`. |
| `docs/what-this-beats.md` | The honest detection ceiling. Read this. |
| `docs/reality-inbound.md` | Exact panel steps to create the VLESS+REALITY inbound. |
| `docs/cost-and-limits.md` | Cost and user limits. |
| `config/oci-firewall-guide.md` | The exact ports, and the two-layer firewall trap. |

## Prerequisites

- A fresh Ubuntu 22.04/24.04 VPS. Oracle Cloud Always Free works, $0.
- Root or sudo SSH access.
- 20 minutes.

## Deploy

### 1. Install the panel

```bash
scp -r IceVPN-Reality user@YOUR_VPS_IP:~/
ssh user@YOUR_VPS_IP
cd IceVPN-Reality
sudo bash scripts/bootstrap.sh
```

It prints your panel URL, username, and password. **Save them, shown once.**

### 2. Open the firewall

Open SSH and 443 in your cloud firewall, and the panel port to YOUR ip only.
See `config/oci-firewall-guide.md`. Two layers.

### 3. Generate REALITY settings

```bash
bash scripts/reality-setup.sh
# pick a target with TARGET=www.samsung.com if you want a different borrow site
```

On the server, generate the key pair:

```bash
/usr/local/x-ui/bin/xray x25519
```

### 4. Create the inbound

Follow `docs/reality-inbound.md` to paste the settings into the panel. Note the
inbound id (usually 1).

### 5. Run your tiers

Mint an API token in the panel, then:

```bash
export ICEVPN_PANEL='http://YOUR_IP:PANELPORT/PATH'
export ICEVPN_TOKEN='your-api-token'
export ICEVPN_INBOUND=1

./scripts/tier-manager.sh list-inbounds     # confirm the inbound id
./scripts/tier-manager.sh free alice        # 5 GB cap, resets every 30 days
./scripts/tier-manager.sh paid bob          # unlimited, expires each cycle
./scripts/tier-manager.sh renew bob         # on payment: clear traffic, extend
./scripts/tier-manager.sh delete alice      # revoke
```

## Client apps (all free)

- **Android:** v2rayNG
- **iPhone/iPad:** streisand or FoXray
- **Windows:** v2rayN or Nekoray
- **Mac:** V2Box or FoXray

Each user imports their VLESS link or the subscription URL from the panel.

## Verify

```bash
bash scripts/test-connection.sh YOUR_VPS_IP
```

Then connect a client on cellular data and confirm your IP changed at ipinfo.io
and DNS does not leak at dnsleaktest.com.

## Security notes, straight

- **The panel is your control room.** Keep its port locked to your IP. Access it
  over an SSH tunnel if your IP changes. Never expose it to the internet.
- **The API token is a password.** It bypasses CSRF and can create/delete users.
  It is in `.gitignore`. Never commit it.
- **Keep Xray and 3x-ui patched.** The crypto is strong, but a stale panel undoes
  it.
- **The borrowed target can rotate.** If your target site changes its TLS, pick a
  new one. This is the one bit of ongoing maintenance REALITY asks of you.

## License

Scripts here are yours. 3x-ui is GPL-3.0 and Xray-core is MPL-2.0. Check both
before shipping anything commercial.