# Card-specific fields

The card editor can add named, typed fields without changing its shared template.
Definitions follow the existing field model and participate in local undo,
preview, copy, export/import and JSON serialization.

These fields use the optional `actitpass_CardField` table, keyed by card and field
ID. Names and values use the existing SPB encrypted text codec. The rekey service
includes both encrypted columns. Values are merged into the card's UI values at
load time; they are not inserted as orphan SPB template-field values. The table
is created only when explicitly saving additional fields. Card deletion removes
its rows. Layout and visibility use the existing card layout metadata.

Changing the shared template was rejected because it would add fields to other
cards. Legacy SPB Wallet and older Wallet APS versions ignore this optional
table: they can read the original template fields but cannot display card-specific
additions. Wallet APS SWL export/import preserves the additions.

After saving a card with additional fields, Wallet APS offers to update its
current template or create a new template. The card is already saved before this
optional dialog appears. Declining or closing it retains the card and its
encrypted additions. The dialog provides a name, icon, existing template folder
and a read-only list of fields. Separate footer buttons select "Изменить шаблон"
or "Создать новый шаблон" using the name, icon and folder currently entered in
the dialog. They wrap onto additional rows on narrow screens. Updating
the current template retains its ID and existing field IDs, appends the added
fields, and explicitly indicates that the template is shared by linked cards.

Creating a separate SPB template allocates fresh template/field IDs. Values,
order and hidden IDs are mapped to those new field IDs, the card is assigned to
the new template, and its view is copied from that template so the additional
fields also exist in `spbwlt_CardViewField`. The card's colour, icon, notes,
background and attachments are retained. Only explicitly mapped old value rows
are replaced; unrelated metadata and the original shared template are preserved.
The optional card-specific rows are removed within the card-save transaction
after their values become normal SPB fields. If template creation fails, the
initially saved card remains available with its additional fields.

The session undo menu includes "Отменить все изменения". It restores the snapshot
before the first recorded change, including session trash state. That first
snapshot is retained when the bounded undo history discards older intermediate
steps, so undo-all still covers a session with more than twelve changes.

This path is checked against native SPB table relationships in synthetic SQLite
wallets. Rendering by the original SPB Wallet application remains a device/manual
check.
