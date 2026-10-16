import '../client.dart';
import '../models.dart';

/// eSIM ordering and management. Buying, renewing and upgrading are limited
/// to 10 requests per minute per account.
class EsimResource {
  EsimResource(this._client);
  final WiilineClient _client;

  /// Buys [count] (1-10) eSIMs for a plan and charges your balance.
  ///
  /// Some networks prepare eSIMs asynchronously: if an eSIM isn't ready within
  /// ~25 seconds it comes back with `isPending` true and no QR code - fetch it
  /// later with [getOrder], or handle the `order.completed` webhook.
  ///
  /// Pass [iccid] to top up an existing eSIM instead (supported plans only;
  /// [count] must be 1).
  Future<IssueResult> issue({required String planId, int count = 1, String? iccid}) async {
    final json = await _client.request('POST', '/api/esim/issue', body: {
      'plan_id': planId,
      'count': count,
      if (iccid != null) 'iccid': iccid,
    });
    return IssueResult(json);
  }

  /// Current status, dates, usage and (where reported) device of an eSIM.
  Future<EsimRecord> info(String iccid) async {
    final json = await _client.request('GET', '/api/esim/info', query: {'iccid': iccid});
    final data = json['data'];
    return EsimRecord(data is Map<String, dynamic> ? data : const {});
  }

  /// Packages that can be applied to the eSIM. When none,
  /// [TopupCheckResult.message] explains why (e.g. the renewal deadline passed).
  Future<TopupCheckResult> checkTopup(String iccid) async {
    final json = await _client.request('GET', '/api/esim/topup-check', query: {'iccid': iccid});
    return TopupCheckResult(json);
  }

  /// Renews the eSIM onto [planId] - use a package id from [checkTopup].
  /// Eligibility is checked before you are charged; a network failure after
  /// the charge is refunded automatically ([RenewResult.refunded]).
  Future<RenewResult> renew({required String iccid, required String planId}) async {
    final json = await _client.request('POST', '/api/esim/renew', body: {
      'iccid': iccid,
      'plan_id': planId,
    });
    return RenewResult(json);
  }

  /// Lists upgrade packages for the eSIM without buying anything.
  Future<TopupListResult> listTopups(String iccid) async {
    final json = await _client.request('GET', '/api/esim/upgrade', query: {'iccid': iccid});
    return TopupListResult(json);
  }

  /// Buys an upgrade package from [listTopups] for the eSIM.
  Future<RenewResult> upgrade({required String iccid, required String productId}) async {
    final json = await _client.request('POST', '/api/esim/upgrade', body: {
      'iccid': iccid,
      'product_id': productId,
    });
    return RenewResult(json);
  }

  /// Replaces the eSIM with a new one (new ICCID and QR code) - e.g. the
  /// customer deleted it or moved to a new device. The active plan and the
  /// remaining data move to the new eSIM and the old one stops working.
  /// Free, but irreversible and limited to 3 replacements per account; not
  /// every eSIM supports it.
  Future<ChangeResult> change(String iccid) async {
    final json = await _client.request('POST', '/api/esim/change', body: {'iccid': iccid});
    return ChangeResult(json);
  }

  /// A previous order and all its eSIMs, by the `orderUuid` from [issue].
  Future<OrderResult> getOrder(String orderUuid) async {
    final json = await _client.request('GET', '/api/esim/order/${Uri.encodeComponent(orderUuid)}');
    return OrderResult(json);
  }
}
