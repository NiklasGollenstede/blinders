{ description = (
    "" # TODO!
    # This flake file defines the inputs (other than except some files/archives fetched by hardcoded hash) and exports all results produced by this repository.
    # It should always pass »nix flake check« and »nix flake show --allow-import-from-derivation«, which means inputs and outputs comply with the flake convention.
); inputs = {

    # To update »./flake.lock«: $ nix flake update
    nixpkgs = { url = "github:NixOS/nixpkgs/nixos-26.05"; };
    functions = { url = "github:NiklasGollenstede/nix-functions"; inputs.nixpkgs.follows = "nixpkgs"; };
    installer = { url = "github:NiklasGollenstede/nixos-installer"; inputs.nixpkgs.follows = "nixpkgs"; inputs.functions.follows = "functions"; };
    systems.url = "github:nix-systems/default-linux";

}; outputs = inputs: inputs.functions.lib.importRepo inputs ./. (repo': let
    repo = repo'.override { defaultPackage = "blinders"; };
    lib = repo.lib.__internal__;
in [ # Run »nix flake show« to see what this merges to:


    ## Exports

    repo # lib.* nixosModules.* overlays.* (legacy)packages.*.* patches.*
    { templates.default = { path = builtins.path { path = "${inputs.self}/template"; name = "blinders-template"; filter = path: type: path != ".blinders"; }; description = "Integrating blinders into a Nix Flake project"; }; }


    ## Examples:

    (lib.blinders.mkBlindersInitApp { inherit inputs; }) # See ./template/flake.nix for a better example.

    (lib.blinders.mkBlindersProfiles {
        inherit inputs; name = "blinders-base-profile";
        config = { pkgs, ...}: { environment.systemPackages = lib.attrValues (lib.fun.getModifiedPackages pkgs repo.overlays); };
    })
    ({ packages = lib.fun.exportFromPkgs { inherit inputs; what = pkgs: {
        blinders-customized = pkgs.blinders.override (old: { context.args.boundArgs = [
            "--nix" "--nixos"
            #"--profile=!${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.blinders-profile}" # use the custom profile built above
            #"--env=!${lib.fun.print-dev-env (pkgs.mkShell { packages = [ pkgs.hello ]; })}" # source this before running the provided command, if any; else, use this as --rcfile to the shell (which is almost equivalent to running »nix develop« in the sandbox, just faster)
            "--only-git=#1" # if --dir is a git repo, only expose the top-level dirs/files that are tracked by git; else warn
            "--hide=?./.blinders/" # if ./.blinders does not exist, create it as directory; then hide it
            "--profile=?./.blinders/nixos-profile" # if there is a ./.blinders/nixos-profile, use that as profile; else ignore
            "--env=?./.blinders/dev-env"
            "--fs=bind:?./.blinders/home/bash_history:~/.bash_history" # if ./.blinders/home/bash_history does not exist, create it as file; then bind it to ~/.bash_history
            "--hide=?.vscode/" "--hide=?.env" # if ./.vscode / ./.env exists (even if git-tracked), hide them; else ignore
            "--read-only-glob=#**/.git/" # make any .git directories read-only; warn if there are none
        ]; });
    }; }; })

]); }
