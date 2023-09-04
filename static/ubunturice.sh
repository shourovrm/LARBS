#!/bin/sh

# Luke's Auto Rice Boostrapping Script (LARBS)
# by Luke Smith <luke@lukesmith.xyz>
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

dotfilesrepo="https://github.com/shourovrm/archrice.git"
progsfile="https://raw.githubusercontent.com/shourovrm/LARBS/master/static/dprogs.csv"
repobranch="master"
export TERM=ansi


installpkg() {
    apt install -y "$1"
}


error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

welcomemsg() {
    echo "Welcome to Luke's Auto-Rice Bootstrapping Script!"
    echo "This script will automatically install a fully-featured Linux desktop, which I use as my main machine."
    echo "-Luke"
    echo "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings."
    echo "If it does not, the installation of some programs might fail."
    read -p "All ready? (y/n): " choice
    [ "$choice" = "y" -o "$choice" = "Y" ] || exit 1
}

### Check if the above changes are committted



getuserandpass() {
    # Prompts user for new username and password.
    echo "First, please enter a name for the user account."
    read -r name
    while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
        echo "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _."
        read -r name
    done

    echo "Enter a password for that user."
    stty -echo
    read -r pass1
    stty echo
    echo

    echo "Retype password."
    stty -echo
    read -r pass2
    stty echo
    echo

    while [ "$pass1" != "$pass2" ]; do
        echo "Passwords do not match. Enter password again."
        stty -echo
        read -r pass1
        stty echo
        echo

        echo "Retype password."
        stty -echo
        read -r pass2
        stty echo
        echo
    done
}


usercheck() {
    if id -u "$name" >/dev/null 2>&1; then
        echo "The user '$name' already exists on this system."
        echo "LARBS can install for a user already existing, but it will OVERWRITE any conflicting settings/dotfiles on the user account."
        read -p "Continue? (y/n): " choice
        [ "$choice" = "y" -o "$choice" = "Y" ] || exit 1
    fi
}

preinstallmsg() {
    echo "The rest of the installation will now be totally automated, so you can sit back and relax."
    echo "It will take some time, but when done, you can relax even more with your complete system."
    read -p "Let's go? (y/n): " choice
    [ "$choice" = "y" -o "$choice" = "Y" ] || exit 1
}

adduserandpass() {
    # Adds user `$name` with password $pass1.
    echo "Adding user \"$name\"..."
    useradd -m -s /bin/zsh "$name" >/dev/null 2>&1 ||
        usermod -a -G sudo "$name" && mkdir -p /home/"$name" && chown "$name":sudo /home/"$name"
    export repodir="/home/$name/.local/src"
    mkdir -p "$repodir"
    chown -R "$name":sudo "$(dirname "$repodir")"
    echo "$name:$pass1" | chpasswd
    unset pass1 pass2
}

refreshkeys() {
    case "$(readlink -f /sbin/init)" in
    *systemd*)
        echo "Updating package lists..."
        apt update >/dev/null 2>&1
        ;;
    *)
        echo "Updating package lists and enabling additional repositories..."
        # Add the universe repository if it's not already present
        add-apt-repository "deb http://mirror.xeonbd.com/ubuntu-archive $(lsb_release -sc) main universe restricted multiverse" -y >/dev/null 2>&1
        apt update >/dev/null 2>&1
        ;;
    esac
}

maininstall() {
    # Installs all needed programs from main repo.
    echo "Installing '$1' ($n of $total). $1 $2"
    installpkg "$1"
}


gitmakeinstall() {
    progname="${1##*/}"
    progname="${progname%.git}"
    dir="$repodir/$progname"
    echo "Installing '$progname' ($n of $total) via 'git' and 'make'. $(basename "$1") $2"
    sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
        --no-tags -q "$1" "$dir" ||
        {
            cd "$dir" || return 1
            sudo -u "$name" git pull --force origin master
        }
    cd "$dir" || exit 1

    # Special case for Neovim
    if [ "$progname" == "neovim" ]; then
        git checkout release-0.9
        make CMAKE_BUILD_TYPE=Release
    else
        make >/dev/null 2>&1
    fi

    make install >/dev/null 2>&1
    cd /tmp || return 1
}

pipinstall() {
    echo "Installing the Python package '$1' ($n of $total). $1 $2"
    [ -x "$(command -v "pip")" ] || installpkg python3-pip >/dev/null 2>&1
    yes | pip install "$1"
}


