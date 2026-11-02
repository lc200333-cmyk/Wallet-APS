# Android cloud document writes

Wallet files selected through SAF may be backed by a stream-only cloud provider.
Such a provider can reject `rw`, and a newly created document may not have a
known size or be readable until its first upload has closed.

The writer validates the local SQLite snapshot and makes the existing private
recovery copy before writing. URIs returned by `ACTION_CREATE_DOCUMENT` are tracked
as newly created until a verified write succeeds. For other nonempty or unknown
size documents, it first copies the original bytes into `Wallet APS/Recovery/Originals`
in private app storage and syncs that backup to disk. Failure to read or back up
the original prevents any write. The five most recent originals are retained per
URI, separately from current working-copy recovery snapshots.

The existing seekable `rw` path remains available. If it fails, the writer tries
an output stream with `wt`, then `w` only if opening the first stream fails.
Transfer, flush and close failures are reported without reopening the stream.
The complete result is read back and compared by byte count and SHA-256. Up to
five read-back attempts accommodate briefly stale cloud reads; an unverified
upload is never reported as saved. This checks the provider's readable contents,
not completion of remote server synchronization. SAF does not guarantee atomic
cloud replacement; both old-original and new-working-copy backups therefore
remain available after failure.

The dependency-free `WalletStreamWriterTest` Java main harness exercises stream
mode fallback, rejected/null streams, transfer/close failures, revoked permission
and preservation of source bytes. Compile it together with `WalletStreamWriter`
using JDK 17+ (`javac --release 17 -d <temporary classes directory> <both sources>`),
then run `java -cp <classes directory> com.lc200333cmyk.walletaps.WalletStreamWriterTest`.

Manual acceptance requires Android plus the actual Drive provider: create/save
a new wallet, edit/reopen a nonempty cloud wallet, save a shorter replacement,
disconnect during upload, revoke write permission, and confirm that failures keep
the working copy and backups. Never use a personal wallet for these checks.
