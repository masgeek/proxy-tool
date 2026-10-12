# PRD — SMS Transactions Android Companion

**Status:** Draft, decisions resolved
**Owner:** —
**Last updated:** 2026-10-12

---

## 1. Summary

An Android application that turns bank and mobile-money SMS alerts into
bookkeeping entries. The user selects which senders to trust, the app parses each
message into a debit or credit, and posts it to the REST API of whichever finance
backend is running, which is Firefly III. The goal is that daily bookkeeping is a side effect of normal phone
use, not a nightly chore.

## 2. Problem

Transaction data exists as plain SMS long before it reaches any bookkeeping tool.
Today that means reading each message and typing each amount, with the
transcription errors that implies. Mobile money in particular emits a message for
every movement, so the manual burden scales with activity.

## 3. Goals

- Capture a transaction within a minute of the SMS arriving, with no user action.
- Let the user control exactly which sender IDs are parsed.
- Post correct income and expense entries to a REST API, idempotently.
- Survive loss of connectivity without losing or duplicating a transaction.
- Make every automatic decision reviewable and reversible.
- Keep the app coupled to exactly one API, so a new bookkeeping backend never
  requires a new Android release.

## 4. Non-goals

- Not a banking app; it never initiates or authorises a payment.
- Not a receipt-scanning or reconciliation product.
- Not a general SMS client; no message content is displayed beyond what a
  transaction needs.
- Out of scope for v1: SMS sending, USSD, card-present transactions, and syncing
  the sender allowlist between devices.

## 5. Users

| Persona | Need |
| --- | --- |
| Household bookkeeper | M-Pesa and bank alerts should become budget entries without typing |
| Freelancer | Income messages should post as deposits to a specific account |
| Family member | A shared allowlist so a spouse's alerts are captured too |

## 6. Platform

Android 10 (API 29) minimum. Kotlin, minSdk 29. Distributed as a sideloaded APK
from repository releases; no Play Store listing in v1, which also removes the SMS
permission review that a Play listing would trigger.

## 7. Functional requirements

Requirement IDs restart per subsection, so cite them as `F7.4-3` for example.

### 7.1 Message capture

| ID | Requirement |
| --- | --- |
| F7.1-1 | Capture through a notification listener as the primary path, so the app needs no SMS permission on stock Android. |
| F7.1-2 | Fall back to an SMS broadcast receiver, used only when notification access is declined. |
| F7.1-3 | Deduplicate messages delivered through more than one path, keyed on sender ID plus message timestamp. |
| F7.1-4 | Discard any message from a non-allowlisted sender before it is parsed or stored. |
| F7.1-5 | Onboarding walks through granting notification access and explains the fallback if it is refused. |
| F7.1-6 | Ship parsers for M-Pesa and the primary bank; new parsers are added as data, not code changes. |

### 7.2 Sender allowlist

| ID | Requirement |
| --- | --- |
| F7.2-1 | Add, remove and rename a sender by its displayed sender ID. |
| F7.2-2 | Per sender, choose accepted directions: credits only, debits only, or both. |
| F7.2-3 | Per sender, choose the target account in the connected backend. |
| F7.2-4 | Per sender, choose the currency; the message never sets the currency, because a misread symbol is silent corruption. |
| F7.2-5 | Per sender, declare which accounts are your own, so movements between them are recognised as internal transfers. |
| F7.2-6 | Per sender, set auto-post limits: maximum single amount, maximum per day, and an always-confirm switch. |
| F7.2-7 | A blocklist is checked before the allowlist, so a sender on both lists is always blocked. |
| F7.2-8 | The allowlist is device-local in v1, with JSON export and import as the backup and transfer mechanism. |

### 7.3 Parsing

| ID | Requirement |
| --- | --- |
| F7.3-1 | Extract amount, direction, timestamp, reference, balance-after and counterparty where present. |
| F7.3-2 | Parsers return a confidence level. Anything below the configured threshold goes to review instead of posting. |
| F7.3-3 | Store the raw message beside the parsed result while pending, and purge raw bodies after the retention period. |
| F7.3-4 | Parsing is entirely on device; only extracted fields are sent to the backend. |
| F7.3-5 | Timestamps are stored in UTC and rendered in the household time zone, so a timezone change never rewrites history. |
| F7.3-6 | Locale is not trusted for number formatting. The sender's currency and a documented thousands-separator rule drive parsing, and anything ambiguous goes to review. |
| F7.3-7 | Detect reversal messages as their own type, carrying a reference back to the original transaction. |
| F7.3-8 | Detect internal-transfer markers: explicit wording, a debit and credit from the same sender inside a matching window, or a destination in the sender's own-account list. |
| F7.3-9 | A reversal or a transfer leg that cannot be matched to a stored entry is parked for review, never posted as a new transaction. |
| F7.3-10 | Cross-sender suppression: entries with the same amount, currency, direction and timestamp window are collapsed into one, with the suppressed copy retained for audit. |

