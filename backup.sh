#!/bin/sh


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
SQLITE_BACKUP_RETRIES=${SQLITE_BACKUP_RETRIES:-0}
SQLITE_BACKUP_SLEEP=${SQLITE_BACKUP_SLEEP:-5}
SQLITE_BACKUP_TIMEOUT=${SQLITE_BACKUP_TIMEOUT:-"5000"}
SQLITE_BACKUP_OUTPUT=${SQLITE_BACKUP_OUTPUT:-"auto"}
SQLITE_BACKUP_COMPRESSION=${SQLITE_BACKUP_COMPRESSION:-""}

# Dynamic vars
cmdname=$(basename "$(readlink -f "$0")")
appname=${cmdname%.*}

# Print usage on stderr and exit
usage() {
    sed -E 's/^\s+//g' <<-EOF
        $0 will backup all tables of a SQLite database, and rotate dumps to
        keep disk usage under control. Dumps can be in textual form (an SQL
        dump), or as another identical SQLite database file.

        Options:
EOF
    head -n 200 "$0" |
        grep -E '\s+-[a-zA-Z-].*)\s+#' |
        sed -E \
            -e 's/^\s+/    /g' \
            -e 's/)\s+#\s+/:\t/g'
    exit "${1:-0}"
}

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -k | --keep) # Number of backups to keep, defaults to empty, meaning keep all backups
            SQLITE_BACKUP_KEEP=$2; shift 2;;
        --keep=*)
            SQLITE_BACKUP_KEEP="${1#*=}"; shift 1;;

        -f | --file | --db | --database) # Path to DB file to backup (mandatory)
            SQLITE_BACKUP_DB=$2; shift 2;;
        --file=* | --db=* | --database=*)
            SQLITE_BACKUP_DB="${1#*=}"; shift 1;;

        -d | --dest | --destination) # Directory where to place (and rotate) backups.
            SQLITE_BACKUP_DESTINATION=$2; shift 2;;
        --dest=* | --destination=*)
            SQLITE_BACKUP_DESTINATION="${1#*=}"; shift 1;;

        -n | --name) # Basename for file/dir to create, date-tags allowed, defaults to: %Y%m%d-%H%M%S.sql.gz
            SQLITE_BACKUP_NAME=$2; shift 2;;
        --name=*)
            SQLITE_BACKUP_NAME="${1#*=}"; shift 1;;

        -v | --verbose) # Be more verbose
            SQLITE_BACKUP_VERBOSE=1; shift 1;;

        -t | --then) # Command to execute once done, path to backup will be passed as an argument.
            SQLITE_BACKUP_THEN=$2; shift 2;;
        --then=*)
            SQLITE_BACKUP_THEN="${1#*=}"; shift 1;;

        -r | --retries) # Number of times to retry backup operation.
            SQLITE_BACKUP_RETRIES=$2; shift 2;;
        --retries=*)
            SQLITE_BACKUP_RETRIES="${1#*=}"; shift 1;;

        -s | --sleep) # Number of seconds to sleep between backup attempts
            SQLITE_BACKUP_SLEEP=$2; shift 2;;
        --sleep=*)
            SQLITE_BACKUP_SLEEP="${1#*=}"; shift 1;;

        -P | --pending) # Extension to give to file while creating backup
            SQLITE_BACKUP_PENDING=$2; shift 2;;
        --pending=*)
            SQLITE_BACKUP_PENDING="${1#*=}"; shift 1;;

        -T | --timeout) # Timeout in ms to acquire DB lock
            SQLITE_BACKUP_TIMEOUT=$2; shift 2;;
        --timeout=*)
            SQLITE_BACKUP_TIMEOUT="${1#*=}"; shift 1;;

        -o | --output) # Output type: auto (the default), sql or db (or bin). When auto, guessed from file extension.
            SQLITE_BACKUP_OUTPUT=$2; shift 2;;
        --output=*)
            SQLITE_BACKUP_OUTPUT="${1#*=}"; shift 1;;

        -c | --compression) # Compression level. When empty, the default, default compression will be triggered when name ends with .gz.
            SQLITE_BACKUP_COMPRESSION=$2; shift 2;;
        --compression=*)
            SQLITE_BACKUP_COMPRESSION="${1#*=}"; shift 1;;

        --with-arg) # Pass created path to backup file to command
            SQLITE_BACKUP_WITHARG=1; shift;;

        --no-arg) # Do not pass path to backup file to command
            SQLITE_BACKUP_WITHARG=0; shift;;

        -h | --help) # Print this help and exit
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

retry() {
    while true; do
        if "$@"; then
            break
        fi

        if [ "$SQLITE_BACKUP_RETRIES" -gt "1" ]; then
            SQLITE_BACKUP_RETRIES=$(( SQLITE_BACKUP_RETRIES - 1 ))
            log "Failed! $SQLITE_BACKUP_RETRIES retries left"
            sleep "$SQLITE_BACKUP_SLEEP"
        else
            return 1
        fi
    done
}

# Return the list of current backup files in the destination directory, sorted
# oldest first.
backups() {
    find "$SQLITE_BACKUP_DESTINATION" \
            -maxdepth 1 \
            -name "$(printf %s\\n "$SQLITE_BACKUP_NAME" | sed 's/%[a-zA-Z]/*/g')" \
            -type f \
            -print0 |
        xargs -0 ls -1rt
}

