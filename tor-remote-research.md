---
name: tor-remote-research
description: Use this skill whenever you (a small local model) need to consult a powerful remote AI model through the anonymizing zkAPI Tor CLI — to get web-scale knowledge, current facts, explanations, or multi-turn research that you cannot answer yourself. The remote model is a paid, observable tool: everything you send it may reveal something about the user you speak for, so every request must be composed, scrubbed, and scoped according to the privacy rules in this file.
---

# Tor Remote Research (zkapi-tor-cli)

You are a small local model. When you lack knowledge, you delegate to a large
remote model by calling:

    ~/zkapi/zkapi-tor-cli.sh <command> ...

The call travels over Tor to a commercial inference provider. Two consequences
define everything else in this file:

1. **What you send is observable.** The remote provider sees your exact
   prompt text, and the network sees timing and volume. The prompt is the
   primary leak: a user's identity is often reconstructable from a single
   sentence that was never scrubbed.
2. **It is slow and metered.** Budgets are per request; expect real latency
   (see "Timing" below). Treat each call as deliberate, not casual.

The core discipline, stated once: **retrieve general rules and raw data from the
remote model; apply them locally, where nothing is observed.**

## Hard privacy rules (non-negotiable)

- **NEVER relay user-private content.** No names, places, employers,
  dates, titles, project names, file paths, amounts, health/legal/relationship
  details, or unusual circumstances. If the user says "my landlord in Lyon is
  withholding the deposit", the remote model may hear "what remedies exist for
  a withheld rental deposit under a fixed-term lease" — nothing more.
- **NEVER forward the user's words.** Do not even paraphrase sentence-for-
  sentence; the user's phrasing, vocabulary, and grammar are a fingerprint.
  Write every prompt yourself, in plain generic technical language, asking
  for the *information* you need, not echoing the *conversation* you are in.
- **Decompose.** If you need facts A, B, and C, and each is innocuous on its
  own, ask them as separate single requests. A request carrying "A and B and
  C together" links all three under one observable identity. Separate
  requests are separate identities (see cost/latency tradeoff below).
- **Generalize conditionals.** Don't describe your situation to get a verdict
  for it. Instead of "what should I do, given C = X?", ask "what matters when
  C varies — e.g. for values like X, Y, Z?" Retrieve the *decision rule*, then
  apply X yourself, locally, where nothing is observed.
- **Prefer generic framing over specific lookups.** "Recent developments in
  topic T" leaks less than "the March 14 announcement by company U about
  product P" — unless the specificity IS the question.
- **Generalize quantities, not just nouns.** A precise number plus a category
  can identify a person even with no name in it. Use bands, orders of magnitude
  and comparisons rather than exact figures: "an income in the middle band of
  the bracket", "roughly double the area median", "a commute in the 20–40
  minute range", "an order of magnitude below the rated limit".
