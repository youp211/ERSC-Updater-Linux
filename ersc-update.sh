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
# Version: 2.0
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
readonly TEMP_ZIP_PATH="/tmp/ersc_update.zip"

# --- Helper Functions ---

# Prints a formatted informational message.
log_info() {
    echo -e "\n[INFO] $1" >&2
}

# Prints a formatted error message to stderr and exits the script.
die() {
    echo -e "\n[ERROR] $1" >&2
    echo "[FATAL] Script aborted." >&2
    exit 1
}

# --- Core Functions ---

# Checks if the script is being run as root and exits if it is.
check_not_root() {
    if [[ "$EUID" -eq 0 ]]; then
        die "This script cannot be run as root. Please run it as your normal user."
    fi
}

# Finds the Elden Ring 'Game' directory for standard and Flatpak Steam installs.
find_game_directory() {
    log_info "Searching for Elden Ring installation directory..."

    # Define potential installation paths
    local flatpak_path="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/ELDEN RING/Game"
    local native_path="$HOME/.steam/steam/steamapps/common/ELDEN RING/Game"

    if [[ -d "$flatpak_path" ]]; then
        echo "$flatpak_path"
        log_info "Flatpak Steam installation detected."
    elif [[ -d "$native_path" ]]; then
        echo "$native_path"
        log_info "Native Steam installation detected."
    else
        die "Could not find Elden Ring 'Game' directory at either standard or Flatpak locations."
    fi
}

# Downloads the latest release from the GitHub repository.
download_latest_release() {
    log_info "Finding latest Seamless Co-op release from GitHub..."

    local download_url
    if ! download_url=$(
        # Retrieve information on the latest mod release from the GitHub API
        curl --silent --fail "$REPO_API_URL" |
        # Parse the JSON API response and find the download URL
        jq --raw-output --exit-status '
            [
	        .assets[] |
	        select(
	            .name |
	            test("^Seamless\\.Co-op\\..*\\.zip$")
	        )
	    ] | first |
	    .browser_download_url'
    ) ; then
        die "Could not find a download URL for 'Seamless.Co-op.*.zip'. The GitHub API response may have changed."
    fi

    log_info "Downloading from: $download_url"
    # Download the file to the specified path, overwriting if it exists.
    wget -qO "$TEMP_ZIP_PATH" "$download_url" || die "Download failed. Check your internet connection or the URL."

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
    if [[ ! -f "$backup_file" ]]; then
        log_info "Creating initial backup of '$settings_file'..."
        mv -v "$settings_file" "$backup_file" || die "Failed to create initial settings backup."
        return
    fi

    # If a backup exists, compare it with the current settings.
    if ! diff -q "$backup_file" "$settings_file" >/dev/null; then
        clear
        echo "Your current settings file is different from your backup."
        echo
        echo "--- Differences (Backup vs. Current) ---"
        # Use diff with -y for side-by-side comparison. '|| true' prevents script exit if files differ.
        diff -y --suppress-common-lines "$backup_file" "$settings_file" || true
        echo "----------------------------------------"
        echo

        while true; do
            read -p "Do you want to replace your backup with your current settings? (y/n) " yn
            case "$yn" in
                [Yy]*)
                    log_info "Updating settings backup..."
                    mv -v "$settings_file" "$backup_file" || die "Failed to update settings backup."
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

    # If the original .exe exists, it means this is the first run or a restore.
    if [[ -f "$original_exe" ]]; then
        log_info "Backing up original '$original_exe' to '$backup_exe'..."
        mv -v "$original_exe" "$backup_exe" || die "Failed to back up original executable."
    elif [[ ! -f "$backup_exe" ]]; then
        # This is a critical error: neither the original nor a backup exists.
        die "Cannot find '$original_exe' or '$backup_exe'. Is this the correct game directory?"
    else
        log_info "Backup '$backup_exe' already exists."
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

# Removes the temporary downloaded zip file.
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f "$TEMP_ZIP_PATH"
    log_info "Cleanup complete."
}

# --- Main Execution ---

main() {
    clear
    echo "--- Elden Ring Seamless Co-op Updater for Linux ---"

    check_not_root

    local game_dir
    game_dir=$(find_game_directory)

    # Change to the game directory to make all file operations relative and simple.
    cd "$game_dir" || die "Could not change to game directory: $game_dir"
    log_info "Operating in game directory: $(pwd)"

    download_latest_release

    # This must be done BEFORE unzipping, as unzip will overwrite the current settings.
    manage_settings_backup

    install_mod_files

    # This must be done AFTER unzipping.
    backup_and_replace_executable

    # This must be done AFTER the new mod files are in place.
    restore_settings

    cleanup

    log_info "Update complete! You can now launch Elden Ring via Steam."
    echo "-----------------------------------------------------"
}

# Run the main function, passing all script arguments to it.
main "$@"
