# CampaignOS: a 20-minute synthetic producer pilot

**Purpose:** rehearse brief → bid basis → reviewed agency evidence → frozen V1 →
creative-only decision → explicit V2 reconciliation → private review and backup.
Allow about 20 minutes **after** the local build. Stop and record a failure rather
than treating this checklist as evidence that the UI passed.

Everything in this scenario is fictional, including Oat & Ember, Northstar Studio,
dates, people and approvals. Use no client documents, accounts, providers, payments
or sharing. The five DOCX files are actual bounded ZIP/XML packages made from the
repository's synthetic test corpus, not files authored or certified by Office.
They exercise body extraction, not Word's visual layout or real-agency fidelity.

## Prepare a fresh local kit and app (outside the 20 minutes)

Use a Mac with the repository's supported Swift/Xcode build tools, Python 3.10+
and Git. Work from the checkout containing this file. Save any current work and
quit other ScreenplayOS instances first. Never replace an installed app for this
pilot. Prefer a clean checkout of the exact PR head you intend to test.

From the repository root:

```sh
git rev-parse HEAD
git status --short
python3 Scripts/check-campaign-agency-fixtures.py --check --self-test
python3 -m unittest discover -s Tests/Packaging -p 'test_campaign_pilot.py' -v

# The destination must not already exist, even if empty or a symlink.
# Use an existing local, nonsynced parent with no symlink path components.
REVIEW="$(mktemp -d "$HOME/CampaignOS-review-XXXXXX")"
PILOT="$REVIEW/pilot"
python3 Scripts/prepare-campaign-pilot.py --output "$PILOT"
```

If any command fails, stop. The generator refuses to merge or overwrite output;
after a failed write, use a different new destination. It does not build or launch
an app, create a screenplay, access user documents or alter campaign storage.
Its output is:

- `documents/`: the five accepted synthetic DOCX originals only. The eleven
  intentionally rejected test payloads are not materialized.
- `expected/`: five exact UTF-8 body-text oracles, including intentional blank
  lines and **no added terminal newline**.
- `expected-lines.txt`: numbered line map. JSON quotes/escapes show whitespace;
  the quotes are not part of the actual text. Coordinates are extracted-body
  lines, never Word pages, visual columns or legal clause numbers.
- `walkthrough.md`: this guide.
- `manifest.json`: full source commit, dirty-tree flag, original/text hashes,
  counts, input hashes and each generated payload's hash. The manifest cannot
  hash itself. It records local fixture validation, **not CI or native acceptance**.

Keep the kit and checkout together. Generated files are owner-readable/writable;
this is not encryption or a signed distribution. The generator validates base64,
filenames, hashes, sizes and the exact corpus against the independent XML/text
oracles. It does not unpack archive members to disk or fetch anything.

Build a separate local app beside the data-only kit, using the existing packaging
workflow:

```sh
# This must be a new app path. Never substitute /Applications/ScreenplayOS.app.
test ! -e "$REVIEW/ScreenplayOS-Campaign-Pilot.app" && \
test ! -L "$REVIEW/ScreenplayOS-Campaign-Pilot.app" && \
SCREENPLAYOS_SIGNING_IDENTITY=- SCREENPLAYOS_NOTARY_PROFILE= \
SCREENPLAYOS_SKIP_REVIEW_CLEANUP=1 \
bash Scripts/package-app.sh "$REVIEW/ScreenplayOS-Campaign-Pilot.app"
```

The default is Apple Silicon. On an Intel Mac add `SCREENPLAYOS_BUILD_ARCH=x86_64`
to that command's environment; `universal` builds both. Packaging normally rejects
dirty source. Only for an intentionally uncommitted local development rehearsal,
add `SCREENPLAYOS_ALLOW_DIRTY=1`; retain its dirty provenance and do not present it
as a clean-head release. A build success is not a test pass. Run the repository's
full macOS test/CI matrix separately and record the exact tested commit and result.

