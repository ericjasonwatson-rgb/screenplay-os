# Beat sheet and screenplay presentation

Outline now gives its main area to the beat sheet, followed by the canonical
scene cards. Structure choices are directly visible there: Hero's Journey,
Save the Cat, Three-Act, TV Acts, Character Arc, Mystery, and Custom Blank.
The existing template contents have not been reauthored or independently audited
as an authoritative account of those frameworks.

Selecting a structure alone does not replace authored work. Create Beat Sheet
initializes an empty outline. Replace Beat Sheet requires an in-app confirmation
that names the loss of beat wording, notes, and links; replacement is undoable.
Only one beat sheet is stored by the existing format. Independent concurrent
versions for different frameworks are not implemented. Scene text and identity
remain canonical; beats link to those scenes rather than copying them.

Workspace selects sidebar content; Mode selects the main creative view.
Workspace now reveals the sidebar when a choice is made and has explanatory
help. The persistent labels remain unchanged to preserve the requested shell.

The shared Script Preview used in Outline, Shot, Boards, and Edit now uses
white paper and dark ink by default, matching Script. Dark Page switches all
these paper surfaces together. Preview body text uses document typography
(default Courier 12). Scene headings display in uppercase in the continuous
editor, scene cards, and previews without rewriting an opened source file.

Validation: 187 Swift tests, 37 Python checks, and 14 importer self-tests.
Native tests cover Unicode heading display and editing, source preservation,
undo, blank-paragraph lock/reopen behavior, historical lock policy, and beat
replacement with notes/links restored through undo and reopen. Live release
verification is recorded separately in the workspace work directory.
