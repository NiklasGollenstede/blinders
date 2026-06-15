dirname: inputs:  let
    lib = inputs.self.lib.__internal__;
in { pkgs, ... }:

## Creates a blinders profile from a given `config` customization.
#  In addition to `config`, pass a list of non-nixpkgs NixOS `modules` to import, and `nixpkgs.lib.nixosSystem` function.
#  Alternatively, pass a set of flake `inputs` to automatically use all inputs' default `modules` and `input.nixpkgs`'s `nixosSystem`.
#  These (and all other) arguments are passed on to `nixos-installer.lib.mkNixosConfiguration`.
#
#  The `pkgs` inside the profile configuration is fixed to the parent `pkgs`, to avoid double-evaluation and mismatching overlays/configuration.
#
#  Example usage:
#    my-blinders = pkgs.blinders.override (old: { context.args.boundArgs = [
#        "--profile=!${mkBlindersProfile { inherit pkgs; config = {
#                environment.systemPackages = [ pkgs.hello ];
#                programs.bash.interactiveShellInit = lib.mkAfter ''
#                    export PS1="(blinders) $PS1"
#                '';
#        }; } }"
#    ]; });
{
    config ? { }, # NixOS configuration to add to the profile.
    #inputs, modules, nixosSystem,
... }@args: let
    system = lib.inst.mkNixosConfiguration ((builtins.removeAttrs args [ "config" ]) // {
        name = "blinders-profile";
        extraModules = (args.extraModules or [ ]) ++ [
            inputs.nixpkgs.nixosModules.readOnlyPkgs
        ] ++ [ {
            _file = "${dirname}/mkBlindersProfile.nix";
            config.nixpkgs.pkgs = pkgs; # very much do use this
            options.nixpkgs.pkgs = lib.mkOption { readOnly = true; }; # do not allow overriding
            config.profiles.blinders.enable = true;
        } ];
        overlays = [ ]; # already in `pkgs`
        mainModule = { _file = "mkBlindersProfile#config"; imports = [ config ]; };
    });
in system.config.system.build.toplevel.overrideAttrs (old: {
    passthru = (old.passthru or { }) // { inherit system; };
})
