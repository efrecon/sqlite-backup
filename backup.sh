#!/usr/bin/env sh


if [ -t 1 ]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi

# All (good?) defaults, we are also able to pick some of the POSTGRES_ led
# variables so as to be able to more easily share secrets with a postgres Docker
# image.
SQLITE_BACKUP_VERBOSE=${SQLITE_BACKUP_VERBOSE:-0}
SQLITE_BACKUP_KEEP=${SQLITE_BACKUP_KEEP:-""}
SQLITE_BACKUP_DB=${SQLITE_BACKUP_DB:-""}
SQLITE_BACKUP_DESTINATION=${SQLITE_BACKUP_DESTINATION:-"."}
SQLITE_BACKUP_NAME=${SQLITE_BACKUP_NAME:-"%Y%m%d-%H%M%S.sql"}
SQLITE_BACKUP_PENDING=${SQLITE_BACKUP_PENDING:-".pending"}
SQLITE_BACKUP_THEN=${SQLITE_BACKUP_THEN:-""}
SQLITE_BACKUP_WITHARG=${SQLITE_BACKUP_WITHARG:-1}

# Dynamic vars
cmdname=$(basename "$(readlink -f "$0")")
appname=${cmdname%.*}

# Print usage on stderr and exit
usage() {
  exitcode="$1"
  cat << USAGE >&2

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
USAGE
  exit "$exitcode"
}

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -k | --keep)
            SQLITE_BACKUP_KEEP=$2; shift 2;;
        --keep=*)
            SQLITE_BACKUP_KEEP="${1#*=}"; shift 1;;

        -f | --file | --db | --database)
            SQLITE_BACKUP_DB=$2; shift 2;;
        --file=* | --db=* | --database=*)
            SQLITE_BACKUP_DB="${1#*=}"; shift 1;;

        -d | --dest | --destination)
            SQLITE_BACKUP_DESTINATION=$2; shift 2;;
        --dest=* | --destination=*)
            SQLITE_BACKUP_DESTINATION="${1#*=}"; shift 1;;

        -n | --name)
            SQLITE_BACKUP_NAME=$2; shift 2;;
        --name=*)
            SQLITE_BACKUP_NAME="${1#*=}"; shift 1;;

        -v | --verbose)
            SQLITE_BACKUP_VERBOSE=1; shift 1;;

        -t | --then)
            SQLITE_BACKUP_THEN=$2; shift 2;;
        --then=*)
            SQLITE_BACKUP_THEN="${1#*=}"; shift 1;;

        -P | --pending)
            SQLITE_BACKUP_PENDING=$2; shift 2;;
        --pending=*)
            SQLITE_BACKUP_PENDING="${1#*=}"; shift 1;;

        --with-arg)
            SQLITE_BACKUP_WITHARG=1; shift;;

        --no-arg)
            SQLITE_BACKUP_WITHARG=0; shift;;

        -\? | --help)
            usage 0;;
        --)
            shift; break;;
        -*)
            echo "Unknown option: $1 !" >&2 ; usage 1;;
    esac
done

# Colourisation support for logging and output.
_colour() {
    if [ "$INTERACTIVE" = "1" ]; then
        # shellcheck disable=SC2086
        printf '\033[1;31;'${1}'m%b\033[0m' "$2"
    else
        printf -- "%b" "$2"
    fi
}
green() { _colour "32" "$1"; }
red() { _colour "40" "$1"; }
yellow() { _colour "33" "$1"; }
blue() { _colour "34" "$1"; }

# Conditional logging
log() {
    if [ "$SQLITE_BACKUP_VERBOSE" = "1" ]; then
        echo "[$(blue "$appname")] [$(yellow info)] [$(date +'%Y%m%d-%H%M%S')] $1" >&2
    fi
}

warn() {
    echo "[$(blue "$appname")] [$(red WARN)] [$(date +'%Y%m%d-%H%M%S')] $1" >&2
}


if [ -z "$SQLITE_BACKUP_DB" ]; then
    warn "No path to DB!"
    usage 1
fi

FILE=$(date +"$SQLITE_BACKUP_NAME")

# Decide name of destination file, this takes into account the pending
# extension, if relevant.
if [ -n "${SQLITE_BACKUP_PENDING}" ]; then
    DSTFILE=${FILE}.${SQLITE_BACKUP_PENDING##.}
else
    DSTFILE=${FILE}
fi

# Create directory if it does not exist
if ! [ -d "${SQLITE_BACKUP_DESTINATION}" ]; then
    log "Creating destination directory ${SQLITE_BACKUP_DESTINATION}"
    mkdir -p "${SQLITE_BACKUP_DESTINATION}"
fi

# Install (pending) backup file into proper name if relevant, or remove it
# from disk.
log "Starting backup of all databases to $FILE"
if sqlite3 "$SQLITE_BACKUP_DB" \
        .dump \
        .exit > "${SQLITE_BACKUP_DESTINATION}/${DSTFILE}"; then
    if [ -n "${SQLITE_BACKUP_PENDING}" ]; then
        mv -f "${SQLITE_BACKUP_DESTINATION}/${DSTFILE}" "${SQLITE_BACKUP_DESTINATION}/${FILE}"
    fi
    log "Backup done"
else
    warn "Could not create backup!"
    rm -rf "${SQLITE_BACKUP_DESTINATION:?}/$DSTFILE"
fi

if [ -n "${SQLITE_BACKUP_KEEP}" ]; then
    # shellcheck disable=SC2012
    while [ "$(ls "$SQLITE_BACKUP_DESTINATION" -1 | wc -l)" -gt "$SQLITE_BACKUP_KEEP" ]; do
        DELETE=$(ls "$SQLITE_BACKUP_DESTINATION" -1 | sort | head -n 1)
        log "Removing old backup $DELETE"
        rm -rf "${SQLITE_BACKUP_DESTINATION:?}/$DELETE"
    done
fi

if [ -n "${SQLITE_BACKUP_THEN}" ]; then
    log "Executing ${SQLITE_BACKUP_THEN}"
    if [ -f "${SQLITE_BACKUP_DESTINATION}/$FILE" ] && [ "$SQLITE_BACKUP_WITHARG" = "1" ]; then
        eval "${SQLITE_BACKUP_THEN}" "${SQLITE_BACKUP_DESTINATION}/$FILE"
    else
        eval "${SQLITE_BACKUP_THEN}"
    fi
fi
