# Arch Linux installer (Full Disk Encryption)

Targeted Arch install script that is entirely based on "Full Disk Encryption" from [Void docs](https://docs.voidlinux.org/installation/guides/fde.html).

## Installation

Just clone the repo:
```bash
pacman -Syu git
git clone https://github.com/IvnLum/Arch-Linux-Crypt-Install
cd Arch-Linux-Crypt-Install

# You must edit target partitions (ENV variables) inside script

./cryptinst.sh
```
