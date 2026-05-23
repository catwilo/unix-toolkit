# rwxdir-scan

Finds paths on the filesystem that carry full read-write-execute permissions — the kind of loose permissions that are easy to create by accident and can become a security risk. Useful for auditing a system and finding what to tighten up.

Targets Debian and non-root Termux on Android. Output is formatted like `ls -la` (symbolic permissions, owner, group, size), and results are copied to the clipboard by default.

## Usage

```sh
./rwxdir-scan                    # scan (clipboard copy on by default)
./rwxdir-scan --scan-directories # directories only
./rwxdir-scan --scan-files       # files only
./rwxdir-scan --scan-all         # both
./rwxdir-scan --real-write-test  # verify writability with a real test
./rwxdir-scan --no-clipboard     # don't copy results to clipboard
./rwxdir-scan --verbose          # detailed output
```

Paths with spaces, quotes, or special characters are handled safely.
