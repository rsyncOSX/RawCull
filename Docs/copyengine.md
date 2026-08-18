# Copying rated and tagged files

## Recommendation

RawCull should continue using `/usr/bin/rsync` for the current release. The
existing implementation is working and already provides dry runs, update
semantics, cancellation, streamed output, metadata copying, and useful
statistics. Replacing it merely to remove visible code would exchange known
complexity for new copy-correctness risks.

A native `CopyEngine` is nevertheless the better long-term design if the
feature remains limited to this promise:

> Copy an explicit set of local files from one user-selected folder into one
> user-selected destination folder.

For that narrow operation, rsync is more capable than RawCull needs. It also
requires RawCull to translate structured Swift state into command-line
arguments and then translate textual output back into structured state. The
current path includes three Swift packages, a subprocess, a temporary
NUL-separated file list, output-version compatibility, and several models and
views coupled to rsync terminology.

Do not replace rsync with a loop containing only `FileManager.copyItem`.
Production-quality file copying needs well-defined behavior for collisions,
metadata, cancellation, partial files, errors, security-scoped URLs, and
progress. A migration should happen only after the native engine implements
and tests those behaviors.

Use the expected future scope to make the final decision:

- Keep rsync if RawCull may add directory synchronization, resume support,
  remote transfer, filters, or sophisticated metadata mirroring.
- Prefer a native engine if RawCull will only copy explicitly selected local
  files into a folder.

## Define the copy contract first

The native implementation must not accidentally choose its behavior through
whichever Foundation API is convenient. RawCull should document and test the
following product decisions before implementing the engine.

### Selection and paths

- Accept a source directory URL, a destination directory URL, and an explicit
  collection of selected source files.
- Decide whether selected files must be direct children of the source folder.
  RawCull currently works with filenames, so limiting the operation to direct
  children is the simplest and safest contract.
- Reject empty names, absolute paths, `.` and `..` components, path separators,
  embedded NUL bytes, and any resolved source outside the selected source
  directory.
- Preserve the exact filesystem name. Do not normalize case or Unicode when
  constructing the source URL.
- Define whether symbolic links are rejected, copied as links, or followed.
  Rejecting them is the least surprising policy for a RAW-photo copy feature.
- Reject a destination that resolves to the source directory. Also define
  behavior when one selected file already resides at its destination URL.
- Deduplicate selections by a stable filesystem identity or resolved URL, not
  only by the displayed filename.

Path validation must be performed again immediately before opening each file.
Validation performed when the user selected a folder does not eliminate races
caused by files or links changing later.

### Existing destination files

The current rsync command uses `--update`. A replacement must preserve that
behavior intentionally or present a new user-visible policy. Before migration,
capture the exact existing behavior in integration tests, including:

- destination absent;
- same size and modification date;
- destination newer than source;
- destination older than source;
- equal dates but different sizes or contents; and
- case-only filename differences on case-sensitive and case-insensitive
  volumes.

The native API should express this as a policy such as `skipExisting`,
`replace`, or `replaceIfSourceIsNewer`. It should never overwrite implicitly.
Every skipped file should have a structured reason in the result.

### Data and metadata

The engine must decide which attributes form part of a successful copy:

- all file bytes;
- file size;
- modification and creation dates;
- permissions;
- extended attributes and Finder metadata;
- resource forks, where present; and
- filesystem flags supported by the destination.

Not every destination filesystem supports every attribute. An exFAT volume,
for example, cannot be expected to behave exactly like APFS. The result should
distinguish a complete data copy with unsupported metadata from a failed data
copy.

`FileManager.copyItem` may be a useful baseline, but its behavior and progress
support must be tested for RawCull's requirements. If byte progress,
cancellation during a large file, cloning, or precise metadata behavior is
required, a small Swift wrapper around the macOS `copyfile(3)` API may be a
better system-level primitive. That choice still produces a native embedded
engine; it does not require an external executable.

### Atomicity and partial files

Do not copy directly to the final destination name. For each file:

1. Create a uniquely named temporary file in the destination directory.
2. Copy bytes and required metadata to that file.
3. Validate the completed copy according to the configured verification
   policy.
4. Atomically rename it to the final name, applying the selected collision
   policy.
5. Remove the temporary file after cancellation or failure.

Creating the temporary file in the destination directory keeps the final
rename on the same volume. Temporary names must be unpredictable and opened
with exclusive-create behavior so an existing file or link cannot be reused.

For ordinary operation, byte count plus successful close and rename is a
reasonable verification level. Optional content hashing provides stronger
verification but reads both files again, which can approximately double I/O.
RawCull should not claim checksum verification unless it actually performs it.

### Progress and cancellation

The engine should expose structured progress rather than lines of process
output. At minimum, progress should contain:

