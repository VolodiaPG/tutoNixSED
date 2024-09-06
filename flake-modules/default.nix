{inputs, ...}: {
  imports = [
    ./fog-node
    ./devShell.nix
  ];

  perSystem = {system, ...}: {
    _module.args = {
      pkgsUnfree = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    };
  };
}
