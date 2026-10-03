# House rules for written text

The rules `/polish` and `$polish` apply. They are for prose that other people
have to act on: memory bank entries, PR descriptions, READMEs, release notes,
handoffs, decision records, commit bodies.

They are not a style preference. Each one exists because the unpolished version
costs the reader time or hides a fact.

Edit the file after you install it. These are the starting opinions, not a law.

## The rules

1. **Use the ordinary word.** `use`, not `utilize`. `start`, not `commence`.
   `so`, not `accordingly`. If a shorter word means the same thing, it wins.

2. **Name the thing.** Replace a category noun with the actual file, command,
   service, or person. "the component" becomes `src/queue/worker.ts`. "the
   team" becomes "billing".

3. **One idea per sentence.** A sentence carrying two claims joined by "and"
   or a semicolon is two sentences that have not been separated yet.

4. **Point at evidence instead of describing it.** `tests/smoke-install.sh`
   and a line number beat a paragraph about what the test covers. A commit SHA
   beats "recent work".

5. **Numbers instead of adjectives.** "12 of 40 endpoints", not "most
   endpoints". "adds 900 ms", not "noticeably slower". If you do not have the
   number, say you do not have it.

6. **Cut filler.** "It is worth noting that", "in order to", "at this point in
   time", "we may want to consider", "as you can see". Delete the phrase and
   read the sentence again; it usually improved.

7. **Claim first, qualification after.** "The installer refuses without Serel
   Memory, because the verify pack writes into the bank." Not the reverse.

8. **Active voice with a named actor.** "The installer refuses", not
   "installation will be refused".

9. **No throat-clearing opener.** Delete the warm-up sentence and start with
   the first sentence that carries information.

10. **No meta commentary.** "This section explains", "as mentioned above",
    "let's dive in". The reader is already here.

11. **Do not restate another file.** If `techContext.md` already lists the
    stack, link to it. Two copies of a fact means one of them will go stale
    and you will not know which.

12. **Cut the AI tells.** Common ones: *delve*, *leverage* as a verb,
    *seamless*, *robust*, *unlock*, *landscape*, *journey*, *comprehensive*,
    *it's not just X, it's Y*, rule-of-three lists that rise in emphasis,
    and a closing paragraph that summarizes what you just read. Replace with
    the plain claim, or delete.

13. **Do not add.** Polish removes and rewrites. It never introduces a claim,
    a number, a name, or a certainty the source did not have.

14. **Keep every qualification.** "on macOS only", "when the cache is warm",
    "we think". Dropping one is not a shorter sentence, it is a different and
    wrong sentence.

15. **Match the register of the file you are in.** A decision record is not a
    changelog is not a README. Do not make one sound like another.

16. **Leave it alone when editing would cost something.** Quoted speech,
    literal commands and paths, error strings, API names, licence and legal
    text, the exact wording of a decision, and any sentence whose shorter
    version loses a fact. "No change" is a valid result for a whole file.

## What a good rewrite looks like

Before:

```text
It is worth noting that we have leveraged a comprehensive caching solution in
order to significantly improve the performance characteristics of the service,
and the initial results have been quite promising. For what it's worth the
team went with Redis, on the account lookup, and in the staging environment
p95 on the /accounts endpoint has come down from 420ms to 90ms, at least as
of the measurements that were taken on 4 March 2026 on the perf/redis-cache
branch, though we haven't yet had a chance to look at production numbers.
```

After:

```text
Redis caches the account lookup. p95 on `/accounts` fell from 420 ms to 90 ms
in staging (4 March 2026, `perf/redis-cache`). Not yet measured in production.
```

Shorter, but that is a side effect. The rewrite is better because it leads with
the cache, gives the numbers, cites where they came from, and keeps the
admission that production is unmeasured.

Every fact in the rewrite was already in the original — the cache, the endpoint,
both numbers, the environment, the date, the branch, the missing production
measurement. That is the test. If a fact only appears in the "after", the
rewrite invented it, and rule 13 says it is not a rewrite any more.
