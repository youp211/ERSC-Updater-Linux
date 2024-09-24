#!/bin/bash

#TODO
#Comments
#Cleanup
#Sript was written very adhoc. I will improve it over time. I originally wrote this for a friend. A lot of people may find this useful... :)

#Functions:
function backupExe {
	if [ -f ./start_protected_game.exe.backup ]; then
	echo "Vanilla game exe has already been backed up... skipping"
	mv -v ./ersc_launcher.exe ./start_protected_game.exe
	elif [ -f ./start_protected_game.exe ]; then
	echo "Backing up vanilla game exe start_protected_game.exe to file start_protected_game.exe.backup"
	mv -v ./start_protected_game.exe ./start_protected_game.exe.backup
		if [ -f ./start_protected_game.exe.backup ]; then
		echo "Backup complete"
		echo "Installing ersc_launcher.exe"
		mv -v ./ersc_launcher.exe ./start_protected_game.exe
			if [ -f ./start_protected_game.exe ];then
			echo "Install complete"
			else
			echo "Error: Installation incomplete. Missing 'start_protected_game.exe' You should not have been able to get this error..."
                        echo "Fatal error. Exiting"
                        exit 1
			fi
		else
			echo "Error: Backup incomplete. You should not have been able to get this error..."
			echo "Fatal error. Exiting"
			exit 1
		fi
	
	fi
}
function backupSettings {
	if [ -f ./ersc_settings.ini.backup ];then
	INICHK=$(diff ./ersc_settings.ini.backup ./SeamlessCoop/ersc_settings.ini)
		if [ "$INICHK" != ""  ];then
			while true; do
				clear
				echo "Your settings backup is different than the current ersc_settings.ini."
				echo ""
				echo ""
				echo "Comparing: Backup File (left)		against		Current file (right)"
				diff -y  --suppress-common-lines ./ersc_settings.ini.backup ./SeamlessCoop/ersc_settings.ini
				echo ""
				echo ""
				read -p "Would you like to backup your current settings and overwrite ersc_settings.ini.backup? (y/n)" usrOption
				case $usrOption in
					[Yy]* ) mv -v ./SeamlessCoop/ersc_settings.ini ./ersc_settings.ini.backup; break;;
					[Nn]* ) echo "Proceeding without ersc_settings.ini backup."; break;;
					* ) echo "Answer yes or no bro...";;
				esac
			done
	fi
	else
	echo "ersc_settings.ini.backup does not exist..."
	echo "Automatically backing up ersc_settings.ini"
	mv -v ./SeamlessCoop/ersc_settings.ini ./ersc_settings.ini.backup
	if [ -f ./ersc_settings.ini.backup ]; then
	
		echo "ersc_settings.ini backup completed..."
	else
		echo "Error: Backup for ersc_settings.ini incomplete. You should not have been able to get this error..."
                echo "Fatal error. Exiting"
                exit 1
		fi

	fi
}
function restoreSettings {


	if [ -f ./ersc_settings.ini.backup ]; then
		echo "Restoring old settings..."
		cp -v ./ersc_settings.ini.backup ./SeamlessCoop/ersc_settings.ini
		elif [ -f ./SeamlessCoop/ersc_settings.ini ]; then
		echo "Settings restoration complete."
		else
			echo "Error: ersc_settings.ini restore incomplete. Missing the file ersc_settings.ini. You should not have been able to get this error..."
                	echo "Fatal error. Exiting"
                	exit 1
		fi
}

#Directories Check
#Currently Tested on Flatpak and Debian, and Gentoo installations. We can add more as more people use it and submit issues. THe local installation direcotry should cover most if not all distibutions of GNU/Linux

if [[ ! -d "/home/$USER/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/ELDEN\ RING/Game" && ! -d "/home/$USER/.steam/steam/steamapps/common/ELDEN RING/Game" ]]; then
  echo "Error: One or both directories do not exist."
  exit 1
fi


#Script Start

clear
echo "Elden Ring Seamless CO-OP Updater for Linux"
sleep 2
clear
cd /tmp
if [ -f /tmp/ersc.zip ]; then
echo "Removing old download of ersc..."
rm -f /tmp/ersc.zip
fi
echo "Attempting to download ERSC from https://api.github.com/repos/LukeYui/EldenRingSeamlessCoopRelease/releases/latest"
curl -s https://api.github.com/repos/LukeYui/EldenRingSeamlessCoopRelease/releases/latest \
| grep https://github.com/LukeYui/EldenRingSeamlessCoopRelease/releases/download/ |grep ersc.zip \
| cut -d : -f 2,3 \
| tr -d \" \
| wget -qi -
if [ -f /tmp/ersc.zip ]; then
echo "Download complete"
else
                        echo "Error: Download failed. Missing /tmp/ersc.zip"
                        echo "Fatal error. Exiting"
                        exit 1
			fi



#Flatpak Installation
if [ -d /home/$USER/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/ELDEN\ RING/Game ]; then
	echo "Flatpak Steam installation detected..."
	cd /home/$USER/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/ELDEN\ RING/Game
	backupSettings
	echo "Installing ersc.zip..."
	unzip -o /tmp/ersc.zip -d /home/$USER/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/ELDEN\ RING/Game/
	backupExe
	restoreSettings
fi
#Other Installation
if [ -d  /home/$USER/.steam/steam/steamapps/common/ELDEN\ RING/Game ]; then
        echo "Local Steam installation detected..."
	cd /home/$USER/.steam/steam/steamapps/common/ELDEN\ RING/Game
        backupSettings
	echo "Installing ersc.zip..."
        unzip -o /tmp/ersc.zip -d /home/$USER/.steam/steam/steamapps/common/ELDEN\ RING/Game/
	backupExe
	restoreSettings
fi
if [ -f /tmp/ersc.zip ]; then
echo "Cleaning up..."
rm -f /tmp/ersc.zip
echo "Clean up Complete."
fi
