# sftp-folder

Shares a local folder over SFTP with a single command, with atomic locking to prevent conflicting sessions. Handy for quick, secure file access between machines — including a phone over Termux — without setting up a permanent server.

Runs on Debian and non-root Termux, with health checks and platform detection built in.

## Usage

```sh
./sftp-folder.sh -d ~/share        # share a directory
./sftp-folder.sh -d ~/share -p 2222 # on a specific port
./sftp-folder.sh -R                # restart
./sftp-folder.sh -RF               # force restart (kill + start)
./sftp-folder.sh --status          # show status
./sftp-folder.sh --stop            # stop the server
```