- total and completed file counts;
- total selected bytes when available;
- bytes completed for the batch and current file;
- current filename; and
- whether the operation is planning, copying, skipping, cancelling, or
  finishing.

Cancellation must be cooperative during a large file, not only between files.
After cancellation, the engine must close handles, remove its temporary file,
stop security-scoped access, and return a cancelled result. Files completed and
renamed before cancellation may remain; that partial-success behavior should
be documented in the UI.

Copying several large RAW files concurrently often reduces performance on SD
cards, spinning disks, and network volumes. Start with one file at a time.
Concurrency can be made a measured optimization later.

### Dry run

Dry run must use the same planning and collision-policy code as a real copy.
It should perform all safe validation and return the actions that would occur,
but it must not create destination files or temporary files. Results should say
which files would be copied, replaced, or skipped and why.

A dry run is a preview, not a guarantee. Source and destination state may
change before the real operation.

### Security-scoped access

- Resolve the stored bookmarks and call
  `startAccessingSecurityScopedResource()` before enumerating or opening files.
- Keep both access scopes alive for the entire operation, including final
  rename and cleanup.
- Balance every successful start with exactly one stop on success, failure, and
  cancellation.
- Treat stale bookmarks explicitly and ask the user to select the folder again
  when access cannot be restored safely.
- Pass URLs through the engine. Do not convert them to strings and later
  reconstruct them unless required at a system-call boundary.

The security-scoped folder is the authority granted by the user. RawCull must
still enforce its own source-containment and destination rules inside that
scope.

### Results and errors

The native engine should return values rather than logs that another layer has
to parse. A useful model includes:

- a per-file outcome: copied, replaced, skipped, failed, or cancelled;
- source and destination URLs;
- bytes copied;
- preserved or unsupported metadata;
- a typed skip or failure reason;
- aggregate counts and byte totals;
- start time and duration; and
- whether the operation was a dry run.

Expected filesystem errors should be mapped to understandable cases such as
permission denied, destination read-only, destination full, source vanished,
name collision, unsupported metadata, and volume disconnected. Retain the
underlying error for diagnostics without showing sensitive full paths in
ordinary UI or telemetry.

An error in one file should normally be recorded while the remaining selected
files continue. Fatal errors, such as a lost destination volume or lost
security scope, may stop the whole batch.

### Suggested boundary

Keep UI, rating selection, bookmarks, and copy mechanics separate. One
possible boundary is:

```swift
protocol CopyEngine: Sendable {
    func run(
        request: CopyRequest,
        progress: @Sendable (CopyProgress) async -> Void
    ) async -> CopyReport
}
```

`CopyRequest` should contain validated URLs, selected entries, collision and
metadata policies, verification level, and `isDryRun`. `CopyReport` should be
the only input required by the results UI. The concrete engine should not
depend on `RawCullViewModel` or SwiftUI.

The engine must have a clear isolation design. Mutable operation state should
live in an actor or a single task, callbacks must be `Sendable`, and no blocking
file I/O should run on the main actor.

## Native CopyEngine test requirements

Unit tests should cover planning, validation, collision decisions, aggregate
results, cancellation state, and error mapping. Integration tests should copy
real files and verify bytes and metadata.

The filename matrix should include:

- spaces, tabs, newlines, quotes, leading dashes, `#`, `+`, `*`, `?`, and
  brackets;
- composed and decomposed Unicode;
- emoji and non-Latin scripts;
- very long valid names; and
- case-only differences.

The operation matrix should include:

- empty selection and duplicate selection;
- source removed or changed after planning;
- destination created or changed after planning;
- existing older, newer, identical, and different destination files;
- cancellation before a file, during a large file, and before final rename;
- insufficient free space and a read-only destination;
- a destination volume disconnected during copying;
- symbolic links at the source, destination, and temporary-file locations;
- stale or denied security-scoped bookmarks;
- partial metadata support; and
- app termination followed by cleanup of abandoned temporary files.

Run the integration suite on APFS and exFAT. Also manually qualify commonly
used removable media and network shares. Filesystem behavior cannot be proven
from APFS-only unit tests.

## Reducing the complexity of the rsync implementation

RawCull can make the existing solution considerably smaller without changing
the underlying copy tool. The copy operation uses a fixed local-only subset of
rsync, so it does not need a general synchronization configuration model.

### Recommended simplification

Create one RawCull-owned `RsyncCopyEngine` behind the same `CopyEngine`
boundary proposed above. Give it a small request model and a fixed,
allow-listed argument builder for only these behaviors:

- archive or the explicitly required metadata options;
- dry run;
- update/collision policy;
- NUL-separated `--files-from` input;
- itemized changes; and
- any summary output still required by diagnostics.

