---
name: implement
description: Implement one spec or ticket end-to-end - TDD at the pre-agreed seams, then an in-loop code-review pass, then prove the slice through its real entry point, then hand off to no-mistakes to validate and ship (committing the captured evidence with the work, and pointing at it on the PR). Use to build the work described by a spec or a ticket, one ticket per fresh context.
---

# Implement

Implement the work described by the user in the spec or ticket.
Work one ticket per fresh context - clear context between tickets, taking the frontier (any ticket whose blockers are all done).
If you are on the default branch, lease a **treehouse** and do the whole ticket inside it: the gate needs the work committed on a **non-default feature branch**, and the implementation, the demo, the captures and the commit all have to happen in one working tree, so starting in the lease leaves nothing to move.

Use `/tdd` where possible, at the **pre-agreed seams** the spec or ticket already pinned (see `/to-spec` - do not invent new seams here without confirming them).

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once the change works, run `/code-review` for the in-loop review-and-refactor pass.
This is where refactoring happens (the `/tdd` loop deliberately leaves it out): apply the mechanical fixes and the smell-driven refactors it surfaces, re-running the affected tests after each.

## Prove the slice, do not just prove the tests

Before handing off, exercise the ticket through its **real entry point**, the way a user would reach it - curl the endpoint, load the screen with `chrome-devtools-axi`, trigger the job.
You run the demo unattended, so it must not put a browser window in front of the user - that steals focus from whatever they are doing - and it must never drive the user's own Chrome, worse still because it navigates the tabs they are working in.
`chrome-devtools-axi` now attaches to the **standing automation Chrome** - a separate browser on its own profile that nobody browses in - so the second half of that rule is satisfied by configuration rather than by remembering it, and the demo may use the browser as it is.
The first half still binds, because that browser is headful and sits on the user's desktop: reuse the tab that is already there rather than piling up windows with `newpage`, and never raise, focus or resize it.
`CHROME_DEVTOOLS_AXI_HEADED` and `CHROME_DEVTOOLS_AXI_AUTO_CONNECT` are examples of how the rule gets lost rather than the whole list - `AUTO_CONNECT` especially, since it reaches the user's own Chrome and is exactly what this setup replaced - and if the user asks to watch, headed is what they asked for and that half lifts, while their own Chrome stays off limits.
One caveat that is not about the user at all: the bridge is shared, so a demo running while another agent drives the same browser will fight it for the selected page. `CHROME_DEVTOOLS_AXI_SESSION=<name>` gives the demo its own bridge, and its own page selection, against the same browser - the session name is what binds the port, the PID file and the selected-page id together. `CHROME_DEVTOOLS_AXI_PORT` alone does not isolate anything: it moves the port but leaves the session named `default`, so the demo still reads the shared PID file, finds the shared bridge healthy, and reuses it on its original port.

A green suite, a clean review, and green CI all prove the same thing: the code satisfies its own tests.
None of them proves the ticket does what was asked.
This is the mirror of the global rule that a bug is reproduced end-to-end *before* it is fixed, and it applies to features too.
For anything with a UI it is also the only point at which the pixel-perfection bar can be applied at all.

Walk the **behavioural** acceptance criteria `/to-tickets` wrote on the ticket and demonstrate each; they are the ticket's own definition of done.
A happy path you chose yourself demonstrates a feature nobody asked for, however green it comes out.
The template's two fixed checkboxes are not demo items: "Behind `FeatureFlag`" is a property of the change, and "CI green" is settled by the pipeline after the handoff.
If reaching the entry point needs a fact that is not in the repo - which job to trigger, which role gates it, which test account to sign in as - read `docs/external/`; `/grill-with-docs` writes those facts there.

Driving the real entry point yourself is verification you can do unattended, flag flip included, so this neither requires the user to be present nor makes a ticket HITL.

### Reaching the entry point behind a flag

`/to-tickets` gates a slice behind a `FeatureFlag` only when the behaviour is not ready to be live, so a slice arrives either gated or not.
If it is not gated, exercise it directly.
A flag being off is **never** a reason to skip the demo - turning it on is the demo.

