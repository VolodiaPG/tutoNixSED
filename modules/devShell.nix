{
  self,
  lib,
  ...
}: {
  perSystem = {
    config,
    self',
    inputs',
    pkgs,
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        just
        nixos-rebuild
        qemu
        sshpass
        faas-cli
      ];
    };
  };
  flake = {
  };
}
