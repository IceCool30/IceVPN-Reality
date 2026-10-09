#!/usr/bin/env python3
"""
test_btcpay_verify.py - Unit tests for the BTCPay signature + event logic.

Run: python3 webhook/tests/test_btcpay_verify.py
No network, no live BTCPay, no live panel. Pure logic.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import btcpay_verify  # noqa: E402


class TestSignature(unittest.TestCase):
    SECRET = "test-webhook-secret-123"

    def test_compute_matches_known_format(self):
        body = b'{"type":"InvoiceSettled","invoiceId":"abc"}'
        sig = btcpay_verify.compute_signature(self.SECRET, body)
        self.assertTrue(sig.startswith("sha256="))
        self.assertEqual(len(sig), len("sha256=") + 64)  # hex sha256

    def test_valid_signature_passes(self):
        body = b'{"hello":"world"}'
        sig = btcpay_verify.compute_signature(self.SECRET, body)
        self.assertTrue(btcpay_verify.verify_signature(self.SECRET, body, sig))

    def test_wrong_secret_fails(self):
        body = b'{"hello":"world"}'
        sig = btcpay_verify.compute_signature("other-secret", body)
        self.assertFalse(btcpay_verify.verify_signature(self.SECRET, body, sig))

    def test_tampered_body_fails(self):
        body = b'{"amount":1}'
        sig = btcpay_verify.compute_signature(self.SECRET, body)
        tampered = b'{"amount":999999}'
        self.assertFalse(btcpay_verify.verify_signature(self.SECRET, tampered, sig))

    def test_missing_header_fails_closed(self):
        body = b'{}'
        self.assertFalse(btcpay_verify.verify_signature(self.SECRET, body, ""))
        self.assertFalse(btcpay_verify.verify_signature(self.SECRET, body, None))

    def test_malformed_header_fails(self):
        body = b'{}'
        self.assertFalse(btcpay_verify.verify_signature(self.SECRET, body, "nothex"))
        self.assertFalse(btcpay_verify.verify_signature(self.SECRET, body, "sha256=deadbeef"))

    def test_empty_secret_fails_closed(self):
        body = b'{}'
        sig = btcpay_verify.compute_signature("", body)
        self.assertFalse(btcpay_verify.verify_signature("", body, sig))

    def test_whitespace_tolerated(self):
        body = b'{}'
        sig = btcpay_verify.compute_signature(self.SECRET, body)
        self.assertTrue(btcpay_verify.verify_signature(self.SECRET, body, "  " + sig + "\n"))


class TestEventSelection(unittest.TestCase):
    def test_settled_and_confirmed_deliver(self):
        self.assertTrue(btcpay_verify.should_deliver({"type": "InvoiceSettled"}))
        self.assertTrue(btcpay_verify.should_deliver({"type": "InvoiceConfirmed"}))

    def test_unconfirmed_events_ignored(self):
        for t in ("InvoiceCreated", "InvoiceReceivedPayment", "InvoiceProcessing",
                  "InvoicePaid", "InvoiceExpired", "InvoiceInvalid"):
            self.assertFalse(btcpay_verify.should_deliver({"type": t}), t)

    def test_custom_deliver_set(self):
        self.assertTrue(btcpay_verify.should_deliver({"type": "InvoiceProcessing"}, {"InvoiceProcessing"}))


class TestOrderIdExtraction(unittest.TestCase):
    def test_from_invoice_metadata(self):
        ev = {"invoice": {"metadata": {"orderId": "alice@example.com"}}}
        self.assertEqual(btcpay_verify.extract_order_id(ev), "alice@example.com")

    def test_fallback_to_top_level_metadata(self):
        ev = {"invoice": {}, "metadata": {"orderId": "bob"}}
        self.assertEqual(btcpay_verify.extract_order_id(ev), "bob")

    def test_missing_returns_empty(self):
        self.assertEqual(btcpay_verify.extract_order_id({"invoice": {}}), "")
        self.assertEqual(btcpay_verify.extract_order_id({}), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)