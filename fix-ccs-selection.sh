#!/bin/bash
#
# fix-ccs-selection.sh
#
# Fixes Code Composer Studio (Eclipse based, CCS 12 and similar) on macOS 26.1+,
# where selected text is not highlighted. Backports the one-line upstream fix
# (eclipse.platform.swt PR #2694) into the SWT jar CCS already has, because the
# first SWT release with the fix needs Java 17 and CCS runs on Java 11.
#
#   bash fix-ccs-selection.sh            fix it
#   bash fix-ccs-selection.sh undo       put the original file back
#   bash fix-ccs-selection.sh <folder>   only touch the CCS in that folder
#   curl -fsSL <raw link> | bash              fix it, straight from the web
#   curl -fsSL <raw link> | bash -s -- undo   undo it, straight from the web
#
# Why it is safe to stop, kill or re-run this at any moment:
#   - All work happens on a private copy. CCS's file is only ever changed by one
#     atomic rename, so it is always either fully original or fully fixed.
#   - There is no state file. Each run looks at the real file and does what is
#     still missing, so running it twice, or after a crash, simply finishes.
#   - The original is saved, verified, before the fix goes in, and is never
#     overwritten once it is good. A damaged or deleted CCS file is restored
#     from it.
#   - A damaged copy of this file refuses to run at all.

# Run from a pipe (curl ... | bash): bash has only read up to the end of this
# block, the rest is still waiting on stdin. Save it and run the saved copy, so a
# dropped connection can not run half a script. That copy checks its own
# fingerprint before it does anything.
case "$0" in
sh | bash | zsh | dash | */sh | */bash | */zsh | */dash | -*)
	if [ -t 0 ]; then
		echo "Please run me like this: bash fix-ccs-selection.sh"
		return 1 2>/dev/null || exit 1
	fi
	CCS_FIX_TMP=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ccs-fix.XXXXXX") || exit 1
	trap '/bin/rm -rf "$CCS_FIX_TMP"' 0 1 2 15
	/bin/cat >"$CCS_FIX_TMP/fix-ccs-selection.sh"
	IFS= read -r CCS_FIX_FIRST <"$CCS_FIX_TMP/fix-ccs-selection.sh"
	if [ "$CCS_FIX_FIRST" = "# ---- fingerprint starts here ----" ]; then
		/bin/bash "$CCS_FIX_TMP/fix-ccs-selection.sh" "$@" </dev/null
		exit $?
	fi
	# Only bash leaves the rest on stdin. Others read ahead, and what is left is
	# a random part of this file, which must never run.
	echo "The download broke, or this shell is not bash. CCS was not touched."
	echo "Please run the line again, and make sure it ends with: | bash"
	exit 1
	;;
esac
# ---- fingerprint starts here ----

# Run in plain bash with a clean environment, whatever started us. Aliases,
# Homebrew tools or ZIPOPT-style variables must not change how this behaves.
if [ -z "$BASH_VERSION" ] || shopt -qo posix 2>/dev/null; then exec /bin/bash "$0" "$@"; fi
if [ -z "${CCS_FIX_CLEAN:-}" ]; then
	exec /usr/bin/env -i CCS_FIX_CLEAN=1 HOME="$HOME" USER="${USER:-}" TERM="${TERM:-xterm-256color}" \
		NO_COLOR="${NO_COLOR:-}" PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C /bin/bash "$0" "$@"
fi

# Pasting this file into an editor can slip stray key codes into it. Compare a
# fingerprint first, before anything that can change anything is even read.
# Spaces and blank lines do not count, so harmless reformatting still runs.
CHECKSUM=4031252497
if [ "$(sed -n '/^# ---- fingerprint starts here ----$/,$p' "$0" | grep -v '^[[:space:]]*CHECKSUM=' | tr -d ' \t\r\n' | cksum | cut -d' ' -f1)" != "$CHECKSUM" ]; then
	[ -t 1 ] && printf '\033[1;38;5;203m'
	printf '\n  ✋ This copy of me got damaged, so I stopped.\n'
	[ -t 1 ] && printf '\033[0m'
	printf '  CCS was not touched.\n'
	printf '  This usually happens when I get pasted into an editor.\n'
	printf '  Get the original fix-ccs-selection.sh file and run that one.\n'
	printf '  Used the curl line? Just run it again.\n\n'
	exit 1
