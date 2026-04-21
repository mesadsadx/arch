#!/bin/bash
set -e

# ─── ЦВЕТА ────────────────────────────────────────────────────────────────────
R='\033[0;31m'  G='\033[0;32m'  Y='\033[1;33m'
B='\033[0;34m'  C='\033[0;36m'  M='\033[0;35m'
W='\033[1;37m'  DIM='\033[2m'   NC='\033[0m'
BOLD='\033[1m'

# ─── НАСТРОЙКИ ────────────────────────────────────────────────────────────────
USERNAME="metal"
HOSTNAME="arch"
TIMEZONE="Europe/Moscow"
LOCALE="ru_RU.UTF-8"
KEYMAP="ru"
PARALLEL_DL=10
STEP=0
TOTAL_STEPS=13

# Выбранные пользователем параметры
INSTALL_MODE=""
DE_CHOICE=""
GPU_DRIVER=""
EFI_PART=""
SWAP_PART=""
ROOT_PART=""
DISK=""

# ─── УТИЛИТЫ ──────────────────────────────────────────────────────────────────
info()   { echo -e "  ${G}✓${NC}  $1"; }
warn()   { echo -e "  ${Y}▲${NC}  $1"; }
error()  { echo -e "\n  ${R}✗  $1${NC}\n"; exit 1; }
dim()    { echo -e "  ${DIM}$1${NC}"; }

# Проверка что /mnt смонтирован и система установлена
check_mnt() {
    mountpoint -q /mnt || error "/mnt не смонтирован! Запусти скрипт заново."
    [ -f /mnt/usr/bin/bash ] || error "Базовая система не установлена в /mnt. Запусти заново."
}

# Запуск spinner с проверкой кода выхода фонового процесса
run_bg() {
    local msg="$1"; shift
    "$@" &>/tmp/arch_install.log &
    local pid=$!
    spinner $pid "$msg"
    wait $pid || { cat /tmp/arch_install.log; error "Ошибка: $msg"; }
}

spinner() {
    local pid=$1 msg=$2
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${B}${frames[$i]}${NC}  ${DIM}%-52s${NC}" "$msg"
        i=$(( (i+1) % 10 ))
        sleep 0.08
    done
    tput cnorm 2>/dev/null || true
    printf "\r  ${G}✓${NC}  %-52s\n" "$msg"
}

progress_bar() {
    local pct=$(( STEP * 100 / TOTAL_STEPS ))
    local filled=$(( pct / 4 ))
    local empty=$(( 25 - filled ))
    local bar="${G}"
    for ((i=0; i<filled; i++)); do bar+="█"; done
    bar+="${DIM}"
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="${NC}"
    printf "  %b  ${DIM}%d%%  (%d/%d)${NC}\n" "$bar" "$pct" "$STEP" "$TOTAL_STEPS"
}

# ─── ЛОГОТИП ──────────────────────────────────────────────────────────────────
draw_logo() {
    echo -e "${B}"
    echo '                    ██████                    '
    echo '                  ████████                    '
    echo '                ███      ██                   '
    echo '               ██  ████  ██                   '
    echo '              ██  ██████  ██                  '
    echo '             ██  ████████  ██                 '
    echo '            ██  ██      ██  ██                '
    echo '           ██  ██  ████  ██  ██               '
    echo '          ██████████████████████              '
    echo -e "${NC}"
    echo -e "         ${W}${BOLD}A R C H   L I N U X${NC}"
    echo -e "     ${DIM}Auto Installer v3.0  ·  2026${NC}"
    echo ""
}

header() {
    clear
    echo -e "${B}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${B}  ║${NC}$(draw_logo | tr '\n' '|' | sed 's/|/\n  ║/g' | head -1)"
    # Просто чистый хедер
    clear
    echo ""
    draw_logo
    echo -e "${B}  ═══════════════════════════════════════════════════════${NC}"
    [ $STEP -gt 0 ] && { echo ""; progress_bar; }
    echo -e "${B}  ═══════════════════════════════════════════════════════${NC}"
    echo ""
}

