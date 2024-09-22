# Kubernetes module for fog-node
{
  self,
  lib,
  inputs,
  ...
}: let
  inherit (inputs) kubenix openfaas;
in {
  flake = {
    nixosModules.kubernetes2 = {
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

    nixosModules.cluster = {
      pkgs,
      config,
      ...
    }: let
      # When using easyCerts=true the IP Address must resolve to the master on creation.
      # So use simply 127.0.0.1 in that case. Otherwise you will have errors like this https://github.com/NixOS/nixpkgs/issues/59364
      kubeMasterIP = "10.1.1.2";
      kubeMasterHostname = "api.kube";
      kubeMasterAPIServerPort = 6443;
    in {
      programs.bash.shellAliases = {
        kubectl = "kubectl";
        k = "kubectl";
        k9 = "sudo k9s --kubeconfig /etc/kubernetes/cluster-admin.kubeconfig -A";
      };

      networking = {
        enableIPv6 = false;
        firewall.enable = lib.mkForce false;
        nftables.enable = lib.mkForce false;
        resolvconf.enable = lib.mkForce false;
        nameservers = ["8.8.8.8" "8.8.4.4"];
      };

      systemd.services.fix-dns = {
        description = "Fix DNS resolution";
        after = ["network.target"];
        before = ["kubelet.service"];
        wantedBy = ["multi-user.target"];
        script = ''
          echo "nameserver 8.8.8.8" > /etc/resolv.conf
          echo "nameserver 8.8.4.4" >> /etc/resolv.conf
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      # resolve master hostname
      networking.extraHosts = "${kubeMasterIP} ${kubeMasterHostname}";

      services = {
        kubernetes = {
          roles = ["master" "node"];
          masterAddress = kubeMasterHostname;
          apiserverAddress = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
          easyCerts = true;
          apiserver = {
            securePort = kubeMasterAPIServerPort;
            advertiseAddress = kubeMasterIP;
          };

          # use coredns
          addons.dns.enable = true;

          # needed if you use swap
          kubelet.extraOpts = "--fail-swap-on=false";
        };

        mosquitto = {
          enable = true;
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
          kubectl
          k9s
          mosquitto
          kompose
          kubernetes
        ];
        etc = {
          "kubenix.json".source =
            (kubenix.evalModules.${pkgs.system} {
              module = self.outputs.nixosModules.kubernetes2;
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
      system.stateVersion = "22.05";
    };
  };
}
