#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# install-debian.sh: Install Debian 13 + KDE Plasma on a whole disk without
# the GUI installer.
#
# WARNING: This erases the disk completely. Nothing on it survives!
#
set -euo pipefail

### Settings (edit) ###########################################################
DISK=/dev/nvme0n1
HOSTNAME=izanagi
USERNAME=ray
FULLNAME="Ray Chen"
TIMEZONE=Asia/Singapore
LOCALE=en_US.UTF-8
KEYMAP=us
SWAP_SIZE=64G
ESP_SIZE=1G
BOOT_SIZE=954M
SUITE=trixie
MIRROR=http://deb.debian.org/debian
###############################################################################

log() { printf '\n==> %s\n' "$*"; }
die() {
  echo "ERROR: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || die "run as root (sudo bash install-debian.sh)"

# Run in a private mount namespace. Otherwise the target's mounts (and the
# /dev, /proc, ... bind mounts below them) leak into the namespaces of
# running services like udevd and logind, the final `umount -R /mnt`
# can't reach those copies, and vg0 stays busy at the end. As a bonus the
# mounts vanish on their own if the script fails halfway.
if [ -z "${INSTALL_DEBIAN_PRIVATE_NS:-}" ]; then
  exec env INSTALL_DEBIAN_PRIVATE_NS=1 \
    unshare --mount --propagation private bash "$0" "$@"
fi

[ -d /sys/firmware/efi ] || die "not booted in UEFI mode"
[ -b "$DISK" ] || die "$DISK is not a block device"

# nvme0n1 -> nvme0n1p1, sda -> sda1
part() { if [[ "$DISK" =~ [0-9]$ ]]; then echo "${DISK}p$1"; else echo "${DISK}$1"; fi; }
ESP="$(part 1)"
BOOT="$(part 2)"
LUKS="$(part 3)"
CRYPT_NAME="$(basename "$LUKS")_crypt"

lsblk "$DISK"
read -rp "Type the disk name ($DISK) to ERASE it and continue: " ans
[ "$ans" = "$DISK" ] || die "aborted"

log "Live-environment tools"
apt-get update
apt-get install -y debootstrap gdisk parted cryptsetup lvm2 dosfstools

log "Partitioning $DISK"
swapoff -a || true
vgchange -an vg0 2>/dev/null || true
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+"$ESP_SIZE" -t1:ef00 -c1:EFI \
  -n2:0:+"$BOOT_SIZE" -t2:8300 -c2:boot \
  -n3:0:0 -t3:8309 -c3:luks "$DISK"
partprobe "$DISK"
udevadm settle

log "Filesystems for ESP and /boot"
mkfs.fat -F32 -n EFI "$ESP"
mkfs.ext4 -F -L boot "$BOOT"

log "LUKS2 (you'll set the disk passphrase now)"
cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 \
  --key-size 512 --pbkdf argon2id "$LUKS"
cryptsetup open "$LUKS" "$CRYPT_NAME"

log "LVM: vg0 with swap + root"
pvcreate "/dev/mapper/$CRYPT_NAME"
vgcreate vg0 "/dev/mapper/$CRYPT_NAME"
lvcreate -y -L "$SWAP_SIZE" -n swap vg0
lvcreate -y -l 100%FREE -n root vg0
mkswap -L swap /dev/vg0/swap
mkfs.ext4 -F -L root /dev/vg0/root

log "Mounting target"
mount /dev/vg0/root /mnt
mkdir -p /mnt/boot && mount "$BOOT" /mnt/boot
mkdir -p /mnt/boot/efi && mount "$ESP" /mnt/boot/efi

log "debootstrap $SUITE"
debootstrap --arch amd64 --components=main,contrib,non-free,non-free-firmware \
  "$SUITE" /mnt "$MIRROR"

log "Base configuration"
rm -f /mnt/etc/apt/sources.list
cat >/mnt/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: $MIRROR
Suites: $SUITE $SUITE-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $SUITE-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

echo "$HOSTNAME" >/mnt/etc/hostname
cat >/mnt/etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
EOF

cat >/mnt/etc/fstab <<EOF
/dev/mapper/vg0-root                       /          ext4  errors=remount-ro  0 1
UUID=$(blkid -s UUID -o value "$BOOT")  /boot      ext4  defaults           0 2
UUID=$(blkid -s UUID -o value "$ESP")                             /boot/efi  vfat  umask=0077         0 1
/dev/mapper/vg0-swap                       none       swap  sw                 0 0
EOF

echo "$CRYPT_NAME UUID=$(blkid -s UUID -o value "$LUKS") none luks,discard,x-initrd.attach" >/mnt/etc/crypttab

mkdir -p /mnt/etc/initramfs-tools/conf.d
echo "RESUME=/dev/mapper/vg0-swap" >/mnt/etc/initramfs-tools/conf.d/resume

cat >/mnt/etc/default/keyboard <<EOF
XKBMODEL="pc105"
XKBLAYOUT="$KEYMAP"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

log "Entering chroot"
for d in dev proc sys run; do
  mount --rbind "/$d" "/mnt/$d"
  mount --make-rslave "/mnt/$d"
done

# Written to a file (not piped in on stdin) so apt can't swallow the rest of the
# script and passwd gets the real terminal for your password
cat >/mnt/root/setup.sh <<'CHROOT'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Locale and time zone
apt-get install -y locales
sed -i "s/^# *\($LOCALE .*\)/\1/" /etc/locale.gen
locale-gen
update-locale LANG="$LOCALE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

# Also keep a copy of shim + its fallback loader at \EFI\BOOT\ (and keep
# it updated on GRUB upgrades): if the firmware ever loses its boot
# entries (BIOS update, CMOS reset), the fallback recreates them.
echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' |
  debconf-set-selections

# Kernel, firmware, encryption/LVM boot support, Secure Boot-signed bootloader
apt-get install -y \
  linux-image-amd64 linux-headers-amd64 \
  firmware-linux-free firmware-misc-nonfree firmware-amd-graphics firmware-realtek amd64-microcode \
  cryptsetup cryptsetup-initramfs lvm2 \
  grub-efi-amd64 grub-efi-amd64-signed shim-signed efibootmgr \
  sudo console-setup keyboard-configuration tasksel

# Same software selection as the installer: standard utilities + KDE Plasma
tasksel install standard desktop kde-desktop

# Root locked; sudo user (you'll set its password now)
passwd -l root
useradd -m -s /bin/bash -c "$FULLNAME" -G sudo "$USERNAME"
echo "Set the password for $USERNAME:"
passwd "$USERNAME"

# Bootloader (installs shim for Secure Boot) and initramfs that unlocks LUKS
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian \
  --force-extra-removable
update-grub
update-initramfs -u -k all
CHROOT

chroot /mnt env USERNAME="$USERNAME" FULLNAME="$FULLNAME" \
  TIMEZONE="$TIMEZONE" LOCALE="$LOCALE" bash /root/setup.sh
rm -f /mnt/root/setup.sh

log "Cleaning up"
umount -R /mnt
vgchange -an vg0
cryptsetup close "$CRYPT_NAME"

log "Done. Remove the USB and reboot."
echo "First boot: enter the LUKS passphrase, then Ctrl+Alt+F2, log in as $USERNAME, clone"
echo "the dotfiles repo and run linux/sh/ in order (see linux/README.md)."
