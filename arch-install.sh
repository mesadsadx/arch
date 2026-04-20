#!/bin/bash
# Arch Linux auto-installer for:
# CPU: AMD Ryzen 7 7700
# GPU: NVIDIA RTX 5070
# RAM: 16GB DDR5
# Disk: NVMe 1TB

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════${NC}\n"; }

# ─── НАСТРОЙКИ ────────────────────────────────────────────────────────────────
USERNAME="metal"
HOSTNAME="arch"
TIMEZONE="Europe/Moscow"
LOCALE="ru_RU.UTF-8"
KEYMAP="ru"
# ──────────────────────────────────────────────────────────────────────────────

check_uefi() {
    [ -d /sys/firmware/efi ] || error "Не UEFI режим. Зайди в BIOS и включи UEFI."
}

check_internet() {
    ping -c 1 archlinux.org &>/dev/null || error "Нет интернета. Подключись и запусти снова."
}

select_disk() {
    section "Выбор диска"
    echo "Доступные диски:"
    lsblk -d -o NAME,SIZE,MODEL | grep -v loop
    echo ""
    warn "Введи имя диска (например: nvme0n1 или sda)"
    warn "НЕ вводи номер раздела!"
    read -rp "Диск: /dev/" DISK
    DISK="/dev/$DISK"
    [ -b "$DISK" ] || error "Диск $DISK не найден"
}

select_partitions() {
    section "Выбор разделов"
    echo "Разделы на $DISK:"
    lsblk "$DISK" -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
    echo ""
    warn "Укажи EFI раздел Windows (обычно nvme0n1p1, ~100-500MB, тип EFI)"
    read -rp "EFI раздел: /dev/" EFI_PART
    EFI_PART="/dev/$EFI_PART"

    warn "Укажи раздел для SWAP (если уже создал через cfdisk)"
    warn "Если не создавал — нажми Enter, swap будет пропущен"
    read -rp "SWAP раздел (Enter = пропустить): /dev/" SWAP_PART
    [ -n "$SWAP_PART" ] && SWAP_PART="/dev/$SWAP_PART"

    warn "Укажи раздел для корня / (Linux filesystem, всё свободное место)"
    read -rp "ROOT раздел: /dev/" ROOT_PART
    ROOT_PART="/dev/$ROOT_PART"

    echo ""
    info "EFI:  $EFI_PART"
    info "SWAP: ${SWAP_PART:-пропущен}"
    info "ROOT: $ROOT_PART"
    echo ""
    warn "Всё верно? Это НЕ удалит Windows. (y/n)"
    read -rp "> " confirm
    [ "$confirm" = "y" ] || error "Отменено"
}

format_and_mount() {
    section "Форматирование и монтирование"

    info "Форматирую ROOT ($ROOT_PART) в ext4..."
    mkfs.ext4 -F "$ROOT_PART"

    if [ -n "$SWAP_PART" ]; then
        info "Форматирую SWAP ($SWAP_PART)..."
        mkswap "$SWAP_PART"
        swapon "$SWAP_PART"
    fi

    info "Монтирую разделы..."
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot

    info "Готово"
}

install_base() {
    section "Установка базовой системы"
    info "Это займёт несколько минут..."

    pacstrap /mnt \
        base base-devel linux linux-headers linux-firmware \
        amd-ucode \
        networkmanager \
        grub efibootmgr os-prober \
        nano sudo git curl wget \
        pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
        bluez bluez-utils \
        ntfs-3g \
        flatpak \
        --noconfirm

    info "Базовая система установлена"
}

configure_system() {
    section "Настройка системы"

    info "Генерирую fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab

    info "Настраиваю систему в chroot..."
    arch-chroot /mnt /bin/bash <<CHROOT
set -e

# Временная зона
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Локаль
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Пользователь
useradd -mG wheel,video,audio,input,storage,optical $USERNAME
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Сервисы
systemctl enable NetworkManager
systemctl enable bluetooth

# Bluetooth автовключение
sed -i 's/#AutoEnable=false/AutoEnable=true/' /etc/bluetooth/main.conf 2>/dev/null || true

# Flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

CHROOT

    info "Система настроена"
}

set_passwords() {
    section "Установка паролей"
    warn "Введи пароль для ROOT:"
    arch-chroot /mnt passwd

    warn "Введи пароль для пользователя $USERNAME:"
    arch-chroot /mnt passwd "$USERNAME"
}