fi

CLASS=org/eclipse/swt/graphics/TextLayout.class
OLD_HEX=" 06 41 df ff ff ff c0 00 00"  # CONSTANT_Double 2147483647.0 (0x7fffffff)
NEW_BYTES='\x53\x12\xd0\x00\x00'       # turns that entry into 5000000.0
NEW_BYTES_SKIP=2                       # tag and first byte stay the same
NEW_BYTES_COUNT=5
BACKUP_NAME=swt-tahoe-backup
WORK_PREFIX=.ccs-fix-work
HOME_DIR=${CCS_FIX_HOME:-$HOME}

WORK=""
PARTIAL=""
STEP=""
MODE=fix
ONLY_ROOT=""
COUNT_FIXED=0
COUNT_OK=0
COUNT_FAILED=0

# ---------------------------------------------------------------- output ----

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	TTY=1
	OFF=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m' CLEAR=$'\r\033[K'
	GREEN=$'\033[38;5;42m' BLUE=$'\033[38;5;39m' YELLOW=$'\033[38;5;220m'
	RED=$'\033[38;5;203m' PINK=$'\033[38;5;213m'
else
	TTY=""
	OFF="" BOLD="" DIM="" CLEAR="" GREEN="" BLUE="" YELLOW="" RED="" PINK=""
fi

rainbow_line() {
	local c line=""
	if [ -n "$TTY" ]; then
		for c in 196 202 208 214 220 226 190 154 118 82 48 49 50 51 45 39 33 27 63 99 135 171 207 213; do
			line="$line"$'\033[38;5;'"$c"'m━━'
		done
		printf '  %s%s\n' "$line" "$OFF"
	else
		printf '  ================================================\n'
	fi
}

banner() {
	echo
	rainbow_line
	printf '  %s✨ CCS Selection Fixer%s\n' "$BOLD$PINK" "$OFF"
	printf '  %s%s%s\n' "$DIM" "$1" "$OFF"
	rainbow_line
	printf '  %sYou can stop me any time. Nothing will break. Just run me again.%s\n\n' "$DIM" "$OFF"
}

section() { printf '  %s📦 %s%s\n' "$BOLD$BLUE" "$1" "$OFF"; }

step() {
	STEP=$1
	[ -n "$TTY" ] && printf '     %s➜%s %s...' "$BLUE" "$OFF" "$STEP"
}

step_ok() { printf '%s     %s✔%s %s\n' "$CLEAR" "$GREEN" "$OFF" "${1:-$STEP}"; STEP=""; }
step_warn() { printf '%s     %s!%s %s\n' "$CLEAR" "$YELLOW" "$OFF" "$1"; STEP=""; }
step_fail() { printf '%s     %s✖%s %s\n' "$CLEAR" "$RED" "$OFF" "$1"; STEP=""; }

big_box() { # color, title, lines...
	local color=$1 title=$2
	shift 2
	printf '\n  %s%s%s\n' "$BOLD$color" "$title" "$OFF"
	while [ $# -gt 0 ]; do
		printf '  %s\n' "$1"
		shift
	done
	echo
}

# -------------------------------------------------------- staying tidy ------

cleanup() {
	[ -n "$WORK" ] && rm -rf -- "$WORK"
	[ -n "$PARTIAL" ] && rm -f -- "$PARTIAL"
	WORK=""
	PARTIAL=""
}

stopped() {
	trap '' INT TERM HUP
	cleanup
	[ -n "$STEP" ] && printf '%s' "$CLEAR"
	big_box "$YELLOW" "✋ Okay, I stopped." \
		"Nothing is broken. CCS still works." \
		"Run me again any time and I will finish the job."
	exit 130
}

trap stopped INT TERM HUP
trap cleanup EXIT
trap '' PIPE  # a closed Terminal window must not stop the cleanup

# Leftovers from a run that was killed outright. A live run's folder is skipped.
sweep_stale() { # dir
	local item pid
	for item in "$1/$WORK_PREFIX".* "$1"/*.partial.*; do
		[ -e "$item" ] || continue
		pid=${item##*.}
		case $pid in '' | *[!0-9]*) continue ;; esac
		[ "$pid" = "$$" ] && continue
		kill -0 "$pid" 2>/dev/null || rm -rf -- "$item"
	done
}

# ------------------------------------------------------ looking at a jar ----

constant_info() { # reads a class on stdin, prints "<count> <byte offset>"
	od -An -v -tx1 | tr -s ' \n\t' ' ' | awk -v p="$OLD_HEX" '
		{ i = index($0, p); n = gsub(p, "&"); print n + 0, (i - 1) / 3; seen = 1 }
		END { if (!seen) print 0, 0 }'
}

classify() { # jar -> MISSING, BROKEN, ORIGINAL, FIXED or UNKNOWN
	local jar=$1 count
	[ -f "$jar" ] || { echo MISSING; return; }
	unzip -tqq "$jar" >/dev/null 2>&1 || { echo BROKEN; return; }
	unzip -l "$jar" "$CLASS" >/dev/null 2>&1 || { echo BROKEN; return; }
	count=$(unzip -p "$jar" "$CLASS" 2>/dev/null | constant_info | cut -d' ' -f1)
	case $count in
		0) echo FIXED ;;
		1) echo ORIGINAL ;;
		*) echo UNKNOWN ;;
	esac
}

entry_list() { # jar, out: "crc name" of everything except the files we change
	unzip -v "$1" 2>/dev/null | awk -v class="$CLASS" '
		NF == 8 && length($7) == 8 && $8 != class && $8 !~ /^META-INF\/[^\/]*\.(SF|RSA|DSA|EC)$/ { print $7, $8 }
	' | sort >"$2"
}

# ------------------------------------------------------ changing a jar ------

copy_mode() { # from, to
	local mode owner
	mode=$(stat -f %Lp "$1" 2>/dev/null) && chmod "$mode" "$2" 2>/dev/null
	[ "$(id -u)" = 0 ] && owner=$(stat -f %u:%g "$1" 2>/dev/null) && chown "$owner" "$2" 2>/dev/null
	return 0
}

swap_in() { # prepared file, live jar, file to copy permissions from
	copy_mode "$3" "$1"
	sync
	mv -f -- "$1" "$2"
}

build_fixed_jar() { # original jar -> $WORK/staged.jar
	local source=$1 staged="$WORK/staged.jar" info offset signatures
	cp -- "$source" "$staged" || return 1
	chmod u+w "$staged" || return 1
	mkdir -p "$WORK/new/${CLASS%/*}" || return 1
	unzip -p "$staged" "$CLASS" >"$WORK/new/$CLASS" 2>/dev/null || return 1
	info=$(constant_info <"$WORK/new/$CLASS")
	[ "${info%% *}" = 1 ] || return 1
	offset=${info##* }
	printf "$NEW_BYTES" | dd of="$WORK/new/$CLASS" bs=1 seek=$((offset + NEW_BYTES_SKIP)) conv=notrunc 2>/dev/null || return 1
	(cd "$WORK/new" && zip -q -X "$staged" "$CLASS") || return 1
	# The Eclipse signature can not match a changed class, so it has to go.
	signatures=$(unzip -Z1 "$staged" | grep -E '^META-INF/[^/]+\.(SF|RSA|DSA|EC)$')
	if [ -n "$signatures" ]; then
		zip -q -d "$staged" $signatures || return 1
	fi
}

verify_fixed_jar() { # original jar: is $WORK/staged.jar exactly original + the fix?
	local source=$1 staged="$WORK/staged.jar" before="$WORK/before.class" after="$WORK/after.class"
	[ "$(classify "$staged")" = FIXED ] || return 1
	unzip -p "$source" "$CLASS" >"$before" 2>/dev/null || return 1
	unzip -p "$staged" "$CLASS" >"$after" 2>/dev/null || return 1
	[ "$(wc -c <"$before")" = "$(wc -c <"$after")" ] || return 1
	[ "$(cmp -l "$before" "$after" | wc -l | tr -d ' ')" = "$NEW_BYTES_COUNT" ] || return 1
	entry_list "$source" "$WORK/entries.before"
	entry_list "$staged" "$WORK/entries.after"
	[ -s "$WORK/entries.after" ] && cmp -s "$WORK/entries.before" "$WORK/entries.after"
}

save_backup() { # verified original jar, backup path
	PARTIAL="$2.partial.$$"
	cp -p -- "$1" "$PARTIAL" && cmp -s "$1" "$PARTIAL" && sync && mv -f -- "$PARTIAL" "$2"
	local result=$?
	[ "$result" = 0 ] || rm -f -- "$PARTIAL"
	PARTIAL=""
	return $result
}

restore_backup() { # backup path, live jar
	cp -- "$1" "$WORK/staged.jar" && cmp -s "$1" "$WORK/staged.jar" && swap_in "$WORK/staged.jar" "$2" "$1"
}

# ---------------------------------------------------------- the two jobs ----

fix_jar() { # plugins dir, backup dir, jar name
	local live="$1/$3" backup="$2/$3" source="$WORK/source.jar" live_state backup_state

	step "Looking at your CCS"
	# Everything below works from this private snapshot, so another copy of this
	# script changing the live file half way through can not get mixed in.
	if [ -e "$live" ] && ! cp -p -- "$live" "$source"; then
		step_fail "Could not read the CCS file, so I did not touch it. Is your disk full?"
		return 1
	fi
	live_state=$(classify "$source")
	backup_state=$(classify "$backup")

	case $live_state in
		FIXED)
			step_ok "Already fixed! Nothing to do."
			[ "$backup_state" = ORIGINAL ] || step_warn "No safety copy here, so 'undo' will not work. CCS is fine."
			COUNT_OK=$((COUNT_OK + 1))
			return 0
			;;
		ORIGINAL) step_ok "Found the file that needs fixing" ;;
		MISSING | BROKEN)
			if [ "$backup_state" != ORIGINAL ]; then
				step_fail "A CCS file is damaged and there is no safety copy to repair it."
				printf '       %sPlease reinstall CCS, then run me again.%s\n' "$DIM" "$OFF"
				return 1
			fi
			step "Repairing a damaged CCS file"
			if ! restore_backup "$backup" "$live" || ! cp -p -- "$backup" "$source"; then
				step_fail "Could not repair the file. Is your disk full?"
				return 1
			fi
			step_ok "Repaired a damaged CCS file from the safety copy"
			;;
		*)
			step_fail "This CCS looks different from what I know, so I did not touch it."
			return 1
			;;
	esac

	if [ "$backup_state" = ORIGINAL ]; then
		step_ok "Safety copy is already saved"
	else
		step "Saving a safety copy"
		if ! save_backup "$source" "$backup"; then
			step_fail "Could not save a safety copy, so I did not touch CCS. Is your disk full?"
			return 1
		fi
		step_ok "Saved a safety copy"
	fi

	step "Preparing the fix"
	if ! build_fixed_jar "$source"; then
		step_fail "Could not prepare the fix, so I did not touch CCS. Is your disk full?"
		return 1
	fi
	step_ok "Prepared the fix"

	step "Double-checking the fix"
	if ! verify_fixed_jar "$source"; then
		step_fail "The fix did not pass my check, so I did not touch CCS."
		return 1
	fi
	step_ok "Double-checked the fix"

	step "Putting the fix in"
	if ! swap_in "$WORK/staged.jar" "$live" "$source" || [ "$(classify "$live")" != FIXED ]; then
		step_fail "Could not put the fix in. Run me again."
		return 1
	fi
	step_ok "Fix is in!"
	COUNT_FIXED=$((COUNT_FIXED + 1))
}

undo_jar() { # plugins dir, backup dir, jar name
	local live="$1/$3" backup="$2/$3"

	step "Looking for the safety copy"
	if [ "$(classify "$backup")" != ORIGINAL ]; then
		step_fail "No good safety copy here, so I can not undo. Reinstall CCS to go back."
		return 1
	fi
	step_ok "Found the safety copy"

	if cmp -s "$live" "$backup"; then
		step_ok "CCS already has the original file. Nothing to do."
		COUNT_OK=$((COUNT_OK + 1))
		return 0
	fi

	step "Putting the original file back"
	if ! restore_backup "$backup" "$live"; then
		step_fail "Could not put the original back. Is your disk full?"
		return 1
	fi
	step_ok "Original file is back"
	COUNT_FIXED=$((COUNT_FIXED + 1))
}

# --------------------------------------------------------------- finding ----

find_plugin_dirs() {
	local root
	# A folder given by hand means that folder only, so undo can not reach further.
	if [ -n "$ONLY_ROOT" ]; then
		set -- "$ONLY_ROOT"
	else
		set -- /Applications/ti "$HOME_DIR/ti"
	fi
	for root in "$@"; do
		[ -d "$root" ] || continue
		find "$root/" -maxdepth 8 -type d -name plugins 2>/dev/null
	done | sed 's://*:/:g' | sort -u | while IFS= read -r dir; do
		set -- "$dir"/org.eclipse.swt_*.jar
		[ -e "$1" ] && printf '%s\n' "$dir"
	done
}

install_root() { # plugins dir
	case $1 in
		*/ccs/eclipse/*) printf '%s\n' "${1%%/ccs/eclipse/*}" ;;
		*) printf '%s\n' "${1%/plugins}" ;;
	esac
}

jar_names() { # plugins dir, backup dir: every SWT jar there, or that should be there
	local jar
	for jar in "$1"/org.eclipse.swt.cocoa.macosx*.jar "$2"/org.eclipse.swt.cocoa.macosx*.jar; do
		[ -f "$jar" ] && printf '%s\n' "${jar##*/}"
	done | sort -u
}

can_write() { # dir
	local probe="$1/$WORK_PREFIX.$$"
	mkdir "$probe" 2>/dev/null && rmdir "$probe" 2>/dev/null
}

need_admin() { # all plugin dirs on stdin: does anything need more rights?
	local dir root
	while IFS= read -r dir; do
		root=$(install_root "$dir")
		can_write "$dir" || return 0
		if [ -d "$root/$BACKUP_NAME" ]; then
			can_write "$root/$BACKUP_NAME" || return 0
		else
			can_write "$root" || return 0
		fi
	done
	return 1
}

ask_for_admin() {
	if [ "$(id -u)" = 0 ]; then
		big_box "$RED" "✖ Your Mac is blocking me." \
			"Open System Settings > Privacy & Security > App Management." \
			"Turn on Terminal. Do the same under Full Disk Access." \
			"Then run me again. Nothing was changed."
		exit 1
	fi
	printf '  %s🔑 CCS is locked, so your Mac needs your password.%s\n' "$BOLD$YELLOW" "$OFF"
	printf '  %sType it and press Enter. The letters stay invisible. That is normal!%s\n\n' "$DIM" "$OFF"
	if ! sudo -v; then
		big_box "$RED" "✖ That did not work." \
			"You need the password of an admin on this Mac." \
			"Run me again to retry. Nothing was changed."
		exit 1
	fi
	exec sudo /usr/bin/env CCS_FIX_CLEAN=1 CCS_FIX_HOME="$HOME_DIR" HOME="$HOME" TERM="$TERM" NO_COLOR="${NO_COLOR:-}" \
		PATH="$PATH" LC_ALL=C /bin/bash "$0" "$@"
}

# ------------------------------------------------------------------ main ----

for arg in "$@"; do
	case $arg in
		undo | --undo | -u | UNDO | Undo) MODE=undo ;;
		*)
			if [ -d "$arg" ]; then
				ONLY_ROOT=$arg
			elif [ "$arg" != "$0" ]; then
				printf '  %s! I do not know "%s", so I will ignore it.%s\n' "$YELLOW" "$arg" "$OFF"
			fi
			;;
	esac
