{
  lib,
  makeDesktopItem,
  runCommand,
  symlinkJoin,
  writeShellApplication,
  writeText,
  umu-launcher,
  winetricks,
  coreutils,
  curl,
  wget,
  procps,
  findutils,
  gamemode,
  pname ? "epic-games-launcher",
  location ? "$HOME/.local/share/nix-epic-games-launcher",
  useGameMode ? false,
  useWineD3D ? false,
  # Lutris/umu launcher flags plus Proton CEF workaround for a white window.
  launcherArgs ? "-opengl -SkipBuildPatchPrereq --in-process-gpu",
  disableHardwareAcceleration ? false,
  # winewayland cannot dock XEmbed tray icons into the host panel.
  enableProtonWayland ? false,
  # Proton package (steamcompattool output, or Chaotic proton-cachyos with bin/).
  protonVersion ? null,
  configFile ? null,
  environment ? { },
  preLaunchArgs ? "",
}:

let
  inherit (lib)
    concatStringsSep
    escapeShellArg
    getExe
    getName
    getOutput
    mapAttrsToList
    optional
    optionalAttrs
    optionalString
    ;

  # Steam compat tools put proton + compatibilitytool.vdf at the root of the
  # steamcompattool output. Chaotic's proton-cachyos instead nests them under
  # bin/ and often has no steamcompattool output — same layout probe as
  # steam-config-nix (compatToolDir).
  protonCompatPath =
    if protonVersion == null then
      ""
    else
      let
        base = getOutput "steamcompattool" protonVersion;
      in
      runCommand "${getName protonVersion}-steamcompattool" {
        preferLocalBuild = true;
        allowSubstitutes = false;
      } ''
        if [ -e ${escapeShellArg "${base}/proton"} ] || [ -f ${escapeShellArg "${base}/compatibilitytool.vdf"} ]; then
          ln -s ${escapeShellArg base} "$out"
        elif [ -e ${escapeShellArg "${base}/bin/proton"} ] || [ -f ${escapeShellArg "${base}/bin/compatibilitytool.vdf"} ]; then
          ln -s ${escapeShellArg "${base}/bin"} "$out"
        else
          echo "nix-epic-games-launcher: no Proton compat tool found in ${base} or ${base}/bin" >&2
          exit 1
        fi
      '';

  extraCompatPaths = protonCompatPath;

  installerUrl = "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi";

  mergedEnvironment = {
    GAMEID = "umu-egs";
    STORE = "egs";
    WINE_SIMULATE_WRITECOPY = "1";
    WINEDLLOVERRIDES = "locationapi=d";
    PROTON_USE_NTSYNC = "1";
    LAUNCHER_ARGS = launcherArgs;
    DISABLE_EPIC_HWACCEL = if disableHardwareAcceleration then "1" else "0";
  }
  // environment
  // {
    # Always set these so session-wide Proton flags cannot leak in.
    # WineD3D disables vkd3d-proton, so DX12 games see no GPU.
    PROTON_USE_WINED3D = if useWineD3D then "1" else "0";
    # winewayland cannot dock XEmbed tray icons into the host panel.
    PROTON_ENABLE_WAYLAND = if enableProtonWayland then "1" else "0";
    PROTON_USE_WAYLAND = if enableProtonWayland then "1" else "0";
  }
  // optionalAttrs (preLaunchArgs != "") { PRE_LAUNCH_ARGS = preLaunchArgs; };

  packagedConfig = writeText "nix-epic-games-launcher.env" (
    concatStringsSep "\n" (mapAttrsToList (k: v: "${k}=${escapeShellArg v}") mergedEnvironment) + "\n"
  );

  resolvedConfig = if configFile != null then configFile else packagedConfig;

  script = writeShellApplication {
    name = pname;
    runtimeInputs = [
      coreutils
      curl
      wget
      procps
      findutils
      winetricks
      umu-launcher
    ]
    ++ optional useGameMode gamemode;

    text = ''
      set -euo pipefail

      LOCATION="''${LOCATION:-${location}}"
      LOCATION="''${LOCATION/#\~/$HOME}"
      STATE_DIR="$LOCATION"
      WINEPREFIX_DIR="$STATE_DIR/prefix"
      INSTALLER_DIR="$STATE_DIR/installer"
      LOG_DIR="$STATE_DIR/logs"
      CONFIG_FILE="''${EPIC_GAMES_LAUNCHER_CONFIG:-${resolvedConfig}}"
      PACKAGED_PROTON="${protonCompatPath}"
      PACKAGED_COMPAT_PATHS="${extraCompatPaths}"
      INSTALLER_URL="''${EPIC_GAMES_INSTALLER_URL:-${installerUrl}}"
      INSTALLER_MSI="$INSTALLER_DIR/EpicGamesLauncherInstaller.msi"
      UMU_RUN=${escapeShellArg (getExe umu-launcher)}
      EPIC_EXE=""

      export WINEPREFIX="$WINEPREFIX_DIR"
      export GAMEID="''${GAMEID:-umu-egs}"
      export STORE="''${STORE:-egs}"

      if [ -r "$CONFIG_FILE" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        set +a
      fi

      info() { printf '\033[1;34mnix-epic-games-launcher:\033[0m %s\n' "$*" >&2; }
      err() { printf '\033[1;31mnix-epic-games-launcher:\033[0m %s\n' "$*" >&2; }

      find_proton_dir() {
        local candidate="$1"
        if [ -e "$candidate/proton" ]; then
          printf '%s' "$candidate"
          return 0
        fi
        if [ -e "$candidate/bin/proton" ]; then
          printf '%s' "$candidate/bin"
          return 0
        fi
        return 1
      }

      resolve_proton() {
        local resolved=""
        if [ -n "''${PROTONPATH:-}" ]; then
          if ! resolved="$(find_proton_dir "$PROTONPATH")"; then
            err "PROTONPATH does not look like a Proton build: $PROTONPATH"
            err "Need a Steam compat tool directory containing a proton script (or bin/proton)."
            return 1
          fi
        elif [ -n "$PACKAGED_PROTON" ] && [ -d "$PACKAGED_PROTON" ]; then
          if ! resolved="$(find_proton_dir "$PACKAGED_PROTON")"; then
            err "Packaged Proton does not look like a Proton build: $PACKAGED_PROTON"
            err "Need a Steam compat tool directory containing a proton script (or bin/proton)."
            return 1
          fi
        else
          err "No Proton found."
          err "Set programs.epic-games-launcher.protonVersion (e.g. pkgs.proton-cachyos)"
          err "or export PROTONPATH to a Steam compat tool directory."
          return 1
        fi
        export PROTONPATH="$resolved"

        if [ -n "$PACKAGED_COMPAT_PATHS" ]; then
          if [ -n "''${STEAM_EXTRA_COMPAT_TOOLS_PATHS:-}" ]; then
            export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$PACKAGED_COMPAT_PATHS:''${STEAM_EXTRA_COMPAT_TOOLS_PATHS}"
          else
            export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$PACKAGED_COMPAT_PATHS"
          fi
        fi
      }

      run_umu() {
        local -a cmd=()
        ${optionalString useGameMode "cmd+=(${escapeShellArg "${gamemode}/bin/gamemoderun"})"}
        if [ -n "''${PRE_LAUNCH_ARGS:-}" ]; then
          local -a pre_args=()
          # shellcheck disable=SC2206
          read -r -a pre_args <<<"''${PRE_LAUNCH_ARGS}"
          cmd+=("''${pre_args[@]}")
        fi
        cmd+=("$UMU_RUN")
        exec "''${cmd[@]}" "$@"
      }

      looks_like_installer() {
        local f="$1" magic
        [ -s "$f" ] || return 1
        magic="$(head -c 2 "$f")"
        if [ "$magic" = "MZ" ]; then
          return 0
        fi
        # OLE compound document (MSI)
        magic="$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')"
        [ "$magic" = "d0cf11e0" ]
      }

      epic_exe() {
        local c
        local candidates=(
          "$WINEPREFIX_DIR/drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
          "$WINEPREFIX_DIR/drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
          "$WINEPREFIX_DIR/drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe"
          "$WINEPREFIX_DIR/drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe"
        )
        for c in "''${candidates[@]}"; do
          if [ -s "$c" ]; then
            printf '%s' "$c"
            return 0
          fi
        done
        c="$(find "$WINEPREFIX_DIR/drive_c" -name 'EpicGamesLauncher.exe' -type f 2>/dev/null | head -n 1 || true)"
        if [ -n "$c" ] && [ -s "$c" ]; then
          printf '%s' "$c"
          return 0
        fi
        return 1
      }

      download_installer() {
        local tmp
        mkdir -p "$INSTALLER_DIR"
        if looks_like_installer "$INSTALLER_MSI"; then
          return 0
        fi
        tmp="$(mktemp "$INSTALLER_MSI.XXXXXX.tmp")"
        info "Downloading Epic Games Launcher installer"
        info "  from: $INSTALLER_URL"
        info "  to:   $INSTALLER_MSI"
        if curl -fL --progress-bar -o "$tmp" "$INSTALLER_URL"; then
          :
        elif wget --show-progress -O "$tmp" "$INSTALLER_URL"; then
          :
        else
          rm -f "$tmp"
          err "Failed to download Epic Games Launcher installer (need network + curl/wget)"
          return 1
        fi
        if ! looks_like_installer "$tmp"; then
          rm -f "$tmp"
          err "Download does not look like a Windows installer (MSI/EXE)"
          return 1
        fi
        mv -f "$tmp" "$INSTALLER_MSI"
        chmod u+rw "$INSTALLER_MSI"
        info "Installer ready ($(du -h "$INSTALLER_MSI" | cut -f1))"
      }

      ensure_prefix() {
        mkdir -p "$WINEPREFIX_DIR" "$LOG_DIR"
        if [ -r "$WINEPREFIX_DIR/system.reg" ]; then
          return 0
        fi
        info "Creating Proton prefix at $WINEPREFIX_DIR"
        "$UMU_RUN" wineboot -u || {
          err "umu-run failed to create the prefix"
          return 1
        }
      }

      # Hide Wine's floating systray window. Icons still dock to the host
      # tray when winex11 can see _NET_SYSTEM_TRAY (XWayland + xembedsniproxy).
      apply_systray_workaround() {
        local reg="$WINEPREFIX_DIR/user.reg"
        if [ ! -f "$reg" ]; then
          return 0
        fi
        if grep -q '"ShowSystray"=dword:00000000' "$reg"; then
          return 0
        fi
        printf '\n[Software\\\\Wine\\\\Explorer]\n"ShowSystray"=dword:00000000\n' >> "$reg"
      }

      kill_epic() {
        pkill -f 'EpicGamesLauncher' 2>/dev/null || true
        pkill -f 'EpicWebHelper' 2>/dev/null || true
        pkill -f 'UnrealCEFSubProcess' 2>/dev/null || true
        pkill -f 'CrashReportClient' 2>/dev/null || true
        pkill -f wineserver 2>/dev/null || true
      }

      install_epic() {
        info "Installing Epic Games Launcher (quiet MSI)"
        "$UMU_RUN" msiexec /i "$INSTALLER_MSI" /q || true
        kill_epic
        if EPIC_EXE="$(epic_exe)"; then
          return 0
        fi
        info "Quiet install did not produce EpicGamesLauncher.exe — running installer UI"
        info "Finish setup, then close it"
        "$UMU_RUN" "$INSTALLER_MSI" || true
        kill_epic
      }

      ensure_epic() {
        if EPIC_EXE="$(epic_exe)"; then
          return 0
        fi
        download_installer
        ensure_prefix
        apply_systray_workaround
        install_epic
        if EPIC_EXE="$(epic_exe)"; then
          return 0
        fi
        err "EpicGamesLauncher.exe not found under $WINEPREFIX_DIR"
        err "Finish the installer, then run ${pname} again."
        return 1
      }

      prepare() {
        mkdir -p "$STATE_DIR" "$INSTALLER_DIR" "$LOG_DIR"
        resolve_proton
        export WINEPREFIX="$WINEPREFIX_DIR"
      }

      usage() {
        cat <<EOF
      Usage: ${pname} [command]

        (no args)         Launch Epic Games
        --help            Show this help
        --info            Show config / paths
        --kill            Force quit Epic Games / wineserver
        --fix-webcache    Kill processes and clear the launcher CEF/web cache
        --winecfg         Wine settings
        --winetricks …    winetricks in the prefix
        --umu <args>      Pass arguments to umu-run

      State: $STATE_DIR
      Config: $CONFIG_FILE
      EOF
      }

      case "''${1:-}" in
        --help|-h) usage; exit 0 ;;
        --info)
          prepare
          cat <<EOF
      State:      $STATE_DIR
      Wineprefix: $WINEPREFIX_DIR
      Proton:     ''${PROTONPATH:-}
      umu-run:    $UMU_RUN
      config:     $CONFIG_FILE
      installer:  $INSTALLER_URL
      launcher:   $(epic_exe 2>/dev/null || echo "(not installed)")
      EOF
          exit 0
          ;;
        --kill)
          kill_epic
          info "Stopped Epic Games / wineserver."
          exit 0
          ;;
        --fix-webcache)
          prepare
          kill_epic
          rm -rf \
            "$WINEPREFIX_DIR/drive_c/users/steamuser/AppData/Local/EpicGamesLauncher/Saved/webcache" \
            "$WINEPREFIX_DIR/drive_c/users/steamuser/AppData/Local/EpicGamesLauncher/Saved/webcache_4430" \
            "$WINEPREFIX_DIR/drive_c/users/steamuser/AppData/Local/EpicGamesLauncher/Saved/GPUCache" \
            "$WINEPREFIX_DIR/drive_c/users/steamuser/AppData/Roaming/Epic/EpicGamesLauncher/Saved/webcache" \
            "$WINEPREFIX_DIR/drive_c/users/steamuser/AppData/Roaming/Epic/EpicGamesLauncher/Saved/webcache_4430"
          find "$WINEPREFIX_DIR/drive_c/users" -type d \( -name 'webcache*' -o -name 'GPUCache' \) \
            -path '*EpicGamesLauncher*' -prune -exec rm -rf {} + 2>/dev/null || true
          info "Cleared Epic Games web/CEF cache. Run ${pname} again."
          exit 0
          ;;
        --winecfg)
          prepare
          ensure_prefix
          exec "$UMU_RUN" winecfg
          ;;
        --winetricks)
          prepare
          ensure_prefix
          shift
          exec "$UMU_RUN" winetricks "$@"
          ;;
        --umu)
          prepare
          ensure_prefix
          shift
          exec "$UMU_RUN" "$@"
          ;;
        "")
          prepare
          ensure_epic
          apply_systray_workaround
          info "Launching $EPIC_EXE"
          launcher_args=()
          if [ -z "''${LAUNCHER_ARGS+x}" ]; then
            launcher_args=(-opengl -SkipBuildPatchPrereq --in-process-gpu)
          elif [ -n "''${LAUNCHER_ARGS}" ]; then
            # shellcheck disable=SC2206
            read -r -a launcher_args <<<"''${LAUNCHER_ARGS}"
          fi
          if [ "''${DISABLE_EPIC_HWACCEL:-0}" = "1" ]; then
            launcher_args+=(--disable-gpu)
          fi
          run_umu "$EPIC_EXE" "''${launcher_args[@]}"
          ;;
        *)
          err "Unknown command: $1"
          usage
          exit 1
          ;;
      esac
    '';
  };

  desktopItem = makeDesktopItem {
    name = pname;
    exec = "${script}/bin/${pname}";
    icon = "nix-epic-games-launcher";
    comment = "Epic Games (umu-launcher + Proton)";
    desktopName = "Epic Games";
    categories = [ "Game" ];
  };

  iconShare = runCommand "nix-epic-games-launcher-icon" { } ''
    install -Dm644 ${../../assets/nix-epic-games-launcher.svg} \
      "$out/share/icons/hicolor/scalable/apps/nix-epic-games-launcher.svg"
  '';
in
symlinkJoin {
  name = pname;
  paths = [
    script
    desktopItem
    iconShare
  ];
  passthru = {
    inherit protonVersion protonCompatPath extraCompatPaths;
    envConfig = resolvedConfig;
    inherit installerUrl;
  };
  meta = {
    description = "Declarative Epic Games Launcher using umu-launcher and an external Proton";
    homepage = "https://github.com/gaavin/nix-epic-games-launcher";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
