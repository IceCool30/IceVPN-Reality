# Creating the VLESS + REALITY inbound

This is the part the bootstrap script does not do for you, because it needs a few
choices. It is a few fields in the 3x-ui panel. Run `../scripts/reality-setup.sh`
first to generate the keys and print the exact values.

## Pick your target (the site you borrow TLS from)

This is the most important choice. The target must be:

- A real website that supports **TLS 1.3 and HTTP/2**.
- **Not blocked** in the country your server is in.
- **Not hosted by the same company as your VPS.** If your VPS is Oracle, do not
  borrow an Oracle site. If it is a generic host, avoid sites on that same
  network. Borrowing a neighbor is weaker camouflage.
- A **non-redirecting** domain. Use the primary domain, not one that 301s to www.

Good, stable picks that people commonly use: `www.samsung.com`,
`swcdn.apple.com`, `www.microsoft.com`, `cdn.jsdelivr.net`, `www.nvidia.com`,
`www.lovelive-anim.jp`. Verify TLS 1.3 + h2 with:

```
echo | openssl s_client -connect www.samsung.com:443 -tls1_3 -alpn h2 2>/dev/null | grep 'ALPN'
```

You want to see `ALPN protocol: h2`.

## Generate the key pair

On the server (so xray is installed), run:

```
/usr/local/x-ui/bin/xray x25519
```

It prints two lines: `Private key:` and `Password:`. The Password IS the public
key. Copy both exactly.

## Create the inbound in the panel

Log into the 3x-ui panel, go to Inbounds, Add Inbound:

| Field | Value |
|-------|-------|
| Protocol | vless |
| Listening port | 443 |
| Transport | tcp |
| Security | reality |
| dest / target | your-target:443 (e.g. www.samsung.com:443) |
| serverNames (SNI) | your-target (must match dest host) |
| Private key | from `xray x25519` |
| Password (public key) | from `xray x25519` |
| shortIds | one 8-hex-char value, or leave a single empty entry |
| spiderX | / |
| Fingerprint (uTLS) | chrome |
| Flow | xtls-rprx-vision |
| xver | 0 |

Save it. Note the inbound id (usually 1).

## Add users

Either click-add in the panel, or drive it with the tier manager:

```
export ICEVPN_PANEL='http://IP:PANELPORT/PATH'
export ICEVPN_TOKEN='your-api-token'
export ICEVPN_INBOUND=1
./tier-manager.sh free alice     # 5 GB cap, resets every 30 days
./tier-manager.sh paid bob       # unlimited, expires each billing cycle
```

Each user gets a VLESS link. They import it into their client app.

## Client apps (all free)

- **Android:** v2rayNG (Play Store or GitHub)
- **iPhone/iPad:** streisand (App Store) or FoXray
- **Windows:** v2rayN or Nekoray
- **Mac:** V2Box or FoXray

The user pastes the VLESS link, or imports the subscription URL the panel
generates, and connects.

## Minting an API token (for tier-manager.sh)

The tier manager authenticates with a Bearer API token, which bypasses the
panel's CSRF protection (that only guards browser logins). Mint a token in the
panel under Settings / API tokens, or via the management CLI. Put it in
`ICEVPN_TOKEN`. Treat it like a password.