# Simple Automated Backup Solution for SQLite3

This project arranges to continuously and regularly dump a [SQLite] database in
a format that permits recovery in case of disasters. The project is tuned for
usage within a Dockerised environment. Typical scenarios will periodically
restart containers based on this image using a host-wide cron-like daemon such
as [dockron].

  [SQLite]: https://www.sqlite.org/
  [dockron]: https://github.com/efrecon/dockron

## Usage and Command-Line Options

This shell (not bash) script has the following options:

```text
./backup.sh will backup all tables of the SQLite databases passed as arguments,
and rotate dumps to keep disk usage under control. Dumps can be in
textual form (an SQL dump), or as another identical SQLite database
file.

Options:
    -k | --keep:        Number of backups to keep, defaults to empty, meaning keep all backups
    -d | --dest | --destination:        Directory where to place (and rotate) backups.
    -n | --name:        Basename for file/dir to create, %-tags allowed, defaults to: %f-%Y%m%d-%H%M%S.sql.gz.
    -v | --verbose:     Be more verbose
    -t | --then:        Command to execute once done, path to backup will be passed as an argument.
    -r | --retries:     Number of times to retry backup operation.
    -s | --sleep:       Number of seconds to sleep between backup attempts
    -P | --pending:     Extension to give to file while creating backup
    -T | --timeout:     Timeout in ms to acquire DB lock
    -o | --output:      Output type: auto (the default), sql or db (or bin). When auto, guessed from file extension.
    -c | --compression: Compression level. When empty, the default, default compression will be triggered when name ends with .gz.
    --with-arg: Pass created path to backup file to command
    --no-arg:   Do not pass path to backup file to command
    -h | --help:        Print this help and exit

Description:
In the backup name, specified by -n, most %-led tags will be passed to
the date command with the current date and time. Two extra format
strings are supported: %o and %f mean basename of the db file, with and
without extensions.
```

Note that for the removal of older backups to properly function, `backup.sh`
needs to "own" the target directory.

## Outputs

This script is able to generate two types of backups:

+ Textual SQL dumps (as of the `.dump` SQLite command).
+ Binary exact copies of the databases (as of the `.backup` SQLite command).

Unless specified otherwise, the type of the backup will be decided by the
extension of the basename, e.g. `.sql` for SQL dumps, or `.db` for binary
database backups.

## Docker

`backup.sh` is specified as the default entrypoint for the image. By default,
the Docker image encapsulates `backup.sh` behind [`tini`][tini] so that it will
be able to properly terminate sub-processes when stopping the container.

  [tini]: https://github.com/krallin/tini

### Example

Provided that you have built a Docker image called `efrecon/sqlite-backup` and
have a `db.sqlite3` file in the current directory, the following command would
generate a backup and dump it to the standard out.

```shell
docker run -it --rm \
  -v $(cwd):/data \
  efrecon/sqlite-backup \
    -k 10 \
    -d /tmp \
    -t cat \
    /data/db.sqlite3
```

In practice, this will:

1. Generate a temporary file with the `.pending` name in the `/tmp` directory.
2. Rename the file using the default timestamp output template, i.e. containing
   the current date and time.
3. (Possibly) remove older backups that would have been done in the `/tmp`
   directory to keep the last 10 ones.
4. Dump the content of the file by passing its filename to the `cat` command.
