#!/bin/bash

# ==============================================================================
# Elden Ring Seamless Co-op Updater for Linux
#
# Description:
# This script automates updating the "Elden Ring Seamless Co-op" mod on Linux.
# It automatically finds the latest release from GitHub, downloads it, detects
# the Elden Ring installation path (for both standard and Flatpak Steam),
# backs up existing mod settings, and installs the new files.
#
# Author: youp211
# Version: 2.3
# ==============================================================================

# --- Script Configuration ---

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipelines return the exit status of the last command to fail, not the last command.
set -o pipefail

# --- Global Variables ---
readonly REPO_API_URL="https://api.github.com/repos/LukeYui/EldenRingSeamlessCoopRelease/releases/latest"
# Elden Ring's Steam App ID, used to confirm a library actually contains the game.
readonly ELDEN_RING_APP_ID="1245620"
# Created securely at runtime via mktemp (see main); populated before first use.
TEMP_ZIP_PATH=""
# Path (relative to the game dir) of the mod settings file and its backup.
readonly SETTINGS_FILE="SeamlessCoop/ersc_settings.ini"
readonly SETTINGS_BACKUP="ersc_settings.ini.backup"

# Co-op password handling, set from command-line flags (see parse_args).
#   prompt  - default: ask the user interactively
#   migrate - keep the password from the existing installation, no prompt
#   set     - use the password given with --password, no prompt
#   skip    - leave the password untouched, no prompt
PASSWORD_MODE="prompt"
NEW_PASSWORD=""
# Password found in the existing installation before the update (may be empty).
EXISTING_PASSWORD=""

# --- Helper Functions ---

# Prints a formatted informational message.
log_info() {
    echo -e "\n[INFO] $1" >&2
}

# Prints a formatted warning message to stderr without exiting.
log_warn() {
    echo -e "\n[WARN] $1" >&2
}

# Prints a formatted error message to stderr and exits the script.
die() {
    echo -e "\n[ERROR] $1" >&2
    echo "[FATAL] Script aborted." >&2
    exit 1
}

# Prints command-line usage.
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Updates the Elden Ring Seamless Co-op mod. With no options, you are asked
whether to keep your existing co-op password or enter a new one.

Options:
  -m, --migrate-password   Keep the co-op password from your existing install
                           without asking.
  -p, --password PASSWORD  Set the co-op password to PASSWORD without asking.
      --skip-password      Do not ask about or change the co-op password.
  -h, --help               Show this help and exit.
EOF
}

# Parses command-line arguments into the PASSWORD_MODE / NEW_PASSWORD globals.
parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -m|--migrate-password)
                PASSWORD_MODE="migrate"
                ;;
            -p|--password)
                (( $# >= 2 )) || die "Option '$1' requires a password argument."
                PASSWORD_MODE="set"
                NEW_PASSWORD="$2"
                shift
                ;;
            --password=*)
                PASSWORD_MODE="set"
                NEW_PASSWORD="${1#*=}"
                ;;
            --skip-password)
                PASSWORD_MODE="skip"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "Unknown option: $1"
                ;;
        esac
        shift
    done

    if [[ "$PASSWORD_MODE" == "set" ]]; then
        validate_password "$NEW_PASSWORD" || die "Invalid password given with --password."
    fi
}

# Returns success if the password can be safely written to the settings file.
validate_password() {
    local pw="$1"
    if [[ -z "$pw" ]]; then
        echo "The password cannot be empty." >&2
        return 1
    fi
    if [[ "$pw" == *$'\n'* || "$pw" == *$'\r'* ]]; then
        echo "The password cannot contain line breaks." >&2
        return 1
    fi
    return 0
}

# Prints the co-op password stored in the given settings file (empty if none).
read_password() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    # Match 'cooppassword = value', tolerating spaces and Windows line endings.
    sed -nE 's/^[[:space:]]*cooppassword[[:space:]]*=[[:space:]]?(.*)$/\1/p' "$file" \
        | tr -d '\r' | head -n 1
}

