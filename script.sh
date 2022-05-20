#!/bin/bash

set -euo pipefail

DIR=$PWD

# Fix sudoers
echo "%wheel ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/10-installer

# Update Mirrors
sudo reflector --verbose -c US --protocol https --sort rate --latest 10 \
    --download-timeout 5 --save /etc/pacman.d/mirrorlist

# X570 AORUS ULTRA
if [[ $(sudo dmidecode) =~ "X570 AORUS ULTRA" ]];
then
    # Enable AIO support
    sudo pacman -S --noconfirm liquidctl
    cat << EOF | sudo tee /etc/systemd/system/liquidcfg.service
[Unit]
Description=AIO startup service

[Service]
Type=oneshot
ExecStart=liquidctl initialize all
ExecStart=liquidctl --match kraken set pump speed 70
ExecStart=liquidctl --match kraken set fan speed  20 30  30 50  34 80  40 90  50 100

[Install]
WantedBy=default.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable liquidcfg --now
    # Set system clock to local time
    sudo timedatectl set-local-rtc 1
fi

# NVIDIA Cards
if [[ $(lspci) =~ "NVIDIA Corporation" ]];
then
    # Fix screen tearing
    sudo pacman -S --noconfirm nvidia-settings
    cat << EOF | sudo tee /etc/X11/xorg.conf.d/20-nvidia.conf
Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    Monitor        "Monitor0"
    DefaultDepth    24
    SubSection     "Display"
        Depth       24
    EndSubSection
    Option         "MetaModes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
    Option         "AllowIndirectGLXProtocol" "off"
    Option         "TripleBuffer" "on"
EndSection
EOF
fi

# Update System
sudo pacman -Syu --noconfirm

# Package Cleanup Configuration
cat << EOF | sudo tee /etc/systemd/system/paccache.service
[Unit]
Description=Remove unused cached package files

[Service]
Type=oneshot
ExecStart=paccache  -rk3
# Lowering priority
OOMScoreAdjust=1000
Nice=19
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
IOSchedulingPriority=7
# Sandboxing and other hardening
ProtectProc=invisible
ProcSubset=pid
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateNetwork=yes
PrivateIPC=yes
ProtectHostname=yes
ProtectClock=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictAddressFamilies=none
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RemoveIPC=yes
PrivateMounts=yes
SystemCallFilter=@system-service @file-system
SystemCallArchitectures=native
EOF

cat << EOF | sudo tee /etc/systemd/system/paccache.timer
[Unit]
Description=Discard unused packages weekly

[Timer]
OnCalendar=weekly
AccuracySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable paccache.timer --now

# Download wallpapers
bg="/usr/share/endeavouros/backgrounds"
git clone https://gitlab.com/endeavouros-filemirror/Community-wallpapers.git
mkdir -p $bg
sudo cp -r Community-wallpapers/eos_wallpapers_classic $bg
sudo cp -r Community-wallpapers/eos_wallpapers_community $bg
rm -rf Community-wallpapers

# Install paru
git clone https://aur.archlinux.org/paru.git ~/git/aur/paru
cd ~/git/aur/paru
makepkg -si --noconfirm
cd $DIR
paru -Syu --noconfirm --skipreview

# Install software
sudo pacman -S --noconfirm alacritty bat btop exa fd font-manager libreoffice-fresh \
    neovim procs ranger ripgrep tree zsh
paru -S --noconfirm --skipreview autotiling icdiff shell-color-scripts sublime-text-4 \
    timeshift-bin typora

