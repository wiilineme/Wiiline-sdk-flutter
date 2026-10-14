# wiiline_sdk

Official Dart and Flutter SDK for the Wiiline eSIM API - plans, eSIM ordering and management, and webhook verification. Pure Dart: works in Flutter apps (iOS, Android, web, desktop) and on Dart servers.

## Install

```bash
flutter pub add wiiline_sdk     # Flutter
dart pub add wiiline_sdk        # Dart server
```

## Getting an account

You need a Wiiline partner account and an API key. Accounts are invite-only:

1. **Request access** at [wiiesim.me/register](https://wiiesim.me/register). Our team reviews the request and emails you your sign-in details.
2. **Sign in** at [wiiesim.me/login](https://wiiesim.me/login) and **activate your account** (one-time $200 fee, of which **$100 is credited to your balance**).
3. **Sign the NDA** on your dashboard, then **top up your balance**.
4. **Create an API key** under **API Tokens** (starts with `wii_`, shown once).

New accounts can start in **testing mode** (mock data, nothing charged) - your account manager switches you to live.

## ⚠️ Never put your API key in an app

Anything shipped inside a Flutter app can be extracted, and the key spends your account balance. Use the SDK in one of two ways:

**1. On your server (Dart backend)** - with the API key:

```dart
import 'dart:io';
import 'package:wiiline_sdk/wiiline_sdk.dart';

final client = WiilineClient(apiKey: Platform.environment['WIILINE_API_KEY']);
```

**2. In your Flutter app** - through **your own backend**, which holds the key, authenticates your user and forwards the same paths (`/api/plans`, `/api/esim/...`) to `https://wiiesim.me`:

```dart
final client = WiilineClient(
  baseUrl: 'https://api.your-company.com/wiiline',          // your backend
  headers: {'Authorization': 'Bearer $yourUserSessionToken'}, // your auth, not the Wiiline key
);
```

The models, errors and methods are identical in both modes.

## Quick start

```dart
// Plans (cache them - prices change rarely)
final page = await client.plans.list(planType: 'country', filter: 'japan');
final plan = page.plans.first;
print('${plan.name}: ${plan.price} ${plan.currency} - ${plan.activationTypeDescription}');

// Buy an eSIM
final order = await client.esim.issue(planId: plan.planUuid);
final esim = order.esims.first;
if (esim.isPending) {
  // Some networks finish later - poll getOrder() or use the order.completed webhook
  final later = await client.esim.getOrder(order.orderUuid);
} else {
  print(esim.qrcode);          // render as a QR code
  print(esim.iosTapLink);      // one-tap install on iPhone
  print(esim.androidTapLink);  // one-tap install on Android
}
print('Charged: ${order.transaction?.amountCharged}');
```

## Flutter example

```dart
class EsimCard extends StatelessWidget {
  const EsimCard({super.key, required this.client, required this.iccid});
  final WiilineClient client;
  final String iccid;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EsimRecord>(
      future: client.esim.info(iccid),
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return Text(e is WiilineApiException ? e.message : 'Something went wrong');
        }
        if (!snap.hasData) return const CircularProgressIndicator();
        final esim = snap.data!;
        return Column(children: [
          Text('Status: ${esim.status.name}'),
          if (esim.planActivatedAt == null && esim.activateBefore != null)
            Text('Activate before ${esim.activateBefore!.toLocal()}'),
          if (esim.dataLeftMb != null) Text('${esim.dataLeftMb!.toStringAsFixed(0)} MB left'),
          if (esim.installDevice != null) Text('Installed on ${esim.installDevice}'),
        ]);
      },
    );
  }
}
```

## eSIM management

```dart
final esim = await client.esim.info(iccid);                 // status, dates, usage, device
final options = await client.esim.checkTopup(iccid);        // compatible packages
if (!options.topupAvailable) print(options.message);        // why not (e.g. deadline passed)

final renewed = await client.esim.renew(iccid: iccid, planId: options.packages.first.id);
if (renewed.isPending) print('Confirmation follows via webhook');

final upgrades = await client.esim.listTopups(iccid);
await client.esim.upgrade(iccid: iccid, productId: upgrades.packages.first.id);
```

Buying, renewing and upgrading are limited to **10 requests per minute**.

### Dates and activation

- `planActivatedAt` / `planExpiredAt` are `null` until the eSIM is first used.
- `activateBefore` is the activation deadline, where the network sets one. Depending on the network the plan then starts automatically or can no longer be activated - `plan.otherInfo` says which.
- `renewBefore` (some networks) is the last date the eSIM can be renewed.
- `Plan.activationType` is `pdp` (starts on first use) or `immediate` (starts at purchase).
- All dates are UTC `DateTime`s.

## Error handling

Every failed call throws `WiilineApiException`:

```dart
try {
  await client.esim.renew(iccid: iccid, planId: planId);
} on WiilineApiException catch (e) {
  print(e.status);      // HTTP status, 0 for network/timeout
  print(e.code);        // e.g. 'Insufficient balance', 'Renewal not available', 'eSIM not found'
  print(e.message);     // human-readable reason
  print(e.retryAfter);  // seconds, on 429
}
```

Some failures come back as HTTP 200 with `success: false` - the SDK throws for those too, so catch the exception rather than checking status codes. Errors like `Renewal not available` and `Insufficient balance` happen **before** you are charged; a provider failure after a charge is refunded automatically.

## Webhooks (Dart server)

Register an HTTPS endpoint under **Webhooks** in your dashboard. Every event has the same structure: `event.order`, `event.esim` and `event.change`.

```dart
import 'package:shelf/shelf.dart';
import 'package:wiiline_sdk/wiiline_sdk.dart';

Future<Response> wiilineWebhook(Request request) async {
  final body = await request.readAsString(); // the RAW body
  final WebhookEvent event;
  try {
    event = constructWebhookEvent(body, request.headers['x-webhook-signature'], secret);
  } on WiilineApiException {
    return Response(400);
  }

  switch (event.type) {
    case WebhookEventTypes.orderCompleted:
      print('eSIM ready: ${event.esim?.qrcode}');
    case WebhookEventTypes.esimInstalled:
      print('Installed on ${event.change['device']}');
    case WebhookEventTypes.esimUsageThreshold:
      print('${event.esim?.iccid} used ${event.change['threshold']}%');
    case WebhookEventTypes.orderFailed:
      print('Failed, refunded: ${event.change['refunded']}');
  }
  return Response.ok('ok'); // answer within 10s
}
```

Retries reuse the same `event.id` - store it and ignore duplicates.

## License

MIT
