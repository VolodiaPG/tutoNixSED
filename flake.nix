{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    srvos.url = "github:numtide/srvos";
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
        ./modules/devShell.nix
        ./modules/kube.nix
        ./modules/cloud-init.nix
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
        nixosConfigurationsFunction.os = {pwd}:
          inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
              "${inputs.nixpkgs}/nixos/modules/profiles/all-hardware.nix"
              inputs.self.outputs.nixosModules.base
              inputs.self.outputs.nixosModules.kube
              inputs.self.outputs.nixosModules.cloud-init
              inputs.srvos.nixosModules.server
              inputs.srvos.nixosModules.mixins-terminfo
              inputs.srvos.nixosModules.mixins-cloud-init
              inputs.srvos.nixosModules.mixins-systemd-boot
              {
                services.getty.autologinUser = "toto";
                #services.getty.autologinUser =
                #  cfg.user;
                users.allowNoPasswordLogin = true;
                users.users."toto" = {
                  isNormalUser = true;
                  home = "/home/${cfg.user}";
                  initialPassword = cfg.user; # Replace with your own password
                  extraGroups = ["wheel" "networkmanager"]; # Add the user to important groups
                };

                security.sudo.wheelNeedsPassword = false;
                # Enable a basic firewall (optional)
                networking.firewall.enable = true;
                networking.firewall.allowedTCPPorts = [22]; # Open SSH port

                virtualisation.vmVariant.virtualisation = {
                  forwardPorts = [
                    {
                      from = "host";
                      host.port = 4444;
                      guest.port = 22;
                    }
                  ];
                  memorySize = 4096;
                  cores = 4;
                  diskSize = 10 * 1024;
                  sharedDirectories.current = {
                    source = "${pwd}";
                    target = "/home/${cfg.user}/mycelium";
                  };
                };
              }
            ];
            specialArgs = {inherit (inputs.self) outputs;};
          };

        nixosModules.base = {
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
          };

          #users.mutableUsers = false;
          #users.users.root = {
          #  isSystemUser = true;
          #  password = "root";
          #};
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