section() {
    STEP=$((STEP + 1))
    clear
    echo ""
    draw_logo
    echo -e "${B}  ═══════════════════════════════════════════════════════${NC}"
    echo ""
    progress_bar
    echo ""
    echo -e "${B}  ═══════════════════════════════════════════════════════${NC}"
    echo -e "${B}  ║${NC}  ${W}${BOLD}$1${NC}"
    echo -e "${B}  ═══════════════════════════════════════════════════════${NC}"
    echo ""
}

# ─── МЕНЮ С ЦИФРАМИ ───────────────────────────────────────────────────────────
# Возвращает индекс в MENU_RESULT
arrow_menu() {
    local prompt="$1"; shift
    local options=("$@")
    local count=${#options[@]}
    local choice

    echo -e "  ${C}${BOLD}$prompt${NC}\n"
    for i in "${!options[@]}"; do
        echo -e "  ${B}$((i+1))${NC}  ${options[$i]}"
    done
    echo ""

    while true; do
        read -rp "  Введи номер [1-${count}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            MENU_RESULT=$((choice - 1))
            break
        fi
        warn "Введи число от 1 до ${count}"
    done
}

# ─── АВТОДЕТЕКТ ЖЕЛЕЗА ────────────────────────────────────────────────────────
detect_hardware() {
    section "Определение железа"

    # CPU
    CPU_NAME=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "?")
    CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo 2>/dev/null | awk '{print $3}')

    # GPU
    GPU_NAME=$(lspci 2>/dev/null | grep -Ei "VGA|3D|Display" | head -1 | sed 's/.*: //' | sed 's/ (.*//')
    if echo "$GPU_NAME" | grep -qi "nvidia"; then
        GPU_TYPE="nvidia"
    elif echo "$GPU_NAME" | grep -qi "amd\|radeon\|advanced micro"; then
        GPU_TYPE="amd"
    elif echo "$GPU_NAME" | grep -qi "intel"; then
        GPU_TYPE="intel"
    else
        GPU_TYPE="unknown"
    fi

    # RAM
    RAM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')

    # Диск
    MAIN_DISK=$(lsblk -d -o NAME,SIZE,TYPE | grep disk | head -1 | awk '{print "/dev/"$1}')
    DISK_SIZE=$(lsblk -d -o NAME,SIZE | grep -v NAME | head -1 | awk '{print $2}')

    # Вывод
    echo -e "  ${B}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${B}│${NC}  ${DIM}CPU${NC}   ${W}$CPU_NAME${NC}"
    echo -e "  ${B}│${NC}  ${DIM}     ${NC}  ${DIM}$CPU_CORES ядер · ${CPU_VENDOR}${NC}"
    echo -e "  ${B}│${NC}"
    echo -e "  ${B}│${NC}  ${DIM}GPU${NC}   ${W}$GPU_NAME${NC}"
    echo -e "  ${B}│${NC}  ${DIM}     ${NC}  ${DIM}Тип: $GPU_TYPE${NC}"
    echo -e "  ${B}│${NC}"
    echo -e "  ${B}│${NC}  ${DIM}RAM${NC}   ${W}$RAM_TOTAL${NC}"
    echo -e "  ${B}│${NC}"
    echo -e "  ${B}│${NC}  ${DIM}DISK${NC}  ${W}$MAIN_DISK${NC}  ${DIM}($DISK_SIZE)${NC}"
    echo -e "  ${B}└─────────────────────────────────────────────────┘${NC}"
    echo ""

    # Microcode
    if [ "$CPU_VENDOR" = "GenuineIntel" ]; then
        UCODE="intel-ucode"
    else
        UCODE="amd-ucode"
    fi

    # Предложить основной диск
    echo -e "  ${DIM}Обнаружен диск: ${W}$MAIN_DISK${NC}"
    echo -e "  ${DIM}Использовать его? (Enter = да, введи другой)${NC}\n"
    read -rp "  /dev/" custom_disk
    if [ -n "$custom_disk" ]; then
        DISK="/dev/$custom_disk"
    else
        DISK="$MAIN_DISK"
    fi

    info "Железо определено"
    sleep 1
}

# ─── РЕЖИМ УСТАНОВКИ ──────────────────────────────────────────────────────────
select_install_mode() {
    section "Режим установки"

    arrow_menu "Выбери режим:" \
        "🪟  Dual Boot — рядом с Windows (EFI не форматируется)" \
        "💿  Чистая установка — VM или новый диск (EFI форматируется)"

    INSTALL_MODE=$((MENU_RESULT + 1))

    if [ "$INSTALL_MODE" == "1" ]; then
        info "Dual Boot — Windows останется"
    else
        info "Чистая установка"
    fi
    sleep 0.5
}

