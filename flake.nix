{
  description = "Ren TUI - terminal LXMF / NomadNet client for Reticulum";

  inputs = {
    # nixos-24.11 ships Odin 2024-10 which cannot compile core:sys/posix for this tree.
    # Unstable tracks recent Odin (dev-2026-07+), matching CI/docker pins.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      version = "0.1.3";
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          ren-tui = pkgs.callPackage ./packaging/ren-tui.nix {
            inherit version;
            src = self;
          };
        in
        {
          default = ren-tui;
          inherit ren-tui;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/ren-tui";
        };
      });

      formatter = forAllSystems (
        system: (import nixpkgs { inherit system; }).nixfmt-rfc-style
      );
    };
}
