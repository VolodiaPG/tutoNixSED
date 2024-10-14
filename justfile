# SSH command with default options for connecting to the VM
export SSHPASS:="myce"
export SSH_CMD := "sshpass -e ssh -t -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no myce@127.0.0.1 -p 4444"

# Registry for storing images temporarily
REGISTRY := env_var_or_default('REGISTRY', "ttl.sh/" + `whoami` + "-" + `hostname`)

# Time that the image will be stored in the registry
TAG := env_var_or_default('TAG', "10m")

_default:
    @just --list

# connects inside the VM using SSH
ssh:
    @{{SSH_CMD}}

# Log in to OpenFaaS
faas-login:
    #!/usr/bin/env bash
    PASS=$({{SSH_CMD}} sudo kubectl get secret -n openfaas basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode)
    echo $PASS | {{SSH_CMD}} faas-cli login --password-stdin --gateway http://127.0.0.1:31112
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
    {{SSH_CMD}} << EOF
    cd /home/myce/mycelium/functions
    faas-cli publish -f "{{file}}"
    faas-cli deploy -f "{{file}}"
    EOF

# Publish a test message to MQTT broker (run this command from within the VM)
mqtt:
    #!/usr/bin/env bash
    {{SSH_CMD}} 'mosquitto_pub -h localhost -t sample-topic -m "Hello World!"'

# Build and run the VM
vm clean='false':
    #!/usr/bin/env bash
    set -e
    SYSTEM=$(case "$(uname -s)-$(uname -m)" in \
        Linux-x86_64)  echo "x86_64-linux" ;; \
        Linux-aarch64)  echo "aarch64-linux" ;; \
        Darwin-x86_64) echo "x86_64-darwin" ;; \
        *)             echo "Unsupported system" && exit 1 ;; \
    esac)
    HOST_SYSTEM=$(case "$(uname -s)-$(uname -m)" in \
        Linux-x86_64)  echo "x86_64-linux" ;; \
        Linux-aarch64)  echo "aarch64-linux" ;; \
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
    if [ "{{clean}}" = "true" ]; then
    rm *.qcow2 || true
    fi
    if [[ "$(uname -s)" == "Linux" ]]; then
    exec $vmpath/bin/run-* -nographic -cpu host -enable-kvm
    else
        exec $vmpath/bin/run-* -nographic -cpu host
    fi