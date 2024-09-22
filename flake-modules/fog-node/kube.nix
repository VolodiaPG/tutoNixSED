# Definitions can be imported from a separate file like this one
{
  self,
  lib,
  inputs,
  k3s-macos,
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

    nixosModules.kube = {
      pkgs,
      config,
      ...
    }: {
      programs.bash.shellAliases = {
        k = "sudo kubectl --kubeconfig /var/lib/k0s/pki/admin.conf";
        k9 = "sudo k9s --kubeconfig /var/lib/k0s/pki/admin.conf -A";
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
      networking.firewall.enable = lib.mkForce false;
      # systemd.services.k3s.path = [pkgs.ipset];
      services = {
        k0s = {
          enable = true;

          # role = "controller+worker";

          # The first controller to bring up does not have a join token,
          # it has to be flagged with "isLeader".
          isLeader = true;

          # spec.api.address = "10.0.2.1";
          # spec.api.sans = [
          #   "10.0.2.1"
          # ];
          # #  spec.api = {
          #   address = "127.0.0.1";
          #   sans = ["127.0.0.1"];
          # };
          spec.api.address = "192.0.2.1";
          spec.api.sans = [
            "192.0.2.1"
            "192.0.2.2"
          ];
         

          # Test non-default options:
          #
          #  spec.network.provider = "calico";
          # spec.network.calico.mode = "bird";
          #  spec.network.dualStack.enabled = true;
          # spec.network.dualStack.IPv6podCIDR = "fd00::/108";
          # spec.network.dualStack.IPv6serviceCIDR = "fd01::/108";
          # spec.network.controlPlaneLoadBalancing.enabled = true;
          # spec.network.nodeLocalLoadBalancing.enabled = true;
          # spec.storage.type = "kine";
        };
        # k3s = {
        #   enable = true;
        #   # extraFlags = [
        #   #   "--disable-network-policy"
        #   #   "--flannel-backend=host-gw"
        #   #   "--disable=traefik"
        #   #   "--disable=servicelb"
        #   #   "--disable=local-storage"
        #   #   "--kube-proxy-arg=proxy-mode=iptables"
        #   #   "--kube-proxy-arg=conntrack-max-per-core=0"
        #   #   "--kubelet-arg=cloud-provider=external"
        #   #   "--kubelet-arg=provider-id=k3s://$(hostname)"
        #   # ];
        #  extraFlags = toString [
        #     "--disable metrics-server"
        #     "--disable traefik"
        #   ];
        # };
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

      environment.variables = {
        ETCD_UNSUPPORTED_ARCH = "arm64";
        TERM = "screen-256color";
      };

      environment = {
        systemPackages = with pkgs; [
          k0s
          k9s
          kubectl
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
