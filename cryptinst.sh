#!/bin/bash
#
## ENV - VARIABLES
#

EFI_PARTITION=/dev/vda1
CRYPT_PARTITION=/dev/vda2
CRYPT=cv
MOUNT_POINT=/mnt
ROOT_SUB=@
SWAP_SUB=@swap
HOME_SUB=@home
SNAPSHOTS_SUB=@snapshots
BTRFS_OPTS="rw,noatime,compress=zstd,discard=async"

#
## LUKS - BTRFS Setup
#

echo "=> Formatting as encrypted partition..."
cryptsetup luksFormat --type luks1 -y $CRYPT_PARTITION
echo "=> Open the encrypted volume (re-type passphrase)"
cryptsetup open $CRYPT_PARTITION $CRYPT
echo "=> Formatting as FAT EFI partition..."
mkfs.fat -F32 -n EFI $EFI_PARTITION
echo "=> Formatting as BTRFS Encrypted volume..."
mkfs.btrfs /dev/mapper/$CRYPT
echo "=> Mounting Encrypted BTRFS Volume..."
mount -o $BTRFS_OPTS /dev/mapper/$CRYPT $MOUNT_POINT
echo "=> Creating Encrypted BTRFS @ROOT @SWAP @HOME @SNAPSHOTS SUB-Volume..."
btrfs su cr $MOUNT_POINT/@
btrfs su cr $MOUNT_POINT/@swap
btrfs su cr $MOUNT_POINT/@home
btrfs su cr $MOUNT_POINT/@snapshots
echo "=> Successfully Created all SUB-Volumes..."
echo "=> Umounting Encrypted BTRFS Volume..."
umount $MOUNT_POINT
echo "=> Mounting Encrypted BTRFS @ROOT SUB-Volume..."
mount -o $BTRFS_OPTS,subvol=@ /dev/mapper/$CRYPT $MOUNT_POINT
echo "=> Creating tree hierarchy mount points {efi, swap, home, .snapshots} ..."
mkdir $MOUNT_POINT/{efi,swap,home,.snapshots}
echo "=> Mounting Encrypted BTRFS SUB-Volumes tree hierarchy..."
mount -o $BTRFS_OPTS,subvol=@swap /dev/mapper/$CRYPT $MOUNT_POINT/swap
mount -o $BTRFS_OPTS,subvol=@home /dev/mapper/$CRYPT $MOUNT_POINT/home
mount -o $BTRFS_OPTS,subvol=@snapshots /dev/mapper/$CRYPT $MOUNT_POINT/.snapshots
echo "=> Encrypted storage is now ready for installation!!!"
read -p "Continue..."

#
## SWAP / Partitions mount setup
#

echo "=> Allocating space for swapfile..."
truncate -s 0 $MOUNT_POINT/swap/swapfile
chattr +C $MOUNT_POINT/swap/swapfile
fallocate -l $(awk '/MemTotal/ {print $2"K"}' /proc/meminfo) $MOUNT_POINT/swap/swapfile
echo "=> Preparing swapfile..."
chmod 600 $MOUNT_POINT/swap/swapfile
mkswap $MOUNT_POINT/swap/swapfile
echo "=> Preparing TEMP SUB-Volumes for pacman..."
mkdir -p $MOUNT_POINT/var/cache
btrfs su cr $MOUNT_POINT/var/cache/pacman
btrfs su cr $MOUNT_POINT/var/tmp
btrfs su cr $MOUNT_POINT/srv
echo "=> Mounting EFI Partition..."
mount -o rw,noatime $EFI_PARTITION $MOUNT_POINT/efi

read -p "Continue to install base packages before chroot target..."

#
## Arch base target install
#

echo "=> Installing packages into target..."
pacstrap $MOUNT_POINT base linux linux-firmware btrfs-progs cryptsetup neovim sudo
for dir in dev proc sys run; do mount --rbind /$dir $MOUNT_POINT/$dir; mount --make-rslave $MOUNT_POINT/$dir; done
cp /etc/resolv.conf $MOUNT_POINT/etc
echo "=> Base system prepared"

#
## Copy this script trimmed (script for chroot)
#

echo "=> Trimming script inside chroot..."
echo "=> Copying trimmed script..."

echo -e '#!/bin/bash\n\n'"$(sed -n -e '/.*ENV/,$p' cryptinst.sh | sed '1,/^$/d' | head -11)" > $MOUNT_POINT/tmp/cryptinst_chroot.sh
echo -e "$(sed -n -e '/.*<i>/,$p' cryptinst.sh | sed '1,/^$/d')" >> $MOUNT_POINT/tmp/cryptinst_chroot.sh
chmod +x $MOUNT_POINT/tmp/cryptinst_chroot.sh
read -p "Continue to enter chroot..."
echo "=> Chroot..."
chroot $MOUNT_POINT /bin/bash -c "./tmp/cryptinst_chroot.sh"
rm $MOUNT_POINT/tmp/cryptinst_chroot.sh
umount -l $MOUNT_POINT
cryptsetup luksClose $CRYPT
read -p "System Installed, Press Enter to Exit..."
exit
#reboot

#
## <i> Trimmed chroot script
#

echo "=> Now inside target base-system!!!"
echo "=> Now customize system..."
read -p "Press Enter to Continue..."

