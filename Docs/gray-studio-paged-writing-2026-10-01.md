# Gray studio and paged writing — 2026-10-01

The studio uses matte neutral gray surfaces and separators while retaining white screenplay paper and the existing Dark Page option. The reference is Ableton Live's theme/contrast approach, not a copied interface: https://www.ableton.com/en/live-manual/12/first-steps/

The native editor derives page positions from the same attributed fragments used by PDF export. Zoom uses scroll-view magnification, keeping typography and wrapping at document scale. Page gaps, ordinary page numbers, and generated dialogue continuations are presentation only. Gray “PDF 1” source guides are no longer drawn. If fragment mapping or native line boundaries do not match, the editor explicitly falls back to continuous view and directs the user to Print Preview. Historical whitespace-trimming production locks remain compatible.

Casing is an ephemeral source-mapped projection shared by the editor and ordinary PDF output. Scene headings, character cues, transitions, shots, and standalone O.S./V.O./O.C./CONT'D extensions display uppercase. Ordinary directions such as (whispers) retain their authored case. First action occurrences of known dialogue names display uppercase; names without dialogue cues cannot yet be identified automatically, and ambiguous names still require author review. Authored source text and IDs remain intact.

Title Page opens a separate editing sheet. PDF already carries a separate unnumbered title page; its credit block now measures multiline height. A narrowly scoped repair recognizes the exact six generic title placeholders at the end of old imports. It writes a full safety snapshot, supports Undo, and moves those lines verbatim into title-page additional credits. It does not invent writer or contact information. Current FDX imports already isolate TitlePage XML.

Final Draft references:
- https://kb.finaldraft.com/hc/en-us/articles/27646947570196-What-are-script-elements
- https://kb.finaldraft.com/hc/en-us/articles/15575069544724-Why-isn-t-the-title-page-the-first-page-of-my-script
- https://kb.finaldraft.com/hc/en-us/articles/27724447299220-How-do-I-create-a-title-page

Validation: 190 Swift tests, 37 Python checks, and 14 contract self-tests passed. New coverage checks casing/source preservation, title-tail snapshot/Undo/reopen/PDF separation, and native line positions against print fragments at multiple zoom levels. These changes target the legacy screenplay editor; they do not establish complete native-package editor parity or Final Draft feature parity.

Live verification (2026-10-02): the initial review instance stalled on full-script opening. Page-plan validation now measures natural wrapping before assigning page coordinates, avoiding mixed layout during validation. The rebuilt main app opened the 173-element Chickamauga document responsively, with an 11-page print projection and no continuous-view fallback notice. The separate Title Page repair ran through the app on the user's document; readback confirmed 167 remaining elements byte-for-value equal to the original prefix and all six trailing lines preserved in title-page credits. The original pre-repair document is also retained at work/Chickamauga-title-repair.open-screenplay.json. Gray surfaces, white paper, uppercase final transition, and removal of trailing title text were visually verified. Writer/contact fields remain blank because the source contained generic placeholders, not actual credit information.
