// Typed views over the API's JSON. Every model keeps the full response in
// `raw`, so fields the SDK doesn't map yet are still reachable, and parsing is
// tolerant: a missing or differently-typed field becomes null instead of
// throwing.

String? _str(Object? v) => v == null ? null : (v is String ? (v.isEmpty ? null : v) : '$v');
num? _num(Object? v) => v is num ? v : (v is String ? num.tryParse(v) : null);
int? _int(Object? v) => _num(v)?.toInt();
double? _double(Object? v) => _num(v)?.toDouble();
bool? _bool(Object? v) => v is bool ? v : (v == 1 || v == '1' || v == 'true' ? true : (v == 0 || v == '0' || v == 'false' ? false : null));
Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : const {};
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

/// Parses ISO 8601 and the API's `YYYY-MM-DD HH:MM:SS` form (UTC) to a UTC DateTime.
DateTime? parseApiDate(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  final normalized = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(s) ? '${s.replaceFirst(' ', 'T')}Z' : s;
  return DateTime.tryParse(normalized)?.toUtc();
}

/// How a plan activates (`Plan.activationType`).
enum ActivationType {
  /// Activates on first use; many plans also auto-activate after a set number
  /// of days if unused (see `activationTypeDescription` / `otherInfo`).
  pdp,

  /// Starts at purchase - the usage period counts from the order time.
  immediate,

  /// A value this SDK version doesn't know.
  unknown;

  static ActivationType parse(Object? v) => switch (_str(v)?.toUpperCase()) {
        'PDP' => ActivationType.pdp,
        'IMMEDIATE' => ActivationType.immediate,
        _ => ActivationType.unknown,
      };
}

/// The unified eSIM status (see the API docs, "eSIM Status Values").
enum EsimStatus {
  released, installed, active, pending, expired, suspended, inactive, deleted, error, unknown;

  static EsimStatus parse(Object? v) {
    final s = (_str(v) ?? '').toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return switch (s) {
      'released' || 'provisioned' || 'ready' || 'available' => EsimStatus.released,
      'installed' || 'downloaded' => EsimStatus.installed,
      'active' || 'enabled' || 'running' || 'activated' || 'inuse' => EsimStatus.active,
      'pending' || 'processing' || 'new' || 'created' => EsimStatus.pending,
      'expired' => EsimStatus.expired,
      'suspended' || 'blocked' => EsimStatus.suspended,
      'inactive' || 'disabled' => EsimStatus.inactive,
      'deleted' || 'cancelled' || 'canceled' => EsimStatus.deleted,
      'error' || 'failed' => EsimStatus.error,
      _ => EsimStatus.unknown,
    };
  }
}

/// A network covering a country.
class NetworkCoverage {
  NetworkCoverage({this.name, this.speed});
  factory NetworkCoverage.fromJson(Map<String, dynamic> j) =>
      NetworkCoverage(name: _str(j['network_name']), speed: _str(j['speed']));
  final String? name;
  final String? speed;
}

/// A country covered by a plan.
class PlanCountry {
  PlanCountry({this.code, this.name, this.imageUrl, this.networks = const []});
  factory PlanCountry.fromJson(Map<String, dynamic> j) => PlanCountry(
        code: _str(j['code']),
        name: _str(j['name']),
        imageUrl: _str(j['image_url']),
        networks: _list(j['network_coverage']).map(NetworkCoverage.fromJson).toList(),
      );
  final String? code;
  final String? name;
  final String? imageUrl;
  final List<NetworkCoverage> networks;
}

/// A plan from the catalogue. [price] is the base price - the amount actually
/// charged (with the service fee) is in [Transaction.amountCharged].
class Plan {
  Plan(this.raw)
      : planUuid = _str(raw['plan_uuid']) ?? '',
        planCode = _str(raw['plan_code']),
        name = _str(raw['name']) ?? '',
        days = _int(raw['days']),
        price = _double(raw['price']),
        currency = _str(raw['currency']),
        data = _str(raw['data']),
        dataType = _str(raw['data_type']),
        activationType = ActivationType.parse(raw['activation_type']),
        activationTypeDescription = _str(raw['activation_type_description']),
        otherInfo = _str(raw['other_info']),
        planType = _str(raw['plan_type']),
        regionName = _str(raw['region_name']),
        countriesIncluded = _str(raw['countries_included']),
        countryIso2 = _str(raw['countryIso2']),
        operators = _str(raw['operators']),
        speed = _str(raw['speed']),
        apn = _str(raw['apn']),
        tether = _bool(raw['tether']),
        canRenew = _bool(raw['can_renew']),
        countries = _list(raw['countries']).map(PlanCountry.fromJson).toList();

