# Synthetic month-history native observation

Observed approximately October 3, 2026, 21:27–21:32 CDT (October 4 UTC), on the frozen Counters candidate. Runtime revision: `8432b3a15b7cee4a266a053a2f6fe3049fbcdda8`; executable SHA256: `52d1e49ca7cb1f03903b68f797decd5b1ec60f779a31b2ccd9f30dee0e9b3e6c`. All 103 frozen inputs and the executable remained unchanged; [candidate manifest](interface-counter-candidate-source.json).

## Fixture and verification boundary

One existing release generator case passed, exit 0, in 2.470 seconds. This was not a full-suite rerun. The fixture contains 76 synthetic entities, 1,440 minute buckets and 696 older hourly buckets: 162,336 declared records, 95,794,824 encrypted bytes. It stayed within the unchanged importer limits of 165,000 records and 128 MiB.

Fixture manifest SHA256: `34b6bee6d48ac349af7d534b393298b5c09ec4f13ce43a81510f85127ff45d00`. Generator test executable SHA256: `9bbec6cb5cfa36335d7a0362ea1770bf88f538b44f0a4f72401f635487b021b6`. The verification app imported into disposable encrypted storage with an ephemeral key; no normal-store or Keychain persistence was tested.

## Native observations

- History's picker included the synthetic applications and workspaces. Application 65 at thirty days showed 2,134 buckets, 5% CPU average/maximum, 66 MB memory average/maximum, 100% metric coverage, five-second fixture cadence, zero recorded gaps and physical-footprint labeling. Returning from Settings preserved its name/range; a later capture showed 2,133 buckets.
- The one-hour range showed 57 application buckets; returning to thirty days showed 2,133. Workspace 1 showed 2,132 buckets, 6% CPU, 67 MB memory and the same coverage/cadence/method disclosures, with September weekly chart labels.
- In disposable Settings, reducing retention from thirty days to twenty-four hours changed displayed encrypted storage from 91.2 MB to 61.1 MB. History retained Workspace 1 and the selected thirty-day view, but showed 1,436 buckets and a chart contracted to the last day. No storage error appeared.
- CUA Command-Q completed; the retained direct child and parent exited 0 without launcher signal.

Counts changed at maintenance/clock boundaries; these are captured observations, not a fixed-count before/after experiment. The initial empty System history resolved after Raise and selecting thirty days, but its cause is unproven. Spinner appearance and responsiveness while queries were pending were not observed; completed navigation is not an input-to-render latency measurement.

This synthetic month is not thirty elapsed real days, a soak, forensic deletion proof, sustained CPU/RSS or rendering-budget acceptance. No benchmark/profiler or new runtime change accompanied the check. Screenshots were inspected inline only and not retained. Private identities, paths, seed location and raw logs are omitted. All settings changes were confined to disposable verification storage.