### 7.4 Posting

| ID | Requirement |
| --- | --- |
| F7.4-1 | The app posts to the intermediate ingestion API only. It never talks to a bookkeeping backend directly. |
| F7.4-2 | The app's contract is one endpoint shape and one canonical payload, versioned independently of any backend. |
| F7.4-3 | Map direction explicitly per backend; see section 9. |
| F7.4-4 | Apply a configurable tag or category prefix per sender, for example `sms:m-pesa`. |
| F7.4-5 | Use the parsed reference as the transaction description or note. |
| F7.4-6 | Retry transient failures with exponential backoff and jitter, capped at a total retry budget per entry, then dead-letter to needs_review. |
| F7.4-7 | A `4xx` response is never retried blindly; it becomes needs_review with the response recorded. |
| F7.4-8 | Send a stable idempotency key derived from sender, reference and timestamp. |
| F7.4-9 | Dry-run mode parses and displays without ever posting. |
| F7.4-10 | Rate-limit posting, for example 5 requests per 10 seconds, so a backlog does not trip backend limits. |
| F7.4-11 | Record the provider's returned transaction id so a posted entry can be opened and audited. |
| F7.4-12 | Enforce the per-sender auto-post limits. An entry above a limit, or beyond the daily total, is routed to review instead of posted. |
| F7.4-13 | Resolve an `accountHint` against the provider's account list; an unresolvable hint parks the entry rather than defaulting to an account. |
| F7.4-14 | Where the account currency differs from the transaction currency, supply a base amount from a configured rate source or park the entry. Never post an unconverted amount into a different-currency account. |
| F7.4-15 | Internal transfers post as a balanced pair of legs, never as income and expense; see section 9.1. |
| F7.4-16 | Honour a global pause: while paused, entries are accepted and queued but nothing is forwarded to the provider. |

### 7.5 Offline and recovery

| ID | Requirement |
| --- | --- |
| F7.5-1 | Queue entries in a local Room database with state pending, posting, posted, failed or needs_review. |
| F7.5-2 | A WorkManager job drains the queue on connectivity, with the backoff rules in F7.4-6. |
| F7.5-3 | Nothing is dropped; the queue survives app restart and reboot. |
| F7.5-4 | An inbox lists pending, failed and needs_review entries with retry, edit and discard. |
| F7.5-5 | A posted entry can be voided in the app, which reverses it in the provider rather than only hiding it locally. |
| F7.5-6 | Cap both queues: the app queue and the service entry store have a maximum size, and reaching it raises an alert rather than filling the disk. |
| F7.5-7 | Retain posted and suppressed entries for a bounded period (default 90 days); retain needs_review entries until resolved. |

### 7.6 Connection and credentials

| ID | Requirement |
| --- | --- |
| F7.6-1 | Store the ingestion API token in the Android keystore; never in preferences, logs or crash output. |
| F7.6-2 | The app never holds a bookkeeping backend credential; provider credentials live only in the ingestion service. |
| F7.6-3 | Validate connectivity, TLS and token on pairing, with a distinct error for each failure. |
| F7.6-4 | Require HTTPS. Cleartext traffic is refused rather than downgraded. |
| F7.6-5 | One ingestion endpoint at a time. Switching bookkeeping backend is a server-side operation and requires no app change. |
| F7.6-6 | Requests carry a bearer token **and** a per-request HMAC signature over timestamp, nonce and body. The service rejects a timestamp outside a short window and replays of a seen nonce. |
| F7.6-7 | The token is rotatable and revocable per device, without a service restart. |

### 7.7 Reporting and alerting

