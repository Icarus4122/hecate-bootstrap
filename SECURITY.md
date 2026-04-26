# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Hecate, please report it
responsibly:

1. **Do not** open a public GitHub issue.
2. Open a [private security advisory](https://github.com/Icarus4122/hecate-bootstrap/security/advisories/new)
   on this repository.
3. Alternatively, contact the maintainer directly via the email listed in the
   Git commit history.

Please include:

- A description of the vulnerability and its potential impact.
- Steps to reproduce or a proof of concept.
- Your operating system and Docker version.

You should receive an acknowledgment within **72 hours**. A fix or mitigation
will be prioritized based on severity.

## Scope

Hecate is an operator workstation bootstrap - it provisions hosts, builds
Docker images, and manages tooling.  Vulnerabilities of interest include:

- Privilege escalation via `labctl` or bootstrap scripts
- Path traversal or escape in workspace scaffolding
- Credential leakage in logs, images, or compose files
- Supply-chain issues in binary sync or image build

## Binary sync supply-chain controls

`scripts/sync-binaries.sh` pins external binaries via `manifests/binaries.tsv`
(8-column TSV with a `sha256` field).  After download, real digests are
verified with `sha256sum`; mismatches delete the temp file, refuse to promote
the destination, and exit non-zero.

The transitional `TODO_SHA256` sentinel is accepted in default/dev mode (with
a `[WARN]` line) but **must** be refused for release-grade sync.  Run with
`STRICT_CHECKSUMS=1` (or `--strict-checksums`) when validating a release - any
unpinned row will fail before download.

Checksums reduce, but do not eliminate, supply-chain risk: a compromised
upstream release could publish both the artifact and a matching digest.  Pair
checksum verification with pinned release tags, infrequent rotation, and
out-of-band review of new binaries before pinning their digests.