# Install JetBrains Mono fonts
wget -q https://download.jetbrains.com/fonts/JetBrainsMono-2.242.zip
unzip -q JetBrainsMono-2.242.zip -d JetBrains
sudo cp JetBrains/fonts/variable/* /usr/share/fonts/TTF
rm -rf JetBrains JetBrainsMono-2.242.zip

url="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/Ligatures"
sudo wget -q -P /usr/share/fonts/TTF \
    ${url}/Regular/complete/JetBrains%20Mono%20Regular%20Nerd%20Font%20Complete%20Mono.ttf \
    ${url}/Bold/complete/JetBrains%20Mono%20Bold%20Nerd%20Font%20Complete.ttf \
    ${url}/Italic/complete/JetBrains%20Mono%20Italic%20Nerd%20Font%20Complete.ttf \
    ${url}/BoldItalic/complete/JetBrains%20Mono%20Bold%20Italic%20Nerd%20Font%20Complete.ttf
fc-cache

# Install themes for typora
git clone --depth=1 https://github.com/liangjingkanji/DrakeTyporaTheme.git \
    ~/.config/Typora/themes
rm -rf ~/.config/Typora/themes/{.git*,issues.md,LICENSE,README.md}
sed -i 's/--text-size:\(.\)*/--text-size: 14px;/' ~/.config/Typora/themes/drake/font.css

# Install nordic themes for gtk
cfg=~/.config/gtk-3.0/settings.ini
paru -S --noconfirm --skipreview nordic-theme nordic-darker-theme
sed -i 's/gtk-theme-name=\(.\)*/gtk-theme-name=Nordic-darker/' $cfg
sed -i 's/gtk-icon-theme-name=\(.\)*/gtk-icon-theme-name=Adwaita/' $cfg

# Install nord theme for alacritty
git clone https://github.com/hsuchan/dotfiles.git ~/git/hsuchan/dotfiles
mkdir ~/.config/alacritty
cp ~/git/hsuchan/dotfiles/alacritty/* ~/.config/alacritty/.

# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
sudo chsh -s /usr/bin/zsh $USER

# Install p10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.powerlevel10k

# Configure p10k and oh-my-zsh
cp p10k.zsh ~/.p10k.zsh
cp zshrc ~/.zshrc

# Install shell-color-scripts
cat << EOF >> ~/.zshrc

# shell-color-scripts
colorscript --random
EOF

# Install bumblebee-status
git clone https://github.com/tobi-wan-kenobi/bumblebee-status \
    ~/.config/i3/bumblebee-status

# Multi-display support
read -r n o1 o2 < <(xrandr --listactivemonitors | awk 'NR == 1; NR > 1 {print $0 | "sort -nrk3"}' | \
    awk '{ print $NF }' | xargs)
case $n in
    2) 
        echo "xrandr --output $o1 --primary --auto --output $o2 --auto --right-of $o1" > ~/.xprofile
        nitrogen --head=0 --set-zoom --save ${bg}/eos_wallpapers_community/krimkerre_4_endy_neon.jpg
        nitrogen --head=1 --set-zoom --save ${bg}/eos_wallpapers_community/Endy_vector_satelliet.png
	cat ~/git/hsuchan/dotfiles/i3/config | sed -e "s/monitor1/$o1/" -e "s/monitor2/$o2/" > \
            ~/.config/i3/config
        ;;
    1|*)
        echo "xrandr --output $o1 --primary --auto" > ~/.xprofile
        nitrogen --set-zoom --save ${bg}/eos_wallpapers_community/krimkerre_4_endy_neon.jpg
	cat ~/git/hsuchan/dotfiles/i3/config | sed -e "s/monitor1/$o1/" -e "s/monitor2/$o1/" > \
            ~/.config/i3/config
        ;;
esac

# Mount VMware shared drive
if [[ $(lspci) =~ "VMware SVGA II Adapter" ]];
then
    mkdir ~/Shared
    sudo sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
    cat << EOF | sudo tee -a /etc/fstab
    # Use shared folders between VMware guest and host
    .host:/Shared    /home/hchan/Shared/    fuse.vmhgfs-fuse    defaults,allow_other    0    0
EOF
    sudo systemctl daemon-reload
fi

# Disable beep on shutdown
echo "blacklist pcspkr" | sudo tee /etc/modprobe.d/blacklist.conf