# Writes the co-op password into the given settings file, preserving the rest of
# the file (including Windows line endings). Adds the key if it is missing.
write_password() {
    local file="$1" pw="$2" tmp
    [[ -f "$file" ]] || return 0
    tmp="$(mktemp "${file}.XXXXXX")" || die "Failed to create a temporary file next to '$file'."
    local has_key=0
    grep -qE '^[[:space:]]*cooppassword[[:space:]]*=' "$file" && has_key=1
    # The password is passed through the environment so no characters in it need
    # escaping (awk -v would interpret backslashes).
    if ! ERSC_PW="$pw" awk -v has_key="$has_key" '
        BEGIN { pw = ENVIRON["ERSC_PW"]; done = 0; eol = "" }
        {
            cr = (sub(/\r$/, "") ? "\r" : "")
            if (NR == 1) eol = cr
            if (!done && has_key && $0 ~ /^[[:space:]]*cooppassword[[:space:]]*=/) {
                print "cooppassword = " pw cr; done = 1; next
            }
            print $0 cr
            # Key missing: insert it directly under the [PASSWORD] section header.
            if (!done && !has_key && $0 ~ /^[[:space:]]*\[PASSWORD\][[:space:]]*$/) {
                print "cooppassword = " pw cr; done = 1
            }
        }
        END {
            # Neither the key nor the section exists: append both.
            if (!done) {
                print "[PASSWORD]" eol
                print "cooppassword = " pw eol
            }
        }' "$file" > "$tmp"; then
        rm -f "$tmp"
        die "Failed to update the password in '$file'."
    fi
    # Keep the original file permissions, then replace it atomically.
    chmod --reference="$file" "$tmp" 2>/dev/null || true
    mv "$tmp" "$file" || { rm -f "$tmp"; die "Failed to update the password in '$file'."; }
}

# Remembers the password from the existing installation, before the new mod
# files overwrite the settings. Prefers the live settings file over the backup.
capture_existing_password() {
    EXISTING_PASSWORD="$(read_password "$SETTINGS_FILE")"
    if [[ -z "$EXISTING_PASSWORD" ]]; then
        EXISTING_PASSWORD="$(read_password "$SETTINGS_BACKUP")"
    fi
}

# Asks the user for a new password until a valid one is entered or the input is
# left empty. Prints the password on stdout (empty means "don't change").
prompt_new_password() {
    local pw
    while true; do
        read -rp "Enter a co-op password (leave empty to keep the current setting): " pw
        [[ -z "$pw" ]] && return 0
        if validate_password "$pw"; then
            printf '%s\n' "$pw"
            return 0
        fi
    done
}

# Decides which co-op password to use (from flags, or by asking the user) and
# writes it into the installed settings file and its backup.
configure_password() {
    [[ "$PASSWORD_MODE" == "skip" ]] && return 0
    log_info "Configuring co-op password..."

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        log_warn "'$SETTINGS_FILE' not found. Skipping password setup."
        return 0
    fi

    local current chosen=""
    current="$(read_password "$SETTINGS_FILE")"

    case "$PASSWORD_MODE" in
        set)
            chosen="$NEW_PASSWORD"
            ;;
        migrate)
            if [[ -z "$EXISTING_PASSWORD" ]]; then
                log_warn "No password found in the existing installation. Leaving the password unchanged."
                return 0
            fi
            chosen="$EXISTING_PASSWORD"
            ;;
        prompt)
            # Never block automated / piped runs waiting for input.
            if [[ ! -t 0 ]]; then
                log_info "Not running interactively. Leaving the password unchanged."
                return 0
            fi
            if [[ -n "$EXISTING_PASSWORD" ]]; then
                echo "Your existing installation uses the co-op password: $EXISTING_PASSWORD" >&2
                local yn
                while true; do
                    read -rp "Use the same password for multiplayer? (y/n) " yn
                    case "$yn" in
                        [Yy]*) chosen="$EXISTING_PASSWORD"; break ;;
                        [Nn]*) chosen="$(prompt_new_password)"; break ;;
                        *) echo "Please answer yes (y) or no (n)." >&2 ;;
                    esac
                done
            else
                echo "No co-op password is set. Everyone you play with must use the same password." >&2
                chosen="$(prompt_new_password)"
            fi
            ;;
    esac

    if [[ -z "$chosen" ]]; then
        log_info "Leaving the password unchanged."
        return 0
    fi

    if [[ "$chosen" == "$current" ]]; then
        log_info "Password already set. No change needed."
    else
        write_password "$SETTINGS_FILE" "$chosen"
        log_info "Password saved to '$SETTINGS_FILE'."
    fi

    # Keep the backup in sync so the next run doesn't report a settings difference
    # caused only by the password.
    if [[ -f "$SETTINGS_BACKUP" && "$(read_password "$SETTINGS_BACKUP")" != "$chosen" ]]; then
        write_password "$SETTINGS_BACKUP" "$chosen"
        log_info "Password also updated in '$SETTINGS_BACKUP'."
    fi
}