| ID | Requirement |
| --- | --- |
| F7.7-1 | A daily notification summarising posted, failed and needs-review counts. |
| F7.7-2 | On-device statistics: entries per day, total in, total out, unposted count. All local. |
| F7.7-3 | The service exports metrics for queue depth, dead-letter count, posting error rate and posting latency. |
| F7.7-4 | Alert when dead-lettered entries exist beyond a short window, or when queue depth exceeds its cap — wired into the existing Prometheus and Grafana stack. |
| F7.7-5 | Notify once when an unlisted sender is observed, so a changed sender ID is noticed rather than silently dropping transactions. |
| F7.7-6 | On-device settings expose the auto-post limits, the kill switch and the pending-queue depth. |

## 8. Parsing specification

Parsers are named rules matching a sender ID pattern, stored as data so a new
sender is a configuration change.

| Parser | Matches | Extracts |
| --- | --- | --- |
| `mpesa` | M-Pesa sender IDs | amount, direction from body, balance, transaction code as reference |
| `bank_card` | issuing bank sender IDs | amount, direction from debit/credit wording, balance, masked card or last four digits |
| `salary` | known employer or payroll senders | amount as credit, payee from the sender name |

Direction detection is deliberately explicit. Ambiguous wording resolves to
needs_review, never to a guess.

Worked examples, M-Pesa:

```
KSH 1,500.00 sent to 07XX XXX XXX on 12/10/2026 14:32. Balance KSH 24,300.00
→ amount 1500.00, direction debit, reference from the send line, currency KES

You have received KSH 45,000.00 from JOHN DOE on 12/10/2026 09:15. Balance KSH 69,300.00
→ amount 45000.00, direction credit, reference received from JOHN DOE, currency KES
```

## 9. Backend mapping

| Field | Firefly III |
| --- | --- |
| Amount | `amount`, string decimal |
| Direction | `type`: `withdrawal` / `deposit` |
| Description | `description` |
| Date | `date`, ISO 8601 |
| Tags | `tag_names` |
| Idempotency | `external_id` |
| Internal transfer | native `transfer` with source and destination, else two entries tagged with the shared `transferGroupId` |
| Reversal | delete or reverse the original |

Every entry posts to the asset account chosen per sender, so credits and debits
land correctly without the app knowing the chart of accounts.

Firefly III request shape:

```json
{
  "type": "withdrawal",
  "date": "2026-10-12T14:32:00+03:00",
  "amount": "1500.00",
  "currency_code": "KES",
  "description": "M-Pesa send 07XX XXX XXX",
  "tag_names": ["sms:m-pesa"]
}
```

### 9.1 Internal transfers: the ledger approach

A movement between two of your own accounts is not income and not an expense. It
is a movement. Posting it as a debit and the matching credit as income would
inflate both totals and quietly corrupt every budget that uses them.

Internal transfers are therefore modelled as a **balanced pair of ledger legs**
rather than a special transaction type:

| Property | Observed leg | Counterpart leg |
| --- | --- | --- |
| Origin | The SMS that arrived | Synthesised by the ingestion service |
| Direction | As parsed | Opposite of the observed leg |
| Account | Source account | Destination account |
| Amount | As parsed, identical | Identical |
| `transferGroupId` | Shared | Shared |
| `leg` | `source` | `destination` |
| `synthetic` | `false` | `true` |
| `classification` | `internal_transfer` | `internal_transfer` |

Consequences of this model:

- Income and expense totals exclude both legs, because neither is income or
  expense. Cash flow is unaffected: the money moved, so total cash is unchanged.
- Only the observed leg comes from a message. The counterpart is derived, so it
  can never disagree with the original by a rounding or transcription error.
- If the destination account is unknown, the counterpart leg is not created and
  the observed leg is parked for review rather than posted as a lone expense.
- Reconciliation stays simple: one group, two legs, equal and opposite.

Where the provider has a native transfer representation, the adapter uses it and
records the group id; otherwise it writes two entries linked by the shared
`transferGroupId` in the tag, so a reader can still pair them.

Detection rules, applied in order:

1. Explicit wording in the message ("to your own account", "transfer to", "internal transfer").
2. Destination present in the sender's own-account list (F7.2-5).
3. A debit and a credit from the same sender, same amount and currency, within a
   matching window (default 15 minutes), where the reference or counterparty links them.
4. None of the above: the debit is treated as an expense. Being wrong in this
   direction is recoverable by tagging; being wrong in the other silently
   misreports spending.

### 9.2 Reversals

A reversal references the original transaction rather than describing a new one.
The service voids the matched entry, or, if the provider has no void, posts the
compensating entry and links both with a `reverses` reference. A reversal with no
match is parked for review, because posting it as a fresh transaction would
invent an amount that never happened.

### 9.3 Cross-sender suppression

