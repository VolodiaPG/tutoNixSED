let
  cfg = import ../cfg.nix;
  user = cfg.user;
  ghUsers = map (str: "gh:" + str) cfg.ghUsers;
in {
  flake = {
    nixosModules.cloud-init = {
      pkgs,
      config,
      ...
    }: let
      settingsFormat = builtins.toJSON;
      basecfg = settingsFormat config.services.cloud-init.settings;
      cfgfile = settingsFormat {
        users = [
          {
            name = user;
            groups = ["sudo"];
            sudo = "ALL=(ALL) NOPASSWD:ALL";
            lock_passwd = true;
            ssh_import_id = ghUsers;
          }
        ];
      };
    in {
      environment.systemPackages = [pkgs.ssh-import-id pkgs.cloud-init];
      environment.etc."/cloud/cloud.cfg.d/01_ssh.cfg".text = ''
        #cloud-config
        users:
        - name: myce
          groups: [sudo]
          sudo: ALL=(ALL) NOPASSWD:ALL
          ssh_import_id:
            - gh:volodiapg
          lock_passwd: true
      '';
      system.stateVersion = "22.05"; # Do not change
    };
  };
}