# --- Core Functions ---

# Checks if the script is being run as root and exits if it is.
check_not_root() {
    if [[ "$EUID" -eq 0 ]]; then
        die "This script cannot be run as root. Please run it as your normal user."
    fi
}

# Verifies that all required external tools are installed before doing any work.
check_dependencies() {
    local -a required=("curl" "wget" "unzip" "jq")
    local -a missing=()
    local cmd
    for cmd in "${required[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if (( ${#missing[@]} > 0 )); then
        die "Missing required tool(s): ${missing[*]}
       Install them with your package manager, e.g.:
         Debian/Ubuntu: sudo apt install ${missing[*]}
         Fedora:        sudo dnf install ${missing[*]}
         Arch:          sudo pacman -S ${missing[*]}"
    fi
}

# Collects every Steam "steamapps" library directory on this machine.
#
# Steam can spread games across multiple libraries (secondary drives, custom
# folders). Each Steam data root records these in steamapps/libraryfolders.vdf.
# We scan all known native and Flatpak roots, then parse every "path" entry so
# installs outside the default location are found too. Prints one steamapps path
# per line on stdout.
find_steam_libraries() {
    # Known Steam data roots (native variants + Flatpak). Symlinks mean several
    # of these often point at the same place; duplicates are removed later.
    local -a steam_roots=(
        "$HOME/.steam/steam"
        "$HOME/.steam/root"
        "$HOME/.local/share/Steam"
        "$HOME/.steam/debian-installation"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    )

    # Emit the canonical (symlink-resolved) path so that, e.g., the ~/.steam/steam
    # symlink and its ~/.local/share/Steam target don't show up as two installs.
    local root vdf lib
    for root in "${steam_roots[@]}"; do
        [[ -d "$root/steamapps" ]] || continue
        # The root's own steamapps is always a candidate library.
        realpath "$root/steamapps"

        # Parse additional library paths from libraryfolders.vdf, if present.
        vdf="$root/steamapps/libraryfolders.vdf"
        [[ -f "$vdf" ]] || continue
        while IFS= read -r lib; do
            [[ -n "$lib" && -d "$lib/steamapps" ]] && realpath "$lib/steamapps"
        done < <(grep -E '"path"' "$vdf" | sed -E 's/.*"path"[[:space:]]*"(.*)"$/\1/')
    done
}