# ─── ВЫБОР DE ─────────────────────────────────────────────────────────────────
select_de() {
    section "Рабочее окружение"

    arrow_menu "Выбери DE:" \
        "🖥   KDE Plasma 6   — современный, кастомизируемый, похож на Windows" \
        "🌀  GNOME 46        — минималистичный, похож на macOS" \
        "🪶  XFCE            — лёгкий, классический, для слабых ПК" \
        "🌿  Hyprland        — тайловый WM на Wayland, максимум кастома"

    DE_CHOICE=$MENU_RESULT

    case $DE_CHOICE in
        0) info "KDE Plasma 6" ;;
        1) info "GNOME 46" ;;
        2) info "XFCE" ;;
        3) info "Hyprland" ;;
    esac
    sleep 0.5
}

# ─── ВЫБОР ДРАЙВЕРА GPU ───────────────────────────────────────────────────────
select_gpu_driver() {
    section "Драйвер GPU"

    echo -e "  ${DIM}Обнаружена видеокарта:${NC} ${W}$GPU_NAME${NC}\n"

    case "$GPU_TYPE" in
        nvidia)
            arrow_menu "Рекомендованный: nvidia-open" \
                "⚡  nvidia-open   — открытые модули, рекомендуется RTX 20XX+" \
                "🔒  nvidia        — закрытый драйвер, для старых карт" \
                "🖥   nouveau       — свободный, слабее по производительности"
            case $MENU_RESULT in
                0) GPU_DRIVER="nvidia-open" ;;
                1) GPU_DRIVER="nvidia" ;;
                2) GPU_DRIVER="nouveau" ;;
            esac
            ;;
        amd)
            arrow_menu "AMD — драйверы встроены в ядро" \
                "🔴  amdgpu + mesa + vulkan-radeon  — рекомендуется" \
                "🔴  amdgpu + mesa                  — без Vulkan"
            case $MENU_RESULT in
                0) GPU_DRIVER="amd-vulkan" ;;
                1) GPU_DRIVER="amd" ;;
            esac
            ;;
        intel)
            arrow_menu "Intel — выбери драйвер" \
                "🔵  intel-media-driver + mesa  — для 8-го поколения и новее" \
                "🔵  libva-intel-driver + mesa  — для старых карт"
            case $MENU_RESULT in
                0) GPU_DRIVER="intel-new" ;;
                1) GPU_DRIVER="intel-old" ;;
            esac
            ;;
        *)
            warn "GPU не определён — будет установлена mesa"
            GPU_DRIVER="mesa"
            ;;
    esac

    info "Драйвер: $GPU_DRIVER"
    sleep 0.5
}

# ─── РАЗДЕЛЫ ──────────────────────────────────────────────────────────────────
select_partitions() {
    section "Разметка диска"

    echo -e "  ${DIM}Разделы на ${W}$DISK${DIM}:${NC}\n"
    lsblk "$DISK" -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | while IFS= read -r line; do
        echo -e "    ${DIM}$line${NC}"
    done
    echo ""

    warn "Если разделы не созданы — открой второй терминал (Alt+F2) и запусти cfdisk $DISK"
    echo ""

    echo -e "  ${C}EFI раздел${NC} ${DIM}(~512MB, тип EFI System):${NC}"
    read -rp "  /dev/" p; EFI_PART="/dev/$p"

    echo -e "\n  ${C}SWAP раздел${NC} ${DIM}(Enter = пропустить):${NC}"
    read -rp "  /dev/" p; [ -n "$p" ] && SWAP_PART="/dev/$p"

    echo -e "\n  ${C}ROOT раздел${NC} ${DIM}(всё остальное):${NC}"
    read -rp "  /dev/" p; ROOT_PART="/dev/$p"

    echo ""
    echo -e "  ${B}┌──────────────────────────────────┐${NC}"
    echo -e "  ${B}│${NC}  EFI   ${W}$EFI_PART${NC}"
    echo -e "  ${B}│${NC}  SWAP  ${W}${SWAP_PART:-пропущен}${NC}"
    echo -e "  ${B}│${NC}  ROOT  ${W}$ROOT_PART${NC}"
    echo -e "  ${B}└──────────────────────────────────┘${NC}"
    echo ""

    echo -e "  ${Y}Всё верно? Windows НЕ будет удалена. (y/n)${NC}"
    read -rp "  > " ok
    [[ "$ok" == "y" ]] || error "Отменено"
}

