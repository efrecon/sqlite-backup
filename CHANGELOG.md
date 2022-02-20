# Changes

## v1.0.0

This is the first ever release outside of the draft development process. This
release has added the following features lately:

+ Ability to retry backups on failure.
+ Support for backups both as textual SQL dumps (as before), but also as perfect
  database binary copies.
+ Ability to compress the backups using `gzip`.

All changes have been made in a backwards compatibility manner: the default for
the options are still the same and all new features need to be turned on
explicitely via the new command-line options or `SQLITE_BACKUP_*` prefixed
environment variables.

## v2.0.0

This release brings that ability to backup several databases at the same time.
The old option `-f` has been removed, instead the paths to the databases to
backup are taken from the arguments to the script. In order to enable different
destination filenames in the destination directory, two pseudo-date formatting
strings are supported by the `-n` option: `%o` and `%f`. These will be replaced
by the basename of the file, respectively with and without extensions.
