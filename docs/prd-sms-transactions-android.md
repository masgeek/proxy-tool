# PRD — SMS Transactions Android Companion

**Status:** Draft, decisions resolved
**Owner:** —
**Last updated:** 2026-10-12

---

## 1. Summary

An Android application that turns bank and mobile-money SMS alerts into
bookkeeping entries. The user selects which senders to trust, the app parses each
message into a debit or credit, and posts it to the REST API of whichever finance
backend is running — Firefly III first, then Actual Budget, Econumo and
ezBookkeeping. The goal is that daily bookkeeping is a side effect of normal phone
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

### 7.1 Message capture

| ID | Requirement |
| --- | --- |
| F1 | Capture through a notification listener as the primary path, so the app needs no SMS permission on stock Android. |
| F2 | Fall back to an SMS broadcast receiver, used only when notification access is declined. |
| F3 | Deduplicate messages delivered through more than one path, keyed on sender ID plus message timestamp. |
| F4 | Discard any message from a non-allowlisted sender before it is parsed or stored. |
| F5 | Onboarding walks through granting notification access and explains the fallback if it is refused. |
| F6 | Ship parsers for M-Pesa and the primary bank; new parsers are added as data, not code changes. |

### 7.2 Sender allowlist

| ID | Requirement |
| --- | --- |
| F7 | Add, remove and rename a sender by its displayed sender ID. |
| F8 | Per sender, choose accepted directions: credits only, debits only, or both. |
| F9 | Per sender, choose the target account in the connected backend. |
| F10 | Per sender, choose the currency; the message never sets the currency, because a misread symbol is silent corruption. |
| F11 | A blocklist is checked before the allowlist, so a sender on both lists is always blocked. |
| F12 | The allowlist is device-local in v1, with JSON export and import as the backup and transfer mechanism. |

### 7.3 Parsing

| ID | Requirement |
| --- | --- |
| F13 | Extract amount, direction, timestamp, reference, balance-after and counterparty where present. |
| F14 | Parsers return a confidence level. Anything below the configured threshold goes to review instead of posting. |
| F15 | Store the raw message beside the parsed result while pending, and purge raw bodies after the retention period. |
| F16 | Parsing is entirely on device; only extracted fields are sent to the backend. |
| F17 | Timestamps are stored in UTC and rendered in the household time zone, so a timezone change never rewrites history. |
| F18 | Locale is not trusted for number formatting. The sender's currency and a documented thousands-separator rule drive parsing, and anything ambiguous goes to review. |

### 7.4 Posting

| ID | Requirement |
| --- | --- |
| F19 | Firefly III REST API v2 is the first target: `POST /api/v2/accounts/{id}/transactions`. |
| F20 | Actual Budget, Econumo and ezBookkeeping follow as secondary targets. |
| F21 | Map direction explicitly per backend; see section 9. |
| F22 | Apply a configurable tag or category prefix per sender, for example `sms:m-pesa`. |
| F23 | Use the parsed reference as the transaction description or note. |
| F24 | Retry transient failures with exponential backoff and jitter, capped at a total retry budget per entry, then dead-letter to needs_review. |
| F25 | A `4xx` response is never retried blindly; it becomes needs_review with the response recorded. |
| F26 | Send a stable idempotency key derived from sender, reference and timestamp. |
| F27 | Dry-run mode parses and displays without ever posting. |
| F28 | Rate-limit posting, for example 5 requests per 10 seconds, so a backlog does not trip backend limits. |
| F29 | Record the backend's returned transaction id so a posted entry can be opened and audited. |

### 7.5 Offline and recovery

| ID | Requirement |
| --- | --- |
| F30 | Queue entries in a local Room database with state pending, posting, posted, failed or needs_review. |
| F31 | A WorkManager job drains the queue on connectivity, with the backoff rules in F24. |
| F32 | Nothing is dropped; the queue survives app restart and reboot. |
| F33 | An inbox lists pending, failed and needs_review entries with retry, edit and discard. |
| F34 | A posted entry can be voided in the app, which reverses it in the backend rather than only hiding it locally. |

### 7.6 Connection and credentials

| ID | Requirement |
| --- | --- |
| F35 | Store backend URL and token in the Android keystore; never in preferences, logs or crash output. |
| F36 | Validate connectivity, TLS and token on pairing, with a distinct error for each failure. |
| F37 | Require HTTPS. Cleartext traffic is refused rather than downgraded. |
| F38 | One active backend at a time; switching backends requires re-pairing and never mixes queues. |

### 7.7 Reporting

| ID | Requirement |
| --- | --- |
| F39 | A daily notification summarising posted, failed and needs-review counts. |
| F40 | On-device statistics: entries per day, total in, total out, unposted count. All local. |

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

