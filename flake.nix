{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs:
    with inputs; let
      inherit (self) outputs;
      flakeDocker = flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = import nixpkgs {
            inherit system;
          };

          dockerImage = pkgs.dockerTools.buildImage {
            name = "enos_deployment";
            tag = "latest";
            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              pathsToLink = [
                "/bin"
                "/"
              ];
              paths = with pkgs; [
                parallel
              ];
            };

            config = {
              Env = ["RUN=python" "HOME=/root"];
              Entrypoint = [""];
            };
          };
        in {
          packages.docker = dockerImage;
          formatter = pkgs.alejandra;
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              just
              nixos-rebuild
              qemu
            ];
          };
        }
      );
      flakeModules = {
        nixosModules.vmConfig = {
          pkgs,
          lib,
          ...
        }: {
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
          services.k3s = {
            enable = true;
          };
          # useful packages
          # environment.systemPackages = with pkgs; [
          #   faas-cli
          #   kubectl
          #   arkade
          # ];

          system.stateVersion = "22.05"; # Do not change
        };
      };
      flakeVM = flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = import nixpkgs {
            inherit system;
          };
          os = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
              "${nixpkgs}/nixos/modules/profiles/all-hardware.nix"
              outputs.nixosModules.vmConfig
            ];
          };
          vm = import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
            inherit pkgs;
            inherit (pkgs) lib;
            inherit (os) config;
            memSize = 4096; # During build-phase, here, locally
            additionalSpace = "2G"; # Space added after all the necessary
            format = "qcow2-compressed";
          };
        in {
          packages.vm = vm;
        }
      );
    in
      nixpkgs.lib.foldl nixpkgs.lib.recursiveUpdate {}
      [
        flakeDocker
        flakeModules
        flakeVM
      ];
}
