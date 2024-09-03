{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    kubenix = {
      url = "github:hall/kubenix?ref=refs/tags/0.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    openfaas = {
      url = "github:openfaas/faas-netes?ref=refs/tags/0.17.2";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [./modules/devShell.nix];
      systems = ["x86_64-linux"];
      perSystem = {
        pkgs,
        self',
        inputs',
        ...
      }: {
        formatter = pkgs.alejandra;
        packages.vm = import "${inputs'.nixpkgs}/nixos/lib/make-disk-image.nix" {
          inherit pkgs;
          inherit (pkgs) lib;
          inherit (self'.outputs.nixosModules.os) config;
          memSize = 4096; # During build-phase, here, locally
          additionalSpace = "2G"; # Space added after all the necessary
          format = "qcow2-compressed";
        };
      };
      flake = {
        os = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
            "${inputs.nixpkgs}/nixos/modules/profiles/all-hardware.nix"
            self.outputs.nixosModules.base
            self.outputs.nixosModules.kube
          ];
          specialArgs = {inherit (self) outputs;};
        };

        nixosModules.base = {pkgs, ...}: {
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };

          boot = {
            growPartition = true;
            kernelParams = ["console=ttyS0"]; # "preempt=none"];
            loader.grub = {
              device = "/dev/vda";
            };
            loader.timeout = 0;
          };

          users.mutableUsers = false;
          users.users.root = {
            isSystemUser = true;
            password = "root";
          };
          services = {
            openssh = {
              enable = true;
              permitRootLogin = "yes";
            };
          };

          system.stateVersion = "22.05"; # Do not change
        };
      };
    };
}
