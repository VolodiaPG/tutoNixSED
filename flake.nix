{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs:
    with inputs; let
      inherit (self) outputs;
      flakeDevEnv = flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = import nixpkgs {
            inherit system;
          };
        in {
          formatter = pkgs.alejandra;
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              just
              nixos-rebuild
              qemu
              sshpass
            ];
          };
        }
      );
      flakeDocker = flake-utils.lib.eachSystem ["x86_64-linux"] (
        system: let
          pkgs = import nixpkgs {
            inherit system;
          };

          dockerImage = pkgs.dockerTools.buildImage {
            name = "tutosed";
            tag = "latest";
            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              pathsToLink = [
                "/bin"
                "/"
              ];
              paths = with pkgs; [
                busybox
                parallel
              ];
            };

            config = {
              Entrypoint = ["sleep" "9999999"];
            };
          };
        in {
          packages.docker = dockerImage;
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

          users.mutableUsers = false;
          users.users.root = {
            isSystemUser = true;
            password = "root";
          };

          services.openssh = {
            enable = true;
            permitRootLogin = "yes";
          };

          services.k3s = {
            enable = true;
          };

          systemd.services.startTutoSEDContainer = {
            description = "Launch our tutosed container image";
            after = ["k3s.service"];
            wantedBy = ["multi-user.target"];
            script = ''
              ${pkgs.k3s}/bin/k3s kubectl create deployment tutosed --image=ghcr.io/volodiapg/tutosed:latest
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = "yes";
            };
          };

          system.stateVersion = "22.05"; # Do not change
        };
      };
      flakeVM = flake-utils.lib.eachSystem ["x86_64-linux"] (
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
        flakeDevEnv
        flakeDocker
        flakeModules
        flakeVM
      ];
}