echo "@ HWCLOCK, TIMEZONE & KEYMAP @"
read -p "Press Enter to Uncomment target HWCLK, TIMEZONE & KEYMAP"
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock --systohc
echo "LANG=es_ES.UTF-8" > /etc/locale.conf
echo "KEYMAP=de-latin1" > /etc/vconsole.conf

#
## Uncomment libc-locales, set hostname, customize hosts file
#

echo "@ libC Locales @"
read -p "Press Enter to Uncomment target libc-Locales"
nvim /etc/locale.gen
locale-gen
echo "@ Hostname @"
read -p "Press Enter to set Hostname"
nvim /etc/hostname
echo "@ Hosts File @"
read -p "Press Enter to update Hosts file"
echo "#<ip-address>   <hostname.domain.org> <hostname>" >> /etc/hosts
echo "127.0.0.1   localhost.localdomain localhost" >> /etc/hosts
echo "::1   localhost.localdomain localhost ip6-localhost" >> /etc/hosts
nvim /etc/hosts
echo "=> Setting Bash as default shell"
chsh -s /bin/bash root
echo "@ ROOT password @"
read -p "Press Enter to set ROOT password"
passwd root

#
## EDIT visudo members accesses (uncomment wheel group)
#

read -p "Press Enter to grant %wheel group sudo access"

EDITOR=nvim visudo

echo "=> Setting partitions mountpoints (FSTAB)..."

echo "tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0" > /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/mapper/$CRYPT) / btrfs $BTRFS_OPTS,subvol=$ROOT_SUB 0 1" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/mapper/$CRYPT) /swap btrfs defaults,subvol=$SWAP_SUB 0 2" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/mapper/$CRYPT) /home btrfs $BTRFS_OPTS,subvol=$HOME_SUB 0 2" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/mapper/$CRYPT) /.snapshots btrfs $BTRFS_OPTS,subvol=$SNAPSHOTS_SUB 0 2" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value $EFI_PARTITION) /efi vfat defaults,noatime 0 2" >> /etc/fstab
echo "/swap/swapfile none swap sw 0 0" >> /etc/fstab

echo "=> Installing GRUB package..."
pacman -S grub efibootmgr

echo -e 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5' > /etc/default/grub
echo -e 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 rd.auto=1 rd.luks.allow-discards"' >> /etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value $CRYPT_PARTITION):$CRYPT root=/dev/mapper/$CRYPT cryptkey=rootfs:/boot/keyfile.bin\"" >> /etc/default/grub
echo -e 'GRUB_DISABLE_OS_PROBER=false\nGRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
echo "@ GRUB cfg file CHECK @"
read -p "Press Enter to check GRUB CFG"
nvim /etc/default/grub

echo "=> Generating second slot keyfile for auto decryption (decrypt once)..."
dd bs=515 count=4 if=/dev/urandom of=/boot/keyfile.bin
cryptsetup -v luksAddKey $CRYPT_PARTITION /boot/keyfile.bin
chmod 000 /boot/keyfile.bin
chmod -R g-rwx,o-rwx /boot
echo "cryptroot UUID=$(blkid -s UUID -o value $CRYPT_PARTITION) /boot/keyfile.bin luks" >> /etc/crypttab

sed -i 's/^HOOKS.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/g' /etc/mkinitcpio.conf
sed -i 's:^FILES.*:FILES=(/boot/keyfile.bin):g' /etc/mkinitcpio.conf

echo "=> Installing GRUB into efi..."
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id="Linux"
grub-mkconfig -o /boot/grub/grub.cfg

echo "=> Installing specified packages..."
pacman -Sy dhcpcd networkmanager bluez xorg sddm wayland weston xorg-xwayland
pacman -S xfce4 plasma-desktop kscreen sddm plasma-pa konsole kitty gvfs gvfs-mtp fuse3 firefox pcmanfm-qt
pacman -S pipewire rtkit slurp xdg-desktop-portal xdg-desktop-portal-kde xdg-desktop-portal-wlr

groupadd bluetooth
groupadd pipewire
groupadd dialout
groupadd pulse
groupadd pulse-access

echo "=> Linking DHCP Daemon..."
systemctl enable dhcpcd NetworkManager NetworkManager-dispatcher NetworkManager-wait-online

echo "=> Linking WPA_SUPPLICANT Daemon..."
systemctl enable wpa_supplicant

echo "=> Linking Common Daemons..."
systemctl enable dbus bluetooth sddm

echo "=> Linking pipewire defaults..."
mkdir -p /etc/pipewire/pipewire.conf.d /etc/alsa/conf.d

echo "=> Add user..."
read -p "Press Enter to add user accounts"
nvim /tmp/usertmp
while read u; do useradd -m "$u"; done < /tmp/usertmp
echo "=> User accounts added..."
while read u; do usermod -aG wheel,tty,dialout,audio,video,bluetooth,pipewire,pulse,pulse-access "$u"; done < /tmp/usertmp
echo "=> User accounts added to every set group"

read -p "Press Enter to set 1st user password"
passwd $(head -n 1 /tmp/usertmp)

echo "=> Generating initramfs..."
mkinitcpio -p linux
echo "=> Done!!!"
exit

#
## <e> End chroot script
#
