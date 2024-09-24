# SSH command with default options for connecting to the VM
export SSH_CMD := "ssh -o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null myce@127.0.0.1 -p 4444"

# Registry for storing images temporarily
REGISTRY := env_var_or_default('REGISTRY', "ttl.sh/" + `whoami` + "-" + `hostname`)

# Time that the image will be stored in the registry
TAG := env_var_or_default('TAG', "10m")

_default:
    @just --list

# connects inside the VM using SSH
ssh:
    @$SSH_CMD

# Log in to OpenFaaS
faas-login:
    #!/usr/bin/env bash
    PASS=$($SSH_CMD sudo kubectl get secret -n openfaas basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode)
    echo $PASS | faas-cli login --password-stdin
    echo "PASSWORD: $PASS"

# Publish OpenFaaS functions using the registry variables and modify the function file
faas-pub: faas-login
    #!/usr/bin/env bash
    cd {{ justfile_directory() }}/functions
    for file in *.yml; do
        if [ -f "$file" ]; then
            just faas-pub-single $file
        fi
    done

# Publish a single OpenFaaS function using the registry variables and modify the function file
faas-pub-single file:
    #!/usr/bin/env bash
    cd {{ justfile_directory() }}/functions
    sed -i "s|image: .*|image: {{ REGISTRY }}/$(basename {{file}} .yml):{{ TAG }}|" "{{file}}"
    faas-cli publish -f "{{file}}"
    faas-cli deploy -f "{{file}}"

# Set up port forwarding for OpenFaaS gateway
tun:
    $SSH_CMD "sudo k3s kubectl port-forward -n openfaas svc/gateway 8080:8080"&
    $SSH_CMD -N -g -L "8080:127.0.0.1:8080"
    wait

# Publish a test message to MQTT broker (run this command from within the VM)
mqtt:
    mosquitto_pub -h localhost -t sample-topic -m "Hello World!"

# Build and run the VM
vm:
    #!/usr/bin/env bash
    set -e
    SYSTEM=$(case "$(uname -s)-$(uname -m)" in \
        Linux-x86_64)  echo "x86_64-linux" ;; \
        Darwin-arm64)  echo "aarch64-linux" ;; \
        Darwin-x86_64) echo "x86_64-linux" ;; \
        *)             echo "Unsupported system" && exit 1 ;; \
    esac)
    HOST_SYSTEM=$(case "$(uname -s)-$(uname -m)" in \
        Linux-x86_64)  echo "x86_64-linux" ;; \
        Darwin-arm64)  echo "aarch64-darwin" ;; \
        Darwin-x86_64) echo "x86_64-darwin" ;; \
        *)             echo "Unsupported system" && exit 1 ;; \
    esac)
    echo "Using system: $SYSTEM on host $HOST_SYSTEM"
    vmpath=$(nix build --impure --print-out-paths --expr "
    let
    self = builtins.getFlake ''path://{{ justfile_directory() }}'';
      vm = self.nixosConfigurationFunctions.vm {system=\"$SYSTEM\"; hostPlatform=\"$HOST_SYSTEM\"; pwd=''{{ justfile_directory() }}'';};
      install = vm.config.system.build.vm;
    in
    install" )
    rm *.qcow2 || true
    if [[ "$(uname -s)" == "Linux" ]]; then
    exec $vmpath/bin/run-* -nographic -cpu host -enable-kvm
    else
        exec $vmpath/bin/run-* -nographic -cpu host
    fi