- **The place can be the identifier.** A well-known city is unremarkable; a rare
  place combined with one niche attribute (a single employer, one specialty
  school, one hospital, one museum, an airport with two flights a day) is close
  to a name. Prefer the *class* of place ("a mid-sized university town with one
  dominant employer", "a coastal city with a seasonal economy") or the mechanism
  ("how do short-term-rental rules bite when…"). If you need the place itself,
  send it alone, with nothing else about the user attached — or ask about a set
  of comparable candidates so no single one is the subject.
- **Logs, versions and error strings are fingerprints.** Never paste internal
  hostnames, tenant/account IDs, internal or `.local`/staging URLs, config
  excerpts containing project names, literal stack traces, or an unusual
  library-version combination that only one company runs. Ask about the error
  *class* and the general failure mode instead of the exact message plus your
  stack. This is where technical work leaks most, and it feels like good
  engineering practice, which is why it must be a hard rule.
- **For security and incident questions**, ask about the vulnerability class,
  the standard mitigations, and how to test locally — not about the live
  environment, its vendor, or an incident in flight. Urgency is exactly when to
  prefer the class-level question: it usually solves the case anyway, and a
  rushed specific prompt is the one that gets away.
- **Never send a document.** A contract, invoice, log, report, codebase excerpt
  or config file is the most identifying thing available. Extract what you need
  locally, then ask a *reference* question about the clause type, the charge
  type, the failure mode. The artifact never travels; only the abstract question
  does.
- **Self-check before firing:** re-read your prompt and ask "if the provider
  logged this sentence and someone tried to profile *who asked it*, what
  would they learn beyond the topic itself?" If the answer is anything about
  the user, scrub it.

## Commands

    ~/zkapi/zkapi-tor-cli.sh make_single_request "<prompt>"   # fresh identity, one Q&A
    ~/zkapi/zkapi-tor-cli.sh start_conversation "<prompt>"    # fresh identity, opens a session
    ~/zkapi/zkapi-tor-cli.sh ask "<follow-up>"                # continue that session
    ~/zkapi/zkapi-tor-cli.sh list_models                      # models with reviewed budgets
    ~/zkapi/zkapi-tor-cli.sh set_model [id]                   # choose model (bare = show current)

- The assistant's reply goes to **stdout**; progress/waiting lines go to
  **stderr**. Capture them separately if you parse output.
- The tool is stateful between calls (server pid, chosen model, conversation
  history in /tmp/zkapi-tor-cli.<uid>/), and stateless inside any one call.

### Single request vs conversation: the privacy/cost decision

`make_single_request` tears down and rebuilds the whole anonymity stack:
**a brand-new network identity for every call**. `ask` adds to the running
conversation on the same identity — the provider *can link* everything in
one conversation (documented and intended). Choose accordingly:

- Unrelated questions → separate `make_single_request` calls (unlinked).
- Questions whose *relationship is itself a clue* (B only makes sense given
  A), or genuine multi-turn work → one conversation, pay bootstrap once.
- When a conversation would leak a pattern, prefer scrubbing each question
  into independence and using single requests instead.

### One at a time — the CLI is a singleton

`make_single_request` and `start_conversation` **kill the running daemon and
start a new one**. Two invocations in parallel therefore destroy each other's
server and fight over the single wallet/companion and the single settlement
queue. Never background two calls at once, and never parallelize a batch to
save wall-clock time. A batch is strictly sequential.

## Model selection: verify, do not trust

`set_model` **does not validate anything** — it writes an id to a file and
prints `model set: <id>` for any string at all. A wrong id looks like success
until the request fails, several minutes and one budget unit later.

- **The only authority is the live list**, from `list_models` or from the
  `available models:` block the CLI prints after a `model_budget_unavailable`
  failure. A repo-checked `models.json`, a README example, or an id from a
  previous session may all be absent from the live reviewed policy.
- **The built-in default model can be stale.** If the very first call fails
  with `model_budget_unavailable`, that is the expected cause: adopt an id from
  the printed live list.
- **An id can be present in the live list and still be provider-rejected**
  (`upstream_error: The inference provider rejected the request.`). Observed: an
  entry whose id carried a leading `~` (an alias/display decoration) was in the
  live list and every request to it was refused, while ordinary unadorned ids
  from the same list worked. Smoke-test anything that looks aliased.
- **Smoke-test before committing a batch.** One cheap call costs minutes but
  protects every call after it:

      ~/zkapi/zkapi-tor-cli.sh make_single_request "Reply with exactly: SMOKE OK"

  If you get `SMOKE OK`, the model id, circuit, daemon, wallet and reviewed
  policy are all healthy — and any later failure is then known to be transient,
  not systemic.

## Running it: never block on the call

Long calls run as background processes and you poll:

    nohup ~/zkapi/zkapi-tor-cli.sh make_single_request "<prompt>" \
      > /tmp/zr.out 2>/tmp/zr.err &
    zr_pid=$!
    # ... do other work; then check on it:
    wait "$zr_pid" 2>/dev/null
    cat /tmp/zr.out        # empty + nonempty /tmp/zr.err => failure, read it

Rules of thumb:
- `make_single_request` / `start_conversation`: always background them.
  First call after a break: allow up to ~3–4 minutes.
- `ask`: usually seconds-to-a-minute; synchronous is acceptable.
- If output is empty but the process died, stderr holds the reason
  (daemon error JSON, wait messages, or the model list).

### Validate output, not exit code

**Empty stdout with exit code 0 is a real failure mode** (observed: the model
returned an empty completion). Success is defined as: process exited 0 **and**
stdout is non-empty **and** stderr contains no error JSON. Do not treat a
non-empty stderr as failure either — bootstrap notices are always printed
there on successful runs. Grep for the specific error tokens in the playbook,
never for "is stderr non-empty".

    if [ "$rc" -eq 0 ] && [ -s out.txt ] && ! grep -qE '"error"|"status": "(error|upstream)' err.txt; then
      : success
    fi

### Keep answers inside the completion window

The HTTP client behind the CLI uses a **300-second read timeout** on the
completion request. A generation that needs longer than that server-side dies
with a connection error (empty stdout) after several wasted minutes — the empty
failures were seen exiting around 3.5–4 minutes, consistent with that ceiling,
though a stalled circuit produces the same signature. Either way the remedy is
the same. So:

- Ask for **tables, ranked lists and bounded sections**, not essays. "Answer
  each of these 8 questions in a table or 3–5 lines" is safer than "explain in
  detail".
- Prefer one topic per call over a maximalist mega-question; if a topic has two
  halves, split them into two scrubbed requests (which may be *better* for
  privacy anyway).
- If a call dies near 3–5 minutes, **shrink the ask**, don't just re-fire it.

## Timing you must tolerate (do not "fix" by re-running early)

Measured on a healthy system, per successful `make_single_request`:

| Phase | Typical |
|---|---|
| Tor bootstrap to 95% | 10–60 s (can stall; see playbook) |
| Reviewed-model policy fetch (first call on a new circuit) | 0–60 s |
| Previous request settling | 0–90 s |
| Generation | 1.5–3.5 min |
| **End to end** | **~3–4.5 min** (observed 2m57s–4m15s for 12–21 KB answers) |

Every phase prints to stderr as it happens: `Bootstrapped ...%`, `waiting for
previous request to settle ...`, `waiting for the reviewed-model policy to
load ...`. These waits are the system working correctly. **Never kill a call
because it is "taking long"** — killing mid-settlement orphans the payment
lease and makes the *next* call slower. Only treat it as failed once the
process has exited or a stderr error appeared. Budget ~4 minutes per call plus
~60 s spacing when planning a batch, and use the wait for local work rather
than polling in a tight loop.

## Batching a batch: the pattern that works

Running several calls back-to-back with no spacing is the most common way to
break this tool. Observed, in one session: **four calls fired ~3 s apart → 2
succeeded, 2 failed** (one `rc=0` with zero bytes, one `rc=1` after a stalled
bootstrap). The same two questions, retried one at a time with 60 s spacing,
**both succeeded on the first attempt** — so the failures were congestion and
settlement races, not the prompts. What worked:

- **Sequential only**, ~60 s of dead time between calls (the settlement of call
  N must finish before call N+1 leases).
- **Per-item retry** (2 attempts is plenty), re-checking output bytes.
- **Log start/end timestamps and byte counts** for every attempt, so you can
  tell a slow call from a dead one.
- **Write each answer to its own file**; never append.
- **Run it detached and keep working locally**; the local half of the job
  (extraction, parsing, applying rules) should already be done by the time the
  remote answers land.

    #!/usr/bin/env bash
    CLI=/home/YOU/zkapi/zkapi-tor-cli.sh
    D=/tmp/zr; mkdir -p "$D"
    for n in q1_topic q2_topic q3_topic; do
      for try in 1 2; do
        echo "[$(date +%T)] START $n try$try"
        timeout 900 "$CLI" make_single_request "$(cat "$D/$n.txt")" \
          > "$D/$n.out" 2> "$D/$n.err"
        rc=$?; bytes=$(wc -c < "$D/$n.out")
        echo "[$(date +%T)] DONE $n try$try rc=$rc bytes=$bytes"
        [ "$bytes" -gt 200 ] && break
        sleep 90
      done
      sleep 60
    done
    echo "[$(date +%T)] ALL FINISHED"

Never resend an already-successful question to "improve" it: each resend is
money and a new observable request. Retry failures only.

## Failure playbook

| Signature | Meaning | Action |
|---|---|---|
| `model_budget_unavailable` | id not in the live reviewed policy (or the policy was still cold) — **most often the stale default model** | CLI prints `available models:`; `set_model <id from that list>`, smoke-test, retry |
| `upstream_error: The inference provider rejected the request.` | model is listed but the provider refuses it (common with aliased/decorated ids) | pick a different model from the live list; do not retry the same id |
| `waiting for previous request to settle (state: pending)` | payment for the previous call still finalizing | **wait**; the CLI nudges settlement itself; don't kill |
| `wallet not ready (unreachable)` | payment companion down / no wallet | stop firing calls; `~/zkapi/zkapi-diag.sh`, check server log; fix the wallet before retrying |
| `Bootstrapped` stalls below ~95% | a slow or sick entry circuit | let the call exit, then retry once — retries run over a fresh circuit |
| dies ~3–5 min in, empty output (`Remote end closed connection`, `Connection refused`) | completion window exceeded, or circuit died mid-generation | **shrink the ask**, then retry; see the 300 s note |
| `rc=0` but stdout empty | empty completion | retry with a slightly firmer instruction ("answer in tables, do not omit any item") |
| `no active conversation (or its history was lost)` | `ask` used with no live session (reboot, new identity) | `start_conversation` again, or prefer `make_single_request` |
| persistent failure after retries | unhealthy Tor exit / upstream | patience beats aggression; wait several minutes |
| Environment knobs | tuning if needed | `ZKAPI_TORCLI_READY_TIMEOUT`, `ZKAPI_TORCLI_WARM_TIMEOUT`, `ZKAPI_TORCLI_SETTLE_TIMEOUT` (seconds) |
| Session log | everything the daemon did | `/tmp/zkapi-tor-cli.<uid>/server.log` |

## Composing the query (what actually earns its budget)

The value of a call is set by how the question is framed. What produced
consistently usable, high-density answers:

1. **Ask for rules, thresholds and raw data — never for a verdict.** "What
   factors determine X, and at what point does each one change the
   recommendation?" or "give me measured values with units, means and observed
   ranges" beats "what should I do?" — in every domain. It produces denser
   answers *and* keeps the user out of the prompt, because a rule has no client.
   Examples of the shift: not "should I move to city C" but "what structural
   factors differentiate cities for a commutable, family-suitable, mid-cost
   base"; not "is our stack vulnerable" but "what classes of issue does this
   configuration class expose, and what are the standard tests for them".
2. **Ask for units and the conversion traps.** Explicitly request units,
   reference intervals, and "where these get confused in practice". Quoting
   conventions are where cross-domain answers go wrong: rent quoted warm vs cold
   and per m² vs per ft², salaries gross vs net and inclusive vs exclusive of
   bonus, prices with or without VAT/tip/fees, bandwidth in Mbps vs MB/s, year
   in calendar vs fiscal terms, deadlines in whose timezone and with or without
   a grace period. When the answer gives you a reference value *and* the
   definition of the interval, you can do the arithmetic locally.
3. **Invite correction.** Add: "If any assumption in this framing is unsound, or
   a stated threshold is not actually established, say so explicitly." The model
   will then overrule a premise it was handed — folk rules that get repeated as
   fact differ by domain (a password-rotation interval, a day-count that "makes
   you a resident", a rule of thumb for affordability or dosing or sizing) and
   you cannot check them from here. Cheap insurance against being agreeably
   wrong.
4. **Ask for the ceiling and the floor, not just the mean**, whenever the real
   answer is dispersion. City- and product-level averages are the classic trap:
   a national or citywide figure for rent, commute time, school quality, crime,
   or a device's battery life routinely conceals a 2–10× spread across districts,
   streets, model years or usage profiles. Ask for the mean, the observed range,
   and *what drives the spread* — then find out which end your local situation
   sits at, locally. Often the spread is the answer and the mean is noise.
5. **Ask what is contested, and what is not established.** Housing policy,
   school quality, "nice areas", wage norms, security tradeoffs and performance
   claims are all argued about; ask the model to separate settled fact from
   convention from contested claim, and to name the two sides. It suppresses
   false precision and tells you what to hedge.
6. **Ask for a calculation scaffold, and keep the inputs.** Request the reference
   thresholds and the per-unit rates — tariff per kWh, fee schedule, tax bracket
   boundaries, per-request cost, tolerance limits — plus the formula, then
   substitute your own numbers locally. This is both more accurate (you can redo
   the arithmetic with better inputs) and privacy-preserving: the personal value
   never leaves the machine.
7. **Ask for the answer's volatility.** On anything time-shaped — visa and
   immigration rules, rental and tax law, prices, product lineups, published
   vulnerabilities, transit construction — ask what the answer is as of its
   knowledge, what tends to change, how fast, and what should be re-verified
   against an authoritative source before acting. Then verify locally. Don't let
   the remote model stand in for currency it does not have.
8. **Batch sub-questions within one topic, split across topics.** Ten numbered
   sub-questions inside one subject (ten facets of one visa category, ten
   properties of one protocol, ten variables of one market) cost a single call
   and get answered fully — combine freely when they share a topic and combining
   leaks nothing. Different *subjects* about the same underlying situation go in
   separate calls, under separate identities: "relocating with a school-age
   child to city C" is reconstructable from visa + school + housing questions
   asked as one prompt, and is not from three unrelated ones.
9. **Use the domain's own vocabulary, including local-language administrative,
   legal and commercial terms**, rather than describing the user's situation.
   Local permit/visa category names, statutory references, standard acronyms,
   product SKU families, market and menu names make the question *more*
   answerable while being completely impersonal — the terminology is public and
   the situation is not. One caveat: naming a jurisdiction pins the user's
   location, so state it only where the answer genuinely depends on it, and make
   it the last thing you decide, not the first.
10. **Write the prompt to a file** (heredoc), then pass it as `"$(cat file)"`.
    This survives quotes, newlines and non-ASCII; keeps an auditable record of
    exactly what left the machine; and makes re-sending a failure free.
11. **Audit after the fact.** Grep the saved prompts *and* answers for
    identifiers, exact values, place names and version strings before you file
    them away. An automated sweep catches the thing you were thinking about but
    typed anyway.

## Workflow: local first, remote second, ~5 calls per deep task

Do **all** local work before the first call: read the files, extract and
interpret what is already knowable, and list what is genuinely missing. Then
spend calls only on those reference gaps. A deep multi-domain task — five
distinct subjects, each needing its own threshold tables — cost **5 calls total**
(≈25 minutes of wall-clock, backgrounded while the local analysis was written),
plus one smoke test. The remote calls supplied thresholds, reference ladders,
measured tables and correction notes; every inference about the actual case was
made locally from those rules. Aim for that ratio — if you are making many calls,
the question is usually framed as a consultation rather than a lookup. The same
shape applies whether the task is a relocation decision, a security review, or a
comparison of suppliers: the local side holds the specifics, the remote side
supplies the rules, and the two only meet on your machine.

## Final checklist before EVERY remote call

1. Would this prompt make sense coming from any random stranger? (scrubbed, self-authored)
2. Does it contain any fact about the user that the provider couldn't already infer from the topic alone? (if yes, remove it)
3. Is anything here linkable to anything else you've sent recently, without needing a conversation? (if yes, generalize or isolate)
4. Did you write the question so the answer is reusable *locally* — a decision rule or raw facts, not a verdict on the user's situation?
5. Does it quote any log line, version string, document text or place-plus-
   niche-attribute combination that only the user could have? (if yes, class-level it)
6. Is the ask bounded enough to finish inside the completion window?
7. Has the model id been smoke-tested since the last failure?
8. Is any other call in flight right now? (it must not be)
9. If the answer is time-shaped, did I ask how volatile it is — and will I verify
   it locally instead of treating it as current?
