# Changelog

## 0.2.1

- `TopupPackage`: new `planPrice`, `serviceFee`, `planType`, `countriesIncluded`.
  `price` is the full amount charged when the package is applied.
- `esim.checkTopup()` now lists upgrade/downgrade options for more eSIMs.

## 0.2.0

- Added `esim.change(iccid)` - replace an eSIM with a new one (new ICCID and QR
  code); returns `ChangeResult`. Limited to 3 replacements per account.
- Added the `esim.replaced` webhook event (`WebhookEventTypes.esimReplaced`).
- Breaking: removed `Plan.provider`, `EsimRecord.providerStatus`,
  `IssueResult.provider` and `TopupCheckResult.provider` - the API no longer
  says which network supplier fulfils a plan or an eSIM.

## 0.1.0

- Initial release.
- `WiilineClient` with API-key (server) and backend-proxy (Flutter app) modes.
- Plans: `plans.list()`, `plans.get()`.
- eSIMs: `issue()`, `info()`, `checkTopup()`, `renew()`, `listTopups()`,
  `upgrade()`, `getOrder()`.
- Typed models (`Plan`, `EsimRecord`, `Transaction`, results) with UTC dates,
  `EsimStatus` and `ActivationType` enums, device fields, and `raw` access.
- `WiilineApiException` with `code`, `status`, `retryAfter`.
- Webhooks: `verifyWebhookSignature()`, `constructWebhookEvent()` and
  `WebhookEventTypes`, for the unified `{ order, esim, change }` payload.
