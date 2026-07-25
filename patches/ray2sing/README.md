# ray2sing patches

Applied at build time against the commit pinned by `hiddify-core` (see `docs/REALITY_RAY2SING.md`).

| Patch | Purpose |
|-------|---------|
| `0001-reenable-xray-reality-mapping.patch` | Re-enable Xray conversion (`useXrayWhenPossible` / `&core=xray`); default empty Reality/TLS `fp` to `chrome` |

Do not merge upstream Hiddify **app** commits here — only patch the core dependency when building the AAR.
