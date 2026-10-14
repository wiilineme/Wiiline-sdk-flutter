import '../client.dart';
import '../models.dart';

/// The plan catalogue.
class PlansResource {
  PlansResource(this._client);
  final WiilineClient _client;

  /// Lists the plans available to your account.
  ///
  /// [planType] is `country`, `region` or `global`. [filter] searches plan
  /// names and countries. Cache the result - prices change rarely.
  Future<PlansPage> list({String planType = 'country', String? filter, String? planId}) async {
    final json = await _client.request('GET', '/api/plans', query: {
      'plan_type': planType,
      'filter': filter,
      'plan_id': planId,
    });
    return PlansPage(json);
  }

  /// One plan by its `plan_uuid` or `plan_code`.
  Future<Plan> get(String id) async {
    final json = await _client.request('GET', '/api/plans/${Uri.encodeComponent(id)}');
    final data = json['data'];
    return Plan(data is Map<String, dynamic> ? data : const {});
  }
}
