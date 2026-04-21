#!/bin/bash
set -e

# ─── ЦВЕТА ────────────────────────────────────────────────────────────────────
R='\033[0;31m'  G='\033[0;32m'  Y='\033[1;33m'
B='\033[0;34m'  C='\033[0;36m'  W='\033[1;37m'
DIM='\033[2m'   NC='\033[0m'

# ─── НАСТРОЙКИ ────────────────────────────────────────────────────────────────
USERNAME="metal"
HOSTNAME="arch"
TIMEZONE="Europe/Moscow"
LOCALE="ru_RU.UTF-8"
KEYMAP="ru"
PARALLEL_DL=10
STEP=0
TOTAL_STEPS=14

# ─── UI ФУНКЦИИ ───────────────────────────────────────────────────────────────
header() {
    clear
    echo -e "${B}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║                                                  ║"
    echo "  ║        Arch Linux Auto Installer v2.0            ║"
    echo "  ║        Ryzen 7 7700  ·  RTX 5070  ·  NVMe       ║"
    echo "  ║                                                  ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

progress() {
    local pct=$(( STEP * 100 / TOTAL_STEPS ))
    local filled=$(( pct / 5 ))
    local empty=$(( 20 - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -e "  ${DIM}Прогресс:${NC} ${G}${bar}${NC} ${W}${pct}%${NC}  ${DIM}(${STEP}/${TOTAL_STEPS})${NC}\n"
}

section() {
    STEP=$((STEP + 1))
    header
    progress
    echo -e "  ${B}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${B}│${NC}  ${W}$1${NC}"
    echo -e "  ${B}└─────────────────────────────────────────────────┘${NC}\n"
}

info()  { echo -e "  ${G}✓${NC}  $1"; }
warn()  { echo -e "  ${Y}!${NC}  $1"; }
error() { echo -e "  ${R}✗${NC}  $1"; exit 1; }
ask()   { echo -e "  ${C}?${NC}  $1"; }

spinner() {
    local pid=$1 msg=$2
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${B}${frames[$i]}${NC}  ${DIM}%s${NC}" "$msg"
        i=$(( (i+1) % 10 ))
        sleep 0.08
    done
    printf "\r  ${G}✓${NC}  %-50s\n" "$msg"
}

# ─── СТАРТ ────────────────────────────────────────────────────────────────────
setfont ter-v16n 2>/dev/null || true

header
echo -e "  ${W}Этот скрипт установит Arch Linux с полным окружением.${NC}"
echo -e "  ${DIM}Windows не будет удалена при выборе правильных разделов.${NC}\n"

ask "Режим установки:"
echo -e "    ${W}1${NC} — Dual Boot (рядом с Windows)"
echo -e "    ${W}2${NC} — Чистая установка (VM / новый диск)\n"
read -rp "  > " INSTALL_MODE
[[ "$INSTALL_MODE" =~ ^[12]$ ]] || error "Введи 1 или 2"

echo ""
ask "Продолжить? (y/n)"
read -rp "  > " confirm
[[ "$confirm" == "y" ]] || error "Отменено"

# ─── ПРОВЕРКИ ─────────────────────────────────────────────────────────────────
section "Проверка окружения"

[ -d /sys/firmware/efi ] || error "Не UEFI режим — включи EFI в настройках VM/BIOS"

ping -c 1 -W 3 archlinux.org &>/dev/null || error "Нет интернета"
info "UEFI — OK"
info "Интернет — OK"

# ─── ЗЕРКАЛА ──────────────────────────────────────────────────────────────────
section "Настройка быстрых зеркал"

sed -i "s/#ParallelDownloads = 5/ParallelDownloads = ${PARALLEL_DL}/" /etc/pacman.conf

if command -v reflector &>/dev/null; then
    (reflector --country Russia,Germany,Netherlands \
        --protocol https --sort rate --latest 10 \
        --save /etc/pacman.d/mirrorlist &>/dev/null) &
    spinner $! "Подбираю быстрые зеркала..."
    info "Зеркала обновлены"
else
    warn "reflector недоступен — используются дефолтные зеркала"
fi

pacman -Sy --noconfirm &>/dev/null
info "Репозитории синхронизированы"

# ─── ДИСК ─────────────────────────────────────────────────────────────────────
section "Выбор диска и разделов"

echo -e "  ${DIM}Доступные диски:${NC}\n"
lsblk -d -o NAME,SIZE,MODEL | grep -v loop | while read line; do
    echo -e "    ${W}$line${NC}"
done
echo ""

ask "Имя диска (например: nvme0n1 или sda)"
read -rp "  /dev/" DISK
DISK="/dev/$DISK"
[ -b "$DISK" ] || error "Диск $DISK не найден"

echo ""
echo -e "  ${DIM}Разделы на $DISK:${NC}\n"
lsblk "$DISK" -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | while read line; do
    echo -e "    $line"
done
echo ""

ask "EFI раздел (~512MB)"
read -rp "  /dev/" EFI_PART
EFI_PART="/dev/$EFI_PART"

ask "SWAP раздел (Enter = пропустить)"
read -rp "  /dev/" SWAP_PART
[ -n "$SWAP_PART" ] && SWAP_PART="/dev/$SWAP_PART"

ask "ROOT раздел (всё остальное)"
read -rp "  /dev/" ROOT_PART
ROOT_PART="/dev/$ROOT_PART"

echo ""
echo -e "  ${B}┌─────────────────────────────┐${NC}"
echo -e "  ${B}│${NC}  EFI  → ${W}$EFI_PART${NC}"
echo -e "  ${B}│${NC}  SWAP → ${W}${SWAP_PART:-пропущен}${NC}"
echo -e "  ${B}│${NC}  ROOT → ${W}$ROOT_PART${NC}"
echo -e "  ${B}└─────────────────────────────┘${NC}"
echo ""
ask "Всё верно? (y/n)"
read -rp "  > " ok
[[ "$ok" == "y" ]] || error "Отменено"

# ─── ФОРМАТИРОВАНИЕ ───────────────────────────────────────────────────────────
section "Форматирование разделов"

if [ "$INSTALL_MODE" == "2" ]; then
    (mkfs.fat -F32 "$EFI_PART" &>/dev/null) &
    spinner $! "Форматирую EFI (FAT32)..."
fi

(mkfs.ext4 -F "$ROOT_PART" &>/dev/null) &
spinner $! "Форматирую ROOT (ext4)..."

if [ -n "$SWAP_PART" ]; then
    (mkswap "$SWAP_PART" &>/dev/null && swapon "$SWAP_PART") &
    spinner $! "Форматирую SWAP..."
fi

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot
info "Разделы смонтированы"

# ─── БАЗОВАЯ СИСТЕМА ──────────────────────────────────────────────────────────
section "Установка базовой системы"
warn "Это займёт несколько минут..."
echo ""

pacstrap /mnt \
    base base-devel linux linux-headers linux-firmware \
    amd-ucode \
    networkmanager \
    grub efibootmgr os-prober \
    nano sudo git curl wget \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    bluez bluez-utils \
    ntfs-3g flatpak \
    terminus-font \
    --noconfirm 2>&1 | grep -E "^\(|error" | while read line; do
        echo -e "    ${DIM}$line${NC}"
    done

info "Базовая система установлена"

genfstab -U /mnt >> /mnt/etc/fstab
info "fstab сгенерирован"

# ─── НАСТРОЙКА СИСТЕМЫ ────────────────────────────────────────────────────────
section "Настройка системы"

arch-chroot /mnt /bin/bash <<CHROOT
set -e

# Параллельные загрузки в chroot
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = ${PARALLEL_DL}/" /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/{s/^#//}" /etc/pacman.conf || true

# Временная зона
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Локаль
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen &>/dev/null
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "FONT=ter-v16n" >> /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Пользователь
useradd -mG wheel,video,audio,input,storage,optical ${USERNAME}
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Сервисы
systemctl enable NetworkManager &>/dev/null
systemctl enable bluetooth &>/dev/null
sed -i 's/#AutoEnable=false/AutoEnable=true/' /etc/bluetooth/main.conf 2>/dev/null || true

# Flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &>/dev/null || true
CHROOT

info "Система настроена"

# ─── ПАРОЛИ ───────────────────────────────────────────────────────────────────
section "Установка паролей"

warn "Пароль для ROOT:"
arch-chroot /mnt passwd

warn "Пароль для ${USERNAME}:"
arch-chroot /mnt passwd "$USERNAME"

# ─── GRUB ─────────────────────────────────────────────────────────────────────
section "Установка загрузчика GRUB"

arch-chroot /mnt /bin/bash <<CHROOT
set -e
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=3/' /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot \
    --bootloader-id=GRUB --quiet
grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
CHROOT

info "GRUB установлен"

# ─── KDE PLASMA ───────────────────────────────────────────────────────────────
section "Установка KDE Plasma 6"
warn "Это займёт несколько минут..."
echo ""

arch-chroot /mnt /bin/bash <<CHROOT
pacman -S --noconfirm --needed \
    plasma plasma-wayland-session sddm \
    dolphin konsole kate ark gwenview okular \
    plasma-nm plasma-pa kscreen \
    haruna fastfetch \
    xdg-desktop-portal-kde \
    2>&1 | grep -E "^\(|error" | sed 's/^/    /'

systemctl enable sddm &>/dev/null

# Alt+Shift раскладка
mkdir -p /home/${USERNAME}/.config
cat > /home/${USERNAME}/.config/kxkbrc <<EOF
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
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
CHROOT

info "KDE Plasma установлен"

# ─── NVIDIA ───────────────────────────────────────────────────────────────────
section "Драйверы NVIDIA RTX 5070"

arch-chroot /mnt /bin/bash <<CHROOT
pacman -S --noconfirm --needed \
    nvidia-open nvidia-open-dkms nvidia-utils \
    lib32-nvidia-utils nvtop nvidia-settings \
    2>&1 | grep -E "^\(|error" | sed 's/^/    /'

sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1"/' /etc/default/grub

mkinitcpio -P &>/dev/null
grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
systemctl enable nvidia-suspend nvidia-hibernate nvidia-resume &>/dev/null 2>&1 || true
CHROOT

info "Драйвер NVIDIA установлен"

# ─── ИГРЫ ─────────────────────────────────────────────────────────────────────
section "Steam · Lutris · Heroic · GameMode"

arch-chroot /mnt /bin/bash <<CHROOT
pacman -Sy --noconfirm --needed \
    steam lutris \
    lib32-mesa lib32-nvidia-utils \
    wine wine-mono winetricks \
    gamemode lib32-gamemode \
    mangohud lib32-mangohud \
    gamescope \
    2>&1 | grep -E "^\(|error" | sed 's/^/    /'
CHROOT

info "Игровые пакеты установлены"

# ─── YAY ──────────────────────────────────────────────────────────────────────
section "Установка yay (AUR)"

arch-chroot /mnt /bin/bash <<CHROOT
cd /tmp
sudo -u ${USERNAME} git clone https://aur.archlinux.org/yay.git &>/dev/null
cd yay
sudo -u ${USERNAME} makepkg -si --noconfirm &>/dev/null
CHROOT

info "yay установлен"

# ─── ПРИЛОЖЕНИЯ ───────────────────────────────────────────────────────────────
section "Приложения"

arch-chroot /mnt /bin/bash <<CHROOT
# Системные
pacman -S --noconfirm --needed \
    obs-studio htop p7zip unrar xdg-utils \
    2>&1 | grep -E "^\(|error" | sed 's/^/    /'

# AUR пакеты — параллельно где возможно
sudo -u ${USERNAME} yay -S --noconfirm \
    visual-studio-code-bin \
    zen-browser-bin \
    ayugram-desktop \
    discord \
    spotify \
    heroic-games-launcher-bin \
    modrinth-app \
    gruvbox-plus-icon-theme-git \
    2>&1 | grep -E "^\(|==>|error" | sed 's/^/    /'

# Фикс цветов Discord на NVIDIA
sed -i 's|Exec=/usr/bin/discord|Exec=/usr/bin/discord --use-gl=desktop|' \
    /usr/share/applications/discord.desktop 2>/dev/null || true

# Claude Code
pacman -S --noconfirm nodejs npm &>/dev/null
npm install -g @anthropic-ai/claude-code &>/dev/null

# fastfetch конфиг
mkdir -p /home/${USERNAME}/.config/fastfetch
cat > /home/${USERNAME}/.config/fastfetch/config.jsonc <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "display": { "separator": "  ", "color": { "keys": "blue", "title": "cyan" } },
  "modules": [
    "title", "separator",
    "os", "host", "kernel", "uptime",
    "packages", "shell", "display",
    "de", "wm", "theme", "icons",
    "terminal", "cpu", "gpu",
    "memory", "disk", "locale",
    "break", "colors"
  ]
}
EOF
echo 'fastfetch' >> /home/${USERNAME}/.bashrc
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
CHROOT

info "Все приложения установлены"

# ─── XBOX DNS ─────────────────────────────────────────────────────────────────
section "Xbox DNS + финальная настройка"

arch-chroot /mnt /bin/bash <<CHROOT
cat > /home/${USERNAME}/apply-xbox-dns.sh <<'EOF'
#!/bin/bash
CONN=$(nmcli -t -f NAME connection show --active | head -1)
nmcli connection modify "$CONN" ipv4.dns "13.107.237.38 13.107.238.38"
nmcli connection modify "$CONN" ipv4.ignore-auto-dns yes
nmcli connection up "$CONN"
echo "Xbox DNS применён: $CONN"
EOF
chmod +x /home/${USERNAME}/apply-xbox-dns.sh
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/apply-xbox-dns.sh
CHROOT

info "Xbox DNS скрипт: ~/apply-xbox-dns.sh"

# ─── ФИНАЛ ────────────────────────────────────────────────────────────────────
header
STEP=$TOTAL_STEPS
progress

echo -e "  ${G}╔══════════════════════════════════════════════════╗${NC}"
echo -e "  ${G}║           Установка завершена успешно!           ║${NC}"
echo -e "  ${G}╚══════════════════════════════════════════════════╝${NC}\n"

echo -e "  ${W}Установлено:${NC}"
echo -e "  ${DIM}├${NC} KDE Plasma 6 · Breeze Dark · Gruvbox иконки"
echo -e "  ${DIM}├${NC} NVIDIA nvidia-open · Wayland · DRM"
echo -e "  ${DIM}├${NC} Steam · Lutris · Heroic · Wine · GameMode · gamescope"
echo -e "  ${DIM}├${NC} Zen Browser · Ayugram · Discord · Spotify"
echo -e "  ${DIM}├${NC} VS Code · OBS · Haruna · Ark · Flatpak"
echo -e "  ${DIM}├${NC} Modrinth App · Claude Code · yay"
echo -e "  ${DIM}└${NC} Alt+Shift раскладка · fastfetch · Xbox DNS скрипт\n"

echo -e "  ${W}После перезагрузки:${NC}"
echo -e "  ${DIM}1.${NC} Войди как ${W}${USERNAME}${NC}"
echo -e "  ${DIM}2.${NC} ${W}bash ~/apply-xbox-dns.sh${NC}"
echo -e "  ${DIM}3.${NC} Параметры системы → Иконки → ${W}Gruvbox-Plus-Dark${NC}"
echo -e "  ${DIM}4.${NC} Steam → Настройки → Совместимость → ${W}Proton для всех игр${NC}"
echo -e "  ${DIM}5.${NC} CS2 лаунч опции: ${W}gamescope -w 1280 -h 960 -W 1920 -H 1080 -f -- %command%${NC}\n"

ask "Перезагрузиться сейчас? (y/n)"
read -rp "  > " do_reboot
if [ "$do_reboot" == "y" ]; then
    umount -R /mnt
    reboot
else
    info "Запусти вручную: umount -R /mnt && reboot"
fi