# ─── ФОРМАТИРОВАНИЕ ───────────────────────────────────────────────────────────
format_and_mount() {
    section "Форматирование"

    [ -b "$EFI_PART" ]  || error "EFI раздел не найден: $EFI_PART"
    [ -b "$ROOT_PART" ] || error "ROOT раздел не найден: $ROOT_PART"

    if [ "$INSTALL_MODE" == "2" ]; then
        (mkfs.fat -F32 "$EFI_PART" &>/dev/null) &
        spinner $! "Форматирую EFI → FAT32"
    fi

    (mkfs.ext4 -F "$ROOT_PART" &>/dev/null) &
    spinner $! "Форматирую ROOT → ext4"

    if [ -n "$SWAP_PART" ] && [ -b "$SWAP_PART" ]; then
        (mkswap "$SWAP_PART" &>/dev/null && swapon "$SWAP_PART") &
        spinner $! "Форматирую SWAP"
    fi

    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot

    info "Разделы смонтированы"
}

# ─── ЗЕРКАЛА И PACMAN ─────────────────────────────────────────────────────────
setup_mirrors() {
    section "Быстрые зеркала и загрузка"

    sed -i "s/#ParallelDownloads = 5/ParallelDownloads = ${PARALLEL_DL}/" /etc/pacman.conf 2>/dev/null || true

    # Сначала принудительно ставим быстрые зеркала
    cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = https://mirror.yandex.ru/archlinux/$repo/os/$arch
Server = https://archlinux.uk.mirror.allworldit.com/archlinux/$repo/os/$arch
Server = https://mirror.osbeck.com/archlinux/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
EOF
    info "Зеркала: Яндекс + резервные"

    if command -v reflector &>/dev/null; then
        run_bg "Уточняю зеркала через reflector" \
            reflector --country Russia,Germany,Netherlands --protocol https \
            --sort rate --latest 10 --save /etc/pacman.d/mirrorlist
    fi

    run_bg "Синхронизирую репозитории" pacman -Sy --noconfirm

    # Обновляем keyring — без этого pacstrap падает с ошибкой подписи
    run_bg "Обновляю keyring (исправляет ошибки подписей)" \
        pacman -S --noconfirm --needed archlinux-keyring
}

# ─── БАЗОВАЯ СИСТЕМА ──────────────────────────────────────────────────────────
install_base() {
    section "Базовая система"

    warn "Идёт загрузка — может занять несколько минут..."
    echo ""

    local attempt=1
    while [ $attempt -le 3 ]; do
        info "Попытка $attempt из 3..."
        pacstrap -K /mnt \
            base base-devel linux linux-headers linux-firmware \
            "$UCODE" \
            networkmanager \
            grub efibootmgr os-prober \
            nano sudo git curl wget \
            pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
            bluez bluez-utils \
            ntfs-3g flatpak \
            terminus-font \
            --noconfirm && break
        warn "Попытка $attempt не удалась. Повтор через 5 секунд..."
        sleep 5
        attempt=$((attempt + 1))
    done
    [ $attempt -le 3 ] || error "pacstrap завершился с ошибкой после 3 попыток. Проверь интернет."

    # Проверяем что система реально установилась
    [ -f /mnt/usr/bin/bash ] || error "pacstrap не установил систему — /mnt/usr/bin/bash не найден"

    info "Базовая система установлена"

    genfstab -U /mnt >> /mnt/etc/fstab
    info "fstab сгенерирован"
}

