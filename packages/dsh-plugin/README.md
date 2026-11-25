# AgentRing DSH plugin

A DeepSeek Harness Host plugin that reports agent lifecycle, tool calls,
approvals and user questions to the local AgentRing daemon.

```sh
dsh plugin --profile desktop add "$PWD/packages/dsh-plugin"
```

The profile stores a link to this checkout. Host plugins have no HMR: restart
DSH or toggle the bundle off/on in Plugins after editing `index.js`.

The event mapping and reconciliation behavior are documented in
[`docs/DETAIL.md`](docs/DETAIL.md). The daemon must listen on
`127.0.0.1:7801` (override with `AGENTRING_PORT` in the Harness process).