# Compress or not the file which path is passed as a parameter. Return the name
# of the file to keep (either the compressed path or uncompressed).
compress() {
    # Compress depending on SQLITE_BACKUP_COMPRESSION and target name. Keep
    # original file until we have checked the integrity of the target.
    if [ "$SQLITE_BACKUP_COMPRESSION" = "" ]; then
        if printf %s\\n "$SQLITE_BACKUP_NAME" | grep -Eq '\.gz$'; then
            gzip -k "$1"
        fi
    elif [ "$SQLITE_BACKUP_COMPRESSION" -gt "0" ]; then
        gzip -k -"${SQLITE_BACKUP_COMPRESSION}" "$1"
    fi

    # If we compressed, check integrity. Remove whichever of the files is
    # relevant, i.e., in most cases, the original file as the compressed file
    # worked.
    if [ -f "${1}.gz" ]; then
        if gzip -t "${1}.gz"; then
            rm -f "$1"
            printf %s\\n "${1}.gz"
        else
            rm -f "${1}.gz"
            warn "Compression to ${1}.gz failed"
            printf %s\\n "${1}"
        fi
    else
        printf %s\\n "${1}"
    fi
}

# No DB to backup. Bail out!
if [ -z "$SQLITE_BACKUP_DB" ]; then
    warn "No path to DB!"
    usage 1
fi

# Guess output type out of backup file name template extension (no ending $ to
# be sure we can have .gz also).
if [ "$SQLITE_BACKUP_OUTPUT" = "auto" ]; then
    if printf %s\\n "$SQLITE_BACKUP_NAME" | grep -Eq '\.(sql|txt|dmp|dump)'; then
        SQLITE_BACKUP_OUTPUT=dump
    else
        SQLITE_BACKUP_OUTPUT=db
    fi
    log "Selected output type: $SQLITE_BACKUP_OUTPUT"
fi

# Automatically add a .gz when compression is turn on by force and to a give
# level.
if [ -n "$SQLITE_BACKUP_COMPRESSION" ] && [ "$SQLITE_BACKUP_COMPRESSION" -gt "0" ]; then
    SQLITE_BACKUP_NAME="${SQLITE_BACKUP_NAME}.gz"
    log "Automatically added .gz extension -> $SQLITE_BACKUP_NAME"
fi

# Decide name of destination file, this takes into account the pending
# extension, if relevant.
ZFILE=$(date +"$SQLITE_BACKUP_NAME")
FILE=$(printf %s\\n "$ZFILE" | sed -E 's/\.gz$//')
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
log "Starting backup of all databases to $ZFILE"
case "$SQLITE_BACKUP_OUTPUT" in
    dump | sql)
        if ! retry sqlite3 -readonly "$SQLITE_BACKUP_DB" \
                ".timeout $SQLITE_BACKUP_TIMEOUT" \
                .dump \
                .exit > "${SQLITE_BACKUP_DESTINATION}/${DSTFILE}"; then
            warn "Could not create backup!"
            rm -rf "${SQLITE_BACKUP_DESTINATION:?}/$DSTFILE"
        fi
        ;;
    db | bin | sqlite*)
        if ! retry sqlite3 -readonly "$SQLITE_BACKUP_DB" \
                ".timeout $SQLITE_BACKUP_TIMEOUT" \
                ".backup '${SQLITE_BACKUP_DESTINATION}/${DSTFILE}'" \
                .exit; then
            warn "Could not create backup!"
            rm -rf "${SQLITE_BACKUP_DESTINATION:?}/$DSTFILE"
        fi
        ;;
    *)
        warn "$SQLITE_BACKUP_OUTPUT is not a recognised backup output type"
        usage 1
        ;;
esac

# Compress on demand when we have succeeded making a backup
if [ -f "${SQLITE_BACKUP_DESTINATION}/${DSTFILE}" ]; then
    if [ -n "${SQLITE_BACKUP_PENDING}" ]; then
        mv -f "$(compress "${SQLITE_BACKUP_DESTINATION}/${DSTFILE}")" "${SQLITE_BACKUP_DESTINATION}/${ZFILE}"
    else
        compress "${SQLITE_BACKUP_DESTINATION}/${DSTFILE}" > /dev/null
    fi
    log "Backup done"
fi

if [ -n "${SQLITE_BACKUP_KEEP}" ]; then
    while [ "$(backups | wc -l)" -gt "$SQLITE_BACKUP_KEEP" ]; do
        DELETE=$(backups | head -n 1)
        log "Removing old backup $DELETE"
        rm -rf "$DELETE"
    done
fi

if [ -n "${SQLITE_BACKUP_THEN}" ]; then
    log "Executing ${SQLITE_BACKUP_THEN}"
    if [ -f "${SQLITE_BACKUP_DESTINATION}/$ZFILE" ] && [ "$SQLITE_BACKUP_WITHARG" = "1" ]; then
        eval "${SQLITE_BACKUP_THEN}" "${SQLITE_BACKUP_DESTINATION}/$ZFILE"
    else
        eval "${SQLITE_BACKUP_THEN}"
    fi
fi