# ─── СИСТЕМА ──────────────────────────────────────────────────────────────────
configure_system() {
    section "Настройка системы"
    check_mnt

    (arch-chroot /mnt /bin/bash <<CHROOT
set -e
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = ${PARALLEL_DL}/" /etc/pacman.conf
sed -i '/^\[multilib\]/{n;s/^#//}' /etc/pacman.conf
sed -i 's/^#\[multilib\]/[multilib]/' /etc/pacman.conf

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen &>/dev/null
echo "LANG=${LOCALE}" > /etc/locale.conf
printf "KEYMAP=${KEYMAP}\nFONT=ter-v16n\n" > /etc/vconsole.conf

echo "${HOSTNAME}" > /etc/hostname
printf "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}\n" > /etc/hosts

if id -u ${USERNAME} &>/dev/null; then
    userdel -r ${USERNAME} 2>/dev/null || true
fi
useradd -mG wheel,video,audio,input,storage,optical ${USERNAME}
grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers || echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

systemctl enable NetworkManager &>/dev/null
systemctl enable bluetooth &>/dev/null
sed -i 's/#AutoEnable=false/AutoEnable=true/' /etc/bluetooth/main.conf 2>/dev/null || true
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &>/dev/null || true
CHROOT
    ) || error "Ошибка настройки системы"
    info "Система настроена"
}

# ─── ПАРОЛИ ───────────────────────────────────────────────────────────────────
set_passwords() {
    section "Пароли"
    check_mnt

    warn "Пароль для root:"
    arch-chroot /mnt /usr/bin/passwd || error "Не удалось установить пароль root"

    warn "Пароль для ${USERNAME}:"
    arch-chroot /mnt /usr/bin/passwd "$USERNAME" || error "Не удалось установить пароль $USERNAME"
}

# ─── GRUB ─────────────────────────────────────────────────────────────────────
install_grub() {
    section "Загрузчик GRUB"
    check_mnt

    arch-chroot /mnt /bin/bash <<CHROOT || error "Ошибка установки GRUB"
set -e
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=3/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --no-nvram --removable
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

    info "GRUB установлен"
}

# ─── УСТАНОВКА DE ─────────────────────────────────────────────────────────────
install_de() {
    section "Рабочее окружение"
    check_mnt

    case $DE_CHOICE in
    0) # KDE Plasma
        warn "Устанавливается KDE Plasma 6..."
        arch-chroot /mnt pacman -Sy --noconfirm
        arch-chroot /mnt pacman -S --noconfirm --needed \
            plasma sddm \
            dolphin konsole kate ark gwenview okular \
            plasma-nm plasma-pa kscreen haruna fastfetch \
            xdg-desktop-portal-kde \
            || error "Ошибка установки KDE"
        arch-chroot /mnt systemctl enable sddm &>/dev/null

        # Alt+Shift раскладка
        arch-chroot /mnt /bin/bash <<CHROOT
mkdir -p /home/${USERNAME}/.config
cat > /home/${USERNAME}/.config/kxkbrc <<EOF
[Layout]
LayoutList=us,ru
Model=pc105
Options=grp:alt_shift_toggle
ResetOldOptions=true
SwitchMode=Global
UseConfigFile=true
VariantList=,
EOF
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
CHROOT
        info "KDE Plasma 6 установлен"
        ;;

    1) # GNOME
        warn "Устанавливается GNOME 46..."
        arch-chroot /mnt pacman -S --noconfirm --needed \
            gnome gnome-extra gdm \
            xdg-desktop-portal-gnome \
            || error "Ошибка установки GNOME"
        arch-chroot /mnt systemctl enable gdm &>/dev/null
        info "GNOME установлен"
        ;;

    2) # XFCE
        warn "Устанавливается XFCE..."
        arch-chroot /mnt pacman -S --noconfirm --needed \
            xfce4 xfce4-goodies lightdm lightdm-gtk-greeter \
            xdg-desktop-portal-gtk \
            || error "Ошибка установки XFCE"
        arch-chroot /mnt systemctl enable lightdm &>/dev/null
        info "XFCE установлен"
        ;;

    3) # Hyprland
        warn "Устанавливается Hyprland..."
        arch-chroot /mnt pacman -S --noconfirm --needed \
            hyprland xdg-desktop-portal-hyprland \
            waybar wofi kitty \
            sddm \
            || error "Ошибка установки Hyprland"
        arch-chroot /mnt systemctl enable sddm &>/dev/null

        # Базовый конфиг Hyprland
        arch-chroot /mnt /bin/bash <<CHROOT
