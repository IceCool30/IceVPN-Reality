# Cost and Limits

Straight answer, same as the Outline build.

## Cost to run

**Software: $0.** Xray-core and 3x-ui are open source (3x-ui is GPL-3.0). The
client apps (v2rayNG, streisand, v2rayN, V2Box) are free. No license fees.

**Server: $0 to a few dollars a month.** One small Linux VPS.

- **$0/month: Oracle Cloud Always Free.** Real compute forever, 10 TB/month
  outbound. Enough for you and a small group. This is the real no-cost answer.
- **$4 to $12/month: a cheap paid VPS** when you outgrow free or want a specific
  country's exit.

**Domain: not required.** This is the win over a normal TLS setup. REALITY
borrows someone else's TLS, so you never buy a domain or manage a certificate.
A domain is only optional polish.

**Total: $0/month** on the free tier for personal and small-group use.

## How many users

Not just you. The tier manager creates one client per person, each with their own
UUID and link, each with its own rules:

- Free: data cap (default 5 GB), resets every 30 days.
- Paid: unlimited, expires each billing cycle, renewed on payment.

Same model as before, same panel. The limit is bandwidth, not people. On Oracle's
free 10 TB/month, a handful of heavy users or many light users fit fine.

## The honest ceiling

Strong against protocol/DPI detection (see what-this-beats.md). That is the real
upgrade over the Outline build and the reason to use this one.

The limits, unchanged and worth repeating:

- **One server, one IP.** Single point of failure, one exit location.
- **Does not beat IP-reputation blocks.** Netflix and banks can still flag the
  datacenter IP. REALITY does not change the IP.
- **No audit.** Well-configured and current, not third-party audited.
- **You maintain it.** Keep Xray and 3x-ui patched, keep the panel off the
  public internet, refresh the borrowed target if it ever rotates.

## Bottom line

For you and a small circle who need to get past censorship or appear as normal
web traffic: **$0/month on Oracle free, REALITY-grade anti-detection, multiple
users, free capped + paid unlimited tiers.** You outgrow it only when combined
bandwidth passes the free allowance, then it is a $5-12/month VPS, not a rewrite.