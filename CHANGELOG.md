# Changelog

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
