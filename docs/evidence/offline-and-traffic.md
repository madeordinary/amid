# Local offline and traffic observations

Observed 2026-10-02 on arm64 macOS 27.0.1. The app has no account, update endpoint, analytics or network client dependency. Source absence alone does not establish measured traffic behavior.

## Network-denied collector process

The release probe ran under a process-scoped sandbox profile:

```sh
/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' .build/release/amid-probe
```

It exited 0. `offline-probe.json` reports available collection with 729 observed processes, 208 inaccessible, 354 app groups, 10 projects and 23 listeners; its own process was observed. The summary excludes identifying metadata. No machine network setting was changed. This verifies the collector can run without network operations; it does not prove every GUI flow under a network denial or establish cross-OS support for this test utility.

## Owned GUI network observation

For the owned performance app PID 41875, `nettop -n -P -p 41875 -L 7 -s 10 -J bytes_in,bytes_out -x` exited 0. The app was checked alive before/during the observation. `network-observation.csv` contains seven column headers and no process socket rows. No DNS resolution, endpoint details or payload capture was requested.

No socket rows were observed in this roughly one-minute window. This is a bounded observation, not proof that every future runtime path sends zero bytes. The window predates the latest package. Reference idle/background traffic and longer production-use observations remain release checks.
