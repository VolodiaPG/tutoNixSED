# Introduction to Mycelium

This demo focuses on running the minimal stack required to emulate the Mycelium project.

## Getting started with Mycelium

This tutorial works best on Linux, especially for the VM part that needs a linux x86 system to be generated (Macos Intel series should work as well, but M-series Macs are not supported due to [an unidentifed bug](https://github.com/NixOS/nixpkgs/issues/295363)).

### Prerequisites

1. Have [nix](https://nixos.org/download#download-nix) installed
2. Have [docker](https://docs.docker.com/engine/install) installed

### Instructions

1. Now, from the root of this repository you can `nix develop` to enter the dev shell
3. Run `just` will list all available commands
4. `just vm` will boot the VM locally and connect you as the `myce` user, password is `myce`
5. `just ssh` will connect you inside from another terminal using ssh
6. See OpenFaas and MQTT Connectors running on k3s with `k9`, to quit, type `:q`
7. Add the `functions/sample-topic-func` by doing `just faas-pub`. The command will build the function, push it to [ttl.sh](https://ttl.sh) and deploy it on OpenFaas. The image is only stored for a limited time on ttl.sh.
8. Check that everything is running with `k9`
9. In the VM, run `just mqtt` to publish a message to mosquitto, the MQTT broker inside the VM.
10. Check that the message is received by the MQTT connector with `k9` by inspecting the logs of the function

Enjoy!
