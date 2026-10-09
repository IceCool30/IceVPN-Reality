# BTCPay payment webhook -> auto-renew

This closes the freemium loop. When a crypto payment settles in your BTCPay
Server, BTCPay calls this webhook, it verifies the payment is real, and it renews
that user's tier automatically. No manual step.

## Why BTCPay and not Stripe/PayPal

From the earlier cost breakdown: card processors classify VPNs as high-risk and
freeze accounts. BTCPay is self-hosted, processes crypto (Bitcoin, Lightning,
and altcoins), takes no cut, and no one can freeze your money. That is why this
integration exists.

## The flow

1. A user pays. You create the BTCPay invoice with `metadata.orderId` set to the
   user's handle/email (the same email you used in `tier-manager.sh paid bob`).
2. BTCPay confirms the payment on-chain.
3. BTCPay POSTs a webhook to this server with the event `InvoiceSettled` (or
   `InvoiceConfirmed`).
4. This server verifies the signature. Bad signature => 401, nothing happens.
5. On a valid settled event, it runs `tier-manager.sh renew <orderId>`, which
   clears the user's used traffic and pushes their expiry out another cycle.

## Security (this is the load-bearing part)

- **Signature is mandatory.** BTCPay signs each webhook with
  `BTCPay-Sig: sha256=HMAC-SHA256(secret, raw_body)`. We verify it in constant
  time. A missing, malformed, or wrong signature is rejected with 401 and no
  action. Without this check, anyone could POST a fake "paid" event and get a
  free tier. Do not remove it.
- **We act on settled/confirmed, not merely "paid."** `InvoicePaid` and
  `InvoiceProcessing` mean marked paid but not confirmed on-chain. Acting on
  those risks renewing for a payment that never confirms. We default to
  `InvoiceSettled` and `InvoiceConfirmed`.
- **Bind to localhost and front it with TLS.** Run it behind a reverse proxy or a
  Cloudflare Tunnel. Never expose the raw port to the internet.
- **The secret and token are passwords.** They are in `.gitignore`. Never commit
  them.

## Run it

```bash
export BTCPAY_SECRET='the-webhook-secret-from-btcpay'
export ICEVPN_PANEL='http://127.0.0.1:PANELPORT/PATH'
export ICEVPN_TOKEN='your-3xui-api-token'
export ICEVPN_INBOUND=1
export LISTEN_HOST=127.0.0.1
export LISTEN_PORT=8321
python3 webhook_server.py
```

Health check: `curl http://127.0.0.1:8321/health` -> `ok`.

## Run it as a service

Copy `icevpn-webhook.service` to `/etc/systemd/system/`, put your secrets in
`/etc/icevpn/webhook.env`, then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now icevpn-webhook
sudo journalctl -u icevpn-webhook -f
```

## Point BTCPay at it

In BTCPay: Settings -> Webhooks -> Create webhook. Set the URL to
`https://your-domain/btcpay` (through your TLS proxy). Enable the invoice events.
Copy the secret BTCPay generates into `BTCPAY_SECRET`.

Use the "Redeliver" button on an invoice to test without a real payment.

## Test it without a live server

```bash
python3 tests/test_btcpay_verify.py
```

14 unit tests cover the signature (valid, wrong secret, tampered body, missing
and malformed header, empty secret) and event selection.

## Putting TLS in front

Simplest options:
- **Cloudflare Tunnel** (free): `cloudflared tunnel --url http://127.0.0.1:8321`,
  then point BTCPay at the tunnel hostname. No open ports, TLS handled.
- **Caddy** (one line, auto HTTPS): `caddy reverse-proxy --from pay.yourdomain --to 127.0.0.1:8321`.
- **nginx** with a cert you already have.