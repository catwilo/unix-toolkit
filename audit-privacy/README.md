# audit-privacy

Privacy audit tool for shell/config projects. Scans for credentials, private IPs, and MAC addresses before publishing to GitHub.

## Compatible
Termux (no-root), Debian, Raspbian, macOS — no external dependencies.

## Usage

    # Audit all projects under scripts/
    ./audit-privacy.sh

    # Audit specific dirs
    ./audit-privacy.sh ../noemap ../clipso

## Output
- [OK]   clean, safe to publish
- [WARN] public IP or MAC, review manually
- [ERR]  credential or private IP, fix before publish

## Detection
| Pattern | Severity |
|---|---|
| password, token, secret, api_key... | ERR |
| RFC1918 private IPs (10.x, 192.168.x, 172.16-31.x) | ERR |
| MAC addresses | WARN |
| Public IPs (except known-safe: 1.1.1.1, 8.8.8.8...) | WARN |

## Safe IPs (skipped)
1.1.1.1  1.0.0.1  8.8.8.8  8.8.4.4  9.9.9.9

## Exit codes
- 0 = all clean
- 1 = hits found