install_grub() {
    section "Установка GRUB"

    arch-chroot /mnt /bin/bash <<CHROOT
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

    info "GRUB установлен"
}

install_kde() {
    section "Установка KDE Plasma"
    info "Это займёт несколько минут..."

    arch-chroot /mnt /bin/bash <<CHROOT
pacman -S --noconfirm \
    plasma \
    plasma-wayland-session \
    sddm \
    dolphin konsole kate \
    ark gwenview okular \
    plasma-nm plasma-pa \
    kscreen \
    haruna \
    fastfetch \
    xdg-desktop-portal-kde \
    --noconfirm

systemctl enable sddm

# Alt+Shift переключение раскладки через kxkbrc
mkdir -p /home/$USERNAME/.config
cat > /home/$USERNAME/.config/kxkbrc <<EOF
[Layout]
DisplayNames=,
LayoutList=us,ru
Model=pc105
Options=grp:alt_shift_toggle
ResetOldOptions=true
ShowFlag=false
ShowLabel=true
ShowLayoutIndicator=true
ShowSingle=false
SwitchMode=Global
UseConfigFile=true
VariantList=,
EOF
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
CHROOT

    info "KDE Plasma установлен"
}

install_nvidia() {
    section "Установка драйверов NVIDIA RTX 5070"

    arch-chroot /mnt /bin/bash <<CHROOT
pacman -S --noconfirm \
    nvidia-open \
    nvidia-open-dkms \
    nvidia-utils \
    lib32-nvidia-utils \
    nvtop \
    nvidia-settings

# Модули в initramfs
sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf

# DRM modesetting
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1"/' /etc/default/grub

mkinitcpio -P
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable nvidia-suspend nvidia-hibernate nvidia-resume 2>/dev/null || true
CHROOT

    info "Драйвер NVIDIA установлен"
}

install_gaming() {
    section "Установка Steam, Lutris, Heroic и игровых пакетов"

    arch-chroot /mnt /bin/bash <<CHROOT
# Включаем multilib
sed -i '/^#\[multilib\]/s/^#//' /etc/pacman.conf
sed -i '/^\[multilib\]/{n;s/^#//}' /etc/pacman.conf
pacman -Sy

pacman -S --noconfirm \
    steam \
    lutris \
    lib32-mesa \
    wine \
    wine-mono \
    winetricks \
    gamemode \
    lib32-gamemode \
    mangohud \
    lib32-mangohud \
    --noconfirm
CHROOT

    info "Steam, Lutris и игровые пакеты установлены"
}

install_aur() {
    section "Установка yay (AUR helper)"

    arch-chroot /mnt /bin/bash <<CHROOT
cd /tmp
sudo -u $USERNAME git clone https://aur.archlinux.org/yay.git
cd yay
sudo -u $USERNAME makepkg -si --noconfirm
CHROOT

    info "yay установлен"
}

install_apps() {
    section "Установка приложений (AUR + pacman)"

    arch-chroot /mnt /bin/bash <<CHROOT
# Системные утилиты
pacman -S --noconfirm \
    htop \
    p7zip \
    unrar \
    obs-studio \
    xdg-utils

# VS Code (с Microsoft маркетплейсом)
sudo -u $USERNAME yay -S --noconfirm visual-studio-code-bin

# Zen Browser (форк Firefox с современным UI)
sudo -u $USERNAME yay -S --noconfirm zen-browser-bin

# Ayugram (форк Telegram)
sudo -u $USERNAME yay -S --noconfirm ayugram-desktop

# Discord с фиксом цветов для NVIDIA
sudo -u $USERNAME yay -S --noconfirm discord
# Фикс цветового искажения на NVIDIA — меняем флаг запуска
sed -i 's|Exec=/usr/bin/discord|Exec=/usr/bin/discord --use-gl=desktop|' \
    /usr/share/applications/discord.desktop 2>/dev/null || true

# Spotify
sudo -u $USERNAME yay -S --noconfirm spotify

# Heroic Games Launcher (Epic / GOG / Amazon)
sudo -u $USERNAME yay -S --noconfirm heroic-games-launcher-bin

# Modrinth App (Minecraft лаунчер)
sudo -u $USERNAME yay -S --noconfirm modrinth-app

CHROOT

    info "Приложения установлены"
}

install_claude() {
    section "Установка Claude Code"

    arch-chroot /mnt /bin/bash <<CHROOT
pacman -S --noconfirm nodejs npm
npm install -g @anthropic-ai/claude-code
CHROOT

    info "Claude Code установлен — при первом запуске: claude"
}

