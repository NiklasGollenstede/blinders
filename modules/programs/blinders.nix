dirname: inputs: { config, options, pkgs, lib, noUserModules, ... }: let lib = inputs.self.lib.__internal__; in let
    cfg = config.programs.blinders;
in {

    options = { programs.blinders = {
        enable = lib.mkEnableOption "the »blinders« sandboxing tool";
        package = (lib.mkPackageOption pkgs "blinders" { }) // {
            apply = pkg: pkg.override (old: { context.args.boundArgs = (old.context.args.boundArgs or [ ]) ++ cfg.args; });
        };
        args = lib.mkOption {
            description = "Arguments to bind to the blinders program (in addition to anything already bound to `.package`).";
            type = lib.types.listOf lib.types.str; default = [ ]; example = [ "--nix" "--tty" ];
        };
        system-profile.enable = lib.mkEnableOption "a system-wide blinders profile in /etc/blinders/system-profile";
        system-profile.config = lib.mkOption {
            description = "The NixOS configuration to use for the system-wide blinders profile.";
            default = { }; visible = "shallow"; inherit (noUserModules.extendModules { }) type;
        };
    }; };


    config = {

        environment.systemPackages = lib.mkIf cfg.enable [ cfg.package ];
        programs.blinders.system-profile.enable = lib.mkIf cfg.enable (lib.mkDefault true);

        environment.etc."blinders/system-profile" = lib.mkIf cfg.system-profile.enable {
            source = cfg.system-profile.config.system.build.toplevel;
        };

        programs.blinders.system-profile.config = {
            nixpkgs.hostPlatform = config.nixpkgs.hostPlatform;
            profiles.blinders.enable = true;
            nixpkgs.pkgs = pkgs; # optimization
            nixpkgs.overlays = lib.mkForce [ ];
        };

    };

}