The same movement is often announced twice, by the mobile money provider and by
the bank. Entries are fingerprinted on amount, currency, direction and a short
timestamp window; a second entry inside the window is suppressed and linked to the
first, with both retained so the suppression is auditable and reversible. The
window is a configuration value, because a wider window suppresses more and risks
discarding two genuine identical payments in quick succession.

## 9A. Why auto-post needs limits

SMS sender IDs are not authenticated. Anyone able to deliver a message to the
phone can choose the sender string, so a perfectly formatted fake transaction
arriving from a familiar sender ID would be posted without question. This is the
weakest point in an otherwise automated design, and it is why "fully automatic"
is bounded rather than absolute.

Controls, applied in order:

1. **Sender must be allowlisted** — the message is discarded otherwise (F7.1-4).
2. **Amount ceiling per transaction** — above it, the entry goes to review.
3. **Daily total per sender** — crossing it pauses auto-post for that sender until
   the user clears it, which catches a burst of spoofed messages that stay small.
4. **Optional always-confirm sender** — for senders the user does not want
   trusted fully, every entry is confirmed.
5. **Reversibility** — every posted entry can be voided, so a bad batch costs
   minutes rather than a manual cleanup.

These limits are the reason auto-posting is safe to leave on. Without them the
correct default would be confirm-everything, which defeats the purpose.

## 9B. Authentication of ingestion requests

The endpoint accepts writes to financial records from the public internet, so a
bearer token alone is thin: a leaked token would let an attacker inject plausible
transactions. Each request therefore carries, in addition to the token:

- a timestamp, rejected outside a short window (default 5 minutes);
- a single-use nonce, remembered briefly and rejected on replay;
- an HMAC signature over timestamp, nonce and body, keyed per device.

Credentials are stored server-side in a secret store, rotated per device, and the
Caddy route adds rate limiting so the service is not the first line of defence
against abuse.


## 10. Ingestion API (intermediate layer)

The app posts to one service, and that service owns every backend difference. The
canonical model is the contract; a backend adapter is the only place a field
differs.

### 10.1 Why

Without this layer, every new bookkeeping backend means: a new adapter in the app,
a release, and every phone updated before the backend can be used. With it, a new
backend is a server-side change, and the app keeps one code path, one payload and
one set of tests. It also keeps backend credentials off the handset.

The same entry point can later accept other sources — email, a bank webhook, a
modem — without changing the mobile client.

### 10.2 Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/health` | Liveness plus the active adapter name and version |
| `GET` | `/v1/provider` | Active provider, its accounts and capabilities |
| `POST` | `/v1/entries` | Ingest one canonical transaction; stored first, idempotent |
| `POST` | `/v1/entries/batch` | Ingest up to 100, for draining a backlog |
| `GET` | `/v1/entries` | Review queue; filter by state, sender, date, currency |
| `GET` | `/v1/entries/{id}` | One entry with its provider result and edit history |
| `POST` | `/v1/entries/{id}/approve` | Post a reviewed entry |
| `POST` | `/v1/entries/{id}/reject` | Do not post; keep for the record |
| `POST` | `/v1/entries/{id}/edit` | Correct amount, account, classification or tags |
| `POST` | `/v1/entries/{id}/retry` | Re-attempt a failed entry |
| `POST` | `/v1/entries/{id}/void` | Reverse a posted entry in the provider |
| `POST` | `/v1/entries/approve-batch` | Bulk approve a filtered set |
| `GET` | `/v1/entries/counts` | Counts by state, for the app summary |
| `GET` | `/v1/senders` | Sender allowlist as the service sees it |
| `PUT` | `/v1/senders/{senderId}` | Update direction, account, tag and auto-post limits |
| `POST` | `/v1/control/pause` | Kill switch: accept and store, forward nothing |
| `POST` | `/v1/control/resume` | Resume forwarding |

All responses are JSON. Errors carry a stable machine code, a human message, and
whether the caller should retry.

### 10.3 Canonical transaction

```json
{
  "idempotencyKey": "mpesa:OE6K2L8Q4M:2026-10-12T14:32:00Z",
  "occurredAt": "2026-10-12T14:32:00Z",
  "direction": "debit",
  "amount": { "value": "1500.00", "currency": "KES" },
  "description": "M-Pesa send 07XX XXX XXX",
  "reference": "OE6K2L8Q4M",
  "source": { "channel": "sms", "senderId": "MPESA", "label": "M-Pesa" },
  "accountHint": "cash",
  "tags": ["sms:m-pesa"],
  "classification": "expense",
  "confidence": 0.98,
  "metadata": { "balanceAfter": "24300.00", "rawRetainedUntil": "2026-11-12T00:00:00Z" }
}
```

