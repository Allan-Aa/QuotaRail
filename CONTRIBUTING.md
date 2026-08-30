# Contributing

1. Keep provider integrations read-only and fail closed when their schema or login state is unavailable.
2. Run `./test.sh` and `./build-app.sh` before proposing a change. Run `./visual-check.sh` for rail, overlay, size, or motion changes.
3. Do not add or use macOS system-pointer injection for routine QA. Prefer app-internal preview states and read-only window metadata.
4. Do not add credentials, cookies, Keychain exports, local databases, generated `dist/` apps, or `.build/` output to Git.
5. Update the README and third-party notices when changing the release bundle or attribution.
