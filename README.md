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

## License

[MIT](./LICENSE)
