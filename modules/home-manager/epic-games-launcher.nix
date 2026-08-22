{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatStringsSep
    escapeShellArg
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.epic-games-launcher;
in
{
  options.programs.epic-games-launcher = {
    enable = mkEnableOption "Epic Games Launcher (umu-launcher + external Proton via nix-epic-games-launcher)";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      defaultText = literalExpression "nix-epic-games-launcher.packages.\${pkgs.stdenv.hostPlatform.system}.epic-games-launcher";
      example = literalExpression "nix-epic-games-launcher.packages.\${pkgs.stdenv.hostPlatform.system}.epic-games-launcher";
      description = ''
        epic-games-launcher package to install. When you import
        `nix-epic-games-launcher.homeModules.epic-games-launcher` from the flake,
        this defaults to that flake's `epic-games-launcher` — you usually do not
        need to set it.
      '';
    };

    protonVersion = mkOption {
      type = types.nullOr types.package;
      default = null;
      example = literalExpression "pkgs.proton-cachyos";
      description = ''
        Proton build passed to umu-launcher as PROTONPATH. Accepts Steam
        compatibility tools with a `steamcompattool` output (proton-ge-bin)
        and packages that nest the tool under `bin/` (Chaotic proton-cachyos).
        Required when the module is enabled.
      '';
    };

    location = mkOption {
      type = types.str;
      default = "${config.xdg.dataHome}/nix-epic-games-launcher";
      defaultText = literalExpression "\${config.xdg.dataHome}/nix-epic-games-launcher";
      description = "Mutable state directory (Proton prefix, installer, logs).";
    };

    gamemode = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Wrap launches with gamemoderun. Requires a working GameMode daemon
        (e.g. programs.gamemode.enable on NixOS).
      '';
    };

    useWineD3D = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Set PROTON_USE_WINED3D=1. That disables DXVK and vkd3d-proton, so
        DirectX 12 games fail with "No valid DX12 video card found". Leave
        off unless the CEF login window is still white after the default
        `-opengl -SkipBuildPatchPrereq --in-process-gpu` workaround. Always
        written so a session-wide PROTON_USE_WINED3D=1 does not leak into games.
      '';
    };

    launcherArgs = mkOption {
      type = types.str;
      default = "-opengl -SkipBuildPatchPrereq --in-process-gpu";
      example = "-opengl -SkipBuildPatchPrereq --in-process-gpu";
      description = ''
        Extra arguments passed to EpicGamesLauncher.exe. `-opengl
        -SkipBuildPatchPrereq` matches Lutris / umu-launcher; `--in-process-gpu`
        is the Proton-CachyOS / Proton-GE workaround for a white CEF window.
        Set to `""` to pass no extra arguments.
      '';
    };

    disableHardwareAcceleration = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Append `--disable-gpu` to EpicGamesLauncher.exe. Try this if the CEF
        window is still white after `--in-process-gpu`.
      '';
    };

    enableProtonWayland = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Set PROTON_ENABLE_WAYLAND=1. Wine's Wayland driver cannot dock the
        Epic Games tray icon into the host notification area, so Proton
        opens a standalone tray window instead. Leave this off so winex11
        can hand the icon to xembedsniproxy (Plasma) or another XEmbed
        tray host. Always written so a session-wide PROTON_ENABLE_WAYLAND=1
        does not leak into Epic Games.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {
        GAMEID = "umu-egs";
        STORE = "egs";
        WINE_SIMULATE_WRITECOPY = "1";
        WINEDLLOVERRIDES = "locationapi=d";
        PROTON_USE_NTSYNC = "1";
      };
      example = {
        MANGOHUD = "1";
      };
      description = "Environment variables written to the generated config and sourced at launch.";
    };

    preLaunchArgs = mkOption {
      type = types.str;
      default = "";
      example = "mangohud";
      description = "Programs prepended before umu-run (e.g. mangohud). gamemode is separate.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Raw lines appended to the generated env config file.";
    };
  };

  config = mkIf cfg.enable (
    let
      envFile = pkgs.writeText "nix-epic-games-launcher.env" (
        concatStringsSep "\n" (
          mapAttrsToList (k: v: "${k}=${escapeShellArg v}") cfg.environment
          ++ [
            "PROTON_USE_WINED3D=${escapeShellArg (if cfg.useWineD3D then "1" else "0")}"
            "LAUNCHER_ARGS=${escapeShellArg cfg.launcherArgs}"
            "DISABLE_EPIC_HWACCEL=${escapeShellArg (if cfg.disableHardwareAcceleration then "1" else "0")}"
            "PROTON_ENABLE_WAYLAND=${escapeShellArg (if cfg.enableProtonWayland then "1" else "0")}"
            "PROTON_USE_WAYLAND=${escapeShellArg (if cfg.enableProtonWayland then "1" else "0")}"
          ]
          ++ lib.optional (cfg.preLaunchArgs != "") "PRE_LAUNCH_ARGS=${escapeShellArg cfg.preLaunchArgs}"
          ++ lib.optional (cfg.extraConfig != "") cfg.extraConfig
        )
        + "\n"
      );

      finalPackage =
        if cfg.package == null then
          null
        else
          cfg.package.override {
            location = cfg.location;
            useGameMode = cfg.gamemode;
            useWineD3D = cfg.useWineD3D;
            launcherArgs = cfg.launcherArgs;
            disableHardwareAcceleration = cfg.disableHardwareAcceleration;
            enableProtonWayland = cfg.enableProtonWayland;
            protonVersion = cfg.protonVersion;
            configFile = envFile;
          };
    in
    {
      home.packages = lib.optional (finalPackage != null) finalPackage;

      assertions = [
        {
          assertion = cfg.package != null;
          message = ''
            programs.epic-games-launcher.package is unset. Import
            nix-epic-games-launcher.homeModules.epic-games-launcher from the flake
            (which sets a default), or set package explicitly to
            nix-epic-games-launcher.packages.''${pkgs.stdenv.hostPlatform.system}.epic-games-launcher.
          '';
        }
        {
          assertion = cfg.protonVersion != null;
          message = ''
            programs.epic-games-launcher.protonVersion is unset. Set it to a Proton
            package such as pkgs.proton-cachyos or pkgs.proton-ge-bin.
          '';
        }
      ];
    }
  );
}
