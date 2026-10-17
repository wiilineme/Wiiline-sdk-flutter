/// Official Dart and Flutter SDK for the Wiiline eSIM API.
///
/// ```dart
/// import 'package:wiiline_sdk/wiiline_sdk.dart';
///
/// final client = WiilineClient(apiKey: 'wii_...'); // server-side only
/// final page = await client.plans.list(planType: 'country', filter: 'japan');
/// final order = await client.esim.issue(planId: page.plans.first.planUuid, idempotencyKey: 'unique-purchase-key');
/// print(order.esims.first.qrcode);
/// ```
library;

export 'src/client.dart' show WiilineClient;
export 'src/errors.dart';
export 'src/models.dart';
export 'src/resources/esim.dart' show EsimResource;
export 'src/resources/plans.dart' show PlansResource;
export 'src/webhooks.dart';
