{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    kubenix.url = "github:hall/kubenix";
    kubenix.inputs.nixpkgs.follows = "nixpkgs";
    openfaas = {
      url = "github:openfaas/faas-netes?ref=refs/tags/0.17.2";
      flake = false;
    };
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
      flakeKube = flake-utils.lib.eachSystem ["x86_64-linux"] (
        system: let
          pkgs = import nixpkgs {
            inherit system;
          };
        in {
          packages.kube =
            (kubenix.evalModules.${system} {
              module = {kubenix, ...}: {
                imports = [kubenix.modules.k8s kubenix.modules.helm];
                  kubernetes.helm.releases.openfaas = {
                    namespace = nixpkgs.lib.mkForce "openfaas";
                    overrideNamespace = false;
                    chart = pkgs.stdenvNoCC.mkDerivation {
                      name = "openfaas";
                      src = inputs.openfaas;

                      buildCommand = ''
                        ls $src
                        cp -r $src/chart/openfaas/ $out
                      '';
                    };
                  };
                  kubernetes.helm.releases.mqtt-connector = {
                    namespace = nixpkgs.lib.mkForce "openfaas";
                    overrideNamespace = false;
                    chart = pkgs.stdenvNoCC.mkDerivation {
                      name = "mqtt-connector";
                      src = inputs.openfaas;

                      buildCommand = ''
                        ls $src
                        cp -r $src/chart/mqtt-connector/ $out
                      '';
                    };
                    values.broker= "tcp://10.0.2.15:1883";
                  };
              };
            })
            .config
            .kubernetes
            .result;
        }
      );
      flakeModules = {
        nixosModules.vmConfig = {
          pkgs,
          lib,
          outputs,
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

          services.mosquitto = {
            enable = true;

            # Mosquitto is only listening on the local IP, traffic from outside is not
            # allowed.
            listeners = [{
              address = "0.0.0.0";
              port = 1883;
              settings.allow_anonymous = true;
              # users = {
              #   # No real authentication needed here, since the local network is
              #   # trusted.
              #   mosquitto = {
              #     acl = [ "readwrite #" ];
              #     password = "mosquitto";
              #   };
              # };
            }];
          };

          environment.systemPackages = with pkgs; [
            k9s
          ];

          programs.bash.shellAliases = {
            kubectl = "k3s kubectl";
            k = "kubectl";
            k9 = "k9s --kubeconfig /etc/rancher/k3s/k3s.yaml -A";
          };

          systemd.services.startTutoSEDContainer = {
            description = "Launch our tutosed container image";
            after = ["k3s.service"];
            wants = ["k3s.service"];
            wantedBy = ["multi-user.target"];
            script = ''
              ${pkgs.k3s}/bin/k3s kubectl apply -f /etc/namespaces.yaml
              ${pkgs.k3s}/bin/k3s kubectl apply -f /etc/kubenix.json
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = "yes";
            };
          };

          environment.etc."kubenix.json".source = outputs.packages.${pkgs.system}.kube;
          environment.etc."namespaces.yaml".text = ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: openfaas
            annotations:
              linkerd.io/inject: enabled
              config.linkerd.io/skip-inbound-ports: "4222"
              config.linkerd.io/skip-outbound-ports: "4222"
            labels:
              role: openfaas-system
              access: openfaas-system
              istio-injection: enabled
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: openfaas-fn
            annotations:
              linkerd.io/inject: enabled
              config.linkerd.io/skip-inbound-ports: "4222"
              config.linkerd.io/skip-outbound-ports: "4222"
            labels:
              istio-injection: enabled
              role: openfaas-fn
          '';

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
            specialArgs = {inherit outputs;};
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
        flakeKube
        flakeModules
        flakeVM
      ];
}
