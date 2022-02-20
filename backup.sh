#!/bin/sh

if [ -t 1 ]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi

# Increase the verbosity of this script when setting this to 1. Otherwise, only
# warnings will be logged.
SQLITE_BACKUP_VERBOSE=${SQLITE_BACKUP_VERBOSE:-0}

# Destination directory where to place the backups, it will be created if it
# does not exist. Default to current directory.
SQLITE_BACKUP_DESTINATION=${SQLITE_BACKUP_DESTINATION:-"."}

# Name of the backup files to create in the destination directory. This support
# %-led date formating tokens, but also supports %f where %f is the basename of
# the original file, without extension and %o, the name of the original file.
# When the output is auto the default, the extension will decide upon the type
# of the backup (textual SQL dump, or binary SQLite file). Also when .gz is
# added, and compression is empty (the default), destination backups will be
# compressed at the default gzip level.
SQLITE_BACKUP_NAME=${SQLITE_BACKUP_NAME:-"%f-%Y%m%d-%H%M%S.sql"}

# How many backups of a given database to keep in the destination directory. The
# default is an empty string, i.e. keep all backups.
SQLITE_BACKUP_KEEP=${SQLITE_BACKUP_KEEP:-""}

# Backups will have the following extension while in progress. They will be
# renamed once all operations are done.
SQLITE_BACKUP_PENDING=${SQLITE_BACKUP_PENDING:-".pending"}

# Command to execute once all backups have been done. The path to the
# destination backups, in the order of the original DB file paths arguments will
# be appended to the command (unless see next variable).
SQLITE_BACKUP_THEN=${SQLITE_BACKUP_THEN:-""}

# Should the path to the backups be passed as argument to the command to execute
# once all backups have been done?
SQLITE_BACKUP_WITHARG=${SQLITE_BACKUP_WITHARG:-1}

# Number of times to retry each backup
SQLITE_BACKUP_RETRIES=${SQLITE_BACKUP_RETRIES:-0}

# Number of seconds to wait between retries.
SQLITE_BACKUP_SLEEP=${SQLITE_BACKUP_SLEEP:-5}

# Number of ms to wait while acquiring a lock on the SQLite DB
SQLITE_BACKUP_TIMEOUT=${SQLITE_BACKUP_TIMEOUT:-"5000"}

# Type of the backup, one of `auto` (decided by the extension of the name of the
# backup, see above), `dump` or `sql` for textual SQL dumps, `bin`, `db`,
# `sqlite` fo binary DB perfect copies.
SQLITE_BACKUP_OUTPUT=${SQLITE_BACKUP_OUTPUT:-"auto"}

# Compression level. Empty for letting the extension of the backup name to
# decide, 0 to switch off, otherwise a level suitable for `gzip`.
SQLITE_BACKUP_COMPRESSION=${SQLITE_BACKUP_COMPRESSION:-""}

# Dynamic vars
cmdname=$(basename "$(readlink -f "$0")")
appname=${cmdname%.*}

# Print usage on stderr and exit
usage() {
    sed -E 's/^\s+//g' <<-EOF
        $0 will backup all tables of the SQLite databases passed as arguments,
        and rotate dumps to keep disk usage under control. Dumps can be in
        textual form (an SQL dump), or as another identical SQLite database
        file.

        Options:
EOF
    head -n 200 "$0" |
        grep -E '\s+-[a-zA-Z-].*)\s+#' |
        sed -E \
            -e 's/^\s+/    /g' \
            -e 's/\)\s+#\s+/:\t/g'
    sed -E 's/^\s+//g' <<EOF

        Description:
        In the backup name, specified by -n, most %-led tags will be passed to
        the date command with the current date and time. Two extra format
        strings are supported: %o and %f mean basename of the db file, with and
        without extensions.
EOF
    exit "${1:-0}"
}

