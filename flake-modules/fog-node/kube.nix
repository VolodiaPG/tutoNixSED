# Definitions can be imported from a separate file like this one
{
  self,
  lib,
  inputs,
  ...
}: let
  inherit (inputs) kubenix openfaas;
in {
  flake = {
    nixosModules.kubernetes = {
      pkgs,
      kubenix,
      ...
    }: {
      imports = [kubenix.modules.k8s kubenix.modules.helm];
      kubernetes.helm.releases = {
        openfaas = {
          namespace = lib.mkForce "openfaas";
          overrideNamespace = false;
          chart = pkgs.stdenvNoCC.mkDerivation {
            name = "openfaas";
            src = openfaas;

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
            src = openfaas;

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
            src = openfaas;

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

    nixosModules.kube = {pkgs, ...}: {
      programs.bash.shellAliases = {
        kubectl = "k3s kubectl";
        k = "sudo kubectl";
        k9 = "sudo k9s --kubeconfig /etc/rancher/k3s/k3s.yaml -A";
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
      services = {
        k3s = {
          enable = true;
          extraFlags = [
            "--disable traefik,local-storage,servicelb,metrics-server"
          ];
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

      environment = {
        systemPackages = with pkgs; [
          k9s
          mosquitto
        ];
        etc = {
          "kubenix.json".source =
            (kubenix.evalModules.${pkgs.system} {
              module = self.outputs.nixosModules.kubernetes;
            })
            .config
            .kubernetes
            .result;
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