| Field | Firefly III | Actual Budget | Econumo | ezBookkeeping |
| --- | --- | --- | --- | --- |
| Amount | `amount`, string decimal | `amount`, negative for spend | `amount` | `amount` |
| Direction | `type`: `withdrawal` / `deposit` | sign of `amount` | transaction type | transaction type |
| Description | `description` | `notes` / `payee_name` | description | comment |
| Date | `date`, ISO 8601 | `date` | date | date |
| Tags | `tag_names` | category | categories | categories |
| Idempotency | `external_id` | external reference | reference | reference |

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

## 10. UX

1. **Pair** — backend URL and token, with a live connection test.
2. **Grant access** — notification access, with the SMS permission fallback.
3. **Allowlist** — choose senders from those observed, set direction, account and
   currency per sender.
4. **Quiet operation** — no notification unless something needs attention.
5. **Inbox** — review, edit, retry or discard anything not posted.

Deliberate absence: no dashboard-first design. The success state is an empty inbox.

## 11. Data model

Local Room entities, device-local only:

| Entity | Key fields |
| --- | --- |
| `Sender` | senderId, label, enabled directions, accountId, currency, tagPrefix |
| `Transaction` | localId, senderId, reference, amountMinor, currency, direction, occurredAtUtc, state, confidence, attempts, lastError, backendId |
| `RawMessage` | transactionId, body, receivedAt, purgeAfter |
| `Endpoint` | backendType, url, tokenRef |

Amounts are stored as minor units in an integer column. Floating point is never
used for money.

## 12. Security and privacy

- Messages are read on device; raw bodies never leave the phone, and only the
  fields needed to build a transaction are transmitted.
- No analytics SDKs, no third-party crash reporting, no network destination other
  than the configured backend.
- Tokens live in the keystore and are redacted from logs, screenshots and any
  exported diagnostics.
- Allowlist and blocklist are checked before parsing, so an unknown sender leaves
  no trace in storage.
- Raw message retention is bounded and configurable, defaulting to 30 days, and is
  enforced by a daily purge job rather than by app exit.
- Uninstall removes the database and keystore entry; the backend keeps whatever it
  already stored, which is why voiding is an explicit operation (F34).

## 13. Permissions and compliance

- Notification listener access avoids `READ_SMS` in the common case, which is the
  recommended route and the one v1 ships.
- The fallback receiver needs `RECEIVE_SMS`; sideloaded distribution avoids the
  Play permission review entirely.
- `POST_NOTIFICATIONS` for the summary and `INTERNET` for the backend call.
  Nothing else is requested.

## 14. Testing strategy

| Layer | Approach |
| --- | --- |
| Parsers | Unit tests over a committed corpus of real messages, expected outputs inline, one test per known sender format |
| Mapping | Unit tests asserting the direction and sign per backend |
| API client | Contract tests against a local Firefly III instance, including a `4xx` and a timeout path |
| Queue | State-machine tests covering retry, dead-letter and manual retry |
| End to end | Instrumented test: inject a message, assert one entry posted and no duplicate on replay |

The parser corpus is the highest-value asset here; it is reviewed with every new
sender format that produces a needs_review entry.

## 15. Success metrics

| Metric | Target |
| --- | --- |
| Parse success rate on allowlisted senders | above 95% |
| Entries needing review | below 2% |
| Duplicate posts | zero, verified by idempotency key |
| Median delay from SMS to posted entry | under 60 seconds |
| Parser corpus growth | no growth without a named failing case |

## 16. Delivery plan

**Phase 1 — Capture and parse.** Notification listener, fallback receiver,
allowlist, M-Pesa and bank parsers, local inbox, dry-run mode, no posting.

**Phase 2 — Firefly III.** Pairing, account mapping, posting with idempotency,
retry budget, background worker, void.

**Phase 3 — Additional backends.** Actual Budget, Econumo, ezBookkeeping.

**Phase 4 — Hardening.** Statistics, parser expansion driven by review inbox, APK
update check, and a server-side relay only if measured coverage gaps justify one.

## 17. Acceptance criteria for Phase 1 + 2

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
- Given a `4xx` from the backend, then the entry is dead-lettered with the response
  recorded and is not retried automatically.

## 18. Decisions taken

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

## 19. Repository context

- Backend stacks: `stacks/budget` (Firefly III is the default app) and
  `stacks/invoice`.
- This app is an external client of those stacks' REST APIs and adds no service to
  the server. Only the optional Phase 4 relay would be a server-side addition.
- The app lives outside this repository until Phase 2, when the Firefly contract
  tests need the real stack to run against.
