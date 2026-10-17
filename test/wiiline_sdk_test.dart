import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wiiline_sdk/wiiline_sdk.dart';

WiilineClient _client(http.Response Function(http.Request) handler) =>
    WiilineClient(apiKey: 'wii_test', httpClient: MockClient((r) async => handler(r)));

void main() {
  group('client', () {
    test('reuses the supplied purchase key and handles pending verification', () async {
      final keys = <String?>[];
      final client = _client((request) {
        keys.add(request.headers['Idempotency-Key']);
        return http.Response(jsonEncode({
          'success': true, 'pending': true, 'order_uuid': 'same-order', 'message': 'Verification pending',
        }), 202);
      });
      final first = await client.esim.issue(planId: 'p1', idempotencyKey: 'stable-purchase-key');
      final retry = await client.esim.issue(planId: 'p1', idempotencyKey: 'stable-purchase-key');
      expect(keys, ['stable-purchase-key', 'stable-purchase-key']);
      expect(first.isPending, isTrue);
      expect(first.esims, isEmpty);
      expect(retry.orderUuid, first.orderUuid);
    });
    test('sends the API key and parses plans', () async {
      late http.Request seen;
      final client = _client((r) {
        seen = r;
        return http.Response(jsonEncode({
          'success': true,
          'data': [
            {'plan_uuid': 'p1', 'name': 'Japan 5GB', 'days': 7, 'price': '9.79', 'activation_type': 'PDP', 'tether': 1}
          ],
          'meta': {'total': 1}
        }), 200);
      });
      final page = await client.plans.list(planType: 'country', filter: 'japan');
      expect(seen.headers['Authorization'], 'Bearer wii_test');
      expect(seen.url.queryParameters, {'plan_type': 'country', 'filter': 'japan'});
      expect(page.plans.single.planUuid, 'p1');
      expect(page.plans.single.price, 9.79);
      expect(page.plans.single.activationType, ActivationType.pdp);
      expect(page.plans.single.tether, isTrue);
    });

    test('parses an issued eSIM, including API date formats', () async {
      final client = _client((_) => http.Response(jsonEncode({
            'success': true,
            'order_uuid': 'o1',
            'data': {
              'response': {
                'esims': [
                  {'iccid': '8985', 'status_qr': 'Released', 'qrcode': 'LPA:1\$a\$b', 'activate_before': '2026-12-12 09:43:08'}
                ]
              }
            },
            'transaction': {'amount_charged': 3.08}
          }), 200));
      final res = await client.esim.issue(planId: 'p1', idempotencyKey: 'purchase-test-1');
      expect(res.orderUuid, 'o1');
      expect(res.esims.single.status, EsimStatus.released);
      expect(res.esims.single.activateBefore, DateTime.utc(2026, 12, 12, 9, 43, 8));
      expect(res.transaction?.amountCharged, 3.08);
    });

    test('throws WiilineApiException on success:false, even with HTTP 200', () async {
      final client = _client((_) => http.Response(
          jsonEncode({'success': false, 'error': 'Renewal not available', 'message': 'Deadline passed'}), 200));
      expect(
        () => client.esim.renew(iccid: '1', planId: 'p'),
        throwsA(isA<WiilineApiException>()
            .having((e) => e.code, 'code', 'Renewal not available')
            .having((e) => e.message, 'message', 'Deadline passed')),
      );
    });

    test('reads retryAfter on 429', () async {
      final client = _client((_) => http.Response(jsonEncode({'success': false, 'error': 'Too many requests', 'retryAfter': 42}), 429));
      expect(() => client.esim.issue(planId: 'p', idempotencyKey: 'purchase-test-2'), throwsA(isA<WiilineApiException>().having((e) => e.retryAfter, 'retryAfter', 42)));
    });

    test('refuses to run with no key against the public API', () {
      expect(() => WiilineClient(), throwsArgumentError);
      expect(() => WiilineClient(baseUrl: 'https://my-backend.example/wiiline'), returnsNormally);
    });
  });

  group('webhooks', () {
    const secret = 'whsec_test';
    final body = jsonEncode({
      'id': 'evt_1',
      'type': 'esim.installed',
      'api_version': '2026-10-13',
      'created_at': '2026-10-13T15:25:00.000Z',
      'data': {
        'order': {'order_uuid': 'o1', 'order_type': 'issue', 'plan_id': 'p', 'status': 'completed'},
        'esim': {'iccid': '8985', 'status': 'INSTALLED', 'install_device': 'iPhone 15 Pro', 'install_count': 3},
        'change': {'device': 'iPhone 15 Pro', 'install_count': 3}
      }
    });
    final now = DateTime.now();
    final t = now.millisecondsSinceEpoch ~/ 1000;
    // Signed exactly like the platform signs (lib/partner-webhooks.ts).
    final header = 't=$t,v1=${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$body'))}';

    test('accepts a valid signature and parses the unified shape', () {
      final ev = constructWebhookEvent(body, header, secret);
      expect(ev.type, WebhookEventTypes.esimInstalled);
      expect(ev.order?.orderUuid, 'o1');
      expect(ev.esim?.status, EsimStatus.installed);
      expect(ev.esim?.installDevice, 'iPhone 15 Pro');
      expect(ev.change['install_count'], 3);
    });

    test('rejects a tampered body, wrong secret and stale timestamp', () {
      expect(verifyWebhookSignature('$body ', header, secret), isFalse);
      expect(verifyWebhookSignature(body, header, 'other'), isFalse);
      expect(verifyWebhookSignature(body, header, secret, now: now.add(const Duration(minutes: 10))), isFalse);
      expect(() => constructWebhookEvent(body, 't=1,v1=00', secret), throwsA(isA<WiilineApiException>()));
    });
  });
}