mkdir -p /home/${USERNAME}/.config/hypr
cat > /home/${USERNAME}/.config/hypr/hyprland.conf <<'EOF'
monitor=,preferred,auto,1
exec-once=waybar
input { kb_layout=us,ru; kb_options=grp:alt_shift_toggle }
general { gaps_in=5; gaps_out=10; border_size=2 }
decoration { rounding=10 }
bind=SUPER,Return,exec,kitty
bind=SUPER,Q,killactive
bind=SUPER,D,exec,wofi --show drun
EOF
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
CHROOT
        info "Hyprland установлен"
        ;;
    esac
}

# ─── ДРАЙВЕРЫ GPU ─────────────────────────────────────────────────────────────
install_gpu_drivers() {
    section "Драйверы GPU: $GPU_DRIVER"

    arch-chroot /mnt /bin/bash <<CHROOT
set -e
pacman -Sy --noconfirm &>/dev/null
case "${GPU_DRIVER}" in
    nvidia-open)
        pacman -S --noconfirm --needed \
            nvidia-open nvidia-open-dkms nvidia-utils \
            lib32-nvidia-utils nvtop nvidia-settings &>/dev/null
        sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1"/' /etc/default/grub
        systemctl enable nvidia-suspend nvidia-hibernate nvidia-resume &>/dev/null 2>&1 || true
        ;;
    nvidia)
        pacman -S --noconfirm --needed \
            nvidia nvidia-utils lib32-nvidia-utils nvtop nvidia-settings &>/dev/null
        sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1"/' /etc/default/grub
        ;;
    nouveau)
        pacman -S --noconfirm --needed mesa xf86-video-nouveau &>/dev/null
        ;;
    amd-vulkan)
        pacman -S --noconfirm --needed \
            mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon \
            xf86-video-amdgpu radeontop &>/dev/null
        ;;
    amd)
        pacman -S --noconfirm --needed mesa lib32-mesa xf86-video-amdgpu &>/dev/null
        ;;
    intel-new)
        pacman -S --noconfirm --needed \
            mesa intel-media-driver vulkan-intel lib32-mesa lib32-vulkan-intel &>/dev/null
        ;;
    intel-old)
        pacman -S --noconfirm --needed \
            mesa libva-intel-driver lib32-mesa &>/dev/null
        ;;
    *)
        pacman -S --noconfirm --needed mesa lib32-mesa &>/dev/null
        ;;
esac
mkinitcpio -P &>/dev/null
grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
CHROOT

    info "Драйвер $GPU_DRIVER установлен"
}

# ─── ИГРЫ ─────────────────────────────────────────────────────────────────────
install_gaming() {
    section "Игровые пакеты"
    check_mnt

    warn "Устанавливаются игровые пакеты..."
    arch-chroot /mnt pacman -S --noconfirm --needed \
        steam lutris \
        wine wine-mono winetricks \
        gamemode lib32-gamemode \
        mangohud lib32-mangohud \
        gamescope \
        || error "Ошибка установки игровых пакетов"
    info "Игровые пакеты установлены"
}

# ─── YAY + ПРИЛОЖЕНИЯ ─────────────────────────────────────────────────────────
install_apps() {
    section "Приложения"
    check_mnt

    # yay
    warn "Устанавливаю yay..."
    arch-chroot /mnt /bin/bash <<CHROOT || error "Ошибка установки yay"
cd /tmp
sudo -u ${USERNAME} git clone https://aur.archlinux.org/yay.git
cd yay
sudo -u ${USERNAME} makepkg -si --noconfirm
CHROOT
    info "yay установлен"

    # Системные пакеты
    warn "Устанавливаю системные пакеты..."
    arch-chroot /mnt pacman -S --noconfirm --needed \
        obs-studio htop p7zip unrar xdg-utils fastfetch \
        nodejs npm \
        || error "Ошибка установки системных пакетов"

    # Claude Code
    run_bg "Claude Code" arch-chroot /mnt npm install -g @anthropic-ai/claude-code

    # AUR пакеты
    warn "AUR пакеты — займёт время, вывод идёт ниже..."
    arch-chroot /mnt sudo -u ${USERNAME} yay -S --noconfirm \
        visual-studio-code-bin \
        zen-browser-bin \
        ayugram-desktop \
        discord \
        spotify \
        heroic-games-launcher-bin \
        modrinth-app \
        gruvbox-plus-icon-theme-git \
        || error "Ошибка установки AUR пакетов"

    # Discord фикс NVIDIA
    arch-chroot /mnt sed -i \
        's|Exec=/usr/bin/discord|Exec=/usr/bin/discord --use-gl=desktop|' \
        /usr/share/applications/discord.desktop 2>/dev/null || true

    # fastfetch конфиг
    arch-chroot /mnt /bin/bash <<CHROOT
mkdir -p /home/${USERNAME}/.config/fastfetch
cat > /home/${USERNAME}/.config/fastfetch/config.jsonc <<'EOF'
{
  "display": { "separator": "  ", "color": { "keys": "blue", "title": "cyan" } },
  "modules": [
    "title","separator","os","host","kernel","uptime",
    "packages","shell","display","de","wm","theme",
    "icons","terminal","cpu","gpu","memory","disk",
    "break","colors"
  ]
}
EOF
echo 'fastfetch' >> /home/${USERNAME}/.bashrc
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
CHROOT

    info "Все приложения установлены"
}

