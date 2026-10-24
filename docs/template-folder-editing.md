# Template folder editing

Template folders reuse `CategoryEditorDialog` for name, icon and color. Deletion
is disabled here: deleting a template folder needs a separate policy for linked
cards and is not part of folder editing.

Folder appearance and hidden default names are stored in the optional
`actitpass_TemplateFolder` table. It is created only on an explicit folder edit;
opening an old wallet does not migrate it. `Name` uses the existing encrypted
text codec and is included in the rekey service. Icons/colors use existing UI
identifiers. Empty renamed folders therefore survive reopening, and the original
default folder does not reappear automatically.

Renaming updates only the encrypted names of templates in the selected logical
folder, using the existing `category: label` representation. Visible labels stay
short. Template/field IDs, values, unknown columns, and card-category rows are
not changed. Folder settings and template names update in one transaction, and
the existing session undo/write-back workflow covers both.

Reusing `spbwlt_Category` was rejected because those rows belong to the card
folder tree: renaming/styling them would also affect “My cards”. No public SPB
schema or encryption algorithm is changed. Older Wallet APS versions ignore
the optional folder appearance table; they can still read template names.

Tests use disposable synthetic wallets for reopen, duplicate rejection,
rekey, card-link preservation, and Windows/Android shared-editor/undo behavior.
Actual Android device behavior is not verified by widget tests.
