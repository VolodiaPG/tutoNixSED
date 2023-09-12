export SSHPASS:="root"
export SSH_CMD:="sshpass -e ssh -t -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no root@127.0.0.1 -p 2221"

_default:
    @just --list

# Run the VM interactively
vm:
    #!/usr/bin/env bash
    set -e
    vm_path=$(nix build --extra-experimental-features nix-command --extra-experimental-features flakes .#vm --print-out-paths --no-link --quiet)/nixos.qcow2
    temp=nixos.env.qcow2
    cp $vm_path $temp
    chmod u+rwx $temp

    qemu-kvm \
        -cpu max \
        -name nixos \
        -m 4096 \
        -smp 4 \
        -drive cache=writeback,file="$temp",id=drive1,if=none,index=1,werror=report -device virtio-blk-pci,drive=drive1 \
        -net nic,netdev=user.0,model=virtio -netdev user,id=user.0,hostfwd=tcp::2221-:22 \
        -enable-kvm \
        -nographic&
    wait

# Build the project as a docker image
container:
    nix build .#docker
    docker load < result

# Push an image to ghcr
_push image user:
    docker tag {{image}} ghcr.io/{{user}}/{{image}}
    docker push ghcr.io/{{user}}/{{image}}

# Push docker images to ghcr
ghcr user: container
    just _push tutosed:latest {{user}}

# connects inside the VM using SSH
ssh-in:
    @$SSH_CMD