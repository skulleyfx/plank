# PLANK on Windows

This branch adds a Windows host and Windows support in the client. It is maintained
by SkulleyFX, on top of instinctual/plank.

| Path | Repository | Branch |
| --- | --- | --- |
| `apps/host/windows` | [skulleyfx/plank-host-windows](https://github.com/skulleyfx/plank-host-windows) | `main` |
| `apps/client` | [skulleyfx/plank-client](https://github.com/skulleyfx/plank-client) | `windows` |

The other submodules still point at the instinctual repositories.

The Windows host started from `plank-host-linux`. The Windows sign-in, service and
display code is different enough to live in its own repository. The Windows client
changes are meant to go back to `plank-client` so every platform uses one client.

## Windows host features

- **Service:** runs on the physical console as a Windows service.
- **Sign-in:** a Windows account, followed by an optional DUO push (Auth API).
- **Login screen:** streams the Windows login screen when nobody is signed in.
- **Reconnects:** single-use resume tickets let a reconnect skip a repeat second factor.
- **Resolution:** switches the display to the resolution the client asks for.
- **Lock on disconnect:** locks the workstation after the last stream ends. The default delay is 30 seconds.