done

if [ "$(uname -s)" != Darwin ]; then
	big_box "$YELLOW" "! This is not a Mac." "This bug only happens on a Mac, so there is nothing to fix here."
	exit 1
fi

if [ "$MODE" = undo ]; then
	banner "Putting CCS back the way it was"
else
	banner "Makes selected text show up in Code Composer Studio"
fi

PLUGIN_DIRS=$(find_plugin_dirs)
if [ -z "$PLUGIN_DIRS" ]; then
	if [ -n "$ONLY_ROOT" ]; then
		searched="I looked in the folder you gave me."
	else
		searched="I looked in /Applications/ti and in the ti folder in your home."
	fi
	big_box "$YELLOW" "🔍 I could not find Code Composer Studio." \
		"$searched" \
		"If yours is somewhere else, run me again and drag its folder in after my name." \
		"CCS 20 and newer is built differently and does not need this fix."
	exit 1
fi

if printf '%s\n' "$PLUGIN_DIRS" | need_admin; then
	ask_for_admin "$@"
fi

while IFS= read -r plugins; do
	root=$(install_root "$plugins")
	backup_dir="$root/$BACKUP_NAME"
	section "${root##*/}"
	sweep_stale "$plugins"
	sweep_stale "$backup_dir"

	names=$(jar_names "$plugins" "$backup_dir")
	if [ -z "$names" ]; then
		step_warn "This one has no file for Mac to fix. Skipping it."
		echo
		continue
	fi

	[ -d "$backup_dir" ] || mkdir -p "$backup_dir"
	WORK="$plugins/$WORK_PREFIX.$$"
	while IFS= read -r name; do
		rm -rf -- "$WORK"
		if ! mkdir "$WORK"; then
			step_fail "Could not start working here."
			COUNT_FAILED=$((COUNT_FAILED + 1))
			continue
		fi
		if [ "$MODE" = undo ]; then
			undo_jar "$plugins" "$backup_dir" "$name" || COUNT_FAILED=$((COUNT_FAILED + 1))
		else
			fix_jar "$plugins" "$backup_dir" "$name" || COUNT_FAILED=$((COUNT_FAILED + 1))
		fi
	done <<<"$names"
	cleanup
	echo
