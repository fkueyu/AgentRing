## What changed

<!-- One or two sentences. Link the issue if there is one. -->

## Why

<!-- The problem this solves, and any tradeoff you chose. -->

## Verification

- [ ] `npm test` (daemon + DSH plugin tests)
- [ ] `swift build -c release --package-path macos`
- [ ] Firmware compiles with the documented FQBN (if firmware changed)
- [ ] Manual app pass through 预览 / 灯光 / 来源 / 通用
- [ ] `/health` shows `version` and `streamFrames` increasing when hardware is connected
- [ ] `npm run version:check` (if `VERSION` changed)
- [ ] Docs/CHANGELOG updated for user-visible changes

## Notes

<!-- Screenshots, serial logs, config snippets. Redact Wi-Fi credentials. -->
