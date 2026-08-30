# Changelog

## 0.9.1 — 2026-08-30

First public beta.

### Highlights

- Native macOS side rail for Codex, Claude, Grok, and Cursor Grok Bot usage.
- Dock-style magnification with adjustable rail, icon, idle, and hover scales.
- Fixed rail sensor window plus separate hover-label and click-card overlay window.
- Always-visible mode and per-provider visibility controls.
- Read-only local credential reuse; no telemetry or QuotaRail server.
- Cursor Grok Bot weekly usage is the primary Cursor metric; monthly usage is secondary.

### Reliability and data honesty

- Provider refreshes run independently so one slow service does not block all values.
- Cursor split-pool percentages are never averaged into a fabricated monthly total.
- Cursor monthly usage and Grok Bot usage can succeed independently.
- Grok gRPC-Web responses require a real success trailer.
- Stale Codex local rate-limit snapshots fail closed.

### Distribution notes

- Requires macOS 13 or later.
- The release app is ad-hoc signed and not notarized. macOS may require right-click → Open.
- Provider endpoints and local schemas are unofficial integration surfaces and may change.
