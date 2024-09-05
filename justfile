export SSHPASS := "root"
export SSH_CMD := "sshpass -e ssh -t -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no root@127.0.0.1 -p 2221"

_default:
    @just --list

# Build the project as a docker image
container:
    nix build .#docker
    docker load < result

# Push an image to ghcr
_push image user:
    docker tag {{ image }} ghcr.io/{{ user }}/{{ image }}
    docker push ghcr.io/{{ user }}/{{ image }}

# Push docker images to ghcr
ghcr user: container
    just _push tutosed:latest {{ user }}

# connects inside the VM using SSH
ssh-in:
    @$SSH_CMD

faas-login:
    #!/usr/bin/env bash
    PASS=$($SSH_CMD kubectl get secret -n openfaas basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode)
    echo $PASS | faas-cli login --password-stdin
    echo "PASSWORD: $PASS"

faas-pub: faas-login
    cd {{ justfile_directory() }}/functions && find . -maxdepth 1 -type f -name '*.yml'  -printf '%f\n' \
        | xargs -I {} faas-cli publish -f {}

faas-deploy: faas-login
    cd {{ justfile_directory() }}/functions && find . -maxdepth 1 -type f -name '*.yml'  -printf '%f\n' \
        | xargs -I {} faas-cli deploy -f {}

tun:
    $SSH_CMD "k3s kubectl port-forward -n openfaas svc/gateway 8080:8080"&
    $SSH_CMD -N -g -L "8080:127.0.0.1:8080"
    wait

mqtt:
    mosquitto_pub -h localhost -t sample-topic -m "Hello World!"

vm:
    #!/usr/bin/env bash
    set -xe
    vmpath=$(nix build --impure --print-out-paths --expr "
    let
    self = builtins.getFlake ''path://{{ justfile_directory() }}'';
      vm = self.nixosConfigurationsFunction.os {pwd=''{{ justfile_directory() }}'';};
      install = vm.config.system.build.vm;
    in
    install" )
    rm *.qcow2
    exec $vmpath/bin/run-* -nographic -cpu host -enable-kvm

ssh:
    ssh -o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null myce@127.0.0.1 -p 4444