This is a locally compiled, ad-hoc-signed app, not a signed/notarized download.
No Gatekeeper bypass is part of this guide. If macOS blocks the app, stop and
record the warning. Do not remove quarantine or disable system protections.
Launch only this newly built app from Finder. Do not pass a screenplay as an
`open -a` argument or rely on double-click document routing: this app has no
file-open delegate for that route. Use its **File > Open...** command instead.

The app normally uses its local preferences and Application Support. A separate
app bundle is **not** a separate app-data sandbox. Use the fresh project below;
do not open, reset, restore over or otherwise modify an existing project/ledger.
The pilot does not require signing in or network access.

## 1. New project and brief (minutes 0–3)

1. Choose **File > New Screenplay**, not Experimental Features / New Writing-Only
   Screenplay. The normal filmmaking project gets a fresh project UUID. Do not
   reuse another project's Save As copy: Save As preserves its identity.
2. In the new Script, enter only this fictional scene heading and action:
   - `INT. FICTIONAL STUDIO KITCHEN - MORNING`
   - `An oat-drink carton stands beside a mug. Morning light crosses the table.`
3. Choose **File > Save As...** and save a new `Oat-Ember-Pilot.screenplayos.json`
   inside the kit. Decline any overwrite. Reopening later must use this file.
4. Choose **Campaign > Campaign Brief & Scope…**. Inspect **Next review step**
   and **Show review checklist**. **Go to Step** only navigates; it does not fill
   scope, import, review or approve anything.
5. In **Brief & Deliverables**, enter:
   - Brand: `Oat & Ember (fictional pilot)`
   - Objective: `Introduce an oat drink for everyday coffee rituals.`
   - Audience: `Adult home-coffee drinkers in the US and UK.`
   - Key message: `Small rituals, brighter mornings.`
   - Mandatory requirements: `Show the carton label clearly. Do not make nutrition or environmental claims.`

**Check:** the saved screenplay still contains only your two synthetic elements.
Opening the Campaign guide did not populate a brief or create an approval.

## 2. Deliverables and bid basis (minutes 3–5)

Use **Add Deliverable** twice and enter:

- `Hero film`: **30 sec**, ratio `16:9`, market `US + UK`, language `en-US`.
- `Social cutdown`: **15 sec**, ratio `9:16`, market `US + UK`, language `en-US`.

Use the duration stepper. Leave Shot coverage empty for this short pilot. Linking
is optional, and the guide should still ask for human coverage review. This does
not certify shot, board, image or semantic coverage.

In **Bid Assumptions**, choose **Add Assumption**:

- Assumption: `One studio day, one location, two adult performers; no travel.`
- Source document / version: `Synthetic creative brief V1`
- Page / section / reference: `Extracted body line 18; not a Word page`

**Check:** there are exactly two deliverables and one assumption. These are manual
scope entries, not a calculated price, budget, production commitment or spend cap.

## 3. Preview, review and cite real DOCX bytes (minutes 5–11)

In **Agency Sources**, import the three V1 files one at a time with **Choose New
Source…**. For each, inspect the original/text hashes, extraction notices and
preview against `manifest.json`, `expected/<name>.txt` and `expected-lines.txt`.
Inspect the original in a local document viewer if available; never infer Word
layout from the line map. If no suitable viewer is available, record visual
original/layout comparison as **not tested**, rather than claiming it passed.

For the first brief, choose **Cancel Import** once. Confirm no source was saved,
then choose it again. Only **Import Preview Locally** retains the source. Import
must not alter your deliverables, assumption or screenplay.

For each saved source, enter **Reviewed by** `Pilot Producer (fictional)` and a
truthful **Review note / changes found**, then **Record Source Review**. For this
synthetic rehearsal the oracles can verify exact extraction. Record any missing
original-layout check explicitly in the note; a pilot review is not real approval.