# ─── Xbox DNS ─────────────────────────────────────────────────────────────────
setup_dns() {
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
}

# ─── ФИНАЛЬНЫЙ ЭКРАН ──────────────────────────────────────────────────────────
finish() {
    STEP=$TOTAL_STEPS
    clear
    echo ""
    draw_logo

    echo -e "${G}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}  ║          ✓  Установка завершена успешно!             ║${NC}"
    echo -e "${G}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "  ${W}Конфигурация:${NC}"
    echo -e "  ${B}│${NC}  DE       ${W}$(case $DE_CHOICE in 0) echo "KDE Plasma 6";; 1) echo "GNOME 46";; 2) echo "XFCE";; 3) echo "Hyprland";; esac)${NC}"
    echo -e "  ${B}│${NC}  GPU      ${W}$GPU_DRIVER${NC}"
    echo -e "  ${B}│${NC}  User     ${W}$USERNAME${NC}"
    echo -e "  ${B}│${NC}  DNS      ${W}Xbox (13.107.237.38)${NC}  ${DIM}→ ~/apply-xbox-dns.sh${NC}"
    echo ""

    echo -e "  ${W}После перезагрузки:${NC}"
    echo -e "  ${DIM}1.${NC}  ${W}bash ~/apply-xbox-dns.sh${NC}"
    echo -e "  ${DIM}2.${NC}  Параметры системы → Иконки → ${W}Gruvbox-Plus-Dark${NC}"
    echo -e "  ${DIM}3.${NC}  Steam → Совместимость → ${W}Proton для всех игр${NC}"
    echo -e "  ${DIM}4.${NC}  CS2 лаунч опции: ${W}gamescope -w 1280 -h 960 -W 1920 -H 1080 -f -- %command%${NC}"
    echo ""

    echo -e "  ${C}Перезагрузиться? (y/n)${NC}"
    read -rp "  > " r
    if [ "$r" == "y" ]; then
        umount -R /mnt
        reboot
    else
        info "umount -R /mnt && reboot — когда будешь готов"
    fi
}

# ════════════════════════════════════════════════════════
#  ЗАПУСК
# ════════════════════════════════════════════════════════
setfont ter-v16n 2>/dev/null || true

clear
echo ""
draw_logo
echo -e "  ${B}═══════════════════════════════════════════════════════${NC}"
echo -e "  ${DIM}Установит Arch Linux с полным окружением.${NC}"
echo -e "  ${DIM}Windows не будет удалена при правильном выборе разделов.${NC}"
echo -e "  ${B}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${C}Начать установку? (y/n)${NC}"
read -rp "  > " start
[[ "$start" == "y" ]] || error "Отменено"

[ -d /sys/firmware/efi ] || error "Не UEFI. Включи EFI в настройках VM/BIOS"
ping -c1 -W3 archlinux.org &>/dev/null || error "Нет интернета"

detect_hardware
select_install_mode
select_de
select_gpu_driver
select_partitions
setup_mirrors
format_and_mount
install_base
configure_system
set_passwords
install_grub
install_de
install_gpu_drivers
install_gaming
install_apps
setup_dns
finish
