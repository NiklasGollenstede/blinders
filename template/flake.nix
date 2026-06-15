{ description = (
    "A minimal example showing how to use blinders for a project."
); inputs = {

    nixpkgs = { url = "github:NixOS/nixpkgs/nixos-26.05"; };
    functions = { url = "github:NiklasGollenstede/nix-functions"; inputs.nixpkgs.follows = "nixpkgs"; };
    installer = { url = "github:NiklasGollenstede/nixos-installer"; inputs.nixpkgs.follows = "nixpkgs"; inputs.functions.follows = "functions"; };
    wiplib = { url = "github:NiklasGollenstede/nix-wiplib"; inputs.nixpkgs.follows = "nixpkgs"; inputs.installer.follows = "installer"; inputs.functions.follows = "functions"; };
    blinders = { url = "github:NiklasGollenstede/blinders"; inputs.nixpkgs.follows = "nixpkgs"; inputs.installer.follows = "installer"; inputs.functions.follows = "functions"; };
    systems.url = "github:nix-systems/default";
    # (There is a bit of an chicken-and-egg problem with lockfiles of templates inside the repo that they should include. Any committed lockfile will necessarily be at least one commit behind (and even for that would need to be updated on every commit`). That is the only reason why this template does not include a lock file -- do commit yours!)

}; outputs = inputs: inputs.functions.lib.importRepo inputs ./. (repo: [

    ## Export your repo's things:
    { overlays.default = (final: prev: { # export packages for consumption in flakes (/nix code) via overlays
        my-dev-shell = final.mkShell { packages = [ final.hello ]; };
    }); }
    { devShells = inputs.functions.lib.exportFromPkgs { inherit inputs; what = pkgs: { # export packages/devShells for CLI consumption via (legacy)packages/devShells.
        default = pkgs.my-dev-shell; # (re-)name your shell "default" for easier use on the CLI
    }; }; }

    ## Enable `nix run .#init` to initialize a blinders sandbox matching this repo to be used rapidly from the CLI or editor integration:
    (inputs.blinders.lib.mkBlindersInitApp {
        inherit inputs;
        config = {pkgs, ... }: {
            environment.systemPackages = [ pkgs.hello ];
            programs.bash.interactiveShellInit = inputs.nixpkgs.lib.mkAfter ''
                export PS1="(blinders) $PS1"
            '';
        };
        devShell = "my-dev-shell"; # A package/devShell in pkgs (see above)
        args = [
            "--read-only-glob=?**/.vscode/"
        ];
        appName = "init"; # (Default) export the app as "init", so it can be run via »nix run .#init -- ...«
        addOutputs = true; # (Default) add all packages from this flake's overlays to the blinders profile, so they're available in the sandbox without needing to explicitly add them to the config
    })

]); }