Rules that keep the contract stable:

- `direction` is one of `debit` or `credit`. Adapters translate it.
- `amount.value` is a string decimal, never a JSON number, so no float rounding
  occurs in transit.
- `idempotencyKey` is required. The service rejects a repeat of a key it has
  already stored, and returns the original record instead of creating a second.
- `confidence` below the configured threshold is stored as `needs_review` and not
  forwarded, which keeps the review decision server-side and auditable.
- `classification` is one of `income`, `expense`, `internal_transfer` or
  `reversal`. For an internal transfer both legs share `transferGroupId`, and the
  counterpart leg carries `synthetic: true`. Income and expense reporting excludes
  `internal_transfer` on both legs.
- Auto-post limits are evaluated by the service, not trusted from the client: the
  app may under-report an amount, so the service compares the canonical amount
  against the sender's configured ceilings.
- `metadata` is provider-agnostic; adapters ignore what they cannot use.

### 10.4 Provider adapter contract

Each backend implements one interface. The service is written against it, so a new
backend is a new file plus a configuration entry.

| Member | Responsibility |
| --- | --- |
| `Name()` / `Version()` | Identity reported by `/v1/health` |
| `HealthCheck(ctx)` | Reachability and credential validity |
| `ListAccounts(ctx)` | Accounts available for sender mapping |
| `CreateTransaction(ctx, txn)` | Convert canonical fields and post; return provider id |
| `VoidTransaction(ctx, providerId)` | Reverse a posted entry |
| `Supports() []Capability` | Optional features such as `void`, `attachments`, `recurring` |
| `TranslateDirection(direction)` | Direction to provider semantics |

Adapter obligations:

- Translate, never reinterpret. The canonical amount, currency and direction are
  already decided by the time an adapter sees them.
- Map an unmapped capability explicitly rather than silently dropping data.
- Surface provider errors as stable codes so the app can distinguish "retry later"
  from "needs review" without parsing prose.
- Never perform a second financial write for one canonical transaction; exactly one
  attempt produces at most one provider entry.

### 10.5 Store: review before posting

The ingestion service owns a database of its own. Every transaction it receives
is written there first and lives there as the system of record, independent of
whether it is ever forwarded to a bookkeeping backend.

That ordering is deliberate. Nothing reaches the budget app before it is stored,
so:

- a crash, a provider outage or a lost phone cannot lose a transaction;
- the entry can be reviewed, corrected, split, rejected or voided before it becomes
  a financial record;
- the history survives an app reinstall, a phone change or a backend switch;
- the audit trail is complete, including entries that were never posted.

`transactions` is a dedicated database on the shared PostgreSQL service, so the
existing `db-backup` tooling covers it. It is not created implicitly: the database
and its role are provisioned like any other application database.

#### Schema

| Table | Purpose | Notable columns |
| --- | --- | --- |
| `entries` | one canonical transaction per row | `idempotency_key` unique, `direction`, `amount`, `currency`, `classification`, `transfer_group_id`, `leg`, `account_hint`, `resolved_account_id`, `confidence`, `state`, `attempts`, `last_error`, `provider_id`, `occurred_at`, `received_at` |
| `senders` | allowlist mirrored server-side | `sender_id` unique, `label`, `directions`, `own_accounts`, `auto_post_max_amount`, `auto_post_max_per_day`, `always_confirm`, `tag_prefix` |
| `review` | every human decision, kept separately | `entry_id`, `action`, `actor`, `reason`, `at` |
| `nonces` | replay protection | `nonce` unique, `seen_at`, expires quickly |
| `links` | pairing of transfer legs and suppressions | `group_id`, `entry_id`, `relation` |

Indexes are required on `idempotency_key`, `(state, occurred_at)` for the review
queue, `(sender_id, occurred_at)` for duplicate fingerprinting, and
`transfer_group_id`.

#### State machine

```
received ──▶ awaiting_review ──▶ approved ──▶ posting ──▶ posted ──▶ voided
                  │                    │           │
                  │                    │           └──▶ failed ──▶ posting
                  ├──▶ rejected        └──▶ needs_review ──▶ posting
                  └──▶ suppressed ──▶ (linked to the entry that won)
```