# Parse options
while [ "$#" -gt "0" ]; do
    case "$1" in
        -k | --keep) # Number of backups to keep, defaults to empty, meaning keep all backups
            SQLITE_BACKUP_KEEP=$2; shift 2;;
        --keep=*)
            SQLITE_BACKUP_KEEP="${1#*=}"; shift 1;;

        -d | --dest | --destination) # Directory where to place (and rotate) backups.
            SQLITE_BACKUP_DESTINATION=$2; shift 2;;
        --dest=* | --destination=*)
            SQLITE_BACKUP_DESTINATION="${1#*=}"; shift 1;;

        -n | --name) # Basename for file/dir to create, %-tags allowed, defaults to: %f-%Y%m%d-%H%M%S.sql.gz.
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
        *)
            break;;
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

# Retry the command formed by all arguments as many times as told by the
# options, sleeping in between.
retry() {
    #shellcheck disable=SC3043 # local is available in most shells.
    local retries || true

    retries="$SQLITE_BACKUP_RETRIES"
    while true; do
        if "$@"; then
            break
        fi

        if [ "$retries" -gt "1" ]; then
            retries=$(( retries - 1 ))
            log "Failed! $retries retries left"
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
            -name "$(basename_subst "$1" | sed 's/%[a-zA-Z]/*/g')" \
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

basename_subst() {
    printf %s\\n "$SQLITE_BACKUP_NAME" |
                sed \
                    -e "s/%o/${1}/g" \
                    -e "s/%f/${1%%.*}/g"
}


if [ "$#" = "0" ]; then
    usage
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

# Collect all file arguments into the files variable. This will work as long as
# the filename does not contain a line break.
files=
for fname; do
    files="${files}$(printf \\n%s "$fname")"
done

# Loose all positional arguments, we are going to reconstruct them using with
# the name of the generated backups.
set --

while IFS= read -r fname; do
    if [ -n "$fname" ]; then
        bname=$(basename "$fname")

        # Decide name of destination file by passing it to the date command. It also
        # supports two additional %-led formats: %o is the basename of the database
        # file and %f the basename without any extensions. This takes into account
        # the pending extension, if relevant.
        ZFILE=$(date +"$(basename_subst "$bname")")
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
        log "Starting backup of all databases from $fname to $ZFILE"
        case "$SQLITE_BACKUP_OUTPUT" in
            dump | sql)
                if ! retry sqlite3 -readonly "$fname" \
                        ".timeout $SQLITE_BACKUP_TIMEOUT" \
                        .dump \
                        .exit > "${SQLITE_BACKUP_DESTINATION}/${DSTFILE}"; then
                    warn "Could not create backup!"
                    rm -rf "${SQLITE_BACKUP_DESTINATION:?}/$DSTFILE"
                fi
                ;;
            db | bin | sqlite*)
                if ! retry sqlite3 -readonly "$fname" \
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
            # Print out progress and reconstruct argument list with the paths to
            # the destinations.
            log "Backup of $fname done"
            set -- "$@" "${SQLITE_BACKUP_DESTINATION}/$ZFILE"
        fi

        if [ -n "${SQLITE_BACKUP_KEEP}" ]; then
            while [ "$(backups "$bname" | wc -l)" -gt "$SQLITE_BACKUP_KEEP" ]; do
                DELETE=$(backups "$bname" | head -n 1)
                log "Removing old backup $DELETE"
                rm -rf "$DELETE"
            done
        fi
    fi
done <<EOF
$(printf %s\\n "$files")
EOF

if [ -n "${SQLITE_BACKUP_THEN}" ]; then
    log "Executing ${SQLITE_BACKUP_THEN}"
    if [ "$SQLITE_BACKUP_WITHARG" = "1" ]; then
        # shellcheck disable=SC2086 # We WANT word splitting!
        set -- ${SQLITE_BACKUP_THEN} "$@"
    else
        # shellcheck disable=SC2086 # We WANT word splitting!
        set -- ${SQLITE_BACKUP_THEN}
    fi
    exec "$@"
fi
