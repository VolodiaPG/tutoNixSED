# Introduction to Nix

This demo focuses on producing docker images and VMs to illustrate the main steps towards a full scale deployment on Grid'5000.

## Getting started

This tutorial works best on Linux, especially for the VM part that needs a linux x86 system to be generated.

1. Install nix: https://nixos.org/download#download-nix
2. Append to /etc/nix/nix.conf:
    ```
    extra-experimental-features = nix-command flakes
    max-jobs = auto
    cores = 0
    log-lines = 50
    ```
3. Now, from the root of this repository you can `nix develop` to enter the dev shell
4. Run `just` will list all available commands
7. `just vm` will boot the VM locally
8. `just ssh` will connect you inside
10. See it running on k3s with `k9`

Enjoy

# How to use Openfaas ?

1. `just vm`
2. `just tun`
3. `just faas-login`
4. Push a function with `just faas-pub` (consider changing the registry from what I set here)
5. `just faas-deploy` deploys the function on k3s
6. `just ssh` to get inside
7. `mosquitto_pub -h localhost -t sample-topic -m "Hello World!"`

> You can monitor the outputs using the shell alias when you are inside the vm (`j ssh-in`) by typing `k9`

This part performs a deep merge of to generate the full ouputs of the flake (this is pretty useful). You can check all the outputs with `nix flake show`.
