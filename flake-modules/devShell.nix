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
        faas-cli
        sshpass
        mosquitto
      ];
    };
  };
  flake = {
  };
}
