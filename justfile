export SSH_CMD := "ssh -o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null myce@127.0.0.1 -p 4444"

# Detect system architecture
SYSTEM := `case "$(uname -s)-$(uname -m)" in \
    Linux-x86_64)  echo "x86_64-linux" ;; \
    Darwin-arm64)  echo "aarch64-linux" ;; \
    Darwin-x86_64) echo "x86_64-linux" ;; \
    *)             echo "Unsupported system" && exit 1 ;; \
esac`

HOST_SYSTEM := `case "$(uname -s)-$(uname -m)" in \
    Linux-x86_64)  echo "x86_64-linux" ;; \
    Darwin-arm64)  echo "aarch64-darwin" ;; \
    Darwin-x86_64) echo "x86_64-darwin" ;; \
    *)             echo "Unsupported system" && exit 1 ;; \
esac`

_default:
    @just --list

# connects inside the VM using SSH
ssh:
    @$SSH_CMD

faas-login:
    #!/usr/bin/env bash
    PASS=$($SSH_CMD sudo kubectl get secret -n openfaas basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode)
    echo $PASS | faas-cli login --password-stdin
    echo "PASSWORD: $PASS"

faas-pub: faas-login
    cd {{ justfile_directory() }}/functions && find . -maxdepth 1 -type f -name '*.yml'  -printf '%f\n' \
        | xargs -I {} faas-cli publish -f {} --platforms linux/$(echo {{ SYSTEM }} | cut -d'-' -f1)

faas-deploy: faas-login
    cd {{ justfile_directory() }}/functions && find . -maxdepth 1 -type f -name '*.yml'  -printf '%f\n' \
        | xargs -I {} faas-cli deploy -f {}

tun:
    $SSH_CMD "sudo k3s kubectl port-forward -n openfaas svc/gateway 8080:8080"&
    $SSH_CMD -N -g -L "8080:127.0.0.1:8080"
    wait

mqtt:
    mosquitto_pub -h localhost -t sample-topic -m "Hello World!"

vm system=SYSTEM host_system=HOST_SYSTEM:
    #!/usr/bin/env bash
    set -e
    echo "Using system: {{ system }} on host {{ host_system }}"
    vmpath=$(nix build --impure --print-out-paths --expr "
    let
    self = builtins.getFlake ''path://{{ justfile_directory() }}'';
      vm = self.nixosConfigurationFunctions.vm {system=\"{{ system }}\"; hostPlatform=\"{{ host_system }}\"; pwd=''{{ justfile_directory() }}'';};
      install = vm.config.system.build.vm;
    in
    install" )
    echo "VM path: $vmpath"
    rm *.qcow2 || true
    if [[ "$(uname -s)" == "Linux" ]]; then
        exec $vmpath/bin/run-* -nographic -cpu host -enable-kvm
    else
        exec $vmpath/bin/run-* -nographic -cpu host
    fi