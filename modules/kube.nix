# Definitions can be imported from a separate file like this one
{
  self,
  lib,
  ...
}: {
  perSystem = {
    config,
    self',
    inputs',
    pkgs,
    lib,
    ...
  }: {
    # Definitions like this are entirely equivalent to the ones
    # you may have directly in flake.nix.
    packages.kube =
      (inputs'.kubenix.evalModules.${pkgs.system} {
        module = {kubenix, ...}: {
          imports = [kubenix.modules.k8s kubenix.modules.helm];
          kubernetes.helm.releases = {
            openfaas = {
              namespace = lib.mkForce "openfaas";
              overrideNamespace = false;
              chart = pkgs.stdenvNoCC.mkDerivation {
                name = "openfaas";
                src = inputs'.openfaas;

                buildCommand = ''
                  ls $src
                  cp -r $src/chart/openfaas/ $out
                '';
              };
            };
            mqtt-connector = {
              namespace = lib.mkForce "openfaas";
              overrideNamespace = false;
              chart = pkgs.stdenvNoCC.mkDerivation {
                name = "mqtt-connector";
                src = inputs'.openfaas;

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
              namespace = lib.mkForce "openfaas";
              overrideNamespace = false;
              chart = pkgs.stdenvNoCC.mkDerivation {
                name = "mqtt-connector";
                src = inputs'.openfaas;

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
  };
  flake = {
    nixosModules.kube = {pkgs, ...}: {
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

        etc = {
          "kubenix.json".source = self.outputs.packages.${pkgs.system}.kube;
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
}