install_theming() {
    section "Кастомизация KDE (тема как на скрине)"

    arch-chroot /mnt /bin/bash <<CHROOT
# Иконки Gruvbox-Plus-Dark
sudo -u $USERNAME yay -S --noconfirm gruvbox-plus-icon-theme-git

# Виджет Now Playing для Spotify на рабочем столе
sudo -u $USERNAME yay -S --noconfirm plasma6-applets-window-title 2>/dev/null || true

# fastfetch конфиг
mkdir -p /home/$USERNAME/.config/fastfetch
cat > /home/$USERNAME/.config/fastfetch/config.jsonc <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "display": {
    "separator": ": ",
    "color": {
      "keys": "blue",
      "title": "blue"
    }
  },
  "modules": [
    "title", "separator",
    "os", "host", "kernel", "uptime",
    "packages", "shell", "display",
    "de", "wm", "wmtheme", "theme",
    "icons", "font", "cursor", "terminal",
    "cpu", "gpu", "memory", "swap",
    "disk", "localip", "locale",
    "break", "colors"
  ]
}
EOF

chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/fastfetch

# Добавляем fastfetch в .bashrc
echo 'fastfetch' >> /home/$USERNAME/.bashrc

CHROOT

    info "Тема и кастомизация настроены"
    warn "После входа: Параметры системы → Внешний вид → Иконки → Gruvbox-Plus-Dark"
    warn "Тема: Breeze Dark (встроена в KDE)"
}

configure_xbox_dns() {
    section "Настройка Xbox DNS"

    arch-chroot /mnt /bin/bash <<CHROOT
cat > /home/$USERNAME/apply-xbox-dns.sh <<'EOF'
#!/bin/bash
CONN=\$(nmcli -t -f NAME connection show --active | head -1)
nmcli connection modify "\$CONN" ipv4.dns "13.107.237.38 13.107.238.38"
nmcli connection modify "\$CONN" ipv4.ignore-auto-dns yes
nmcli connection up "\$CONN"
echo "Xbox DNS применён для: \$CONN"
EOF
chmod +x /home/$USERNAME/apply-xbox-dns.sh
chown $USERNAME:$USERNAME /home/$USERNAME/apply-xbox-dns.sh
CHROOT

    info "Скрипт Xbox DNS сохранён в ~/apply-xbox-dns.sh"
}

finish() {
    section "Установка завершена!"
    echo ""
    info "Установлено:"
    echo "  • KDE Plasma 6 (Wayland) + Breeze Dark"
    echo "  • NVIDIA nvidia-open (RTX 5070)"
    echo "  • Steam + Lutris + Heroic Games Launcher"
    echo "  • Wine + GameMode + MangoHud"
    echo "  • Zen Browser, Ayugram, Discord, Spotify"
    echo "  • VS Code, OBS, Haruna, Ark"
    echo "  • Modrinth App (Minecraft)"
    echo "  • Flatpak + Flathub"
    echo "  • yay (AUR)"
    echo "  • fastfetch + Gruvbox иконки"
    echo "  • Alt+Shift переключение раскладки"
    echo ""
    info "После перезагрузки:"
    echo "  1. Войди под пользователем: $USERNAME"
    echo "  2. Запусти: bash ~/apply-xbox-dns.sh"
    echo "  3. Параметры системы → Иконки → Gruvbox-Plus-Dark"
    echo "  4. В Steam включи Proton для всех игр"
    echo ""
    warn "Готов перезагрузиться? (y/n)"
    read -rp "> " do_reboot
    if [ "$do_reboot" = "y" ]; then
        umount -R /mnt
        reboot
    else
        info "Запусти вручную: umount -R /mnt && reboot"
    fi
}

# ─── ГЛАВНЫЙ ЗАПУСК ───────────────────────────────────────────────────────────
clear
echo -e "${BLUE}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║     Arch Linux Auto Installer         ║"
echo "  ║     Ryzen 7 7700 + RTX 5070           ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${NC}"
echo ""
warn "Этот скрипт установит Arch Linux рядом с Windows"
warn "Windows НЕ будет удалена если выберешь правильные разделы"
echo ""
warn "Продолжить? (y/n)"
read -rp "> " start
[ "$start" = "y" ] || error "Отменено"

check_uefi
check_internet
select_disk
select_partitions
format_and_mount
install_base
configure_system
set_passwords
install_grub
install_kde
install_nvidia
install_gaming
install_aur
install_apps
install_claude
install_theming
configure_xbox_dns
finish