- `awaiting_review` is the default destination for anything that is not eligible
  for automatic posting.
- `suppressed` is used for a cross-sender duplicate; the entry is kept, linked to
  the entry that was posted.
- `voided` records a reversal; the original entry stays visible with its outcome.

#### Posting policy

Two modes, per sender:

- **Review first** — everything lands in `awaiting_review` and is posted only when
  approved, individually or in bulk. This is the default for a new sender.
- **Auto-post** — entries that pass confidence, classification and the configured
  ceilings move straight to `posting`; anything else still stops for review.

Switching a sender between modes does not change entries already stored. Every
transition is written to `review`, so "why was this posted" always has an answer.

#### Review surface

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/entries` | Filter by state, sender, date range, currency; paginated |
| `GET` | `/v1/entries/{id}` | One entry with its provider result and edit history |
| `POST` | `/v1/entries/{id}/approve` | Post now |
| `POST` | `/v1/entries/{id}/reject` | Do not post; keep for the record |
| `POST` | `/v1/entries/{id}/edit` | Correct amount, account, classification or tags |
| `POST` | `/v1/entries/approve-batch` | Bulk approve a filtered set |
| `POST` | `/v1/entries/{id}/void` | Reverse a posted entry |
| `GET` | `/v1/entries/counts` | Counts by state, for the app summary |

Corrections made during review are recorded, so an amount that was misparsed is
visible as a correction rather than silently replaced.


### 10.6 Idempotency and delivery guarantees

- The service stores `idempotencyKey` with the entry and enforces uniqueness, so a
  retried batch cannot duplicate a transaction even if the app lost its response.
- Entries are at-least-once from the app and effectively-once at the provider.
- A provider call that times out is resolved by querying the provider with the
  idempotency reference before retrying, so an ambiguous timeout does not double-post.
- Per-entry retry budget, then dead-letter to `needs_review` with the recorded error.

### 10.7 Operational requirements

- API versioned in the path (`/v1`); the app pins a version and the service
  supports the previous one for at least one app release cycle.
- Structured logs keyed by `idempotencyKey`, with no message bodies and no tokens.
- Health endpoint suitable for the existing monitoring stack: it is the only
  component of this feature that needs to be observable server-side.
- The service holds one provider credential set at a time in v1, stored outside the
  repository.


## 11. UX

1. **Pair** — backend URL and token, with a live connection test.
2. **Grant access** — notification access, with the SMS permission fallback.
3. **Allowlist** — choose senders from those observed, set direction, account and
   currency per sender.
4. **Quiet operation** — no notification unless something needs attention.
5. **Inbox** — review, edit, retry or discard anything not posted.

Deliberate absence: no dashboard-first design. The success state is an empty inbox.

## 12. Data model

The ingestion service's schema is in section 10.5. The app keeps its own local
copy, device-local only:

| Entity | Key fields |
| --- | --- |
| `Sender` | senderId, label, enabled directions, accountId, currency, tagPrefix |
| `Transaction` | localId, senderId, reference, amountMinor, currency, direction, classification, transferGroupId, leg, occurredAtUtc, state, confidence, attempts, lastError, backendId |
| `RawMessage` | transactionId, body, receivedAt, purgeAfter |
| `Endpoint` | ingestionUrl, tokenRef |

The two are not redundant. The app's queue is a delivery buffer; the service's
database is the system of record. Deleting the app clears the buffer but not the
history.

Amounts are stored as minor units in an integer column. Floating point is never
used for money.

## 13. Security and privacy

- Messages are read on device; raw bodies never leave the phone, and only the
  fields needed to build a transaction are transmitted.
- No analytics SDKs, no third-party crash reporting, no network destination other
  than the configured backend.
- The app's only secret is the ingestion API token, held in the keystore and
  redacted from logs, screenshots and any exported diagnostics. Bookkeeping
  backend credentials never reach the phone at all: they are held by the ingestion
  service, so losing the handset does not expose the ledger.
- Provider credentials are stored server-side in a secret store, never in an
  environment file that could be committed.
- Allowlist and blocklist are checked before parsing, so an unknown sender leaves
  no trace in storage.
- Raw message retention is bounded and configurable, defaulting to 30 days, and is
  enforced by a daily purge job rather than by app exit.
- Uninstall removes the database and keystore entry; the backend keeps whatever it
  already stored, which is why voiding is an explicit operation (F34).

## 14. Permissions and compliance

- Notification listener access avoids `READ_SMS` in the common case, which is the
  recommended route and the one v1 ships.
- The fallback receiver needs `RECEIVE_SMS`; sideloaded distribution avoids the
  Play permission review entirely.
- `POST_NOTIFICATIONS` for the summary and `INTERNET` for the backend call.
  Nothing else is requested.

## 15. Testing strategy

| Layer | Approach |
| --- | --- |
| Parsers | Unit tests over a committed corpus of real messages, expected outputs inline, one test per known sender format |
| Mapping | Unit tests asserting the direction and sign per backend |
| Ingestion API | Contract tests against the service, including idempotent replay, a `4xx` and a timeout path |
| Provider adapters | One conformance suite every adapter must pass, so adding a backend cannot regress the ones already shipped |
| Adapters | Fake-provider tests proving direction, sign and account resolution per backend |
| Transfer pairing | Cases proving both legs are balanced, that an unmatched leg never posts, and that income and expense totals exclude the pair |
| Auto-post limits | Boundary tests at, just under and just over each ceiling, including the daily total |
| Auth | Replay, stale-timestamp and wrong-signature rejection |
| Queue | State-machine tests covering retry, dead-letter and manual retry |
| End to end | Instrumented test: inject a message, assert one entry posted and no duplicate on replay |

The parser corpus is the highest-value asset here; it is reviewed with every new
sender format that produces a needs_review entry.

## 16. Success metrics

| Metric | Target |
| --- | --- |
| Parse success rate on allowlisted senders | above 95% |
| Entries needing review | below 2% |
| Duplicate posts | zero, verified by idempotency key |
| Median delay from SMS to posted entry | under 60 seconds |
| Parser corpus growth | no growth without a named failing case |
| Auto-post escapes | zero entries above a ceiling ever posted |
| Reconciliation differences | under 0.5% of entries per month |

## 17. Delivery plan

**Phase 1 — Capture and parse.** Notification listener, fallback receiver,
allowlist with own-account and auto-post limit settings, M-Pesa and bank parsers
including transfer and reversal detection, local inbox, dry-run mode, no posting.
Auto-post ceilings and the transfer model are designed and specified here even
though nothing is posted yet, because both change the parser output shape.

**Phase 2 — Ingestion API, store and Firefly adapter.** The intermediate service
with the canonical model, its own `transactions` database and review queue, the
Firefly III adapter, idempotency, retry and dead-lettering. The app pairs with the
ingestion API and posts canonical transactions. Everything lands in review before
anything is posted.

**Phase 3 — Additional adapters.** Only if another backend is ever wanted. Each is
a new adapter in the service, with no app release.

**Phase 4 — Hardening.** Statement reconciliation, statistics, parser expansion
driven by the review inbox, APK update check, per-sender account mapping managed
through the ingestion API, and a relay path for capture when the phone is off.

## 18. Acceptance criteria for Phase 1 + 2

- Given an allowlisted M-Pesa credit, when the SMS arrives, then a credit entry for
  the configured Firefly account exists within 60 seconds.
- Given an allowlisted debit, when the SMS arrives, then a withdrawal entry exists
  with the parsed amount and reference.
- Given a sender not on the allowlist, when an SMS arrives, then nothing is stored
  and nothing is posted.
- Given the same SMS delivered twice, then exactly one entry exists.
- Given no connectivity, when the SMS arrives, then the entry is queued and posted
  on reconnect, exactly once.
- Given an ambiguous message, then it appears in the inbox as needs_review and is
  not posted.
- Given a `4xx` from the provider, then the entry is dead-lettered with the response
  recorded and is not retried automatically.
- Given the same canonical transaction submitted twice, then the ingestion API
  returns the original record and the provider holds exactly one entry.
- Given a provider call that times out with an unknown outcome, then the service
  queries the provider by idempotency reference before retrying, and still produces
  one entry.
- Given a Firefly III outage lasting several minutes, then queued entries drain
  afterwards in order with no gaps and no duplicates.
- Given a debit and credit from the same sender for the same amount within the
  matching window, then both post as a balanced transfer pair and neither counts as
  income or expense.
- Given an internal transfer whose destination account is unknown, then nothing is
  posted and the entry appears in the inbox.
- Given the same movement announced by two different senders, then one entry is
  posted and the second is suppressed with a link to the first.
- Given a transaction above the per-sender auto-post ceiling, then it is not posted
  automatically and appears in the inbox.
- Given a reversal message for a stored transaction, then the original is voided
  rather than a new entry created.
- Given a replayed request with a previously seen nonce, then the service rejects
  it without writing anything.
- Given the daily auto-post total for a sender is exceeded, then auto-posting for
  that sender pauses until cleared.
- Given dead-lettered entries persist beyond the alert window, then the monitoring
  stack raises an alert.
- Given an entry is ingested while the provider is unreachable, then it is stored
  and appears in the review queue, and nothing is lost when the provider returns.
- Given an entry is edited during review, then the original values and the change
  are both retrievable from the entry.
- Given the app is uninstalled and reinstalled, then the previously stored entries
  and their states are still present server-side.

## 19. Decisions taken

The questions raised during drafting are resolved as follows, and the document no
longer carries them as open items.

| Question | Decision | Why |
| --- | --- | --- |
| Which backend first | Firefly III | Already the default in `stacks/budget`, has a documented REST v2 API, and supports an external id for idempotency |
| Does the allowlist sync | No, device-local with JSON export/import in v1 | Sync adds an auth and conflict surface that buys nothing for a single-user capture tool |
| Is a server-side relay needed | Deferred to Phase 4, only if coverage gaps are measured | The phone is the capture point; a relay only helps when it is off, which is rare |
| Which senders beyond M-Pesa | The primary bank only | Parsers are data, so adding senders later is cheap; guessing formats now wastes effort |
| Ambiguous amounts | Always needs_review | A wrong direction silently corrupts a budget; a review prompt costs seconds |
| Raw message retention | 30 days, configurable | Enough to debug a bad parse, short enough to keep financial data lean |
| Where does backend knowledge live | In the ingestion API, not the app | A new bookkeeping backend becomes a server-side change with no app release, and backend credentials stay off the handset |
| Does the app keep provider accounts | No | Account names change; the app sends an `accountHint` and the service resolves it against the provider, so a renamed account is a config fix rather than a release |
| How are internal transfers represented | As a balanced pair of ledger legs, both classified `internal_transfer` | A provider-native transfer is not guaranteed, and a leg pair is representable everywhere; either leg alone never posts, so income and expense cannot be misreported |
| Is auto-posting safe with spoofable sender IDs | Only with per-sender amount and daily ceilings | Sender IDs are not authenticated, so unbounded auto-post is the weakest link; ceilings bound the damage to a reviewable inbox |
| Ingestion authentication | Bearer token plus per-request HMAC with timestamp and nonce | The endpoint writes financial records from the public internet, so a stolen token alone must not be enough to inject entries |
| Reconciliation | Periodic statement comparison, deferred to Phase 4 | Captured entries will drift; a diff report is how a systematic parse error is caught after the fact |
| Where transactions live before posting | In the ingestion service's own database, as the system of record | Storing first means nothing is lost to a crash, an outage or a lost phone, and the entry can be corrected before it becomes a financial record; review-before-posting then becomes a policy per sender rather than a separate mode |
| Is the app's queue the record | No | The app's Room queue is a delivery buffer; only the service database survives reinstall and phone change |

## 20. Repository context

- Backend stacks: `stacks/budget` (Firefly III is the default app) and
  `stacks/invoice`.
- The ingestion API is the one server-side component of this feature. It belongs in
  this repository as its own stack, following the same conventions as the others:
  bind `127.0.0.1:<allocated port>`, route through Caddy under a host such as
  `ingest.munywele.co.ke`, networks `internal` plus `dokploy-network`, json-file
  logging, resource limits and a `STACK_REVISION` marker. Register the port in
  `docs/ports.md` and add a snippet under `config/caddy/snippets/domains/`.
- Suggested name: `stacks/transactions`, engine unspecified at this point.
- It owns a dedicated `transactions` database on the shared PostgreSQL service,
  created explicitly like every other application database:

  ```bash
  docker exec postgres createdb --username "$POSTGRES_USER" --owner "$POSTGRES_USER" transactions
  ```

  Add `transactions` to the `db-backup` database list. This database is the only
  copy of the captured transactions before they are posted, so losing it loses
  data that exists nowhere else.
- It needs no Redis of its own; the five instances in `stacks/cache` are for
  application stacks, and this service is a queue consumer, not a cache user.
- The Android app itself is not stored in this repository.
- Security note for the ingestion service: it is an unauthenticated-by-default
  endpoint on the public internet that writes financial records. It must require a
  token, and the Caddy route should additionally be rate limited.
