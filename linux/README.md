# <img src="../assets/linux.svg" height="28" align="absmiddle"> dotfiles -- Linux

[[<-- back to main]](../) | [[<img src="../assets/apple.svg" height="14" align="absmiddle"> macOS config -->]](../macos/)

## Environment

### Base System

- **Distro**: Debian 13 Trixie
- **Desktop Environment**: KDE Plasma 6.3 / Wayland

### Disk Layout

Unencrypted ESP and `/boot`, with everything else in LUKS2 + LVM:

```
$DISK
|
+-- p1  ESP          1G     FAT32   /boot/efi    unencrypted (shim + GRUB)
|
+-- p2  boot       954M     ext4    /boot        unencrypted (kernel + initramfs)
|
+-- p3  LUKS2      rest             encrypted:   aes-xts-plain64, 512-bit key
    |                                            (AES-256), argon2id
    +-- <p3>_crypt                  unlocked at boot (passphrase)
        |
        +-- LVM PV
            |
            +-- VG vg0
                |
                +-- LV swap    64G   swap     (also hibernation/resume)
                |
                +-- LV root   rest   ext4   /
```

## Installation

[`install-debian.sh`](./install-debian.sh) installs Debian 13 on a whole
disk, without the GUI installer. It partitions the disk with the layout
above, sets up an encrypted LUKS2 container (AES-256, argon2id) with LVM
inside it for swap and root, and installs Debian into it with
`debootstrap`. It then adds KDE Plasma, a signed shim + GRUB bootloader
for Secure Boot, an initramfs that asks for the LUKS passphrase at boot
(with TRIM and resume from swap enabled), and your user with `sudo`; root
stays locked.

> **⚠️ WARNING**: This erases the target disk completely. Nothing on it
> survives!

1. Flash a Debian 13 **standard** live ISO
   (`debian-live-13.x-amd64-standard.iso`) to a USB stick. It has no
   desktop, which keeps it small: the script downloads KDE itself. Other
   live flavors (e.g. KDE) work too. The netinst ISO won't -- its installer
   only has a minimal BusyBox shell, without bash or apt.
2. Boot it in UEFI mode (F12 on the Gigabyte board, pick the "UEFI:"
   entry). Leave Secure Boot on; the installed system boots signed shim +
   GRUB.
3. It boots to a text console, already logged in as `user` (password
   `live`, with passwordless `sudo`); the rest happens there. Use a wired
   connection: it comes up on its own over DHCP, while Wi-Fi needs manual
   setup because the image has no NetworkManager.
4. Get the script onto the live system. git isn't on the standard image,
   so either:
   - install it first (the live system has apt and network; changes vanish
     on reboot):
     ```sh
     sudo apt update && sudo apt install -y git
     git clone https://github.com/half0wl/dotfiles && cd dotfiles/linux
     ```
   - or download just the script from its raw GitHub URL with `wget` or
     `curl` (both are on the image)
   - or copy it from a second USB stick
5. Edit the _Settings_ block at the top of the script. Check at least:
   - `DISK`: run `lsblk` to find the target disk (default `/dev/nvme0n1`)
   - `USERNAME`, `FULLNAME`, `HOSTNAME`
6. Run it:

   ```sh
   sudo bash install-debian.sh
   ```

   It will ask you to:
   - type the disk name to confirm the wipe
   - set the LUKS passphrase (twice); it's typed at every boot, and losing
     it loses the data
   - set your user password; root stays locked and your user gets sudo

   The KDE install downloads ~2-3 GB and takes a while.

7. When it prints "Done", remove the USB stick and reboot.

If something fails partway, fix the cause and re-run from the start. It
re-wipes the disk, so there's no partial state to clean up. If the target
is still mounted, first run:

```sh
umount -R /mnt; vgchange -an vg0; cryptsetup close <name>_crypt
```

## Setup

On first boot, enter the LUKS passphrase. The login screen won't show yet
on an NVIDIA card (no driver), so press Ctrl+Alt+F2 and log in. The repo
cloned during installation is gone with the live system, so get it again:

```sh
sudo apt install -y git
git clone https://github.com/half0wl/dotfiles && cd dotfiles/linux
```

Then run the scripts in [`sh/`](./sh) in order as the normal user (they
use `sudo` where needed), e.g. `./sh/00-default-dirs.sh`:

