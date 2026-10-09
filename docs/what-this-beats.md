# What this actually beats, and what it does not

Read this before you deploy. The whole reason we are here instead of the plain
Shadowsocks build is detection, so it is worth being precise about which kind.

There are two separate ways something can tell you are using a proxy. They are
different problems with different solutions. VLESS + REALITY solves one of them
well and does not touch the other.

## Layer 1: Protocol / traffic detection (REALITY beats this)

This is when a censor or a middlebox does deep packet inspection or active
probing to see that your traffic is a proxy rather than a normal website.

REALITY is built specifically to defeat this. Here is the mechanism, straight
from the Xray docs:

- REALITY borrows the real TLS 1.3 handshake of an actual website (the "target"
  you pick, like a major CDN or tech company). From the outside, your traffic
  looks like an ordinary TLS visit to that site.
- If a prober connects to your server without the right secret, REALITY forwards
  them to the real target site. There is nothing suspicious to catch, because
  your server behaves like the borrowed site until you prove you are a real
  client.
- There is no certificate to fingerprint and no static TLS signature, because
  there is no separate cert. It reuses the target's handshake shape.
- The client uses uTLS to imitate a real browser's TLS fingerprint (Chrome).

This is the current gold standard for getting past DPI and active probing. It is
what people use to get through the Great Firewall of China. If your threat is
"a network is trying to detect and block that I use a VPN," REALITY is the right
tool and it is strong.

## Layer 2: IP reputation detection (REALITY does NOT beat this)

This is when a website or app checks your IP address against lists of known VPN,
hosting, and datacenter ranges. Netflix, many banks, Cloudflare, and some apps do
this.

Your exit IP is still your VPS's IP, which belongs to Oracle Cloud, Hetzner, or
whoever hosts you. That IP is in every datacenter range database. REALITY hides
HOW you connect. It does not change WHERE you appear to come from.

So no configuration of REALITY will get a datacenter IP past a service that
blocks datacenter IPs. Nothing built on a cheap VPS fixes that. To beat
IP-reputation blocks you need a residential or mobile IP, which is a different
and more expensive problem (residential proxy networks, which are neither free
nor simple).

## The honest summary

| Threat | Does this build handle it? |
|--------|----------------------------|
| My ISP seeing what sites I visit | Yes. Traffic is encrypted to your VPS. |
| Public Wi-Fi snooping | Yes. Same reason. |
| A censor/DPI detecting a proxy | Yes. This is REALITY's whole job. |
| A censor doing active probing | Mostly yes. REALITY forwards probes to the real target. |
| A website blocking known VPN/datacenter IPs | No. The exit IP is still a datacenter IP. |
| Netflix geo-library / bank fraud checks | No. Same IP-reputation wall. |

## What "as strong as possible" means here

For a self-hosted, near-zero-cost build, VLESS + REALITY is close to the ceiling
on the protocol side. The remaining honest limits are:

- **One server, one IP.** Single point of failure, single exit location, easy to
  correlate. Multi-region fixes part of this, at cost.
- **The borrowed target can change.** If the site you borrow rotates its TLS or
  starts redirecting, you pick a new target. Rare, but it is maintenance.
- **No independent audit.** "Strong" here means well-configured and current, not
  third-party audited.
- **You are the admin.** A stale Xray or an exposed panel undoes the crypto. Keep
  it patched and keep the panel off the public internet.

If your actual enemy is a nation-state censor, this is a genuinely strong build.
If your actual enemy is Netflix's VPN blocklist, no amount of REALITY helps, and
you should know that before you spend a weekend on it.