  final Map<String, dynamic> raw;

  /// Use as `planId` when buying.
  final String planUuid;
  final String? planCode;
  final String name;
  final int? days;
  final double? price;
  final String? currency;
  final String? data;

  /// `fixed`, `unlimited` or `unlimited_per_day`.
  final String? dataType;
  final ActivationType activationType;
  final String? activationTypeDescription;

  /// Notes such as the activation deadline or a verification step.
  final String? otherInfo;

  /// `country`, `region` or `global`.
  final String? planType;
  final String? regionName;
  final String? countriesIncluded;
  final String? countryIso2;
  final String? operators;
  final String? speed;
  final String? apn;
  final bool? tether;
  final bool? canRenew;
  final List<PlanCountry> countries;
}

/// One eSIM, as returned by issue / info / order lookups.
class EsimRecord {
  EsimRecord(this.raw)
      : iccid = _str(raw['iccid']),
        status = EsimStatus.parse(raw['status_qr'] ?? raw['status']),
        qrcode = _str(raw['qrcode']),
        iosTapLink = _str(raw['ios_tap_link']),
        androidTapLink = _str(raw['android_tap_link']),
        planActivatedAt = parseApiDate(raw['plan_activated_at']),
        planExpiredAt = parseApiDate(raw['plan_expired_at']),
        activateBefore = parseApiDate(raw['activate_before']),
        renewBefore = parseApiDate(raw['renew_before']),
        dataUsedMb = _double(raw['data_used_mb']),
        dataLeftMb = _double(raw['data_left_mb']),
        dataPackageMb = _double(raw['data_package_mb']),
        unlimited = _bool(raw['unlimited']),
        packageName = _str(raw['package_name']),
        apn = _str(raw['apn']),
        installDevice = _str(raw['install_device']),
        installCount = _int(raw['install_count']),
        installedAt = parseApiDate(raw['installed_at']),
        eid = _str(raw['eid']);

  final Map<String, dynamic> raw;
  final String? iccid;
  final EsimStatus status;

  /// LPA activation string - render it as a QR code.
  final String? qrcode;

  /// One-tap install links for the device itself.
  final String? iosTapLink;
  final String? androidTapLink;

  /// Null until the eSIM is first used.
  final DateTime? planActivatedAt;
  final DateTime? planExpiredAt;

  /// Activation deadline, before first use (where the network sets one).
  final DateTime? activateBefore;

  /// Last date the eSIM can be renewed (some networks).
  final DateTime? renewBefore;
  final double? dataUsedMb;
  final double? dataLeftMb;
  final double? dataPackageMb;
  final bool? unlimited;
  final String? packageName;
  final String? apn;

  /// Device fields - only on networks that report the device.
  final String? installDevice;
  final int? installCount;
  final DateTime? installedAt;
  final String? eid;

  /// True while the eSIM is still being prepared (no QR code yet).
  bool get isPending => status == EsimStatus.pending && (qrcode == null || qrcode!.isEmpty);
}

/// Cost breakdown of a purchase.
class Transaction {
  Transaction(this.raw)
      : planCost = _double(raw['plan_cost']),
        serviceFee = _double(raw['service_fee']),
        amountCharged = _double(raw['amount_charged']),
        balanceBefore = _double(raw['balance_before']),
        balanceAfter = _double(raw['balance_after']),
        planName = _str(raw['plan_name']),
        quantity = _int(raw['quantity']);
  final Map<String, dynamic> raw;
  final double? planCost;
  final double? serviceFee;

  /// The real total charged (plan + service fee).
  final double? amountCharged;
  final double? balanceBefore;
  final double? balanceAfter;
  final String? planName;
  final int? quantity;
}

/// Result of `plans.list()`.
class PlansPage {
  PlansPage(this.raw)
      : plans = _list(raw['data']).map(Plan.new).toList(),
        total = _int(_map(raw['meta'])['total']);
  final Map<String, dynamic> raw;
  final List<Plan> plans;
  final int? total;
}

/// Result of `esim.issue()`.
class IssueResult {
  bool get isPending => raw['pending'] == true || esims.any((esim) => esim.isPending);
  IssueResult(this.raw)
      : orderUuid = _str(raw['order_uuid']) ?? '',
        message = _str(raw['message']),
        esims = _list(_map(_map(raw['data'])['response'])['esims']).map(EsimRecord.new).toList(),
        transaction = raw['transaction'] is Map<String, dynamic> ? Transaction(raw['transaction']) : null;
  final Map<String, dynamic> raw;

