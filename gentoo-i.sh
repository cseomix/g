#!/bin/bash
set -e

### КОНФИГУРАЦИЯ ###
TARGET_DISK="/dev/sda"
TIMEZONE="Europe/Moscow"
HOSTNAME="gentoo"
ROOT_PASSWORD="gentoo0012"
USERNAME="cseomix"
USER_PASSWORD="0012"

### РАЗМЕТКА ДИСКА ###
echo "Разметка диска $TARGET_DISK..."
parted -s $TARGET_DISK mklabel gpt
parted -s $TARGET_DISK mkpart primary 1MiB 513MiB
parted -s $TARGET_DISK set 1 esp on
parted -s $TARGET_DISK mkpart primary 513MiB 100%

### ФОРМАТИРОВАНИЕ ###
echo "Форматирование..."
mkfs.fat -F32 ${TARGET_DISK}1
mkfs.ext4 ${TARGET_DISK}2

### МОНТИРОВАНИЕ ###
echo "Монтирование..."
mount ${TARGET_DISK}2 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount ${TARGET_DISK}1 /mnt/gentoo/boot

### УСТАНОВКА STAGE3 (OpenRC версия) ###
echo "Загрузка stage3..."
cd /mnt/gentoo
STAGE3_URL=$(curl -s https://www.gentoo.org/downloads/ | grep -oP 'https://[^"]*stage3-amd64-desktop-openrc-[^"]*\.tar\.xz' | head -1)
wget $STAGE3_URL
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

### НАСТРОЙКА БАЗОВОЙ СИСТЕМЫ ###
echo "Настройка системы..."

# make.conf с вашими настройками
cat << EOF > /mnt/gentoo/etc/portage/make.conf
# Процессорные флаги
COMMON_FLAGS="-march=znver3 -O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"

# Глобальные USE-флаги
USE="X wayland elogind -systemd dbus screencast nvidia egl gles2 gbm vulkan pipewire"

# Поддержка 32-бит
ABI_X86="32"

# Графическая подсистема
VIDEO_CARDS="nvidia"

# Параметры сборки
MAKEOPTS="-j12"
GENTOO_MIRRORS="https://mirror.yandex.ru/gentoo-distfiles/"

# Лицензии
ACCEPT_LICENSE="nvidia-drivers"
EOF

# resolv.conf
cp /etc/resolv.conf /mnt/gentoo/etc/

# fstab
genfstab -U /mnt/gentoo >> /mnt/gentoo/etc/fstab

# chroot
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

### CHROOT СКРИПТ (OpenRC) ###
chroot /mnt/gentoo /bin/bash << EOF
set -e

### НАСТРОЙКА В CHROOT ###
echo "Настройка в chroot..."

# Часовой пояс
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Локали
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

# Имя хоста
echo $HOSTNAME > /etc/hostname

# Пароль root
echo "root:$ROOT_PASSWORD" | chpasswd

# Обновление репозитория
emerge-webrsync

# Установка исходников ядра и компиляция
echo "Установка и компиляция ядра..."
emerge -q sys-kernel/gentoo-kernel-bin

# Загрузчик
emerge -q sys-boot/grub
grub-install ${TARGET_DISK}
grub-mkconfig -o /boot/grub/grub.cfg

# Сеть
emerge -q net-misc/dhcpcd
rc-update add dhcpcd default

# Пользователь
useradd -m -G wheel,audio,video,usb,portage $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Sudo
emerge -q app-admin/sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# elogind
emerge -q sys-auth/elogind
rc-update add elogind boot

# NVIDIA драйверы
emerge -q x11-drivers/nvidia-drivers

# Обновление системы
emerge -uDNq @world

# Завершение
emerge --depclean -q
EOF

### ЗАВЕРШЕНИЕ ###
echo "Установка завершена! Перезагрузите систему."
umount -R /mnt/gentoo
