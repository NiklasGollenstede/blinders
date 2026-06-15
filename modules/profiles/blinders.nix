dirname: inputs: { config, options, pkgs, lib, modulesPath, modulesVersion, noUserModules, ... }: let lib = inputs.self.lib.__internal__; in let
    cfg = config.profiles.blinders;
in {

    options = { profiles.blinders = {
        enable = lib.mkEnableOption "the base settings for »blinders« profiles";
    }; };


    config = lib.mkIf cfg.enable (lib.mkMerge [ ({

        ${if options?wip then "wip" else null} = {
            experiments.no-state-version.enable = lib.mkIf (lib.hasInfix "-patched/" modulesPath) true;
            base.enable = true;
            base.showDiffOnActivation = false;
            programs.blesh.enable = lib.mkForce false;
        };
        system.stateVersion = lib.mkDefault modulesVersion;

        # Minimalism:
        boot.isContainer = true;
        boot.initrd.systemd.enable = true; # (required by isContainer?)
        profiles.${if options?profiles.minimal then "minimal" else null}.enable = true;
        services.dbus.packages = lib.mkForce [ ];
        programs.git.package = pkgs.gitMinimal;
        security.sudo.enable = false;
        system.fsPackages = lib.mkForce [ ];
        # Avoid building stuff that won't be used:
        systemd.units = lib.mkForce { };
        systemd.user.units = lib.mkForce { };
        system.build.etcMetadataImage = lib.mkForce pkgs.emptyFile;
        system.build.etcBasedir = lib.mkForce pkgs.emptyDirectory;

        # We need / use it as a static /etc, but need symlinks pointing elsewhere (e.g. /var/lib/nixos/) for /etc/{passwd,group,resolv.conf}:
        system.etc.overlay = { enable = true; mutable = false; }; # (ineffective, but this is how the /etc will be used)
        systemd.sysusers.enable = true; # links /etc/passwd and /etc/group into /var/lib/nixos/etc/ (the userborn module links them to /var/lib/nixos/ by default)
        #environment.etc.passwd.text = "root:x:0:0:System administrator:/root:/run/current-system/sw/bin/bash";
        #environment.etc.group.text = "root:x:0:";
        environment.etc."resolv.conf".source = "/var/lib/nixos/etc/resolv.conf";
        networking.resolvconf.enable = false;

    }) ]);

}
