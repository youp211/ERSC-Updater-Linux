    Elden Ring Seamless CO-OP Linux Installer and Updater
# Elden Ring Seamless Co-op Linux Updater

To set the script as executable:
This script automates the process of updating the [Elden Ring Seamless Co-op mod](https://www.nexusmods.com/eldenring/mods/510) on Linux systems. It simplifies the installation and update process by automatically detecting your Elden Ring game directory, downloading the latest mod release, backing up your existing settings, and replacing the necessary files.

## Features

** Terminal Emulator **
*   **Automatic Detection:** Finds your Elden Ring installation whether it's a native Steam install or a Flatpak Steam install.
*   **Latest Release Download:** Automatically fetches the most recent `ersc.zip` from the official GitHub repository.
*   **Settings Backup:** Preserves your `ersc_settings.ini` file, prompting you if changes are detected.
*   **Executable Management:** Backs up the original game executable and replaces it with the mod's launcher.
*   **Clean-up:** Removes temporary download files after a successful update.

Use chmod +x ./ersc-update.sh from the folder you have downloaded the script to.
## Prerequisites

Then type ./ersc-update.sh
Before running the script, ensure you have the following tools installed on your system:

* `curl`
* `wget`
* `unzip`
* `jq`

These are typically pre-installed on most Linux distributions.

## How to Use

** Desktop Environment GUI **
### 1. Download the Script

Note: The exact steps and terminology may vary slightly depending on your specific desktop environment (e.g., GNOME, KDE, MATE).
Save the `ersc-update.sh` script to a convenient location on your computer (e.g., `~/Downloads` or `~/Scripts`).


### 2. Make the Script Executable

Open the "Files" app.
The script needs executable permissions to run. Choose one of the methods below:

Navigate to the script's location.
#### Via Terminal

Right-click on the script and select "Properties."
Open your terminal, navigate to the directory where you saved the script, and run:

Go to the "Permissions" tab.
```bash
chmod +x ./ersc-update.sh
```

Check the "Allow executing file as a program" box.
#### Via Desktop Environment (GUI)

Click "Close."
*   **Note:** The exact steps and terminology may vary slightly depending on your specific desktop environment (e.g., GNOME, KDE Plasma, XFCE, MATE).

Then run the script.
*   **Example (GNOME):**
    1.  Open your file manager (e.g., "Files").
    2.  Navigate to the script's location.
    3.  Right-click on `ersc-update.sh` and select "Properties" (or "Permissions").
    4.  Go to the "Permissions" tab.
    5.  Check the box labeled "Allow executing file as a program" or similar.
    6.  Click "Close" or "OK".

### 3. Run the Script

** Other Notes **
Once the script is executable, you can run it from your terminal:

Run this script and you will not have to change steam options. Just run the game as normal and it will automatically run the elden ring seamless coop mod. If you wish to restore your game. Just run the built in steam integrity check to restore the games original executable file. Alternatively it will be in your game folder named start_protected_game.exe.backup. You can rename this back to the original exe file name start_protected_game.exe and your game will be restored.
```bash
./ersc-update.sh
```

The script will guide you through the update process with on-screen messages.

## Important Notes & Restoration

*   **No Steam Launch Options Needed:** After running this script, you do not need to change any Steam launch options. Simply launch Elden Ring as you normally would from your Steam library, and the Seamless Co-op mod will automatically load.

*   **Restoring the Original Game:** If you wish to revert to the vanilla (unmodded) Elden Ring executable, you have two options:
    *   **Steam's "Verify Integrity of Game Files":** The easiest method is to use Steam's built-in "Verify integrity of game files..." feature. This will detect the modified executable and replace it with the original.
    *   **Manual Restoration:** The script creates a backup of your original `start_protected_game.exe` named `start_protected_game.exe.backup` in your game's `Game` directory. You can manually restore it by:
        1.  Navigating to your Elden Ring `Game` directory (e.g., `~/.steam/steam/steamapps/common/ELDEN RING/Game`).
        2.  Deleting the current `start_protected_game.exe` (which is the mod launcher).
        3.  Renaming `start_protected_game.exe.backup` to `start_protected_game.exe`.

## Troubleshooting

Here are some common issues you might encounter and how to resolve them:

### 1. Script not running or "Permission denied"

*   **Issue:** When you try to run the script, you get an error like "Permission denied."
*   **Solution:** You likely forgot to make the script executable. Follow the steps in the "Make the Script Executable" section above using `chmod +x`.

### 2. "command not found" errors (e.g., `curl`, `wget`, `unzip`, `jq`)

*   **Issue:** The script exits with an error indicating a command like 
    `curl`, `wget`, `unzip`, or `jq` is not found.
*   **Solution:** These are external tools the script relies on. Ensure they are installed on your system.
    *   **Debian/Ubuntu:** `sudo apt install curl wget unzip jq`
    *   **Fedora:** `sudo dnf install curl wget unzip jq`
    *   **Arch Linux:** `sudo pacman -S curl wget unzip jq`
    *   (Adjust for your specific distribution's package manager if different.)

### 3. "Could not find Elden Ring 'Game' directory"

*   **Issue:** The script cannot locate your Elden Ring installation.
*   **Solution:**
    *   Ensure Elden Ring is installed via Steam and that you've launched it at least once.
    *   Verify the default paths the script checks:
        *   `~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/ELDEN RING/Game` (for Flatpak Steam)
        *   `~/.steam/steam/steamapps/common/ELDEN RING/Game` (for native Steam)
    *   If your installation is in a non-standard location (e.g., on a different drive or a custom Steam library folder), you might need to manually adjust the `find_game_directory` function in the script or consider adding a command-line argument for a custom path (an advanced modification).

### 4. "Download failed" or "Could not find a download URL"

*   **Issue:** The script fails to download the mod zip file.
*   **Solution:**
    *   Check your internet connection.
    *   The GitHub API might be temporarily unavailable or the repository structure for releases might have changed. Try running the script again after some time.
    *   Manually visit `https://github.com/LukeYui/EldenRingSeamlessCoopRelease/releases/latest` in your browser to see if the `ersc.zip` file is present and accessible.

### 5. Game not launching with mod after update

*   **Issue:** The script completes successfully, but the game launches vanilla or crashes.
*   **Solution:**
    *   Ensure you are launching the game directly from Steam.
    *   Verify that `start_protected_game.exe` in your game's `Game` directory is indeed the `ersc_launcher.exe` (check its size/date, or try running it directly if you have Wine installed).
    *   If you previously had other mods installed, they might be conflicting. Try a clean install of Elden Ring and then apply the Seamless Co-op mod using this script.
    *   Use Steam's "Verify integrity of game files..." feature to restore the original executable, then try running the script again.