1. **`brief-v1.docx`**, 24 lines. Confirm mandatory lines **13–14** and bid basis
   **18**. The `Café` in line 11 has a combining accent; do not normalize it.
   Header text `FICTIONAL HEADER ONLY: not body evidence` is deliberately absent
   from the body; inspect the omission notice.
   - Note: `Synthetic body checked against the oracle; label/claims restriction retained. One-studio basis retained over the conflicting memo. [Record actual original-view check or not tested.]`
   - After review, choose target type **Assumption**, select your assumption,
     enter first/last line **18 / 18**, and note `One-studio bid basis.`
     Choose **Add Reviewed Citation**.
2. **`deliverables-v1.docx`**, 45 lines. Cells flatten into separate paragraphs
   in XML order; the app does not reconstruct the six-column visual table.
   - Note: `Synthetic matrix body checked: 30-second hero and 15-second social. V1 duration retained over memo. [Record actual original-view check or not tested.]`
   - Cite **19–29** to **Deliverable / Hero film**, note `V1 hero scope.`
   - Cite **31–41** to **Deliverable / Social cutdown**, note `V1 social scope.`
3. **`production-memo-v1.docx`**, 15 lines. Line **5** asks for a 45-second hero;
   line **7** asks for two locations and travel. Both conflict with V1.
   - Note: `Fictional producer resolution for V1: retain the matrix's 30-second hero and brief's one studio/no travel basis. Memo requests are not adopted and are not approval. [Record actual original-view check or not tested.]`
   - Do not cite these contradictory requests as support for your current targets.

**Check:** three source documents, three reviews and three citations. The app
does not detect semantic contradictions or decide document precedence. Your note
records your manual choice; an empty warning list does not prove consistency.

## 4. Freeze V1, then record creative only (minutes 11–13)

In **Baseline & Changes**, name and **Freeze Baseline**:
`Pilot V1 - 30s / one studio`. Inspect its selected UUID and freeze time.
A baseline is an immutable local snapshot, not an approval.

In **Record an approval already received**, select **Creative** and enter only
this explicitly fictional rehearsal record:

- Approved by: `Fictional Creative Reviewer`
- Evidence / message reference: `SIMULATION ONLY. Fictional reviewer accepts Pilot V1 creative direction. No real approval received; no production or spend authorization.`

Choose **Preview Local Record**. Check the exact V1 identity, creative scope,
person and evidence, then **Confirm Local Record** once. Do not select Production
approach or Additional spend. Do not enter real people or approvals.

**Check:** V1 has one creative record and zero production/spend records. This
does not verify identity, create an electronic signature, authorize a provider
request or make a payment. **Undo Draft Change** will not erase this record.

## 5. V2 stays a proposal until you reconcile it (minutes 13–17)

1. In **Agency Sources**, explicitly select the saved `deliverables-v1.docx`
   source. Choose **Choose Revised Source…**, then `deliverables-v2.docx`.
   Inspect and **Import Preview Locally**. Do not import V2 as an unrelated new
   source. It has **57 lines**; hero **19–29**, unchanged social **31–41**, new
   bumper **43–53**, and the one-studio confirmation at **57**.
2. Before editing scope, confirm the draft still says **30-second hero**, has
   only two deliverables, and retains the one-studio assumption. V1's decision
   remains attached to V1 and is historical; it does not approve this revision.
   The revised source requires review and the old matrix citations are stale.
3. In **Brief & Deliverables**, manually change Hero film to **45 sec** and add
   `Bumper`, **6 sec**, ratio `1:1`, market `US + UK`, language `en-US`.
   Do not change the social or studio assumption. This is a fictional adoption
   for the exercise, not an inferred authorization from the document.
4. Return to the selected V2 source and **Record Source Review** as the fictional
   producer. Note `V2 body checked: hero 45 seconds, social unchanged, add 6-second square bumper. One studio retained. [Record actual original-view check or not tested.]`
