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
              faas-cli
            ];
          };
        }
      );
      flakeKube = flake-utils.lib.eachSystem ["x86_64-linux"] (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          packages.kube =
            (kubenix.evalModules.${system} {
              module = {kubenix, ...}: {
                imports = [kubenix.modules.k8s kubenix.modules.helm];
                kubernetes.helm.releases = {
                  openfaas = {
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
                  mqtt-connector = {
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
                    values = {
                      broker = "tcp://10.0.2.15:1883";
                      topic = "sample-topic";
                      clientID = "m1";
                    };
                  };
                  mqtt-connector2 = {
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
                    values = {
                      broker = "tcp://10.0.2.15:1883";
                      topic = "sample-topic-2";
                      clientID = "m2";
                    };
                  };
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

          services = {
            openssh = {
              enable = true;
              permitRootLogin = "yes";
            };

            k3s = {
              enable = true;
            };

            mosquitto = {
              enable = true;

              # Mosquitto is only listening on the local IP, traffic from outside is not
              # allowed.
              listeners = [
                {
                  address = "0.0.0.0";
                  port = 1883;
                  settings.allow_anonymous = true;
                  omitPasswordAuth = true;
                  acl = ["topic readwrite #" "pattern readwrite #"];
                }
              ];
            };
          };

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

          environment = {
            systemPackages = with pkgs; [
              k9s
              mosquitto
            ];
            etc = {
              "kubenix.json".source = outputs.packages.${pkgs.system}.kube;
              "namespaces.yaml".text = ''
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
        flakeKube
        flakeModules
        flakeVM
      ];
}
