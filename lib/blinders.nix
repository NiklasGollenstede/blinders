dirname: inputs: let
    lib = inputs.self.lib.__internal__;
in rec {

    ## Creates an exportable set of blinders profiles to be built on the CLI.
    #  Example usage:
    #    flake.nix: outputs = inputs@{ }: (inputs.blinders.lib.mkBlindersInitApp { inherit inputs; })
    #    CLI $ nix run .#init # creates a ./.blinders/ state directory, by default in the repo root
    #    CLI $ ./.blinders/bin/blinders # launch the configured blinders sandbox
    mkBlindersInitApp = {
        inputs, # `{ self?, nixpkgs, systems?, }`: The top-level flake's `inputs` (as passed to the `outputs` function). Needs to contain at least `nixpkgs`. The `overlays.default` from all other (direct) inputs are added to `pkgs`, and `systems` (if present) should be one of <https://github.com/nix-systems>. `self` is used in some of the defaults for other arguments.
        args ? [ ], # Additional arguments to bind to the blinders program.
        config ? { }, # Blinders profile NixOS configuration.
        devShell ? null, # Name of a package/devShell in `pkgs` to use as blinders »--env«.
        appName ? "init", # Name (not absolute output path) of the exported app (`nix run .#$appName -- ...`).
        addOutputs ? inputs?self.overlays, # Whether to add all packages exported by this flake (via overlays) to the blinders profile.
        extraSetup ? pkgs: ":", # Shell snippet to run during the initialization of the blinders state, e.g. to create bind mount sources that ».args« reference. This runs inside the future blinders state dir, but outside any sandboxing.
        description ? "Initialize blinders for this project.", # Description of the exported app.
    }@extra: { apps = lib.fun.exportFromPkgs ((builtins.removeAttrs extra (lib.attrNames (lib.functionArgs mkBlindersInitApp))) // { inherit inputs; what = pkgs: let
        profile = pkgs.mkBlindersProfile { inherit inputs; config = { _file = "${dirname}/blinders.nix#blindersInitApp"; imports = [ {
            imports = [ { _file = "blindersInitApp#config"; imports = [ config ]; } ];
            options.system.path = lib.mkOption { apply = env: env.override { ignoreSingleFileOutputs = true; }; }; # the below may add stuff to the system env that was not meant for that
            config.environment.systemPackages = lib.optionals addOutputs ((lib.attrValues (lib.fun.getModifiedPackages pkgs inputs.self.overlays)));
        } ]; }; };
        env = lib.fun.print-dev-env pkgs.${devShell};
        blinders = pkgs.blinders.override (old: { context.args.boundArgs = lib.remove null [
            "--nix" "--nixos" "--profile=!${profile}" (if devShell != null then "--env=!${env}" else null)
            "--read-only=!./.blinders/" # add "--hide=!./.blinders/" to args to completely hide it
            "--fs=bind:!./.blinders/home/bash_history:~/.bash_history"
            "--read-only-glob=!**/.git/"
        ]; });
        vsCodeSettings = ''
            "chat.disableAIFeatures": false,
            "chat.tools.terminal.terminalProfile.linux": {
                "path": "''${workspaceFolder}/.blinders/bin/blinders",
                "args": [ "--dir=''${workspaceFolder}" ],
            },
            "chat.tools.terminal.enableAutoApprove": true,
            "chat.tools.terminal.ignoreDefaultAutoApproveRules": true,
            "chat.tools.terminal.autoApprove": {
                "/^/": { "approve": true, "matchCommandLine": true, },
            },
        '';
    in { ${appName} = (pkgs.writeShellScriptBin "init" ''
        set -u -o pipefail # bash
        binaryName='nix run .#'${lib.escapeShellArg appName}' --'
        description=${lib.escapeShellArg description}$'\n'
        argvDesc="" ; details=""
        declare -g -A allowedArgs=(
            [--root=dir]="The path in which to create the ».blinders« state directory. Defaults to the closest parent that contains a».git/config«."
        )

        source ${inputs.functions.lib.bash.generic-arg-parse}
        source ${inputs.functions.lib.bash.generic-arg-help}
        source ${inputs.functions.lib.bash.generic-arg-verify}
        shortArgsAre=flags generic-arg-parse "$@" || exit
        shortArgsAre=flags generic-arg-help "$binaryName" "$argvDesc" "$description" "$details" || exit
        shortArgsAre=flags generic-arg-verify || exit

        if [[ ''${args[root]:-} ]] ; then root=''${args[root]} ; else
            root=$( ${lib.fun.intoRepoDir} pwd ) || exit
        fi ; cd "$root" || exit
        mkdir -p .blinders && cd .blinders || exit

        mkdir -p home bin || exit
        printf '*\n' > ./.gitignore || exit
        : >> ./home/bash_history || exit
        nix build --out-link ./bin/blinders ${blinders} && ln -sfT "$( readlink -f ./bin/blinders )"/bin/blinders ./bin/blinders || exit
        nix build --out-link ./profile ${profile} || exit # for manual discoverability
        ${if devShell != null then "nix build --out-link ./env ${env} || exit" else ":"} # for manual discoverability
        ( ${if lib.isFunction extraSetup then extraSetup pkgs else extraSetup} ) || exit

        cd .. || exit
        printf 'Initialized blinders state for this project in %s/.blinders.\n' "$PWD" >&2
        if [[ ''${TERM_PROGRAM:-} == "vscode" ]] ; then
            workspaces=$( shopt -s nullglob ; echo "$PWD"/*.code-workspace "$PWD"/.vscode/*.code-workspace )
            printf '\nMake sure to have these settings in your the "settings" of your workspace%s or %s/.vscode/settings.json:\n' "''${workspaces:+ (maybe: $workspaces ?)}" "$PWD" >&2
            printf '\n%s' ${lib.escapeShellArg vsCodeSettings} >&2 # (has a tailing newline)
            printf '\nIn a workspace with multiple "folders", initialize the blinders state in each of them, or pick one of the "folders" and add its "name" to the ''${workspaceFolder:name} in the settings to point to the shared .blinders dir (e.g. "''${workspaceFolder:sources}/../.blinders/...").\n' >&2
        fi

    '').overrideAttrs (old: {
        passthru = old.passthru // { inherit profile blinders vsCodeSettings; args = extra; };
        meta = old.meta // { inherit description; };
    }); }; asApps = true; }); };


    ## Creates an exportable set of blinders profiles to be built on the CLI.
    #  Example usage:
    #    flake.nix: outputs = inputs@{ }: (lib.blinders.mkBlindersProfiles { inherit inputs; config = { pkgs, ...}: { ... }; })
    #    CLI $ nix build .#blinders-profile --out-link ./blinders-profile
    #    CLI $ blinders --profile=./blinders-profile ...
    mkBlindersProfiles = {
        inputs, # `{ self?, nixpkgs, systems?, }`: The top-level flake's `inputs` (as passed to the `outputs` function). Needs to contain at least `nixpkgs`. The `overlays.default` from all other (direct) inputs are added to `pkgs`, and `systems` (if present) should be one of <https://github.com/nix-systems>. `self` is used in some of the defaults for other arguments.
        systems ? if inputs?systems then import inputs.systems else lib.fun.defaultSystems, # List of architectures to build for.
        name ? "blinders-profile", # Name of the exported package (`nix build .#$name -- ...`).
        config ? { }, # NixOS configuration to apply for all systems.
    ... }@args: { packages = lib.genAttrs systems (localSystem: let
        system = lib.inst.mkNixosConfiguration ((builtins.removeAttrs args [ "systems" "config" ]) // {
            inherit name;
            extraModules = (args.extraModules or [ ]) ++ [ { _file = "${dirname}/blinders.nix#mkBlindersProfiles"; config = {
                nixpkgs.hostPlatform = localSystem;
                profiles.blinders.enable = true;
            }; } ];
            mainModule = { _file = "mkBlindersProfiles#config"; imports = [ config ]; };
        });
    in { ${name} = system.config.system.build.toplevel.overrideAttrs (old: {
        passthru = (old.passthru or { }) // { inherit system; };
    }); }); };

}
