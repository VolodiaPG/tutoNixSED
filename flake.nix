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
  };

  outputs = inputs @ {flake-parts, ...}: let
    cfg = import ./cfg.nix;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./flake-modules
      ];
      systems = ["x86_64-darwin" "x86_64-linux" "aarch64-darwin" "aarch64-linux"];
      perSystem = {
        pkgs,
        self',
        inputs',
        ...
      }: {
        formatter = pkgs.alejandra;
      };
      flake = {
        _module.args = {
          inherit cfg;
        };
      };
    };
}
