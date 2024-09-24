{inputs, ...}: let
  modules = [
    "${inputs.nixpkgs}/nixos/modules/profiles/all-hardware.nix"
    inputs.self.outputs.nixosModules.base
    inputs.self.outputs.nixosModules.kube
    inputs.srvos.nixosModules.server
    inputs.srvos.nixosModules.mixins-systemd-boot
    inputs.srvos.nixosModules.mixins-nix-experimental
  ];
in {
  imports = [
    ./kube.nix
  ];

  flake = {cfg, ...}: let
  in {
    nixosConfigurationFunctions.vm = {
      system,
      hostPlatform,
      pwd,
    }:
      inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules =
          modules
          ++ [
            "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
            ({pkgs, ...}: {
              environment.systemPackages = [pkgs.just];
              virtualisation.vmVariant.virtualisation = {
                host.pkgs = inputs.nixpkgs.legacyPackages.${hostPlatform};
                forwardPorts = [
                  {
                    from = "host";
                    host.port = 4444;
                    guest.port = 22;
                  }
                  {
                    from = "host";
                    host.port = 5000;
                    guest.port = 5000;
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
            })
          ];
        specialArgs = {inherit (inputs.self) outputs;};
      };

    nixosConfigurations.base = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      inherit modules;
      specialArgs = {inherit (inputs.self) outputs;};
    };

    nixosModules.base = {
      pkgs,
      lib,
      ...
    }: {
      boot.kernelPackages = pkgs.linuxPackages_latest;
      systemd.network = {
        enable = true;
        wait-online.anyInterface = true;
        networks = {
          "10-dhcp" = {
            matchConfig.Name = ["enp*" "wlp*"];
            networkConfig.DHCP = true;
          };
        };
      };
      networking.firewall.allowedUDPPorts = [67];
      services.getty.autologinUser =
        cfg.user;
      users.users.${cfg.user} = {
        isNormalUser = true;
        home = "/home/${cfg.user}";
        extraGroups = ["wheel" "networkmanager"]; # Add the user to important groups
        openssh.authorizedKeys.keyFiles = [
          inputs.ssh-volodiapg
        ];
      };
      security.sudo.wheelNeedsPassword = false;
      # Enable a basic firewall (optional)
      networking.firewall.enable = true;
      networking.firewall.allowedTCPPorts = [22]; # Open SSH port
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };

      boot = {
        growPartition = true;
        kernelParams = ["console=ttyS0"]; # "preempt=none"];
        loader.grub = {
          device = "/dev/vda";
          configurationLimit = 5;
        };
        kernel.sysctl = {
          "net.core.default_qdisc" = lib.mkForce "cake"; #fq_codel also works but is older, allows for fair bandwidth for each application running on this node
          "net.ipv4.tcp_ecn" = 1;
          "net.ipv4.tcp_sack" = 1;
          "net.ipv4.tcp_dsack" = 1;
        };
      };

      users.mutableUsers = false;
      services = {
        openssh = {
          enable = true;
        };
      };

      system.stateVersion = "22.05"; # Do not change
    };
  };
}
