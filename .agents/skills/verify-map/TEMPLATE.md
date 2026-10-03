<!--
Verification map template. One file per feature, written to
<effective bank>/verification/<feature>.md.

A feature is something a person can do, named the way they would name it:
"reset a forgotten password", not "AuthController".

Replace every <angle-bracket> placeholder. Keep the two top-level sections and
their names: Recipe is how to see it work, Records is what someone saw. Delete
these comments in the finished file.
-->

# <Feature name>

<One sentence, in a user's words, for what they can do. No implementation.>

- Status: <verified | unverified | broken>
- Owner: <person or team, or "unowned">

## Recipe

<!--
How to see this feature work with your own eyes. Someone who has never opened
this repo should be able to follow it. Real commands, real URLs, real inputs.
-->

### Launch

```text
<the exact commands to get the thing running, in order>
```

<What the commands cannot say: required env vars, a seeded account, a service
that must be up, roughly how long startup takes.>

### Drive

1. <first action, with the exact input to use>
2. <second action>
3. <keep going until the feature has actually been exercised>

### Observe

- <what proves it worked, in the words that appear on screen or in the log>
- <the check most likely to catch a regression here>

### Clean up

```text
<commands to stop it and undo any state the run created>
```

<Write "nothing to clean up" when that is true. Say it explicitly — a blank
here reads as forgotten.>

## Records

<!--
One entry per run, newest first. A record says what someone saw, not what the
code should do. No record means unverified. That is information, not a failure.
-->

### <YYYY-MM-DD> — <who ran it>

- Revision: <commit SHA or tag the run was against>
- Paths: <the files this feature lives in, so a diff here means re-verify>
- Environment: <OS, runtime version, browser or device, and any config that
  mattered>
- Observation: <what actually appeared. Quote it. "Order #1042 confirmed"
  beats "it worked".>
- Artifact: <path or link to a screenshot, recording, or log excerpt, or
  "none">

<!--
Older runs repeat that heading and those five fields, in date order, newest
first. Leave them in place. They are the history of what this feature has
actually done, and the reason "it worked last month" is checkable.
-->
