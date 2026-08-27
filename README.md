<div align="center">

# nix-epic-games-launcher

**Epic Games on NixOS** — umu-launcher plus an external Proton. Recommended: `proton-cachyos` from [Chaotic-Nyx](https://github.com/chaotic-cx/nyx).

[![NixOS](https://img.shields.io/badge/NixOS-unstable-informational?logo=NixOS)](https://nixos.org)
[![Flake](https://img.shields.io/badge/Flake-enabled-success)](https://nixos.wiki/wiki/Flakes)

</div>

## Quick Start

Point `PROTONPATH` at a Steam compat tool (`steamcompattool` output):

```bash
PROTONPATH=/path/to/proton nix run github:gaavin/nix-epic-games-launcher
```

Requires `x86_64-linux`, flakes, and a Proton already on the system. This flake does not vendor Proton. Prefer [Chaotic-Nyx](https://github.com/chaotic-cx/nyx)'s `proton-cachyos` (see below).

## Install with Home Manager

### 1. Add to flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

    nix-epic-games-launcher.url = "github:gaavin/nix-epic-games-launcher";
    nix-epic-games-launcher.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, chaotic, nix-epic-games-launcher, ... }:
    {
      nixosConfigurations.YOUR_CONFIGURATION = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          chaotic.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit nix-epic-games-launcher; };
              users.YOUR_USERNAME = import ./home.nix;
            };
          }
        ];
      };
    };
}
```

### 2. Enable in `home.nix`

Recommended Proton is [`proton-cachyos`](https://www.nyx.chaotic.cx/) from Chaotic-Nyx. After importing `chaotic.nixosModules.default` (above), it is `pkgs.proton-cachyos`. Other Steam compatibility tools with a `steamcompattool` output (for example `pkgs.proton-ge-bin`) also work.

```nix
{ nix-epic-games-launcher, pkgs, ... }:
{
  imports = [ nix-epic-games-launcher.homeModules.epic-games-launcher ];

  programs.epic-games-launcher = {
    enable = true;
    protonVersion = pkgs.proton-cachyos; # Chaotic-Nyx
  };
}
```

### 3. Build & launch

```bash
nix flake update nix-epic-games-launcher
sudo nixos-rebuild switch --flake .#YOUR_CONFIGURATION
epic-games-launcher
```

First run downloads the MSI installer, creates a Proton prefix, and runs a quiet `msiexec` install. Finish the installer UI if the quiet path does not produce `EpicGamesLauncher.exe`, then run `epic-games-launcher` again.

## Commands

| Command | Purpose |
|---------|---------|
| `epic-games-launcher` | Launch |
| `epic-games-launcher --help` | List all commands |
| `epic-games-launcher --info` | Show config / paths |
| `epic-games-launcher --kill` | Force quit |
| `epic-games-launcher --fix-webcache` | Clear a stuck CEF / login web cache |
| `epic-games-launcher --winecfg` | Wine settings |
| `epic-games-launcher --winetricks …` | winetricks in the prefix |
| `epic-games-launcher --umu …` | Pass args to umu-run |

## Paths

```
~/.local/share/nix-epic-games-launcher/
  prefix/       Proton / Wine prefix
  installer/    EpicGamesLauncherInstaller.msi
  logs/         Debug logs
```

Proton comes from `protonVersion` (or `PROTONPATH`). Epic Games auto-updates inside the prefix.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| White / blank window | `epic-games-launcher --kill`, then launch again. If it persists, set `disableHardwareAcceleration = true` |
| Tray is its own window | Leave `enableProtonWayland` off (default) |
| Stuck on Updating / prereqs | Keep `-SkipBuildPatchPrereq` in `launcherArgs` (default) |
| Login loop / blank CEF | `epic-games-launcher --fix-webcache`, then launch again |
| Proton not found | Add Chaotic-Nyx and set `programs.epic-games-launcher.protonVersion = pkgs.proton-cachyos` |
| DX12: no valid video card | Leave `useWineD3D` off (default), then restart Epic Games |
| Stuck Wine processes | `epic-games-launcher --kill` |
| Start fresh | Remove `~/.local/share/nix-epic-games-launcher/` |

## Advanced

Package only:

```nix
home.packages = [
  (inputs.nix-epic-games-launcher.packages.${pkgs.stdenv.hostPlatform.system}.epic-games-launcher.override {
    protonVersion = pkgs.proton-cachyos;
  })
];
```

Overrides:

```nix
inputs.nix-epic-games-launcher.packages.${pkgs.stdenv.hostPlatform.system}.epic-games-launcher.override {
  location = "$HOME/Games/EpicGames";
  protonVersion = pkgs.proton-cachyos;
  useGameMode = true;
  preLaunchArgs = "mangohud";
}
```

```bash
nix build github:gaavin/nix-epic-games-launcher#epic-games-launcher
```

## Credits

- [Open-Wine-Components/umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) — Proton outside Steam
- [CachyOS/proton-cachyos](https://github.com/CachyOS/proton-cachyos) — Proton build this is written against
- [chaotic-cx/nyx](https://github.com/chaotic-cx/nyx) — recommended package: `proton-cachyos`
- [different-name/steam-config-nix](https://github.com/different-name/steam-config-nix) — Proton compat-tool path layout
- [Lutris Epic Games Store installer](https://lutris.net/games/epic-games-store/) — MSI URL, quiet `msiexec`, `-opengl -SkipBuildPatchPrereq`
- [gaavin/nix-battle-net](https://github.com/gaavin/nix-battle-net) — packaging pattern
