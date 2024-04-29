# Introduction to Nix

This demo focuses on producing docker images and VMs to illustrate the main steps towards a full scale deployment on Grid'5000.

## Nginx HTTPS

This version of the repo is focused on providing an accessible configuration for Nginx w/ SSL and HTTPS.
The setup for nginx is in the `docker-compose.yml` file and the nginx config is in in the `nginx.conf` file.
To start, well, `docker-compose up` and voilà.

If you want to run the whole repo/demo: `just vm`, `just ssh-in`, `cd /mnt`, `docker-compose up` and then connect to `localhost:9008`.

> The nginx configuration serves SSL on port 9008 and http on 80. A standard configurations would aim http on 80 and SSL on 443.

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
5. `just container` will build the container (you need `docker`)
6. `just ghcr <username>` will send it to ghcr.io
7. `just vm` will boot the VM locally
8. `just ssh-in` will connect you inside
9. Check the systemd service with `systemctl status startTutoSEDContainer`
10. See it running on k3s with `k3s kubectl get pods`
10. Check parallel is installed in the container image using `k3s kubectl exec -i <hash of pod> parallel`. You should see a warning.

Enjoy

> We are not going to grid'5000, because then, the complicated part is not Nix anymore, its Grid'5000 and its legacy.

## Architecture of the flake

>In most of my flakes I use `flake-utils` to be able to target different system architecture.

Here, I define multiple flakes for the devenv, VM, modules for the VM.

Each is in its variable that is then injected in the last bit of code:
```nix
nixpkgs.lib.foldl nixpkgs.lib.recursiveUpdate {}
    [
    flakeDevEnv
    flakeModules
    flakeVM
    ];
```

# How to use Openfaas ?

1. `just vm`
2. `just tun`
3. `just faas-login`
4. Push a function with `just faas-pub` (consider changing the registry from what I set here)
5. `just faas-deploy` deploys the function on k3s
6. `just ssh-in` to get inside
7. `mosquitto_pub -h localhost -t sample-topic -m "Hello World!"`

> You can monitor the outputs using the shell alias when you are inside the vm (`j ssh-in`) by typing `k9`

This part performs a deep merge of to generate the full ouputs of the flake (this is pretty useful). You can check all the outputs with `nix flake show`.

