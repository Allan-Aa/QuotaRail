# Security policy

## Reporting a vulnerability

Please do not open a public issue for a vulnerability involving credentials, local usage data, or provider sessions. Contact the maintainer privately with:

- affected QuotaRail version and macOS version;
- the minimum reproducible steps;
- whether a real credential, local database, or provider response is involved; and
- redacted logs only.

Do not include tokens, cookies, SQLite databases, Keychain exports, or provider account data in reports.

## Security boundaries

QuotaRail is a local read-only utility. Its integrations rely on local login state and provider endpoints that may change. A provider value is unavailable when its source cannot be verified; it must not be inferred from unrelated account data.
