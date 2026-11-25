# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 0.3.x | Yes |
| 0.2.x | No |
| 0.1.x | No |

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use the repository's
private security advisory form, or contact the maintainers through the address
listed on the repository profile. Include the affected component (daemon, app,
DSH plugin or firmware), a minimal reproduction and the impact.

## Threat model

AgentRing is a local-first tool, not an internet service.

- The daemon binds `0.0.0.0:7801` for HTTP and `0.0.0.0:7802` for the raw frame
  stream. Only `/frame`, `/health` and the read-only 7802 stream are reachable
  from other hosts; the preview, `/state`, `/config`, `/sources`, `/preview`
  mutations and all write endpoints are loopback-only. There is no
  authentication and no TLS.
- `/sources` exposes local install paths and profile/bundle names to loopback
  clients. `/sources/<id>/install` runs only AgentRing's own hook installers
  (`scripts/install-*-hooks.mjs`); it never runs an arbitrary command from a
  probe. It edits `~/.codex/hooks.json` or `~/.claude/settings.json` as the
  current user and writes a timestamped backup next to the file.
- `POST /preview` / `DELETE /preview` temporarily override what the ring shows.
  Any local process can call them, and the override expires after its TTL at the
  latest.
- Do not expose port `7801` to the public internet or to an untrusted network.
  If you need remote access, put it behind a VPN/reverse proxy with
  authentication and TLS.
- The firmware provisioning AP is open by default and only exists while the
  device has no working Wi-Fi configuration. Set `AP_PASSWORD` in
  `firmware/esp32/agentring_ring/config.h` if you want a protected setup AP.
- Wi-Fi credentials are stored in the ESP32 NVS in plaintext, as is normal for
  Arduino/ESP-IDF provisioning. Anyone with physical access to the board can
  read or replace them.
- The DSH plugin only sends lifecycle metadata (source, session id, cwd, tool
  name and state) to `127.0.0.1`. It does not send prompts, file contents or
  model output.
