# Portable card and folder transfer

Card/folder SWL exports embed the images referenced by the exported cards,
templates, folder ancestors and empty descendant folders. Folder colours,
template categories, card field ordering/visibility, custom fields and
attachments travel with the selected content. An individual card import still
uses the destination folder selected by the user; folder imports restore the
exported subtree below that destination.

Existing embedded icon payloads and filenames are decrypted from the source
and encrypted into the destination without decoding or resizing the image.
Catalogue images and vector glyphs are embedded using the existing SPB-compatible
ICO writer. Import remaps an icon ID if the destination already uses it for a
different image; existing cards and folders retain their original images.
Identical stored payloads are reused without overwriting destination metadata.

Templates with the same name/ID are reused only when field names and types are
compatible. Otherwise the complete source definition is imported with a fresh
ID, so card values are not discarded or assigned to unrelated fields.
After the cards are saved, the user is offered the template editor for each
previously absent definition used by the imported cards. The imported definition
already supports displaying those cards, even if the user chooses "Не сейчас".
Confirmation edits that definition rather than creating a second copy or
changing the cards' field IDs. Source-less legacy definitions retain the existing
field recovery path.

A legacy reference whose image is absent from the source and the available
catalogue retains its ID instead of receiving a random unrelated icon. Missing
source image data cannot be reconstructed from the ID alone.

Synthetic tests in `portable_wallet_transfer_test.dart` cover encrypted export,
empty folders, embedded bytes, collisions, attachments, field metadata and the
accept/decline paths on Windows and narrow Android. Existing import/export,
template, data-integrity and rekey tests remain applicable.