| Script                                                          | Description                                                                                                                                                                                                                                                          | Dependencies                          |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| [`00-default-dirs.sh`](./sh/00-default-dirs.sh)                 | Points the XDG music, pictures and videos dirs at ~/Documents (templates and public share to hidden folders), then removes the unused default folders (asking before deleting any that aren't empty), and creates the folders the XDG dirs point at plus ~/Workspace | None                                  |
| [`01-update.sh`](./sh/01-update.sh)                             | Performs a full upgrade, installs base packages and applies firmware updates. **Reboot afterwards (with an NVIDIA GPU, after `02-nvidia.sh`).**                                                                                                                      | None                                  |
| [`02-nvidia.sh`](./sh/02-nvidia.sh)                             | Installs the NVIDIA open driver, builds it with DKMS for every kernel and signs it for Secure Boot. **Reboot afterwards; with Secure Boot on, enroll the MOK key then.**                                                                                             | None                                  |
| [`03-system.sh`](./sh/03-system.sh)                             | Enables unattended upgrades (keeping all kernels) and the ufw firewall, switches to TTY login, sets the locale and disables onboard Bluetooth                                                                                                                        | None                                  |
| [`04-storage.sh`](./sh/04-storage.sh)                           | Enables TRIM through LUKS and a weekly `fstrim`, shrinks the ext4 root reserve, adds APFS                                                                                                                                                                            | None                                  |
| [`05-shell.sh`](./sh/05-shell.sh)                               | Installs zsh, CLI packages and mise tools, and links the zsh / git / tmux / neovim / gh configs                                                                                                                                                                      | None                                  |
| [`06-keyd.sh`](./sh/06-keyd.sh)                                 | Sets up a macOS-style keyboard with keyd, including per-app overrides                                                                                                                                                                                                | None                                  |
| [`07-audio.sh`](./sh/07-audio.sh)                               | Builds the AAC codec for AirPods Max 2 over Bluetooth (PipeWire) and tunes Bluetooth LE latency                                                                                                                                                                      | None                                  |
| [`08-qemu-vmm.sh`](./sh/08-qemu-vmm.sh)                         | Installs Incus and QEMU for development containers and VMs, initializes Incus and opens ufw for its bridge. **Log out and back in afterwards.**                                                                                                                      | None                                  |
| [`09-podman.sh`](./sh/09-podman.sh)                             | Installs rootless Podman for development containers, with nothing started at boot                                                                                                                                                                                    | None                                  |
| [`10-fonts.sh`](./sh/10-fonts.sh)                               | Installs common and popular fonts                                                                                                                                                                                                                                    | None                                  |
| [`11-apps.sh`](./sh/11-apps.sh)                                 | Installs Ghostty, Sublime Merge, Firefox, Steam, Little Snitch, VLC, Flatpak apps and AI CLIs                                                                                                                                                                        | None                                  |
| [`12-kde-debloat.sh`](./sh/12-kde-debloat.sh)                   | Purges unused KDE apps (previews and asks first)                                                                                                                                                                                                                     | None                                  |
| [`20-kde-config-font.sh`](./sh/20-kde-config-font.sh)           | Sets Inter as the UI font across KDE, GTK and fontconfig                                                                                                                                                                                                             | Plasma session                        |
| [`21-kde-config-dolphin.sh`](./sh/21-kde-config-dolphin.sh)     | Configures Dolphin to show hidden files, use compact views and show the Information panel                                                                                                                                                                            | Plasma session                        |
| [`22-kde-config-spaces.sh`](./sh/22-kde-config-spaces.sh)       | Adds macOS-style Mission Control and Spaces shortcuts                                                                                                                                                                                                                | Plasma session                        |
| [`23-kde-config-desktop.sh`](./sh/23-kde-config-desktop.sh)     | Configures animations, key repeat, mice, screen lock, session restore, display and launch shortcuts                                                                                                                                                                  | Plasma session                        |
| [`24-kde-config-spectacle.sh`](./sh/24-kde-config-spectacle.sh) | Sets where Spectacle saves screenshots and recordings, and their file names                                                                                                                                                                                          | Plasma session                        |
| [`25-app-config-firefox.sh`](./sh/25-app-config-firefox.sh)     | Links Firefox `user.js` prefs                                                                                                                                                                                                                                        | Plasma session; Firefox launched once |
| [`26-app-config-defaults.sh`](./sh/26-app-config-defaults.sh)   | Sets default apps to open files with. Warns about any that are missing                                                                                                                                                                                               | `05-shell.sh`, `11-apps.sh`           |

### Notes

- Scripts takes `--dry-run` (show what would change), `--yes`
  (answer prompts), and `--help`
- Script are idempotent -- on an already set-up host it only
  reports what it skipped and changes nothing
- To see what a run changed, take a snapshot before and after with
  [`etc/snapshot.sh`](./etc/snapshot.sh) and diff the two. It records the
  config links, packages, services and home folders the scripts manage,
  read-only and without sudo:

  ```sh
  ./etc/snapshot.sh --output=/tmp/before.md
  # ... run the scripts ...
  ./etc/snapshot.sh --output=/tmp/after.md
  diff -u /tmp/before.md /tmp/after.md
  ```

## Config

[`conf/`](./conf) is the source of truth. Scripts never write config
themselves; they symlink each file from `conf/` into place (including
files under `/etc`), so editing a config anywhere edits it here. A file
already in the way is backed up to
`~/.local/state/dotfiles-bak/<timestamp>/` first.

KDE settings live in files Plasma rewrites itself (`kdeglobals`, `kwinrc`,
...), so those values are kept in each KDE script's _Settings_ block
instead -- edit the value there, then re-run the script.

---

[[<-- back to main]](../) | [[<img src="../assets/apple.svg" height="14" align="absmiddle"> macOS config -->]](../macos/)
