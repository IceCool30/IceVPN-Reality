"""
btcpay_verify.py - Verify BTCPay Server webhook signatures and pick the event.

Security-critical. A webhook that does not verify the signature lets anyone on
the internet grant themselves a free paid tier. Do not skip this.

VERIFIED AGAINST the BTCPay Greenfield webhooks OpenAPI spec and the eCommerce
integration guide:
  - The signature arrives in the HTTP header `BTCPay-Sig`.
  - Its format is:  sha256=HMAC_SHA256(UTF8(webhook_secret), raw_request_body)
  - HMAC-SHA256, keyed with the webhook secret, over the RAW body bytes (do not
    re-serialize the JSON; sign exactly the bytes you received).
  - Comparison must be constant-time to avoid timing attacks.

Event types BTCPay can send (from the spec): InvoiceCreated,
InvoiceReceivedPayment, InvoiceProcessing, InvoicePaid, InvoiceConfirmed,
InvoiceSettled, InvoiceExpired, InvoiceInvalid, InvoicePaymentSettled.

For delivering a digital good, act on the SETTLED/CONFIRMED events, not merely
"paid". InvoicePaid/InvoiceProcessing mean the invoice is marked paid but the
on-chain transaction may not be confirmed yet. InvoiceConfirmed (one block) and
InvoiceSettled (fully confirmed per your settings) are safe. We default to
InvoiceSettled and also accept InvoiceConfirmed, configurable.
"""

import hashlib
import hmac
import json

# Events we treat as "payment is safe, renew the user".
# InvoiceSettled = fully confirmed. InvoiceConfirmed = at least one confirmation.
DEFAULT_DELIVER_EVENTS = {"InvoiceSettled", "InvoiceConfirmed"}


def compute_signature(secret: str, body_bytes: bytes) -> str:
    """Return the expected `BTCPay-Sig` value: sha256=<hex hmac>.

    secret: the webhook secret string from BTCPay (Settings -> Webhooks).
    body_bytes: the RAW request body bytes, exactly as received.
    """
    digest = hmac.new(secret.encode("utf-8"), body_bytes, hashlib.sha256).hexdigest()
    return f"sha256={digest}"


def verify_signature(secret: str, body_bytes: bytes, header_value: str) -> bool:
    """Constant-time check that header_value matches the computed signature.

    Returns True only if the header is present, well-formed, and matches.
    Any missing/empty/malformed header returns False (fail closed).
    """
    if not secret or not header_value:
        return False
    expected = compute_signature(secret, body_bytes)
    # hmac.compare_digest is constant-time. Compare on the same encoding.
    return hmac.compare_digest(expected, header_value.strip())


def parse_event(body_bytes: bytes) -> dict:
    """Parse the webhook JSON body. Raises ValueError on bad JSON."""
    try:
        return json.loads(body_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError(f"invalid webhook JSON: {exc}") from exc


def should_deliver(event: dict, deliver_events=None) -> bool:
    """True if this event type is one we should renew the user on."""
    events = deliver_events if deliver_events is not None else DEFAULT_DELIVER_EVENTS
    return event.get("type") in events


def extract_order_id(event: dict) -> str:
    """Pull the user handle (orderId) out of invoice metadata.

    We pass the buyer's email/handle as metadata.orderId when creating the
    invoice, per BTCPay's guidance to send the minimal data (orderId) as
    metadata. The webhook embeds the full invoice under `invoice`.
    """
    invoice = event.get("invoice") or {}
    metadata = invoice.get("metadata") or {}
    order_id = metadata.get("orderId")
    if not order_id:
        # Some setups stash it at the top level of metadata; fall back.
        order_id = (event.get("metadata") or {}).get("orderId")
    return order_id or ""