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

```
Description:
  $cmdname will backup all tables of a SQLite database, and rotate dumps to
  keep disk usage under control.

Usage:
  $cmdname [-option arg]...

  where all dash-led single options are as follows:
    -v              Be more verbose
    -f database     Path to DB file to backup (mandatory)
    -d destination  Directory where to place (and rotate) backups.
    -n basename     Basename for file/dir to create, date-tags allowed, defaults to: %Y%m%d-%H%M%S.sql
    -k keep         Number of backups to keep, defaults to empty, meaning keep all backups
    -t command      Command to execute once done, path to backup will be passed as an argument.
    -P pending      Extension to give to file while creating backup
```

Note that for the removal of older backups to properly function, `backup.sh`
needs to "own" the target directory.

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
    -f /data/db.sqlite3 \
    -k 10 \
    -d /tmp \
    -t cat
```

In practice, this will:

1. Generate a temporary file with the `.pending` name in the `/tmp` directory.
2. Rename the file using the default timestamp output template, i.e. containing
   the current date and time.
3. (Possibly) remove older backups that would have been done in the `/tmp`
   directory to keep the last 10 ones.
4. Dump the content of the file by passing its filename to the `cat` command.