done <<<"$PLUGIN_DIRS"

if [ "$COUNT_FAILED" -gt 0 ]; then
	big_box "$RED" "✖ Something went wrong." \
		"CCS was not left half done. Read the red line above, then run me again."
	exit 1
fi

if [ "$COUNT_FIXED" -eq 0 ] && [ "$COUNT_OK" -eq 0 ]; then
	big_box "$YELLOW" "🔍 I found CCS, but it has no file for Mac to fix." "Nothing was changed."
	exit 1
fi

if [ "$MODE" = undo ]; then
	if [ "$COUNT_FIXED" -gt 0 ] && pgrep -x ccstudio >/dev/null 2>&1; then
		big_box "$GREEN" "✅ Undo finished!" "Close Code Composer Studio and open it again."
	else
		big_box "$GREEN" "✅ Undo finished!" "CCS is back to how it was."
	fi
elif [ "$COUNT_FIXED" -eq 0 ]; then
	big_box "$GREEN" "🎉 All good! CCS is already fixed." "You do not need to do anything."
elif pgrep -x ccstudio >/dev/null 2>&1; then
	big_box "$GREEN" "🎉 Fixed!" \
		"${BOLD}One last thing:${OFF} CCS is still open." \
		"Close Code Composer Studio and open it again. Then the fix works."
else
	big_box "$GREEN" "🎉 Fixed!" "Open Code Composer Studio and select some text. You will see it now!"
fi
exit 0
