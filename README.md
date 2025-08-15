# dotfiles

Personal macOS development environment configuration.

## Usage

```sh
./setup.sh <hostname> # Where <hostname> is your desired hostname for
                      # your system, e.g. "rays-macbook-pro"
```

The [`setup.sh $1`](./setup.sh) script takes care of everything:

- Setting macOS hostname to `$1`
- Setting macOS defaults (firewall on, stealthmode, etc.)
- Installing Xcode dev tools and Rosetta
- Show finder hidden files by default
- Installing brew and development dependencies & tools
- Installing a bunch of fonts
- Installing [zprezto](https://github.com/sorin-ionescu/prezto)
- Installing nix via [DetSys Nix Installer](https://manual.determinate.systems/installation/index.html)
- Installing `python3.11.0` as global system default via [pyenv](https://github.com/pyenv/pyenv)
- Creating configuration symlinks for conf files in [`./conf`](./conf) and [`./nvim`](./nvim)
- etc.

## Essential Apps & Configurations

These are apps not bootstrapped by the setup script, and should be installed
& configured accordingly below.

### [OnyX](https://www.titanium-software.fr/en/onyx.html)

#### Settings - Parameters

- Startup Mode -> Verbose
- Applications -> Display debug menu -> On
- Menus -> Show Quit Finder -> On
- Misc
  - CrashReporter Mode -> Developer
  - Prevent `.DS_Store` files from being created on network devices -> On

### [Little Snitch](https://obdev.at/products/littlesnitch/index.html)

#### Settings

- Run in Alert Mode
- Detail Level -> Show Port and Protocol Details
- Preselected Options -> Domain or Host -> Full Hostname
- Confirm connection alert automatically -> Deny connection attempts after 180seconds
- Security -> Allow access via Terminal
- DNS Encryption -> Off
- Advanced -> BPF Monitoring -> On

### [Micro Snitch](https://www.obdev.at/products/microsnitch/download.html)

#### Settings

- Open at login -> On
- Log activity -> On
- Show overlay when devices are active -> Off

### [Amethyst](https://github.com/ianyh/Amethyst/releases/tag/v0.24.0)

#### Settings

- General -> Window Margins -> Enabled, 6px
- Layouts -> Remove Wide, Remove Column
- Debug -> Show debug info about layouts -> On
- Floating
  - Float small windows -> On
  - Automatically float applications listed
    - `com.apple.systempreferences`
- Shortcuts
  - Shrink Main Pane -> Cmd+Shift+H
  - Expand Main Pane -> Cmd+Shift+L
  - Swap focused windows clockwise -> Cmd+Shift+X
  - Relaunch Amethyst -> Cmd+Z
  - Remove everything else

### [Sublime Merge](https://www.sublimemerge.com/download_thanks?target=mac)

#### Settings

- Theme -> Dark
- Font Face -> Monaspace Krypton
- Font Size -> 16

### [Flux](https://justgetflux.com)

#### Settings

- Custom colors -> Set Daytime + Sunset + Bedtime to: 2700K (Tungsten)

### [Raycast](https://www.raycast.com/)

#### Settings - General

- Raycast AI -> Off

#### Settings - Extensions

- Disable everything except:
  - Applications
  - Calculator
  - Clipboard History
  - Search Emoji & Symbols
  - Snippets
  - System
  - System Settings
  - Translate

### [CleanShot X](https://licenses.cleanshot.com/download/cleanshotx)

#### Settings

- Replace macOS default screenshot hotkeys

#### Recording - General

- Display recording time -> On
- Do Not Disturb while recording -> On
- Show cursor -> on
- Highlight clicks -> on
- Show countdown -> On

#### Advanced

- File name: `screencap-,%y,-,%m,-,%d,-,%H,.,%M,.,%S`
- Remove illegal characters -> On
- Use UTC time -> Off
- Keep history -> 1 month
- All-in-One -> Remember last selection
- Add "2x" suffix to retina screenshots -> On

### [Firefox](https://www.firefox.com/en-US/)

- Sign in with Firefox Sync
- DevTools -> Dock to right

### [Ghostty](https://ghostty.org/download)

Configuration handled by setup script.

### [1Password](https://1password.com/downloads/mac)

No additional config.

### [Discord](https://discord.com/download)

No additional config.

### [Slack](https://slack.com/intl/en-sg/downloads/mac)

No additional config.

### [Chrome](https://www.google.com/intl/en_sg/chrome/)

No additional config.

### [Yaak](https://yaak.app/download)

No additional config.

### [Sublime Text](https://www.sublimetext.com/download_thanks?target=mac)

No additional config.

### [AppCleaner](https://freemacsoft.net/appcleaner/)

No additional config.

### [Claude](https://claude.ai/download)

No additional config.

## Essential macOS Settings

### Finder

- New Finder windows show: Documents
- Sync Desktop & Documents folders -> On
- Open folders in tabs instead of new windows -> On
- Show all filename extensions -> On
- Show warning before changing an extension -> Off
- When performing a search -> Search the Current Folder
- Remove items from the Trash after 30 days -> On

### Trackpad

- Scroll Speed -> 80%
- Use Trackpad for dragging -> On
- Dragging style -> Three Finger Drag

### Keyboard

- Key Repeat Rate - Fast 100%
- Delay until repeat - Short 100%
- Function Keys - Use F1, F2, etc. as standard function keys - On
- Modifier Keys - Caps Lock -> Escape
- Shortcuts -> Spotlight -> Show spotlight search -> Off
- Text Replacements -> Delete all

### Input Sources -> U.S.

- Correct spelling automatically -> Off
- Capitalize words automatically -> Off
- Show inline predictive text -> Off
- Show suggested replies -> On
- Add period with double-space -> Off
- Spelling -> Automatic by language
- Use smart quotes and dashes -> Off

### Desktop & Dock

- Dock Size -> Smallest
- Dock Magnification -> 80%
- Position on screen -> Right
- Show suggested & recent apps in Dock -> Off

### Control Center

- Show date -> Display time with seconds
- Battery -> Show percentage

## License

[MIT](./LICENSE)