# Finds the Elden Ring 'Game' directory across all Steam libraries and prints it
# on stdout. If several installs exist, the user is prompted to choose one.
find_game_directory() {
    log_info "Searching for Elden Ring installation directory..."

    # Gather unique steamapps libraries.
    local -a libraries=()
    local seen=" " sa
    while IFS= read -r sa; do
        [[ -n "$sa" ]] || continue
        case "$seen" in *" $sa "*) continue ;; esac  # skip duplicates
        seen+="$sa "
        libraries+=("$sa")
    done < <(find_steam_libraries)

    if (( ${#libraries[@]} == 0 )); then
        die "No Steam installation was found.
       Checked native (~/.steam, ~/.local/share/Steam) and Flatpak locations.
       Is Steam installed and has it been launched at least once?"
    fi

    # Look for the game in every library.
    local -a found=()
    local game
    for sa in "${libraries[@]}"; do
        game="$sa/common/ELDEN RING/Game"
        [[ -d "$game" ]] && found+=("$game")
    done

    if (( ${#found[@]} == 0 )); then
        die "Found Steam, but not the Elden Ring 'Game' directory in any library.
       Searched ${#libraries[@]} Steam librar$([[ ${#libraries[@]} -eq 1 ]] && echo y || echo ies).
       Make sure Elden Ring is installed and has been launched at least once."
    fi

    if (( ${#found[@]} == 1 )); then
        log_info "Elden Ring found at: ${found[0]}"
        printf '%s\n' "${found[0]}"
        return
    fi

    # Multiple installations — let the user pick. Menu goes to stderr so only the
    # chosen path lands on stdout (this function is called via command substitution).
    log_info "Multiple Elden Ring installations detected:"
    local i
    for i in "${!found[@]}"; do
        printf '  %d) %s\n' "$((i + 1))" "${found[$i]}" >&2
    done

    local choice
    while true; do
        read -rp "Select which installation to update [1-${#found[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#found[@]} )); then
            printf '%s\n' "${found[$((choice - 1))]}"
            return
        fi
        echo "Invalid selection. Please enter a number between 1 and ${#found[@]}." >&2
    done
}

# Warns if Steam reports a pending update for Elden Ring. Each Seamless Co-op
# release only supports one game version, so an out-of-date game will fail to
# load the mod. Must be called from inside the game directory.
check_game_up_to_date() {
    # Game dir is <steamapps>/common/ELDEN RING/Game; the manifest lives in <steamapps>.
    local manifest="../../../appmanifest_${ELDEN_RING_APP_ID}.acf"
    [[ -f "$manifest" ]] || return 0

    local state_flags
    state_flags=$(grep -E '"StateFlags"' "$manifest" | grep -oE '[0-9]+' | head -n 1 || true)
    [[ -n "$state_flags" ]] || return 0

    # StateFlags bit 2 (value 2) is Steam's "update required" flag; a fully
    # up-to-date install reports exactly 4.
    if (( state_flags & 2 )); then
        log_warn "Steam reports that Elden Ring has a pending update (StateFlags=$state_flags).
       New Seamless Co-op releases only work with the latest game version.
       Let Steam finish updating the game, then launch it."
    fi
}

# Downloads the latest release from the GitHub repository.
download_latest_release() {
    log_info "Finding latest Seamless Co-op release from GitHub..."

    # Retrieve information on the latest mod release from the GitHub API.
    local release_json
    release_json=$(curl --silent --fail --location "$REPO_API_URL") \
        || die "Could not reach the GitHub API. Check your internet connection and try again."

    # Show which version is being installed, plus its release notes. These state
    # which game version the mod supports (e.g. "Update to game ver 1.17").
    local tag notes
    tag=$(jq --raw-output '.tag_name // "unknown"' <<<"$release_json")
    notes=$(jq --raw-output '.body // ""' <<<"$release_json" | tr -d '\r' | head -n 10)
    log_info "Latest Seamless Co-op release: $tag"
    if [[ -n "$notes" ]]; then
        echo "--- Release notes ---" >&2
        echo "$notes" >&2
        echo "---------------------" >&2
    fi

    local download_url
    if ! download_url=$(
        # Parse the JSON API response and find the download URL
        jq --raw-output --exit-status '
            [
	        .assets[] |
	        select(
	            .name |
	            test("^Seamless\\.Co-op\\..*\\.zip$")
	        )
	    ] | first |
	    .browser_download_url' <<<"$release_json"
    ) ; then
        die "Could not find a download URL for 'Seamless.Co-op.*.zip'. The GitHub API response may have changed."
    fi

    log_info "Downloading from: $download_url"
    # Download to the temp path, overwriting if it exists. --show-progress keeps
    # the user informed on large downloads while -q silences the noisy log lines.
    wget -q --show-progress -O "$TEMP_ZIP_PATH" "$download_url" \
        || die "Download failed. Check your internet connection or the URL."

    log_info "Download complete."
}

# Backs up the user's existing settings file if it's different from the last backup.
manage_settings_backup() {
    log_info "Checking for existing mod settings..."
    local settings_file="SeamlessCoop/ersc_settings.ini"
    local backup_file="ersc_settings.ini.backup"

    # If there's no current settings file, there's nothing to back up.
    if [[ ! -f "$settings_file" ]]; then
        log_info "No existing '$settings_file' found to back up. Skipping."
        return
    fi

    # If a backup doesn't exist, create one from the current settings.
    # Use cp (not mv) so the live settings file survives even if the script is
    # interrupted before restore_settings runs. unzip -o overwrites it anyway.
    if [[ ! -f "$backup_file" ]]; then
        log_info "Creating initial backup of '$settings_file'..."
        cp -v "$settings_file" "$backup_file" || die "Failed to create initial settings backup."
        return
    fi

    # If a backup exists, compare it with the current settings.
    if ! diff -q "$backup_file" "$settings_file" >/dev/null; then
        clear || true
        echo "Your current settings file is different from your backup."
        echo
        echo "--- Differences (Backup vs. Current) ---"
        # Use diff with -y for side-by-side comparison. '|| true' prevents script exit if files differ.
        diff -y --suppress-common-lines "$backup_file" "$settings_file" || true
        echo "----------------------------------------"
        echo

        while true; do
            read -rp "Do you want to replace your backup with your current settings? (y/n) " yn
            case "$yn" in
                [Yy]*)
                    log_info "Updating settings backup..."
                    cp -v "$settings_file" "$backup_file" || die "Failed to update settings backup."
                    break
                    ;;
                [Nn]*)
                    log_info "Keeping existing backup. The current settings file will be overwritten by the new download."
                    break
                    ;;
                *)
                    echo "Please answer yes (y) or no (n)."
                    ;;
            esac
        done
    else
        log_info "Current settings match the backup. No action needed."
    fi
}

# Unzips the mod archive into the current directory.
install_mod_files() {
    log_info "Extracting mod files from '$TEMP_ZIP_PATH'..."
    unzip -o "$TEMP_ZIP_PATH" || die "Failed to extract mod files from zip archive."
    log_info "Extraction complete."
}

# Renames the original game executable and puts the mod launcher in its place.
backup_and_replace_executable() {
    log_info "Replacing game executable with mod launcher..."
    local original_exe="start_protected_game.exe"
    local backup_exe="${original_exe}.backup"
    local mod_launcher="ersc_launcher.exe"

    # Ensure the mod launcher from the zip exists before we do anything.
    if [[ ! -f "$mod_launcher" ]]; then
        die "Mod launcher '$mod_launcher' not found after unzipping. Cannot proceed."
    fi

    # Decide how to preserve the vanilla executable. The key invariant: once a
    # backup of the genuine game exe exists, it must NEVER be overwritten.
    # The mod launcher embeds the path to 'SeamlessCoop/ersc.dll'; the genuine
    # game exe does not. This identifies launchers from any mod version.
    if [[ -f "$backup_exe" && -f "$original_exe" ]] && ! grep -qaF "SeamlessCoop" "$original_exe"; then
        # A backup exists, but the current exe is not the mod launcher. Steam has
        # put the genuine game exe back (game patch or "Verify integrity of game
        # files"), so the old backup is from an outdated game version. Refresh it.
        log_info "'$original_exe' was restored by Steam. Refreshing '$backup_exe' with it..."
        mv -v "$original_exe" "$backup_exe" || die "Failed to refresh executable backup."
    elif [[ -f "$backup_exe" ]]; then
        # A backup already exists and the current exe (if any) is the mod
        # launcher from a previous install. Overwriting the backup with it would
        # destroy the user's only local copy of the original game executable.
        # Discard the old launcher instead and keep the real backup intact.
        log_info "Original executable already backed up as '$backup_exe'. Preserving it."
        rm -f "$original_exe"
    elif [[ -f "$original_exe" ]]; then
        # First install: the current exe is the genuine game launcher, so back it up.
        log_info "Backing up original '$original_exe' to '$backup_exe'..."
        mv -v "$original_exe" "$backup_exe" || die "Failed to back up original executable."
    else
        # Neither the original nor a backup exists — wrong directory or broken install.
        die "Cannot find '$original_exe' or '$backup_exe'. Is this the correct game directory?"
    fi

    # Now, move the mod launcher into place.
    log_info "Installing mod launcher as '$original_exe'..."
    mv -v "$mod_launcher" "$original_exe" || die "Failed to install mod launcher."
    log_info "Executable replaced successfully."
}

# Restores the backed-up settings file after the mod files have been extracted.
restore_settings() {
    log_info "Restoring settings..."
    local settings_file="SeamlessCoop/ersc_settings.ini"
    local backup_file="ersc_settings.ini.backup"

    if [[ -f "$backup_file" ]]; then
        log_info "Restoring settings from '$backup_file'..."
        # The new mod zip will have overwritten the settings, so we copy our backup over it.
        cp -v "$backup_file" "$settings_file" || die "Failed to restore settings."
    else
        log_info "No settings backup found to restore. The default mod settings will be used."
    fi
}

# Removes the temporary downloaded zip file. Registered as an EXIT trap so it
# runs on success, on error (via die), and on interruption (Ctrl-C).
cleanup() {
    [[ -n "$TEMP_ZIP_PATH" && -f "$TEMP_ZIP_PATH" ]] || return 0
    rm -f "$TEMP_ZIP_PATH"
}

# --- Main Execution ---

main() {
    parse_args "$@"

    clear || true
    echo "--- Elden Ring Seamless Co-op Updater for Linux ---"

    check_not_root
    check_dependencies

    # Create a secure, unpredictable temp file and ensure it is always removed,
    # whether the script succeeds, fails via die, or is interrupted.
    TEMP_ZIP_PATH="$(mktemp --tmpdir ersc_update.XXXXXX.zip)" \
        || die "Failed to create a temporary file."
    trap cleanup EXIT

    local game_dir
    game_dir=$(find_game_directory)

    # Change to the game directory to make all file operations relative and simple.
    cd "$game_dir" || die "Could not change to game directory: $game_dir"
    log_info "Operating in game directory: $(pwd)"

    check_game_up_to_date

    download_latest_release

    # These must be done BEFORE unzipping, as unzip will overwrite the current settings.
    capture_existing_password
    manage_settings_backup

    install_mod_files

    # This must be done AFTER unzipping.
    backup_and_replace_executable

    # This must be done AFTER the new mod files are in place.
    restore_settings

    # This must be done AFTER settings are restored, so the password isn't overwritten.
    configure_password

    # Temp file is removed automatically by the EXIT trap (see cleanup).

    log_info "Update complete! You can now launch Elden Ring via Steam."
    echo "-----------------------------------------------------"
    echo "If the mod does not load:"
    echo "  * Make sure Elden Ring is fully updated in Steam. Each mod release only"
    echo "    supports the game version named in the release notes above."
    echo "  * Clear any Elden Ring launch options left over from a manual mod install"
    echo "    (Steam > Elden Ring > Properties > General > Launch Options)."
    echo "  * Try a current Proton or GE-Proton version (Properties > Compatibility)."
    echo "-----------------------------------------------------"
}

# Run the main function, passing all script arguments to it.
main "$@"
