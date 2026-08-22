{
  description = "Declarative Epic Games Launcher on Nix (umu-launcher + external Proton)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      packages = rec {
        epic-games-launcher = pkgs.callPackage ./pkgs/epic-games-launcher { };
        default = epic-games-launcher;
      };
    in
    {
      packages.${system} = packages;

      apps.${system}.default = {
        type = "app";
        program = "${packages.epic-games-launcher}/bin/epic-games-launcher";
      };

      homeModules.epic-games-launcher =
        { lib, pkgs, ... }:
        {
          imports = [ ./modules/home-manager/epic-games-launcher.nix ];
          programs.epic-games-launcher.package = lib.mkDefault (
            self.packages.${pkgs.stdenv.hostPlatform.system}.epic-games-launcher
          );
        };
      homeModules.default = self.homeModules.epic-games-launcher;

      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system} or packages) epic-games-launcher;
      };
    };
}