  /// Keep this - it identifies the order for `esim.getOrder()` and webhooks.
  final String orderUuid;
  final String? message;
  final List<EsimRecord> esims;
  final Transaction? transaction;
}

/// Result of `esim.renew()` and `esim.upgrade()`.
class RenewResult {
  RenewResult(this.raw)
      : orderUuid = _str(raw['order_uuid']) ?? '',
        message = _str(raw['message']),
        iccid = _str(_map(raw['data'])['iccid']),
        status = _str(_map(raw['data'])['status']),
        transaction = raw['transaction'] is Map<String, dynamic> ? Transaction(raw['transaction']) : null,
        refunded = _bool(raw['refunded']) ?? false,
        refundAmount = _double(raw['refund_amount']);
  final Map<String, dynamic> raw;
  final String orderUuid;
  final String? message;
  final String? iccid;

  /// `completed`, or `pending` on networks that confirm asynchronously
  /// (a `renewal.completed` / `renewal.failed` webhook follows).
  final String? status;
  final Transaction? transaction;
  final bool refunded;
  final double? refundAmount;

  bool get isPending => status?.toLowerCase() == 'pending';
}

/// A package that can be applied to an existing eSIM.
class TopupPackage {
  TopupPackage(this.raw)
      : id = _str(raw['id']) ?? '',
        name = _str(raw['name']),
        days = _int(raw['days']),
        data = _str(raw['data']),
        price = _double(raw['price']),
        planPrice = _double(raw['plan_price']),
        serviceFee = _double(raw['service_fee']),
        currency = _str(raw['currency']),
        unlimited = _bool(raw['unlimited']),
        planType = _str(raw['plan_type']),
        countriesIncluded = _str(raw['countries_included']),
        planCode = _str(raw['plan_code']),
        isCurrentPlan = _bool(raw['is_current_plan']);
  final Map<String, dynamic> raw;

  /// Pass to `esim.upgrade()` (or `esim.renew()` as planId).
  final String id;
  final String? name;
  final int? days;
  final String? data;

  /// Total you'll be charged ([planPrice] + [serviceFee]).
  final double? price;
  final double? planPrice;
  final double? serviceFee;
  final String? currency;
  final bool? unlimited;

  /// `country`, `region` or `global`.
  final String? planType;
  final String? countriesIncluded;
  final String? planCode;
  final bool? isCurrentPlan;
}

/// Result of `esim.checkTopup()`.
class TopupCheckResult {
  TopupCheckResult(this.raw)
      : iccid = _str(raw['iccid']),
        topupAvailable = _bool(raw['topup_available']) ?? false,
        message = _str(raw['message']),
        packages = _list(_map(raw['data'])['available_packages']).map(TopupPackage.new).toList();
  final Map<String, dynamic> raw;
  final String? iccid;
  final bool topupAvailable;

  /// Explains why when [topupAvailable] is false.
  final String? message;
  final List<TopupPackage> packages;
}

/// Result of `esim.listTopups()`.
class TopupListResult {
  TopupListResult(this.raw)
      : iccid = _str(_map(raw['data'])['iccid']),
        packages = _list(_map(raw['data'])['available_topups']).map(TopupPackage.new).toList(),
        message = _str(_map(raw['data'])['message']);
  final Map<String, dynamic> raw;
  final String? iccid;
  final List<TopupPackage> packages;

  /// Why the list is empty, when the eSIM can't be renewed.
  final String? message;
}

/// Result of `esim.getOrder()`.
class OrderResult {
  OrderResult(this.raw)
      : orderUuid = _str(_map(raw['order'])['order_uuid']) ?? _str(raw['order_uuid']) ?? '',
        status = _str(_map(raw['order'])['status']),
        esims = _list(raw['esims']).map(EsimRecord.new).toList();
  final Map<String, dynamic> raw;
  final String orderUuid;
  final String? status;
  final List<EsimRecord> esims;
}

/// Result of `esim.change()`: the replacement eSIM (new ICCID and QR code).
/// The old eSIM ([replacedIccid]) stops working.
class ChangeResult {
  ChangeResult(this.raw)
      : message = _str(raw['message']),
        replacedIccid = _str(_map(raw['data'])['replaced_iccid']),
        orderUuid = _str(_map(raw['data'])['order_uuid']),
        esim = EsimRecord(_map(_map(raw['data'])['esim']));
  final Map<String, dynamic> raw;
  final String? message;
  final String? replacedIccid;

  /// `null` in testing mode.
  final String? orderUuid;

  /// The new eSIM - send its [EsimRecord.qrcode] / tap links to the customer.
  final EsimRecord esim;
}
