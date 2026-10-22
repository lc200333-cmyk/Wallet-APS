# Implemented architecture

Audited 2026-10-14. The working tree is mixed: local HEAD `0465b68` (0.5.3),
cached `origin/master` `09ff78e` (0.7.1), with substantial pre-existing local edits.
Remote state was not refreshed. This map describes the actual working sources;
see [audit](ai-readiness-report.md) for discrepancies.

Wallet APS is a Flutter desktop/mobile application for Windows, Android and
Linux. Vault storage is local SQLite `.swl`, compatible with SPB Wallet.
There are no iOS/web runners in this repository. The app checks GitHub release
metadata for updates; offline storage does not imply absence of all networking.

| Component | Responsibility and dependencies |
| --- | --- |
| `app/lib/main.dart` | Entry point, models, application state, dialogs, import/export, icons, responsive UI and update handling; imports repository, services, helpers and widgets |
| `data/spb_wallet_repository.dart` | Re-export of the existing database implementation, not an independent repository abstraction |
| `spb_wallet/spb_wallet_database.dart` | SQLite schema, reading/writing cards/templates/categories, backup, undo snapshots and legacy state; uses codecs and integrity service |
| `spb_wallet/spb_wallet_crypto.dart` | SPB-compatible UTF-16 text and raw payload encryption using PointyCastle AES-ECB and a SHA-1-derived key |
| `spb_wallet/spb_wallet_attachment_codec.dart` | Length-prefixed zlib attachment payloads over the crypto codec |
| `data/legacy_swl/legacy_swl_codec.dart` | Legacy ID/color/icon conversion; uses image decoding |
| `services/wallet_integrity_service.dart` | Inspection and transactional repair of legacy relationships and storage classes |
| `services/wallet_rekey_service.dart` | Transactional re-encryption of known text/payload columns, preserving other tables |
| `controllers`, `features`, `domain` | Entity indexing, category paths, ordering, field visibility and persisted card layout |
| `widgets` | Card surface, screen scaling and workspace geometry |
| `services/platform`, native runners | Clipboard, platform lifecycle and native integration; Android media/privacy and file handling |
| `app/assets` | Icon libraries, branding and base wallet used for vault creation |
| `tools`, `docker`, `.github/workflows` | Packaging, version bump, build environments and release automation |

Typical path: UI action → database API → SQLite/legacy codecs → local file.
Rekey and repair open transactions and roll back on exceptions. Backup uses the
SQLite backup API and validates the resulting database. Layout metadata lives
in `actitpass_State`; compatibility also requires SPB tables, triggers, TEXT IDs,
integer colors and ICO representations to survive round trips.

Most behavior remains coupled to `main.dart` (over 21,000 lines) and a large
database implementation. Do not interpret helper directories as complete layer
separation. Existing widget tests often import the entire entry point.

`plans/01_stack_and_architecture.md` proposes Rust, FFI, Argon2 and authenticated
encryption. These are not the live Dart storage implementation. `core/` exists
in local HEAD but is deleted in the working tree and absent from cached 0.7.1.
Cloud synchronization described by plans is not an implemented app subsystem.

Critical compatibility boundaries: encryption/encoding, unknown legacy metadata,
atomic file replacement, rekey rollback, import/export, icon IDs, Android app ID
`com.example.actit_pass_storage`, native clipboard and desktop/mobile layout.
Changing cryptography requires a separately approved migration design; the legacy
codec is not an authenticated modern vault format.
