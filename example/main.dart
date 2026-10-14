// Run on a server or your machine - never ship the API key in an app.
//   WIILINE_API_KEY=wii_... dart run example/main.dart
import 'dart:io';

import 'package:wiiline_sdk/wiiline_sdk.dart';

Future<void> main() async {
  final client = WiilineClient(apiKey: Platform.environment['WIILINE_API_KEY']);
  try {
    final page = await client.plans.list(planType: 'country', filter: 'japan');
    print('${page.plans.length} plans');
    for (final plan in page.plans.take(5)) {
      print('- ${plan.name}: ${plan.price} ${plan.currency} (${plan.activationType.name})');
    }
  } on WiilineApiException catch (e) {
    print('API error ${e.status} ${e.code}: ${e.message}');
  } finally {
    client.close();
  }
}
