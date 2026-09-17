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
- **Resolution:** switches the display it streams to the resolution the client asks
  for, leaving any other display on the workstation alone.
- **Lock on disconnect:** locks the workstation after the last stream ends. The default delay is 30 seconds.
- **Clipboard text:** plain text both ways, 60 KB per copy, `clipboard_text` in `host.conf`.
  Text only is a deliberate choice: files and images are never carried.
- **Two screens:** composites two workstation displays into one picture and arranges
  them side by side for the session, restoring the previous arrangement afterwards.

## Display layouts

The client asks for a layout and the host either serves it or refuses it.

| Layout | Windows host behaviour |
| --- | --- |
| `physical` | Streams the displays as they are. No mode change, always available. |
| `single` | Switches the streamed display to the requested mode. Other displays are untouched. |
| `dual-horizontal` | Places two workstation displays side by side at the requested modes. |

Virtual displays belonging to other remote-desktop software are ignored when the host
counts its displays: their adapters are matched by name (`Indirect`, `Teradici`,
`Remote`, `DCV`, `Virtual`, `IDD`). The host logs every display with its adapter, its
mode, its position and whether it counted, because a refused layout is otherwise
indistinguishable from a missing display emulator on a machine no shell can reach.

A refused layout no longer fails the connection: the client retries once with the
host's own layout and says so on the stream toolbar. Two screens are not retried,
because one host screen spread across two monitors is not what was asked for.

Two screens need HEVC. H.264 cannot carry a picture wider than 4096 pixels.

## Building

The host is built with MinGW and UCRT64, the client with Visual Studio and Qt 6.10.
Both link the shared Rust QUIC transport, and its ABI must match on both ends;
the current protocol is 13.

The version number is set in two separate places, one per component. Note that nmake
does not notice when the client's version string changes, so the compiled
system-properties object has to be deleted before a version-only rebuild, or the
client reports the previous version and looks like a failed deployment.

## Packaging and signing

WiX 5 builds one MSI per component from `packaging/host/windows` and
`packaging/client/windows`.

`scripts/package/build-windows-msi.ps1` builds the MSIs; it skips a component whose
payload argument is empty. `scripts/package/sign-windows-release.ps1` signs the
programs, builds the MSIs, then signs and timestamps those. Pass `-ClientOnly` or
`-HostOnly` to ship one component without reissuing the other, so no MSI is ever
published carrying a version its binary does not have.

Signing must run in an interactive session of the account holding the certificate:
Windows only unlocks the private key there, so signing over a remote shell fails.

Packaging lessons worth keeping: every `File` element needs a `Name`, or the installed
file is named after the build path; a firewall exception belongs to the component, not
inside a `File`; advertised shortcuts produce a blank icon, so use plain shortcuts with
a real `.ico`; and the host's data directory must survive uninstall, because it holds
the certificate and host ID that keep clients paired.

## What is not done yet

- **Pen pressure on Windows clients.** Pen capture in the client is libinput-only, so
  a Windows client sends pen input as mouse movement. Windows capture through the
  SDL pen events is the next step; the host's own pen injection additionally needs a
  virtual HID runtime that is not currently shipped.
- **Single sign-on.** A session asks for DUO twice, once for PLANK and once for Windows.
- **Support sessions.** Watching or assisting another user's session is designed, not built.