5. For each stale matrix citation choose **Reconcile Citation…**. Compare the
   old excerpt/target with V2. Enter **19–29** for Hero film and **31–41** for
   Social cutdown in their separate flows. Explicitly choose the current target
   (or **Use Previously Cited Target’s Current State**), enter a reconciliation
   note, choose **Preview Replacement**, inspect, then **Confirm Reconciliation**.
   The unchanged social still requires reconciliation to the new source revision.
6. Add a reviewed V2 citation **43–53** to **Bumper**, note `V2 square bumper scope.`
   The brief's line-18 assumption citation remains unchanged.
7. Inspect warnings. If any source/citation warning remains, resolve the actual
   issue rather than freezing to clear it. Freeze `Pilot V2 - reviewed, not approved`.
   Select it and verify **zero** creative, production and spend records. Select V1
   again and verify its single creative record remains historical.

**Check:** three deliverables, one assumption, three source documents with four
retained revisions, four current citations, two baselines, one V1-only creative
decision. Reviews and reconciliation change evidence links, not past snapshots.

## 6. Summary report, reopen, private backup (minutes 17–20)

1. Keep **V1** selected for the before/after comparison. Leave **Include full
   before / after evidence** **off** and choose **Preview Change Review**.
   Confirm the summary identifies V1 and affected scope without dumping before/
   after screenplay or agency text. Names/identities can still be confidential;
   summary mode is not automatic redaction or a client-safe designation.
2. Inspect the complete preview and **Save Reviewed Copy…** as a new local
   `pilot-v1-to-v2-summary.txt` in the kit. Do not send it. A report is not an
   approval, quote, automated repricing or schedule promise.
3. **Close** the Campaign panel and reopen it; check saved fields/history. Close
   it again, save the screenplay and quit this pilot app. Relaunch the same new
   app from Finder and choose **File > Open...** to open your pilot screenplay.
   Open Campaign and check the counts above and the two baselines' decisions.
   Selection/UI state need not persist; select the baselines explicitly.
4. Choose **Private Backup…** and save a new `pilot-campaign-private-backup.json`
   in the kit. Confirm success. This full ledger includes retained originals,
   reviews, citations, baseline snapshots and historical decisions, so keep it
   private alongside the separately saved screenplay.

Campaign data lives in a project-ID-bound Application Support companion, **not
inside the screenplay file**. Save As is not a new campaign identity, and moving
only the screenplay to another Mac does not bring the ledger. A private backup
does not back up screenplay/media or verify the origin of decisions. Restore is
same-project-only and only before a local campaign exists. **Do not delete or
reset app state to test restore in this pilot.** Restore, disk-full and power-loss
recovery remain separate acceptance work. Your local folders may sync through
other software; the app itself performs no upload here.

## Optional extra: identical body, different original (about 3 more minutes)

After completing and backing up the main pilot, select the deliverables source
and revise it with `deliverables-v2-metadata-only.docx`. Compare manifest hashes:
its original SHA-256 differs from V2, while the extracted SHA-256 and 57 lines
are identical. Import must still invalidate the source review and matrix
citations. Do not claim approval carries forward because the body hash matches.
Review/reconcile each affected citation explicitly, or leave this as a recorded
pending-review exercise. This optional step changes the main pilot's counts and
makes the earlier backup a **pre-extra-step** copy; save a new backup if needed.

## Record the outcome and limits

Make a new local note in the kit with the source commit/dirty flag, macOS/Xcode
versions, actual app path, start/end time and each step's **pass / fail / not run**.
Record exact errors and which step failed. Check `manifest.json` rather than
guessing a build's source. CI outcomes need the exact run/head; the generator does
not look them up or assert them. Do not publish private backups or real material.

The following are **not established by completing this rehearsal**: signed or
notarized download distribution, real-agency/Office fidelity, full visual table
order, PDF support (disabled for Campaign agency import), automatic semantic
reconciliation, exhaustive shot coverage, identity-verified approval, spending
authority, cross-device sync, encryption, full disaster recovery, performance,
VoiceOver, physical-keyboard coverage or all picker interruptions. This pilot
creates no real commitment and sends nothing to anyone.