The flag row lives in the shared **DEV** database, and DEV is the only place a demo may ever flip one - never staging, never production.
Point the admin endpoint at DEV before you call it; a flip anywhere else turns an unreleased feature on for that deployment's real traffic.
Treat the flag as **exclusive** - one agent demos it at a time - because it is one shared row with no lock, and the call sites read it through plain `IsEnabled`, which ignores `AllowedUsers`, so there is no way to turn it on for yourself alone.
Read `Enabled` before you touch it: if it is false you are the one turning it on, so flip it for the demo and restore the body you kept on every path out - including when the demo fails or the ticket is abandoned.
A gated slice's flag is expected to be off, so already true means another agent is mid-demo or an interrupted demo never restored it, and the row does not say which: do not flip it and do not demo on top of it, and report it as a blocker naming the flag and the slice you were demoing, for a person to decide whether to wait or clear the row.
Flip it through the admin endpoint rather than SQL, so the flag cache is invalidated; other processes still read the previous value for about a minute.
You hold a name and those routes take an id, so list with the backend's `GET /api/admin/feature-flags` to find it, then work the row through `GET`/`PUT /api/admin/feature-flags/{id}` - keep the whole body, because that `PUT` is a full replacement that silently nulls every field it leaves out.
Name the flag in the capture and say you turned it on for the demo.

The one slice with nothing to exercise is one with no user-reachable path at all, a pure internal seam nothing calls yet; for that, capture that statement instead, rather than skipping the step silently.

### Capture the observable output, not your report of it

A sentence saying the feature works is not evidence; it is the claim the evidence is supposed to support.
Capture what the system actually emitted: the request you sent and the response that came back with its status line, a screenshot of the rendered UI rather than a devtools network or storage panel, or the log lines the job wrote.
Strip every credential from text before you write it - `Authorization` headers and bearer tokens, cookies, session ids, API keys, connection strings, passwords - leaving a visible `<redacted>` where each was, because the capture is committed and becomes permanent history that `ignore_patterns` hides from the gate's own review, so nothing downstream will catch what you leave in.
A screenshot cannot be redacted once it is committed, so keep the secret out of the frame and retake or crop before saving.

Every capture lands in `.no-mistakes/evidence/<branch>/demo/`, nesting on the branch's slashes.
That directory needs the branch **name** only, not an existing ref, so name it after whichever branch will carry the work.
Text you write yourself goes straight there, but a `chrome-devtools-axi screenshot` has to be taken to a path under the temp directory and then moved into place, because that path is validated against MCP roots the axi bridge never negotiates and the temp directory is the only one left.
The refusal is silent - the CLI prints the path it was given and exits 0 whether or not it wrote anything, so a path it refused looks exactly like one it accepted and the only way to know is to check the file exists after the call.

### When the demo shows the wrong behaviour

The ticket is not done.
Fix it and demo again.
By handoff `.no-mistakes/evidence/<branch>/demo/` must hold the captures from the demo that passed and nothing else, so overwrite or delete whatever a failed or superseded attempt left there.
Otherwise the PR carries a screenshot of the bug beside one of the fix, with nothing to say which is which.
Do **not** hand off to `/no-mistakes` with a capture that shows the wrong result and a note explaining it away - this step is the first thing in the whole pipeline that checks the ticket against what was asked rather than against its own tests, so an excuse here defeats it entirely.

## Hand off to the gate

Point the user at the diff itself at this boundary, not only at the outcome.
Losing touch with the codebase costs weeks at exactly the moment an agent hits a bug it cannot solve alone.

Inside the lease you are on a detached HEAD, the one state the gate refuses to validate, so create the feature branch there and then run the gate.
Already on a non-default feature branch there is nothing to create, so commit and run the gate.
See the `## Git Branching` section of the global instructions for the full rule, the exact sequence, and how the lease and the branch get cleaned up afterwards.

Whichever case you are in, the captures ride in the **same commit** as the work, staged alongside it - no second commit, no amend.
The `demo/` subdirectory exists because the branch directory root belongs to the gate's own test step: these captures are taken before the gate with the flag deliberately on, the gate's are produced later with the flag in whatever state the branch ships, and on a flag-gated slice the two would otherwise read as contradicting each other.
Add `.no-mistakes/evidence/**` to `ignore_patterns` in that repo's `.no-mistakes.yaml` if it is missing.

Do **not** put the evidence in the `--intent`: intent is the goal the change serves, never a record of what you ran (see `/no-mistakes`).

## Point at the evidence once the PR exists

Post the comment on a `checks-passed` outcome and on a `passed` one alike: what decides it is whether the PR is still open, not which name the outcome carries.
A repo that skips the ci step never reaches `checks-passed` at all, so its `passed` arrives with the PR open and a human review and merge still pending - exactly the decision the comment is there to reach.
Compose the body into a file of its own and post it with `gh-axi pr comment <number> --body-file <file>`.
Link the committed captures, say they were taken from the working tree before `/no-mistakes` ran, and never embed them inline with image markdown: GitHub fetches comment images anonymously through its camo proxy, so a URL into a private repository renders as a broken image.
Skip the comment only when the PR is already merged or closed, and put the evidence in your closing summary to the user instead.