installationloop() {
    ([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
        curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
    total=$(wc -l </tmp/progs.csv)
    while IFS=, read -r tag program comment; do
        n=$((n + 1))
        echo "$comment" | grep -q "^\".*\"$" &&
            comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
        echo "Installing $program ($n of $total). $comment"
        case "$tag" in
        "G") gitmakeinstall "$program" "$comment" ;;
        "P") pipinstall "$program" "$comment" ;;
        *) maininstall "$program" "$comment" ;;
        esac
    done </tmp/progs.csv
}

putgitrepo() {
    echo "Downloading and installing config files..."
    [ -z "$3" ] && branch="master" || branch="$repobranch"
    dir=$(mktemp -d)
    [ ! -d "$2" ] && mkdir -p "$2"
    chown "$name":sudo "$dir" "$2"
    sudo -u "$name" git -C "$repodir" clone --depth 1 \
        --single-branch --no-tags -q --recursive -b "$branch" \
        --recurse-submodules "$1" "$dir"
    sudo -u "$name" cp -rfT "$dir" "$2"
}

vimplugininstall() {
    echo "Installing neovim plugins..."
    mkdir -p "/home/$name/.config/nvim/autoload"
    curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" >  "/home/$name/.config/nvim/autoload/plug.vim"
    chown -R "$name:sudo" "/home/$name/.config/nvim"
    sudo -u "$name" nvim -c "PlugInstall|q|q"
}


# install_librewolf() {
#     # Update package list and install required packages
#     apt update && apt install -y wget gnupg lsb-release apt-transport-https ca-certificates

#     # Determine the distribution or use 'focal' as a fallback
#     distro=$(if echo " una bookworm vanessa focal jammy bullseye vera uma " | grep -q " $(lsb_release -sc) "; then echo $(lsb_release -sc); else echo focal; fi)

#     # Add the LibreWolf GPG key
#     wget -O- https://deb.librewolf.net/keyring.gpg | gpg --dearmor -o /usr/share/keyrings/librewolf.gpg

#     # Add the LibreWolf APT repository
#     tee /etc/apt/sources.list.d/librewolf.sources << EOF > /dev/null
# Types: deb
# URIs: https://deb.librewolf.net
# Suites: $distro
# Components: main
# Architectures: amd64
# Signed-By: /usr/share/keyrings/librewolf.gpg

# EOF

#     # Update package list again
#     apt update

#     # Install LibreWolf
#     apt install librewolf -y
# }

# makeuserjs(){
# 	# Get the Arkenfox user.js and prepare it.
# 	arkenfox="$pdir/arkenfox.js"
# 	overrides="$pdir/user-overrides.js"
# 	userjs="$pdir/user.js"
# 	ln -fs "/home/$name/.config/firefox/larbs.js" "$overrides"
# 	[ ! -f "$arkenfox" ] && curl -sL "https://raw.githubusercontent.com/arkenfox/user.js/master/user.js" > "$arkenfox"
# 	cat "$arkenfox" "$overrides" > "$userjs"
# 	chown "$name:sudo" "$arkenfox" "$userjs"
# 	# Install the updating script.
# 	mkdir -p /usr/local/lib /etc/pacman.d/hooks
# 	cp "/home/$name/.local/bin/arkenfox-auto-update" /usr/local/lib/
# 	chown root:root /usr/local/lib/arkenfox-auto-update
# 	chmod 755 /usr/local/lib/arkenfox-auto-update
# 	# Trigger the update when needed via a pacman hook.
# 	echo "[Trigger]
# Operation = Upgrade
# Type = Package
# Target = firefox
# Target = librewolf
# Target = librewolf-bin
# [Action]
# Description=Update Arkenfox user.js
# When=PostTransaction
# Depends=arkenfox-user.js
# Exec=/usr/local/lib/arkenfox-auto-update" > /etc/pacman.d/hooks/arkenfox.hook
# }

installffaddons(){
	addonlist="ublock-origin decentraleyes istilldontcareaboutcookies vim-vixen bitwarden libredirect"
	addontmp="$(mktemp -d)"
	trap "rm -fr $addontmp" HUP INT QUIT TERM PWR EXIT
	IFS=' '
	sudo -u "$name" mkdir -p "$pdir/extensions/"
	for addon in $addonlist; do
		addonurl="$(curl --silent "https://addons.mozilla.org/en-US/firefox/addon/${addon}/" | grep -o 'https://addons.mozilla.org/firefox/downloads/file/[^"]*')"
		file="${addonurl##*/}"
		sudo -u "$name" curl -LOs "$addonurl" > "$addontmp/$file"
		id="$(unzip -p "$file" manifest.json | grep "\"id\"")"
		id="${id%\"*}"
		id="${id##*\"}"
		sudo -u "$name" mv "$file" "$pdir/extensions/$id.xpi"
	done
	# Fix a Vim Vixen bug with dark mode not fixed on upstream:
	sudo -u "$name" mkdir -p "$pdir/chrome"
	[ ! -f  "$pdir/chrome/userContent.css" ] && sudo -u "$name" echo ".vimvixen-console-frame { color-scheme: light !important; }