This can remove `SynchronizeConfiguration`, `Params`, and the workaround that
asks a general argument builder to produce two empty paths and then removes
them. For this single local-copy use case, constructing a short array of fixed
arguments locally is easier to audit than configuring a general rsync package.

RawCull can also stop parsing rsync's summary as its primary data model. It
already knows the selection and source sizes, and it can turn itemized records
into structured per-file outcomes while the process runs. Treat the process
exit status as authoritative. Textual summaries may remain diagnostic output,
but the UI should consume a `CopyReport` and use neutral labels such as “Copy
details,” not “rsync output.” This should make it possible to remove the
summary-parser dependency and its openrsync/rsync-version branch.

The process-streaming package can either remain as the one focused dependency
or be replaced by a small RawCull-owned process runner. Owning a process runner
is worthwhile only if it correctly handles concurrent stdout and stderr
drainage, cancellation, termination, exit status, and lifecycle races. Removing
a package is not a simplification if that package's behavior is merely copied
into less-tested application code.

The temporary include list is not inherently a design problem. A
NUL-separated list is a robust way to pass literal filenames without command
line length limits. Keep it unless the chosen rsync supports a thoroughly
tested stdin form that also permits reliable output streaming and
cancellation.

### Hardening rsync

No implementation can honestly be described as “100% secure.” RawCull can,
however, define a threat model, minimize authority, and test concrete security
properties. The current design already has two good properties: it invokes a
fixed absolute executable path and uses a NUL-separated file list.

An rsync engine should additionally enforce all of the following:

- Execute exactly `/usr/bin/rsync` with `Process.executableURL`; never invoke a
  shell and never locate rsync through `PATH`.
- Build an argument array exclusively from fixed allow-listed options. Never
  accept arbitrary rsync options from settings, filenames, bookmarks, or other
  user-controlled text.
- Insert the option terminator `--` before positional source and destination
  arguments if the installed `/usr/bin/rsync` behavior has been verified to
  support it.
- Validate every selected relative name using the same containment and symlink
  rules required by the native engine. `--from0` prevents delimiter injection;
  it does not replace path authorization.
- Create the include-list directory with user-only access, create each file
  exclusively with restrictive permissions, write atomically, and remove it on
  every completion path. On launch, safely remove only stale files matching
  RawCull's exact private naming and ownership rules.
- Do not place secrets in arguments, output, or logs. Avoid logging complete
  source and destination paths in production diagnostics.
- Give the subprocess only the environment it needs. In particular, fix the
  locale to a tested value if any output parsing remains, and do not inherit
  variables that can alter dynamic loading, executable lookup, remote-shell
  behavior, or rsync configuration.
- Capture stdout and stderr separately, drain both concurrently, cap retained
  diagnostic output, and decode invalid byte sequences safely.
- Treat a zero termination status as success. A termination callback or parsed
  “files transferred” count is not evidence of success by itself.
- Surface nonzero status, signal termination, launch failure, and cancellation
  as distinct typed results.
- Pin supported behavior to the system `/usr/bin/rsync`, which RawCull currently
  identifies as openrsync. Test the exact flags and output on every minimum and
  newly supported macOS release rather than assuming compatibility from the
  command name.
- Keep source and destination security-scoped access active until the child has
  terminated and cleanup is complete.
- Apply resource limits in the application: maximum selected-file count,
  maximum retained output, and bounded progress-update frequency.
- Test hostile filenames, path traversal attempts, symlink changes, malformed
  output, huge output, cancellation races, and destination replacement races.

Do not add a bundled or downloaded rsync binary merely to control the version
unless there is a compelling feature requirement. Doing so transfers patching,
code-signing, provenance, licensing, and vulnerability-response responsibility
to RawCull.

Even after this hardening, residual risks remain: operating-system bugs,
filesystem and device failures, changes to the system rsync implementation,
and time-of-check/time-of-use races. The appropriate claim is therefore
“hardened and tested for the documented threat model,” never “100% secure.”

## Migration plan

1. Define `CopyRequest`, `CopyProgress`, and `CopyReport` independently of
   rsync output.
2. Put the existing operation behind `RsyncCopyEngine` and make the UI consume
   only those models.
3. Simplify and harden the fixed rsync argument and process path.
4. Record current rsync collision, metadata, dry-run, and cancellation behavior
   as black-box integration tests.
5. Implement `NativeCopyEngine` against the same contract and test matrix.
6. Compare both engines on representative APFS, exFAT, removable, and network
   destinations.
7. Switch the production default only when the native engine meets the agreed
   contract. Keep rsync temporarily as a development comparison oracle, then
   remove it rather than maintaining two permanent production paths.

This sequence captures most of the architectural benefit early: the UI and
application model become independent of rsync before RawCull takes on the risk
of replacing the actual copy mechanism.
