{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    srvos.url = "github:nix-community/srvos";
    # Use the version of nixpkgs that has been tested to work with SrvOS
    nixpkgs.follows = "srvos/nixpkgs";
    kubenix = {
      url = "github:hall/kubenix?ref=refs/tags/0.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    openfaas = {
      url = "github:openfaas/faas-netes?ref=refs/tags/0.17.2";
      flake = false;
    };
    ssh-volodiapg = {
      url = "https://github.com/volodiapg.keys";
      flake = false;
    };
  };

  outputs = inputs @ {flake-parts, ...}: let
    cfg = import ./cfg.nix;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./flake-modules
      ];
      systems = ["x86_64-linux"];
      perSystem = {
        pkgs,
        self',
        inputs',
        ...
      }: {
        formatter = pkgs.alejandra;
        #packages.disk = import "${inputs'.nixpkgs}/nixos/lib/make-disk-image.nix" {
        #  inherit pkgs;
        #  inherit (pkgs) lib;
        #  inherit (self'.outputs.nixosModules.os) config;
        #  memSize = 4096; # During build-phase, here, locally
        #  additionalSpace = "2G"; # Space added after all the necessary
        #  format = "qcow2-compressed";
        #};
      };
      flake = {
        _module.args = {
          inherit cfg;
        };
      };
    };
}