#category-more-from-mozilla { display: none !important }" > "$pdir/chrome/userContent.css"
}

finalize() {
    echo "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place."
    echo ""
    echo "To run the new graphical environment, log out and log back in as your new user, then run the command 'startx' to start the graphical environment (it will start automatically in tty1)."
    echo ""
    echo "- RMS"
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.



# Check if user is root on Debian distro. Install whiptail.
apt update && apt install -y whiptail ||
	error "Are you sure you're running this as the root user, are on an Ubuntu-based distribution and have an internet connection?"

# Welcome user and pick dotfiles.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

# Refresh Arch keyrings.
refreshkeys ||
	error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl ca-certificates build-essential git zsh; do
	echo "LARBS Installation" 
		echo "Installing \`$x\` which is required to install and configure other programs." 
	installpkg "$x"
done

# Synchronize system time
echo "Synchronizing system time to ensure successful and secure installation of software..."
apt install -y ntp
systemctl enable ntp
systemctl start ntp


adduserandpass || error "Error adding username and/or password."


# Allow user to run sudo without password.
trap 'rm -f /etc/sudoers.d/larbs-temp' HUP INT QUIT TERM PWR EXIT
echo "%sudo ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/larbs-temp


# Make apt colorful (this is default in newer versions of apt).
echo 'APT::Color "1";' > /etc/apt/apt.conf.d/99color

# Use all cores for compilation (useful for some manual installs).
echo "MAKEFLAGS=\"-j$(nproc)\"" >> /etc/environment


# manualinstall $aurhelper || error "Failed to install AUR helper."

# Make sure .*-git AUR packages get updated automatically.
# $aurhelper -Y --save --devel


# Install the dotfiles in the user's home directory, but remove .git dir and
# other unnecessary files.
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -rf "/home/$name/.git/" "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Install vim plugins if not alread present.
[ ! -f "/home/$name/.config/nvim/autoload/plug.vim" ] && vimplugininstall


# Most important command! Get rid of the beep!
# rmmod pcspkr
# echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/abook/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# dbus UUID must be generated for Artix runit.
dbus-uuidgen >/var/lib/dbus/machine-id

# Use system notifications for Brave on Artix
echo "export \$(dbus-launch)" >/etc/profile.d/dbus.sh

# Enable tap to click
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' >/etc/X11/xorg.conf.d/40-libinput.conf

# all this below to get librewolf installed with add-ons and non-bad settings.


# install_librewolf

# echo "setting browser privacy settings and add-ons..." 

# browserdir="/home/$name/.librewolf"
# profilesini="$browserdir/profiles.ini"

# # start librewolf headless so it generates a profile. then get that profile in a variable.
# sudo -u "$name" librewolf --headless >/dev/null 2>&1 &
# sleep 1
# profile="$(sed -n "/default=.*.default-release/ s/.*=//p" "$profilesini")"
# pdir="$browserdir/$profile"

# [ -d "$pdir" ] && makeuserjs

# [ -d "$pdir" ] && installffaddons

# # kill the now unnecessary librewolf instance.
# pkill -u "$name" librewolf


# Allow wheel/sudo users to sudo with password and allow several system commands
# (like `shutdown` to run without password).
echo "%sudo ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-larbs-sudo-can-sudo
echo "%sudo ALL=(ALL:ALL) NOPASSWD: /usr/sbin/shutdown,/usr/sbin/reboot,/usr/bin/systemctl suspend,/usr/sbin/mount,/usr/sbin/umount,/usr/bin/apt update,/usr/bin/apt upgrade,/usr/bin/apt dist-upgrade,/usr/bin/loadkeys" > /etc/sudoers.d/01-larbs-cmds-without-password
echo "Defaults editor=/usr/bin/nvim" > /etc/sudoers.d/02-larbs-visudo-editor

# Create sysctl.d directory if it doesn't exist and set dmesg restrictions
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf


# Last message! Install complete!
finalize

