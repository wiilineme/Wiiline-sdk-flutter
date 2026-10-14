import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'models.dart';

/// Verifying and reading the webhook events Wiiline sends to your endpoint
/// (configured in your dashboard under Webhooks). Server-side only - never
/// put the signing secret in an app.
///
/// Each request carries:
///   X-Webhook-Id:        event id (stable across retries - use it to dedupe)
///   X-Webhook-Event:     event type
///   X-Webhook-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256(secret, "<t>.<raw body>")>

/// The order an event relates to.
class WebhookOrder {
  WebhookOrder(this.raw)
      : orderUuid = '${raw['order_uuid'] ?? ''}',
        orderType = raw['order_type'] as String?,
        planId = raw['plan_id'] as String?,
        status = raw['status'] as String?;
  final Map<String, dynamic> raw;
  final String orderUuid;

  /// issue, topup, renew or upgrade.
  final String? orderType;
  final String? planId;

  /// completed, pending, failed or refunded.
  final String? status;
}

/// A verified webhook event. Every event has the same structure: [order],
/// [esim] and [change] (what happened - its fields depend on [type]).
class WebhookEvent {
  WebhookEvent(this.raw)
      : id = '${raw['id'] ?? ''}',
        type = '${raw['type'] ?? ''}',
        apiVersion = raw['api_version'] as String?,
        createdAt = parseApiDate(raw['created_at']),
        order = (raw['data'] is Map && (raw['data'] as Map)['order'] is Map<String, dynamic>)
            ? WebhookOrder((raw['data'] as Map)['order'] as Map<String, dynamic>)
            : null,
        esim = (raw['data'] is Map && (raw['data'] as Map)['esim'] is Map<String, dynamic>)
            ? EsimRecord((raw['data'] as Map)['esim'] as Map<String, dynamic>)
            : null,
        change = (raw['data'] is Map && (raw['data'] as Map)['change'] is Map<String, dynamic>)
            ? (raw['data'] as Map)['change'] as Map<String, dynamic>
            : const {};

  final Map<String, dynamic> raw;

  /// Event id - identical across retries of the same event.
  final String id;

  /// e.g. `order.completed`, `esim.installed`, `esim.usage_threshold`.
  final String type;
  final String? apiVersion;
  final DateTime? createdAt;

  /// The related order, or null.
  final WebhookOrder? order;

  /// The full current eSIM, or null when the event isn't about one eSIM.
  final EsimRecord? esim;

  /// What happened, e.g. `{previous_status, status}`, `{threshold, ...}`,
  /// `{reason, refunded}`, `{device, eid, install_count, installed_at}`.
  final Map<String, dynamic> change;
}

/// All event types, for subscribing and switching.
abstract final class WebhookEventTypes {
  static const orderCompleted = 'order.completed';
  static const orderFailed = 'order.failed';
  static const renewalCompleted = 'renewal.completed';
  static const renewalFailed = 'renewal.failed';
  static const esimStatusChanged = 'esim.status_changed';
  static const esimInstalled = 'esim.installed';
  static const esimActivated = 'esim.activated';
  static const esimUsageThreshold = 'esim.usage_threshold';
  static const esimExpiringSoon = 'esim.expiring_soon';
  static const esimExpired = 'esim.expired';
  static const webhookTest = 'webhook.test';
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// True only if the request was signed with [secret] and its timestamp is
/// within [tolerance]. Pass the RAW request body exactly as received - not a
/// re-encoded JSON, which changes the bytes.
bool verifyWebhookSignature(
  String rawBody,
  String? signatureHeader,
  String secret, {
  Duration tolerance = const Duration(minutes: 5),
  DateTime? now,
}) {
  if (signatureHeader == null || signatureHeader.isEmpty || secret.isEmpty) return false;
  final parts = <String, String>{};
  for (final piece in signatureHeader.split(',')) {
    final i = piece.indexOf('=');
    if (i > 0) parts[piece.substring(0, i).trim()] = piece.substring(i + 1).trim();
  }
  final t = int.tryParse(parts['t'] ?? '');
  final v1 = parts['v1'];
  if (t == null || v1 == null) return false;

  final nowSec = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  if ((nowSec - t).abs() > tolerance.inSeconds) return false;

  final expected = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$rawBody')).toString();
  return _constantTimeEquals(expected, v1.toLowerCase());
}

/// Verifies a webhook request and returns the parsed event. Throws
/// [WiilineApiException] (`invalid_signature` / `invalid_payload`) when the
/// request can't be trusted - respond 400 then.
///
/// ```dart
/// // shelf
/// final body = await request.readAsString();
/// final event = constructWebhookEvent(body, request.headers['x-webhook-signature'], secret);
/// if (event.type == WebhookEventTypes.orderCompleted) print(event.esim?.qrcode);
/// return Response.ok('ok');
/// ```
WebhookEvent constructWebhookEvent(
  String rawBody,
  String? signatureHeader,
  String secret, {
  Duration tolerance = const Duration(minutes: 5),
  DateTime? now,
}) {
  if (!verifyWebhookSignature(rawBody, signatureHeader, secret, tolerance: tolerance, now: now)) {
    throw WiilineApiException('Webhook signature verification failed', status: 400, code: 'invalid_signature');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(rawBody);
  } catch (_) {
    throw WiilineApiException('Webhook payload is not valid JSON', status: 400, code: 'invalid_payload');
  }
  if (decoded is! Map<String, dynamic> || decoded['id'] is! String || decoded['type'] is! String) {
    throw WiilineApiException('Webhook payload is missing id/type', status: 400, code: 'invalid_payload');
  }
  return WebhookEvent(decoded);
}
