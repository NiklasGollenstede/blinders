#!/usr/bin/env bash
set -o pipefail -u

binaryName=blinders ; if [[ @{args.appName:-} ]] ; then binaryName='nix run .#'@{args.appName}' --' ; fi
description="EXPERIMENTAL: Run programs in a sandbox with access to only a single directory.
"
argvDesc='[PROGRAM=$SHELL [ARGS]...]'
declare -g -A allowedArgs=(
    [-t, --tty]="Create a new (pseudo) terminal for the sandbox. Otherwise, the sandbox will not have a controlling terminal. Defaults to true iff no PROGRAM is passed (explicitly). Use »--no-tty«/»-T« to explicitly disable."
    [-w, --wayland]="Bind the Wayland display socket into the container and set the WAYLAND_DISPLAY environment variable. It may be possible to hijack user input and clipboard contents and the like." # TODO: Consider https://git.sr.ht/~whynothugo/way-secure (not packaged)
    [-d, --dbus]="Bind the user D-Bus session bus socket into the container and set the DBUS_SESSION_BUS_ADDRESS environment variable. Note that this allows the sandbox to »systemd-run --user« arbitrary commands on the host, thus largely invalidating the sandboxing."
    [-g, --gpu]="Bind GPU devices (currently just /dev/dri) into the container. May be required for hardware acceleration in GUI applications."

    [--dir=path]='Host path to bind into the container at the same location. Defaults to ».«. As a precaution, relative paths are only accepted if they point at a child of »$HOME« or »${TMPDIR:-/tmp}«. To use the home itself or a directory outside of home / tmp, explicitly pass an absolute path. If the CWD is not (a child of) »--dir«, it will be set to »--dir«.'
    [--only=[+#!?]rel_path[/] ...]="Relative path inside »--dir« to make accessible (writable). Using one or more »--only« options makes »--dir« itself an otherwise empty directory inside the sandbox. Can be supplied multiple times. Symlinks are copied (instead of bind-mounted). See »--on-missing«."
    [--only-glob=[#!?]glob ...]="Same as »--only«, but with glob patterns instead of literal paths. The patterns are evaluated once at startup."
    [--only-git=[#!?]N]="Same as »--only«, but with the paths read from the output of »git ls-files --cached« in the »--dir«. With »N != 0«, the paths are truncated after the Nth slash (»--only-git=1« thus uses top-level file/dir names). "
    [--hide=[+#!?]rel_path[/] ...]="Relative path inside »--dir« to make inaccessible. Can be supplied multiple times. Does not support symlinks. See »--on-missing«."
    [--hide-glob=[#!?]glob ...]="Same as »--hide«, but with glob patterns instead of literal paths. The patterns are evaluated once at startup."
    [--read-only=[+#!?]rel_path[/] ...]="Relative path inside »--dir« to make read-only. Can be supplied multiple times. Does not support symlinks. See »--on-missing«."
    [--read-only-glob=[#!?]glob ...]="Same as »--read-only«, but with glob patterns instead of literal paths. The patterns are evaluated once at startup."
    [--fs=type:[[+#!?]source[/]:]target ...]="Additional custom filesystem mounts. Can be supplied multiple times. Supports a subset (»bind«, »ro-bind«, »dev-bind«, »symlink«, »tmpfs«, »proc«, »dev«, »dir«) of »bwrap«'s mount options with colons to separate the arguments (e.g. »--fs=tmpfs:/tmp« or »--fs=bind:/host/path:/container/path«). Relative paths are relative to »--dir«, paths starting with »~/« are relative to »"'$HOME'"«. Source paths (where required) that do not exist are considered an error (except with »symlink«). Order for mounts with different targets does not matter, as all mounts are sorted by target path. Later »--fs« mounts with the same target overwrite earlier ones. Use type »none« to remove mounts created by default or other options. Does not support symlinks. See »--on-missing«."

    [-n, --nix]="Allow access to the Nix daemon (and read-only to the Nix DBs). Read access to all of »/nix/store« is always granted."

    [-l, --host-net]="Disable network isolation. Otherwise, only access to non-local IPv4 addresses is allowed. Specifically, this gives the sandbox it's own localhost, forwards DNS to be resolved by the host by default, forbids access to local IPv4 network ranges and all IPv6, but allows all other traffic. The sandbox uses the host's IP address and DNS regardless."
    [-6, --ipv6]="Allow IPv6 traffic. Without »--host-net«, IPv6 is disabled by default because local devices may be accessible via global IPv6 addresses. Has no effect with »--host-net«."

    [--seccomp=string ...]="Apply a custom seccomp system call filter, as string used/understood by nsjail/kafel. May be supplied multiple times, with earlier filters tested first. If »--seccomp-default« is not disabled, then that is applied last. The DEFAULT action (taken if no explicit filter matches) may only be specified once (use »--seccomp-fallback=''« and/or »--no-seccomp-default«/»-S« to do so via a »--seccomp=« string)."
    [-s, --seccomp-default]="Enabled by default. Applies a default system call filter that allows (whitelists) a hopefully reasonable and safe subset of system calls and changes the »--seccomp-fallback=« action (if not set explicitly) to »ERRNO(EPERM)«. (Currently this applies Docker's default policy.)"
    [--seccomp-fallback=action]="Fallback/DEFAULT action for syscalls not matched by any »--seccomp=« or the »--seccomp-default« filter. Defaults to not set / empty, the default is implicitly »ALLOW«, if »--no-seccomp-default« and no »--seccomp=« is supplied or »KILL« otherwise."

    [--nixos]="Whether to treat the »--profile« as NixOS system (only symlink a few paths) or as FHS environment (ro-bind its »/bin«, »/lib«, »/user«, ...). Defaults to true/NisOS if »--profile«/etc/os-release's ID or ID_LIKE is »nixos« and false/FHS otherwise. Use »--no-nixos« to explicitly set to false."
    [--profile=[!#?]path]="System profile to provide the software environment inside the sandbox. Defaults to @{config.boundProfile:+»}@{config.boundProfile:-"the first of »/etc/blinders/system-profile«, »/run/current-system« and »/« that exists"}@{config.boundProfile:+«}. See »--nixos«, »--strict-profile« and »--on-missing«."
    [-p, --strict-profile]="Strictly only use the »--profile« for environment variables and file system contents (»/etc«, and for non-NixOS also »/bin«, »/lib(64)«, and »/usr«), unless overwritten by other options. In »--nixos« mode, this sources »/etc/set-environment«; otherwise, »/etc/environment« is parsed. Without »--strict-profile«, environment variables are inherited and a minimal »/etc« is constructed from ambient information to create a working sandbox environment. With »--strict-profile«, it is the callers responsibility to provide a »--profile« that is suitable in terms of functionality and isolation. Its »/etc« should at least have »passwd« and »group« and a »resolv.conf« as files (or symlinks). Those files (or their targets) will be shadowed by bind-mounted files with minimal correct settings. The files may also be symlinks, in which case the (direct) target files will be shadowed. Eposes the caller's UID+GID, and the env vars USER, GROUP, HOME, TERM and TERM_PROGRAM."
    # TODO?: ditch support for --no-strict-profile and require that blinders is built with a boundProfile?
    [--env=[#!?]env.sh]="Path to a shell script that is sourced in the container before executing the command, to set up environment variables. The path has to be valid inside the container, for example a path in »--dir« or the nix store. If no explicit PROGRAM is given, this will be passed to the shell as »--rcfile« (instead of sourcing it before starting the shell)."
    [--var=NAME[=[VALUE]] ...]="Set an environment variable in the container.
    Can be supplied multiple times. Later options with the same »NAME« overwrite earlier ones. If no »=VALUE« is given, then it is inherited from the host environment (which is different from setting an empty value). These may overwrite variables set by »blinders« itself (depending on other options), but are applied early in the container, before »--profile«/»/etc/environment«/»--env«."

    [--on-missing=action]="Action to take when the source path of one or more default mounts is missing (or otherwise invalid). Valid choices are »abort«/»!« (exit with error, the default for »--on-missing«), »warn«/»#« (print warning and continue without that mount) and »ignore«/»?« (silently continue without that mount). The same options may also be specified for explicitly requested mounts (»--hide[-glob]«, »--read-only[-glob]«, »--fs«) and other options (»--profile«, »--env«) via a prefix of »!«, »#« or »?« in their argument. Here, the default is the first symbol listed in the respective argument's description, and an additional action »+« may be available, which creates the source (as dir if the path ends in »/« or regular file otherwise) and otherwise behaves like »error«. When passing unknown values as arguments, prefix them explicitly."
    [-q, --quiet]="Suppress non-error messages."

    [--nsjail]="Use »nsjail« instead of »bwrap« as the tool to set up namespacing and mounts. This is only partially implemented."
    [-x, --trace]="Enable debug tracing in this script and other verbosity."
    [--dry-run]="Instead of launching the sandbox, print the shell-quoted launch command to stdout. (This implies and requires »--host-net«.)"
)
details='' ; if [[ @{args.boundArgs:-} ]] ; then
    details+=$'Bound arguments:\n    '"$( printf ' %q' "@{args.boundArgs[@]}" )"$'\n'
fi ; details+='
Description:
    Blinders provides a convenient command line interface to create containerized environments that expose only a primary directory, like a source code repository, from the host, but still allow programs inside the sandbox to work effectively (with functioning terminal and/or graphics).
    The main use case is for AI, especially for agents. The agent is supposed to work on one project, and should not be able to read, and definitely not write, anything outside of that project.
    Ideally, any changes made inside the sandbox can be clearly be detected, for example by using git and »--hide«ing the ».git« directory.

    Blinders uses bubblewrap for general namespacing, nsjail for syscall filtering, slirp4netns for networking, and a Nix(OS) for a functioning user space.
    Without arguments, blinders grants access only to the current directory, while preventing local network access and blocking all but a curated list of system calls.
    Optionally, more directories can be bound into the sandbox (or additional files/folders be protected), the network restrictions be lifted, the system call filtering be adjusted, or access to graphical output or compute be granted.

    As the sandbox is meant to run untrusted code or agents, one needs to review all changes made inside the sandbox, before executing any code or using any potentially harmful files that were exposed to the sandbox outside of it.
    Git can be an effective tool for this, as long as diffs/changes are reviewed carefully, and the ».git« directory protected with »--hide« or »--read-only« (see examples).
    Consider, though, that Git, by design, does not track changes to `.gitignore`d files, and that it does not track file permission changes (so the sandbox could make all files world-writable, for example).
    Permissions on the parent directory, and careful, project specific use of »--only-git« may help, but also have limitations and drawbacks (like making many files/directories unmovable mount points, and not updating automatically).

    Another important consideration with sandboxes and containers is the execution environment to provide on the inside, besides access to the intentionally mutable primary directory.
    By default, blinders exposes a subset of the host environment.
    As this can only rely on vague heuristics of what is necessary and safe to expose, it is much better to use a dedicated environment.
    Blinders uses (stripped down) NixOS configurations for this, either system wide (»/etc/blinders/system-profile«) or passed explicitly (as »--profile« and/or »--env« per project).

    Blinders comes with Nix tooling to conveniently set custom profiles and security settings per (Nix) project.
    Especially »mkBlindersInitApp« can be used to bind custom (NixOS) profile configuration, pre-existing dev-shell environments, (security) options, and sandbox-only state directories to blinders as a pre-configured CLI command, which can be used directly or configured as agent terminal environment in VSCode (and in principle other editors).


Example usage:

    Run a shell in a container with access to the current directory and the Wayland display. Can run Firefox, Chrome, VSCode, etc.:
        $ blinders --wayland --tty -- bash

    Open a shell for an AI agent, with explicit (but opportunistic) security settings:
        $ blinders --dir="${workspaceFolder}" --nix --nixos --only-git=#1 --hide=+./.blinders/ --profile=?./.blinders/profile --fs=bind:+./.blinders/home/bash_history:~/.bash_history --hide-glob=?.vscode/ --hide-glob=?.env --read-only-glob=#**/.git/ --tty -- bash

    To obtain a project-specific blinders profile:
        `flake.nix`: outputs.packages.${system}.my-profile = pkgs.mkBlindersProfile { inherit inputs; config.environment.systemPackages = [ pkgs.foo ]; };
        $ nix build .#my-profile --out-link ./.blinders/profile

    To get a system-wide »/etc/blinders/system-profile« for (implicit) ad-hoc use:
        Include in NixOS config: programs.blinders.system-profile.enable = true;
        $ blinders [--profile=/etc/blinders/system-profile]

    To use that with a local dev shell environment:
        $ nix print-dev-env .#my-dev-shell >./.blinders/env
        $ blinders --env=./.blinders/env --profile=/etc/blinders/system-profile

    Or bind arguments, including a profile and/or env, to a custom binders variant:
        `flake.nix`: outputs.packages.${system}.my-blinders = pkgs.blinders.override (old: { context.args.boundArgs = [ "--tty" "--nix" "--nixos" "--profile=${outputs.packages.${system}.my-profile}" "--env=${lib.fun.print-dev-env outputs.packages.${system}.dev-shell}" "--fs=bind:?./.blinders/home/bash_history:~/.bash_history" "--hide-glob=?.env" "--read-only-glob=#**/.git/" ]; });
        $ nix run .#my-blinders --

    All of that can be combined with »mkBlindersInitApp« (even this minimal example will pick up any packages added by your flake and include it s default dev shell environment):
        `flake.nix`: outputs = inputs@{ }: (inputs.blinders.lib.mkBlindersInitApp { inherit inputs; args = [ "--hide=?.env" "--read-only-glob=?**/.vscode/" ]; config = { }; devShell = "default"; })
        $ nix run .#init # creates a ./.blinders/ state directory, by default in the repo root
        $ ./.blinders/bin/blinders # launch the configured blinders sandbox
        Or follow the printed instructions to configure VSCode to use the blinders sandbox as terminal environment for your agents.

    To find out which (additional) syscalls a program needs:
        $ blinders --[no-]seccomp-default --seccomp-fallback=LOG -- ${program}
        # and check "audit" messages from the kernel, e.g. via »dmesg«

Limitations:
    - there are no resource restrictions on the sandbox
    - security review missing
'

invalidArgs=2 ; missingFile=3
exitCodeOnError=$invalidArgs shortArgsAre=FlAgS dupOptsAre=lists generic-arg-parse @{args.boundArgs:+"@{args.boundArgs[@]}"} "$@" || exit
shortArgsAre=FlAgS generic-arg-help "$binaryName" "$argvDesc" "$description" "$details" || exit
exitCodeOnError=$invalidArgs generic-arg-verify || exit


## Helpers

source "@{inputs.functions.lib.bash.prepend_trap}"
prepend_trap 'rm -rf $tmp 2>/dev/null' EXIT ; tmp=$( mktemp -d ) && mkdir -p "$tmp"/etc || exit
split=( $tmp ) ; if (( ${#split[@]} != 1 )) ; then abort "Unexpected space in temp path: $tmp" 1 ; fi

# args: 1: message, 2?: exit code, 3?: hint, 4?: missing path
function ignore { return 1 ; }
function warn { [[ ${args[quiet]:-} ]] || echo "Warning: $1${3:+ ($3)}" >&2 ; return 1 ; }
function abort { echo "Error: $1" >&2 ; exit "${2:-1}" ; }
function create { if [[ ${4:-} ]] ; then
    if [[ $4 == */ ]] ; then mkdir -p "$4" || exit "${2:-1}" ; else mkdir -p "${4%/*}" && : >"$4" || exit "${2:-1}" ; fi
else abort "$@" ; fi ; }
# Takes a »string« optionally starting with !/+, #, or ?, assigns the string to the variable »name« without the prefix, ans sets »report« based on the prefix, or to »default« if there was none:
function pop-report-level { # 1: default, 2: name, 3: string
    report=$1 ; local -n var=$2 ; var=$3
    local re='^([!#?]).*' ; [[ $report == create ]] && re='^([!+#?]).*'
    if [[ ! $var =~ $re ]] ; then return ; fi
    var=${var:1} ; case ${BASH_REMATCH[1]} in
        '+') report=create ;; '!') report=abort ;; '#') report=warn ;; '?') report=ignore ;;
    esac
}


## Mount and environment collection

declare -A environment=( )
function add-env { # 1: name, 2: value
    environment[$1]=$2
}
declare -A targets=( ) # type to apply to a target path (e.g. --bind, --ro-bind, --dir)
declare -A sources=( ) # source path for targets that require one (e.g. --bind, --ro-bind, --file), indexed by target path
declare -A missing=( ) # source paths that do not exist, indexed by target path
declare -A duplicates=( ) # target paths that have more than one assignment
function add-if-exists { [[ $2 == /* && -e $2 ]] && add-mount "$@" ; }
function add-mount { # 1: type, 2?: source, 3: target
    local type=$1 source= hasSource= target=
    if [[ $# == 3 ]] ; then source=$2 hasSource=1 target=$3
    elif [[ $# == 2 ]] ; then target=$2
    else abort "Invalid number of arguments to add-mount function" $invalidArgs ; fi
    [[ $target == /* ]] || abort "Final mount paths must be absolute: $target" $invalidArgs

    if [[ $hasSource ]] ; then
        [[ $source == /* ]] || abort "Final mount paths must be absolute: $source" $invalidArgs
        if [[ $type != --symlink && $type != --file && $type != --bind-data && $type != --ro-bind-data ]] && [[ ! -e $source ]] ; then missing[$target]=$source ; return ; fi
        sources[$target]=$source
    fi
    if [[ ${targets[$target]:-} ]] ; then
        if [[ ! ${duplicates[$target]:-} ]] ; then duplicates[$target]=${targets[$target]} ; fi
        duplicates[$target]+=' '$type
    fi
    targets[$target]=$type
}
# Appends the collected mount arguments to the bwrap/nsjail command.
# Aborts if there are any missing sources or duplicate targets, sorts the arguments by target path (parents before contents), and translates mount args for nsjail mode.
function linearize {
    # Check
    local exitCode=
    if [[ ${#duplicates[@]} -gt 0 ]] ; then
        echo "Duplicate targets:" >&2
        for target in "${!duplicates[@]}" ; do echo "  $target (${duplicates[$target]})" >&2 ; done
        exitCode=$invalidArgs
    fi
    if [[ ${#missing[@]} -gt 0 ]] ; then
        if [[ ${args[on-missing]} != ignore && ! ${args[quiet]:-} ]] ; then
            echo "Missing sources:" >&2
            for target in "${!missing[@]}" ; do echo "  ${missing[$target]} ($target)" >&2 ; done
        fi
        [[ ${args[on-missing]} != abort ]] || exitCode=$missingFile
    fi
    if [[ $exitCode ]] ; then return $exitCode ; fi

    # Ensure parents (which is not actually required for bwrap or nsjail, and --dir is rather expensive with nsjail)
    #for target in "${!targets[@]}" ; do
    #    local parent=${target%/*}
    #    while [[ $parent ]] ; do
    #        if [[ ! ${targets[$parent]:-} ]] ; then
    #            targets[$parent]=--dir
    #        fi
    #        parent=${parent%/*}
    #    done
    #done

    # Sort (+translate)
    while IFS= read -r -d '' target ; do
        if [[ ! ${args[nsjail]:-} ]] ; then
            if [[ ${sources[$target]:-} ]] ; then
                bwrap+=( "${targets[$target]}" "${sources[$target]}" "$target" )
            else
                bwrap+=( "${targets[$target]}" "$target" )
            fi
        else # nsjail: translate
            if [[ $target == *:* ]] ; then abort "Invalid target path for nsjail (contains colon): $target" $invalidArgs ; fi
            type="${targets[$target]#--}"
            case $type in
                # nsjail --mount src:dst:fs_type:options
                tmpfs|proc) nsjail+=( --mount $type:"$target":$type: ) ;;
                dev) nsjail+=( # bwrap seems to do this:
                    --mount tmpfs:"$target":tmpfs:mode=755
                    --bindmount /dev/null:"$target"/null
                    --bindmount /dev/full:"$target"/full
                    --bindmount /dev/zero:"$target"/zero
                    --bindmount /dev/random:"$target"/random
                    --bindmount /dev/urandom:"$target"/urandom
                    --bindmount /dev/tty:"$target"/tty
                    --symlink /proc/self/fd:"$target"/fd
                    --symlink /proc/self/fd/0:"$target"/stdin
                    --symlink /proc/self/fd/1:"$target"/stdout
                    --symlink /proc/self/fd/2:"$target"/stderr
                    --symlink /proc/kcore:"$target"/core
                    --mount devpts:"$target"/pts:devpts:mode=620,ptmxmode=666
                    --mount dir:"$target"/shm:tmpfs:
                    --symlink pts/ptmx:"$target"/ptmx
                    #--bindmount /dev/console:"$target"/console # necessary? (bwrap does more than simply binding this)
                ) ;;
                # nsjail does no distinction on dev?
                bind) nsjail+=( --bindmount "$( realpath "${sources[$target]}" ):${target}" ) ;;
                ro-bind) nsjail+=( --bindmount_ro "$( realpath "${sources[$target]}" ):${target}" ) ;;
                dev-bind) nsjail+=( --bindmount "$( realpath "${sources[$target]}" ):${target}" ) ;;
                dir) nsjail+=( --mount dir:"$target":tmpfs: ) ;; # nsjail does not have a dir type
                symlink) nsjail+=( --symlink "${sources[$target]}:${target}" ) ;;
                *) abort "Unsupported mount type for nsjail: ${targets[$target]}" $invalidArgs ;;
            esac
        fi
    done < <( printf '%s\0' "${!targets[@]}" | sort -z )

    for name in "${!environment[@]}" ; do
        if [[ ${args[nsjail]:-} ]] ; then
            seccomp+=( --env "$name=${environment[$name]}" )
        else
            bwrap+=( --setenv "$name" "${environment[$name]}" )
        fi
    done

    unset -f add-if-exists add-mount add-env linearize
}

function source-env { # 1: spec
    local path=$1 prefix= suffix= ; case $path in
        '!'*) path=${path:1} ; suffix=' || { echo '"$( printf '%q' "--env file »$path« missing" )"' >&2 ; exit '$missingFile' ; }' ;;
        '?'*) path=${path:1} ; prefix='[ -e '"$( printf '%q' "$path" )"' ] && ' ;;
        '#'*) path=${path:1} ;& # fallthrough
        *) prefix='[ -e '"$( printf '%q' "$path" )"' ] && ' ; suffix=' || echo '"$( printf '%q' "--env file »$path« missing" )"' >&2 ' ;;
    esac
    printf %s%s%s "$prefix" '. '"$( printf '%q' "$path" )" "$suffix"
}


## Argument fallbacks

if [[ ${args[trace]:-} ]] ; then declare -p args argv ; set -x ; fi
if [[ ${args[dry-run]:-} ]] ; then
    if [[ ! -v args[host-net] ]] ; then args[host-net]=1 ; fi
    if [[ ! ${args[host-net]:-} ]] ; then abort "»--dry-run« does not work with »--host-net« explicitly disabled." ; fi
fi
case ${args[on-missing]:-} in
    abort|'!'|'') args[on-missing]=abort ;;
    warn|'#') args[on-missing]=warn ;;
    ignore|'?') args[on-missing]=ignore ;;
    *) abort "Invalid value for --on-missing: ${args[on-missing]:-}" $invalidArgs ;;
esac
if [[ ${#argv[@]} == 0 ]] ; then
    if [[ ! -v args[tty] ]] ; then args[tty]=1 ; fi
    if [[ ${args[env]:-} ]] ; then
        #rcDir=$( mktemp -p $tmp -d rcfile.XXXXXXXXXX )
        #printf '%s\n' '[ -n "$PS1" ] && [ -e ~/.bashrc ] && source ~/.bashrc' 'shopt -u expand_aliases' "$( source-env "${args[env]}" )" 'shopt -s expand_aliases' >$rcDir/wrapper
        #add-mount --ro-bind $rcDir /tmp/${rcDir##*/}/wrapper
        #add-mount --ro-bind ${args[env]} /tmp/${rcDir##*/}/env
        #argv=( "$SHELL" --rcfile /tmp/${rcDir##*/}/wrapper )
        printf '%s\n' '[ -n "$PS1" ] && [ -e ~/.bashrc ] && source ~/.bashrc' 'shopt -u expand_aliases' "$( source-env "${args[env]}" )" 'shopt -s expand_aliases' >$tmp/rcfile
        add-mount --ro-bind $tmp/rcfile /tmp/rcfile
        argv=( "$SHELL" --rcfile /tmp/rcfile )
        unset args[env]
    else
        argv=( "$SHELL" )
    fi
fi
pop-report-level abort args[profile] "${args[profile]:-}" ; if [[ ${args[profile]:-} && ! -e ${args[profile]:-} ]] ; then
    $report "--profile »${args[profile]}« does not exist" $missingFile 'using default value'
    unset args[profile]
fi
if [[ ! ${args[profile]:-} ]] ; then
    if [[ @{config.boundProfile:-} ]] ; then args[profile]=@{config.boundProfile}
    elif [[ -e /etc/blinders/system-profile ]] ; then args[profile]=/etc/blinders/system-profile
    elif [[ -e /run/current-system ]] ; then args[profile]=/run/current-system
    else args[profile]=/ ; fi
fi
if [[ ! -v args[nixos] ]] ; then
    { os_release=$(< ${args[profile]}/etc/os-release ) ; } &>/dev/null
    if [[ $os_release == *$'\nID=nixos\n'* || $os_release == *$'\nID_LIKE=nixos\n'* ]] ; then args[nixos]=1 ; else args[nixos]= ; fi
fi
if [[ ! -v args[strict-profile] && ${args[nixos]} ]] ; then args[strict-profile]=1 ; fi
#if [[ ! -v args[env] && ${args[strict-profile]} && ${args[nixos]} ]] ; then args[env]=/etc/set-environment ; fi
if [[ ! -v args[seccomp-default] ]] ; then args[seccomp-default]=1 ; fi
if [[ ${args[seccomp-default]:-} && ! -v args[seccomp-fallback] ]] ; then args[seccomp-fallback]="ERRNO(1)" ; fi # 1: Operation not permitted
#declare -p config_boundArgs args argv_hide argv_read_only argv_hide_glob argv_read_only_glob argv_fs argv_seccomp argv 2>/dev/null ; exit


# Lunching (and --[no-]nsjail mode)

# putting something in nsjail in bwrap mode and vice-versa has no effect
bwrap=( "@{pkgs.bubblewrap!getExe}" )
nsjail=( "@{pkgs.nsjail!getExe}" --mode e ) # ONCE vs EXECVE?
#nsjail+=( --env "BLE_DISABLED=1" ) # ble.sh does weird things that break terminal input (--tty fixes that)
if [[ ${args[trace]:-} ]] ; then nsjail+=( --verbose ) ; else nsjail+=( --quiet ) ; fi
# seccomp-related nsjail flags can be added to »seccomp« regardless of mode:
if [[ ${args[nsjail]:-} ]] ; then
    declare -n seccomp=nsjail
else
    seccomp=( "${nsjail[@]}" ) # bwrap does all this:
    seccomp+=( --keep_env --keep_caps --skip_setsid --disable_rlimits )
    seccomp+=( --disable_clone_newnet --disable_clone_newuser --disable_clone_newns --disable_clone_newpid --disable_clone_newipc --disable_clone_newuts --disable_clone_newcgroup ) # spellchecker: disable-line
    seccomp+=( --disable_proc ) # --bindmount /
fi
function launch {
    #declare -p bwrap nsjail seccomp
    rc='' # ».« instead of »source« works in more shells
    if [[ ${args[strict-profile]:-} && ${args[nixos]:-} ]] ; then rc+='. /etc/set-environment || exit ; ' ; fi
    if [[ ${args[env]:-} ]] ; then rc+="$( source-env "${args[env]}" ) ; " ; fi
    # With --new-session, we may need a new controlling terminal:
    if [[ ${args[tty]:-} ]] ; then # (note that this is purely a usability fix, not a security improvement)
        argv=( @{pkgs.util-linux}/bin/script -q /dev/null -c "$rc exec $( printf '%q ' "${argv[@]}" )" )
    elif [[ $rc ]] || ( [[ ${argv[0]} != /* ]] && [[ ${args[nsjail]:-} || ${args[seccomp-default]:-} || ${argv_seccomp:-} ]] ) ; then
        # nsjail requires the command to be an absolute path
        argv=( /bin/sh -c "$rc exec $( printf '%q ' "${argv[@]}" )" )
    fi
    if [[ ${args[nsjail]:-} ]] ; then
        cmd=( "${nsjail[@]}" -- "${argv[@]}" )
    elif [[ ${argv_seccomp:-} || ${args[seccomp-default]:-} || ${args[no-seccomp-default]:-} ]] ; then
        cmd=( "${bwrap[@]}" -- "${seccomp[@]}" -- "${argv[@]}" )
    else
        cmd=( "${bwrap[@]}" -- "${argv[@]}" )
    fi
    if [[ ${args[dry-run]:-} ]] ; then
        printf '%q ' "${cmd[@]}" ; echo
    else
        if [[ -t 0 ]]; then prepend_trap 'while read -r -t 0.1 -N 1 ; do : ; done' EXIT ; fi # A dumb terminal may inject crafted replies to ANSI escape sequence requests made from the sandbox into the host tty, so *try to* slurp those up before returning. A real solution would require escape sequence filtering outside the sandbox.
        "${cmd[@]}" # last command, but no exec
    fi
}


## Namespacing

# nsjail creates all namespaces by default
bwrap+=( --unshare-all --unshare-user --unshare-cgroup ) # (all leaves the latter two opportunistic)
if [[ ${args[host-net]:-} ]] ; then
    # otherwise, "abstract sockets" are isolated as well
    bwrap+=( --share-net ) # either allow all net or only that configured below
    nsjail+=( --disable_clone_newnet ) # spellchecker: disable-line
fi
bwrap+=( --die-with-parent ) # AI says: nsjail has that by default in execve mode, but not in once mode, and it is generally desirable to avoid orphaned containers
bwrap+=( --new-session ) # Prevent the sandbox from having access to a terminal that is owned by the calling user. (nsjail does something like similar unless disabled via --skip_setsid)
if false ; then
    seccomp+=( --keep_caps )
else
    bwrap+=( --cap-drop ALL ) # also the default, unless later options overwrite it
fi
if true ; then
    nsjail+=( --disable_rlimits )
else
    : # TODO: resource limits
fi
bwrap+=( --hostname blinders )
nsjail+=( --hostname blinders )
bwrap+=( --gid ${GROUPS[0]} )
nsjail+=( --group ${GROUPS[0]} )


## Filesystem

# minimal fs
add-mount --tmpfs /
add-mount --tmpfs /tmp
add-mount --dev /dev
if [[ ${args[nsjail]:-} ]] ; then
    : # nsjail mounts a /proc by default
    : #nsjail+=( --mount binfmt_misc:/proc/sys/fs/binfmt_misc:binfmt_misc: ) # (bwrap does this implicitly with --proc, the dir also exist with nsjail, but is not a mount point ...)
else
    add-mount --proc /proc # (nsjail does this by default)
fi

# Nix
add-mount --ro-bind /nix/store /nix/store
if [[ ${args[nix]:-} ]] ; then
    add-env NIX_REMOTE daemon
    add-mount --ro-bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
    add-mount --ro-bind /nix/var/nix/db /nix/var/nix/db
    # The daemon creates GC roots on the host with container paths as their targets. Those work only if the --out-link has the same path on the host, i.e. if it is inside --dir. There does not appear to be a general solution to this issue: https://github.com/NixOS/nix/issues/9387
fi

# minimal runtime dir skeleton
add-mount --dir /run/user/$UID # has incorrect permissions, but there are no other users in the container
add-env XDG_RUNTIME_DIR /run/user/$UID
add-mount --dir "$HOME"/.cache
add-env XDG_CACHE_HOME "$HOME"/.cache
add-mount --dir "$HOME"/.local/state
add-env XDG_STATE_HOME "$HOME"/.local/state

# Try to create a functional environment:
profile=$( realpath "${args[profile]:-}" ) || abort "--profile »${args[profile]:-}« does not exist" $missingFile
if [[ ${args[strict-profile]:-} ]] ; then
    bwrap+=( --clearenv ) # This may be insufficient (for security): https://github.com/containers/bubblewrap/issues/725
    bwrap=( "@{pkgs.coreutils}/bin/env" - "${bwrap[@]}" ) # ... but this should do the trick.
    add-env TERM "$TERM"
    [[ ! ${TERM_PROGRAM:-} ]] || add-env TERM_PROGRAM "$TERM_PROGRAM"
    add-env USER "$USER"
    add-env HOME "$HOME"
    if [[ ! ${args[nixos]:-} && -e "$profile"/etc/environment ]] ; then # seems to be the most standard place for system-wide environment variables
        while IFS= read -r -d '' line ; do # this should be fairly close to how PAM has been parsing this file for the last 25+ years: https://github.com/linux-pam/linux-pam/blob/master/modules/pam_env/pam_env.c
            line=${line%%#*} # remove comments
            while [[ $line == *[\'\"] ]]; do line=${line%?}; done # bash regexes are somewhat limited
            s="'" ; d='"' ; if [[ ! $line =~ ^([a-zA-Z_]+)=[$s$d]*(.*)[$s$d]*$ ]] ; then continue ; fi
            add-env "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        done < "$profile"/etc/environment
    fi

    if [[ ${args[nixos]:-} ]] ; then
        add-mount     --ro-bind "$( readlink "$profile"/etc )" /etc
        add-if-exists --symlink "$( readlink "$profile"/sw/bin/sh )" /bin/sh
        add-mount     --symlink "$profile" /run/current-system
    else # no warnings, the user chose to use (only) this:
        add-if-exists --ro-bind "$profile"/etc /etc # TODO: not a fan of exposing this much ...
        add-if-exists --ro-bind "$profile"/bin /bin
        add-if-exists --ro-bind "$profile"/lib /lib
        add-if-exists --ro-bind "$profile"/lib64 /lib64
        add-if-exists --ro-bind "$profile"/usr /usr
    fi

    function write-to-etc { # 1: name, 2: contents
        local name=$1 contents=$2
        target=/etc/"$name"
        if [[ -L "$profile"/etc/"$name" ]] ; then
            target=$( readlink "$profile"/etc/"$name" ) # Trying to completely resolve the link on the host would not be correct. Readlink may do an incomplete resolve, but at least it is well defined.
        elif [[ ! -e "$profile"/etc/"$name" ]] ; then
            warn "Can't overwrite /etc/$name in the sandbox: ${args[profile]:-}/etc/$name does not exist as symlink or file" ; return 1
        fi
        printf %s "$contents" >$tmp/etc/"$name"
        add-mount --ro-bind $tmp/etc/"$name" $target
    }

    if [[ ! ${args[host-net]:-} ]] ; then
        write-to-etc resolv.conf "nameserver 10.0.2.3"$'\n' || true
    fi
    write-to-etc passwd "$USER:x:$UID:${GROUPS[0]}::$HOME:/run/current-system/sw/bin/bash"$'\n' || true
    write-to-etc group "${GROUP:-$( id -ng )}:x:${GROUPS[0]}:"$'\n'"nogroup:x:65534:"$'\n' || true

else # generally inherit from the host, but overwrite with some things from the profile if they exist there
    seccomp+=( --keep_env )
    getent passwd "$USER" 2>/dev/null >$tmp/passwd
    add-mount --ro-bind $tmp/passwd /etc/passwd
    getent group "${GROUPS[0]}" 2>/dev/null >$tmp/group
    add-mount --ro-bind $tmp/group /etc/group
    if [[ ${args[host-net]:-} ]] ; then
        add-if-exists --ro-bind "$profile"/etc/resolv.conf /etc/resolv.conf ||
        add-if-exists --ro-bind /etc/resolv.conf /etc/resolv.conf ||
        warn "No resolv.conf found to bind into container, DNS resolution may fail"
    else # NATed networking
        echo "nameserver 10.0.2.3" >$tmp/resolv.conf
        add-mount --ro-bind $tmp/resolv.conf /etc/resolv.conf
    fi

    add-if-exists --ro-bind "$profile"/etc/bashrc /etc/bashrc ||
    add-if-exists --ro-bind /etc/bashrc /etc/bashrc
    add-if-exists --ro-bind "$profile"/etc/profile /etc/profile ||
    add-if-exists --ro-bind /etc/profile /etc/profile
    [[ ! ${args[nixos]:-} ]] || add-mount --symlink "$profile" /run/current-system
    add-if-exists --ro-bind "$profile"/etc/profiles/per-user/"$USER" /etc/profiles/per-user/"$USER" ||
    add-if-exists --ro-bind /etc/profiles/per-user/"$USER" /etc/profiles/per-user/"$USER"

    add-if-exists --ro-bind "$profile"/etc/ssl /etc/ssl ||
    add-if-exists --ro-bind /etc/ssl /etc/ssl ||
    warn "No SSL certificates found to bind into container, TLS connections may fail"
    if [[ ${args[nixos]:-} ]] ; then # NixOS has fonts linked in /etc, other OSes have them in /usr
        add-if-exists --ro-bind "$profile"/etc/fonts /etc/fonts ||
        add-if-exists --ro-bind /etc/fonts /etc/fonts ||
        warn "No fonts found to bind into container, some applications may fail to start or render text"
    fi

    if [[ ${args[nixos]:-} ]] ; then
        add-if-exists --symlink "$( readlink "$profile"/sw/bin/sh )" /bin/sh
        add-if-exists --symlink "$( readlink /lib64/ld-linux-x86-64.so.2 )" /lib64/ld-linux-x86-64.so.2
    else
        add-if-exists --ro-bind "$profile"/bin /bin ||
        warn "No /bin found to bind into container, many applications may fail to start"
        add-if-exists --ro-bind "$profile"/lib /lib ||
        warn "No /lib found to bind into container, many applications may fail to start"
        add-if-exists --ro-bind "$profile"/lib64 /lib64 ||
        warn "No /lib64 found to bind into container, many applications may fail to start"
        add-if-exists --ro-bind "$profile"/usr /usr || # " /usr should be shareable between various FHS-compliant hosts" (https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch04.html#purpose18)
        warn "No /usr found to bind into container, many applications may fail to start"
    fi
fi


## Desktop Options

if [[ ${args[wayland]:-} ]] ; then
    if [[ ! $WAYLAND_DISPLAY ]] ; then abort "Wayland display not set in environment" $missingFile ; fi
    if [[ ! -e /run/user/$UID/$WAYLAND_DISPLAY ]] ; then abort "Wayland display socket not found at /run/user/$UID/$WAYLAND_DISPLAY" $missingFile ; fi
    add-mount --ro-bind /run/user/$UID/$WAYLAND_DISPLAY /run/user/$UID/$WAYLAND_DISPLAY
    add-env WAYLAND_DISPLAY "$WAYLAND_DISPLAY"
    # Safer alternative: https://github.com/igo95862/bubblejail/issues/118#issuecomment-2469502666
    if [[ ! ${args[strict-profile]:-} && ${args[nixos]:-} ]] ; then # NixOS has fonts linked in /etc, other OSes have them in /usr
        add-if-exists --ro-bind "$profile"/etc/fonts /etc/fonts ||
        add-if-exists --ro-bind /etc/fonts /etc/fonts ||
        { warn "No fonts found to bind into container, some applications may fail to start or render text" ; }
    fi
fi

if [[ ${args[dbus]:-} ]] ; then
    if [[ ! $DBUS_SESSION_BUS_ADDRESS ]] ; then abort "D-Bus session bus address not set in environment" $missingFile ; fi
    if [[ $DBUS_SESSION_BUS_ADDRESS != unix:path=/run/user/$UID/* ]] ; then abort "D-Bus session bus address does not appear to be a unix socket in /run/user/$UID" $missingFile ; fi
    busPath=${DBUS_SESSION_BUS_ADDRESS#unix:path=}
    if [[ ! -e $busPath ]] ; then abort "D-Bus session bus socket not found at $busPath" $missingFile ; fi
    add-mount --ro-bind "$busPath" "$busPath"
    add-env DBUS_SESSION_BUS_ADDRESS unix:path="$busPath"
fi

if [[ ${args[gpu]:-} ]] ; then
    add-mount --dev-bind /dev/dri /dev/dri
    add-if-exists --dev-bind /dev/kfd /dev/kfd # for AMD GPU compute
    # TODO: NVIDIA?
fi


## Shared Directory

dir=${args[dir]:-.}
if [[ ! -d $dir ]] ; then abort "Specified --dir »$dir« does not exist or is not a directory" $missingFile ; fi
if [[ $dir != /* ]] ; then
    dir=$( realpath -s -m "${dir%/}" ) || exit
    if [[ $dir != "$HOME"/* && $dir != "${TMPDIR:-/tmp}"/* ]] ; then abort "${args[dir]:+Specified }--dir »${args[dir]:-.}« is neither an absolute path nor under »$HOME« or »${TMPDIR:-/tmp}«" $invalidArgs ; fi
else
    dir=$( realpath -s -m "${dir%/}" ) || exit
fi
if [[ $dir != "$PWD" && $PWD != "$dir"/* ]] ; then
    bwrap+=( --chdir "$dir" ) ; seccomp+=( --cwd "$dir" )
else
    bwrap+=( --chdir "$PWD" ) ; seccomp+=( --cwd "$PWD" )
fi
declare -A dirChildren

for type in only hide read-only ; do # --*-glob
    declare -a argv_${type//-/_} ; declare -n argv_type=argv_${type//-/_} ; declare -n argv_type_glob=argv_${type//-/_}_glob
    if [[ ! ${args[$type-glob]:-} ]] ; then continue ; fi
    for glob in "${argv_type_glob[@]}" ; do
        pop-report-level warn glob "$glob" ; mode=${BASH_REMATCH[1]:-#}
        eval "$(
            shopt -s nullglob dotglob globstar ; cd "$dir"
            declare -a expanded ; expanded=( $glob ) ; declare -p expanded
        )" ; argv_type+=( "${expanded[@]/#/$mode}" )
        if [[ ${#expanded[@]} == 0 ]] ; then
            $report "--$type-glob pattern »$glob« did not match any files in $dir" $missingFile ignoring
        else
            args[$type]=1
        fi
    done
done

if [[ ${args[only-git]:-} ]] ; then for _ in _ ; do
    pop-report-level warn args[only-git] "${args[only-git]}" ; mode=${BASH_REMATCH[1]:-#}
    if [[ ! ${args[only-git]} =~ ^[0-9]+$ ]] ; then $report "Value for --only-git should be a number, got: »${args[only-git]}«" $invalidArgs 'ignoring --only-git' ; break ; fi
    if [[ ! -d $dir/.git ]] ; then $report "Directory »$dir« does not appear to be a Git repository." $invalidArgs 'ignoring --only-git' ; break ; fi
    paths=$( cd "$dir" && git ls-files -z | while IFS= read -r -d '' path ; do
        if [[ $path == *$'\n'* ]] ; then warn "Newline in file path: »$path«" $invalidArgs 'skipping' ; continue ; fi
        IFS=/ read -ra path <<<$path ; if [[ ${args[only-git]} != 0 ]] ; then path=( "${path[@]:0:${args[only-git]}}" ) ; fi
        printf '%s/' "${path[@]}" ; echo
    done | LC_ALL=C @{pkgs.coreutils}/bin/sort | @{pkgs.coreutils}/bin/uniq ) ; readarray -t paths <<<$paths
    declare -a argv_only ; paths=( "${paths[@]/#/$mode}" ) ; argv_only+=( "${paths[@]%/}" ) ; args[only]=1
done ; fi

function ensure-source { # 1: path, 2: reason, 3: report
    local path=$1 reason=$2 report=$3 asDir= ; [[ $path == */ ]] && asDir=1
    absPath=$( cd "$dir" && realpath -s -m "$path" ) || exit
    [[ -e $absPath ]] || $report "$reason »$path« does not exist." $missingFile 'skipping' "$absPath"${asDir:+/} || return 1
}

declare -A uniq=( ) ; for path in "${argv_hide[@]}" ; do
    pop-report-level create path "$path"
    if [[ $path == /* ]] ; then $report "Path to --hide »$path« is absolute. It should be relative (to --dir)." $invalidArgs 'skipping' ; continue ; fi
    ensure-source "$path" "Path to --hide" $report || continue
    type=$( stat -c %F -- "$absPath" ) || exit ; case "$type" in
        'directory') type=dir ;; 'regular file'|'regular empty file') type=reg ;; 'block special file') type=blk ;; 'character special file') type=chr ;; 'fifo') type=fifo ;; 'socket') type=sock ;;
        *) $report "Unsupported file type for --hide: $path => $type." $invalidArgs 'skipping' ; continue ;;
    esac
    if [[ ${uniq[$absPath]:-} ]] ; then continue ; fi ; uniq[$absPath]=1
    dirChildren[$absPath]=1
    add-mount --ro-bind /run/systemd/inaccessible/$type "$absPath"
done

declare -A uniq=( ) ; for path in "${argv_read_only[@]}" ; do
    pop-report-level create path "$path"
    if [[ $path == /* ]] ; then $report "Path to make --read-only »$path« is absolute. It should be relative (to --dir)." $invalidArgs 'skipping' ; continue ; fi
    ensure-source "$path" "Path to make --read-only" $report || continue
    if [[ -L $absPath ]] ; then $report "Unsupported file type for --read-only: $path => symlink." $invalidArgs 'skipping' ; continue ; fi
    if [[ ${uniq[$absPath]:-} ]] ; then continue ; fi ; uniq[$absPath]=1
    if [[ ${dirChildren[$absPath]:-} ]] ; then $report "Path »$path« is specified as both --hide and --read-only." $invalidArgs 'former takes precedence' ; continue ; fi ; dirChildren[$absPath]=1
    add-mount --ro-bind "$absPath" "$absPath"
done

if [[ ! ${args[only]:-} ]] ; then
    add-mount --bind "$dir" "$dir"
else
    add-mount --tmpfs "$dir"
    declare -A uniq=( ) ; for path in "${argv_only[@]}" ; do
        pop-report-level create path "$path"
        if [[ $path == /* ]] ; then $report "--only path »$path« is absolute. It should be relative (to --dir)." $invalidArgs 'skipping' ; continue ; fi
        ensure-source "$path" "--only path" $report || continue
        if [[ ${uniq[$absPath]:-} ]] ; then continue ; fi ; uniq[$absPath]=1
        if [[ ${dirChildren[$absPath]:-} ]] ; then $report "Path »$path« is specified as both --hide or --read-only and --only."  $invalidArgs 'former takes precedence' ; continue ; fi ; dirChildren[$absPath]=1
        if [[ -L $absPath ]] ; then
            add-mount --symlink "$( readlink "$absPath" )" "$absPath"
        else
            add-mount --bind "$absPath" "$absPath"
        fi
    done
fi

for fs in "${argv_fs[@]}" ; do
    type=${fs%%:*} ; rest=${fs/$type:/} ; if [[ $rest == *:* ]] ; then source=${rest%%:*} target=${rest#*:} ; else source= target=$rest ; fi
    pop-report-level create source "$source"
    if [[ $source == '~/'* ]] ; then source=$HOME${source/#\~} ; fi
    if [[ $target == '~/'* ]] ; then target=$HOME${target/#\~} ; fi
    if [[ $target != /* ]] ; then target=$dir/$target ; fi # target not existing is fine
    if [[ ${targets[$target]:-} ]] ; then
        warn "Target path for »--fs=$fs« is already used. Overwriting."
        unset targets[$target] ; unset missing[$target] ; unset sources[$target] ; unset duplicates[$target]
    fi
    case $type in
        bind|ro-bind|dev-bind)
            if [[ $report != ${args[on-missing]} ]] ; then
                ensure-source "$source" "Source path for --fs" $report && source=$absPath || continue
            else source=$( cd "$dir" && realpath -s -m "$source" ) || exit ; fi ;& # fallthrough
        symlink) add-mount --"$type" "$source" "$target" ;;
        tmpfs|proc|dev|dir) add-mount --"$type" "$target" ;;
        none) : ;; # to remove default mounts
        *) abort "Unsupported --fs type: $type" $invalidArgs ;;
    esac
done

if [[ ${args[var]:-} ]] ; then for var in "${argv_var[@]}" ; do
    name=${var%%=*} ; value=${var#*=}
    if [[ $var == "$name" && ${!name@a} == *x* ]] ; then value=${!name} ; fi
    add-env "$name" "$value"
done ; fi


## Syscall Filtering

if [[ ${argv_seccomp:-} || ${args[seccomp-default]:-} || ${args[no-seccomp-default]:-} ]] ; then
    seccomp_string=''
    for filter in "${argv_seccomp[@]}" ; do
        seccomp_string+="$filter"$'\n'
    done
    if [[ ${args[seccomp-default]:-} ]] ; then
        # spellchecker: disable
        # We use Docker's / Moby's default syscall whitelist, but without capability-depended exceptions:
        # https://github.com/moby/profiles/blob/5bb2d1ae8ba7639a0dbb0965df8ce337f190251c/seccomp/default.json
        unconditional=( accept accept4 access adjtimex alarm bind brk capget capset chdir chmod chown chown32 clock_adjtime clock_adjtime64 clock_getres clock_getres_time64 clock_gettime clock_gettime64 clock_nanosleep clock_nanosleep_time64 close close_range connect copy_file_range creat dup dup2 dup3 epoll_create epoll_create1 epoll_ctl epoll_ctl_old epoll_pwait epoll_pwait2 epoll_wait epoll_wait_old eventfd eventfd2 execve execveat exit exit_group faccessat faccessat2 fadvise64 fadvise64_64 fallocate fanotify_mark fchdir fchmod fchmodat fchmodat2 fchown fchown32 fchownat fcntl fcntl64 fdatasync fgetxattr flistxattr flock fork fremovexattr fsetxattr fstat fstat64 fstatat64 fstatfs fstatfs64 fsync ftruncate ftruncate64 futex futex_requeue futex_time64 futex_wait futex_waitv futex_wake futimesat getcpu getcwd getdents getdents64 getegid getegid32 geteuid geteuid32 getgid getgid32 getgroups getgroups32 getitimer getpeername getpgid getpgrp getpid getppid getpriority getrandom getresgid getresgid32 getresuid getresuid32 getrlimit get_robust_list getrusage getsid getsockname getsockopt get_thread_area gettid gettimeofday getuid getuid32 getxattr getxattrat inotify_add_watch inotify_init inotify_init1 inotify_rm_watch io_cancel ioctl io_destroy io_getevents io_pgetevents io_pgetevents_time64 ioprio_get ioprio_set io_setup io_submit ipc kill landlock_add_rule landlock_create_ruleset landlock_restrict_self lchown lchown32 lgetxattr link linkat listen listmount listxattr listxattrat llistxattr llseek lremovexattr lseek lsetxattr lstat lstat64 madvise map_shadow_stack membarrier memfd_create memfd_secret mincore mkdir mkdirat mknod mknodat mlock mlock2 mlockall mmap mmap2 mprotect mq_getsetattr mq_notify mq_open mq_timedreceive mq_timedreceive_time64 mq_timedsend mq_timedsend_time64 mq_unlink mremap mseal msgctl msgget msgrcv msgsnd msync munlock munlockall munmap name_to_handle_at nanosleep newfstatat newselect open openat openat2 pause pidfd_open pidfd_send_signal pipe pipe2 pkey_alloc pkey_free pkey_mprotect poll ppoll ppoll_time64 prctl pread64 preadv preadv2 prlimit64 process_mrelease pselect6 pselect6_time64 pwrite64 pwritev pwritev2 read readahead readlink readlinkat readv recv recvfrom recvmmsg recvmmsg_time64 recvmsg remap_file_pages removexattr removexattrat rename renameat renameat2 restart_syscall riscv_hwprobe rmdir rseq rt_sigaction rt_sigpending rt_sigprocmask rt_sigqueueinfo rt_sigreturn rt_sigsuspend rt_sigtimedwait rt_sigtimedwait_time64 rt_tgsigqueueinfo sched_getaffinity sched_getattr sched_getparam sched_get_priority_max sched_get_priority_min sched_getscheduler sched_rr_get_interval sched_rr_get_interval_time64 sched_setaffinity sched_setattr sched_setparam sched_setscheduler sched_yield seccomp select semctl semget semop semtimedop semtimedop_time64 send sendfile sendfile64 sendmmsg sendmsg sendto setfsgid setfsgid32 setfsuid setfsuid32 setgid setgid32 setgroups setgroups32 setitimer setpgid setpriority setregid setregid32 setresgid setresgid32 setresuid setresuid32 setreuid setreuid32 setrlimit set_robust_list setsid setsockopt set_thread_area set_tid_address setuid setuid32 setxattr setxattrat shmat shmctl shmdt shmget shutdown sigaltstack signalfd signalfd4 sigprocmask sigreturn socketcall socketpair splice stat stat64 statfs statfs64 statmount statx symlink symlinkat sync sync_file_range syncfs sysinfo tee tgkill time timer_create timer_delete timer_getoverrun timer_gettime timer_gettime64 timer_settime timer_settime64 timerfd_create timerfd_gettime timerfd_gettime64 timerfd_settime timerfd_settime64 times tkill truncate truncate64 ugetrlimit umask uname unlink unlinkat uretprobe utime utimensat utimensat_time64 utimes vfork vmsplice wait4 waitid waitpid write writev process_vm_readv process_vm_writev ptrace )
        if false ; then # This prints out all the syscalls that nsjail/kafel does not understand (on the currrent architecture?), with the syscall number, if one exists (on the currrent architecture). Enable this if and run: nix run .#blinders -- --seccomp-default
            declare -A unknown=( )
            for syscall in "${unconditional_known[@]}" ; do
                seccomp_string="ALLOW { $syscall } DEFAULT ALLOW"
                if ! "${seccomp[@]}" --bindmount / --seccomp_string "$seccomp_string" --quiet -- $( realpath $( which sh ) ) -c true &>/dev/null ; then #
                    unknown[$syscall]=$( "@{pkgs.audit}"/bin/ausyscall --exact $syscall 2>/dev/null | cut -f 2 || echo x )
                fi
            done ; declare -p unknown ; exit 0
        fi # result on x86_64:
        declare -A unknown=( [chown32]=x [clock_adjtime64]=x [clock_getres_time64]=x [clock_gettime64]=x [clock_nanosleep_time64]=x [close_range]=436 [epoll_pwait2]=441 [faccessat2]=439 [fadvise64_64]=x [fchmodat2]=452 [fchown32]=x [fcntl64]=x [fstat]=5 [fstat64]=x [fstatat64]=x [fstatfs64]=x [ftruncate64]=x [futex_requeue]=456 [futex_time64]=x [futex_wait]=455 [futex_waitv]=449 [futex_wake]=454 [getegid32]=x [geteuid32]=x [getgid32]=x [getgroups32]=x [getresgid32]=x [getresuid32]=x [getuid32]=x [getxattrat]=464 [io_pgetevents]=333 [io_pgetevents_time64]=x [ipc]=x [landlock_add_rule]=445 [landlock_create_ruleset]=444 [landlock_restrict_self]=446 [lchown32]=x [listmount]=458 [listxattrat]=465 [llseek]=x [lstat]=6 [lstat64]=x [map_shadow_stack]=453 [memfd_secret]=447 [mmap2]=x [mq_timedreceive_time64]=x [mq_timedsend_time64]=x [mseal]=462 [newselect]=x [openat2]=437 [pidfd_open]=434 [pidfd_send_signal]=424 [pkey_alloc]=330 [pkey_free]=331 [pkey_mprotect]=329 [ppoll_time64]=x [process_mrelease]=448 [pselect6_time64]=x [recv]=x [recvmmsg_time64]=x [removexattrat]=466 [riscv_hwprobe]=x [rseq]=334 [rt_sigtimedwait_time64]=x [sched_rr_get_interval_time64]=x [semtimedop_time64]=x [send]=x [sendfile]=40 [setfsgid32]=x [setfsuid32]=x [setgid32]=x [setgroups32]=x [setregid32]=x [setresgid32]=x [setresuid32]=x [setreuid32]=x [setuid32]=x [setxattrat]=463 [sigprocmask]=x [sigreturn]=x [socketcall]=x [stat]=4 [stat64]=x [statfs64]=x [statmount]=457 [statx]=332 [timer_gettime64]=x [timer_settime64]=x [timerfd_gettime64]=x [timerfd_settime64]=x [truncate64]=x [ugetrlimit]=x [uname]=63 [uretprobe]=x [utimensat_time64]=x [waitpid]=x )
        defines='' ; allow+='ALLOW { '
        for syscall in "${unconditional[@]}" ; do
            if [[ ${unknown[$syscall]:-} ]] ; then
                if [[ ${unknown[$syscall]} == x ]] ; then
                    continue # can't fix that
                else
                    defines+="#define $syscall ${unknown[$syscall]}"$'\n'
                fi
            fi
            allow+="$syscall, "
        done
        defines+=$'#define AF_VSOCK 40\n#define PER_LINUX 0x0000\n#define PER_LINUX32 0x0008\n#define UNAME26 0x1000\n'
        allow+='socket(domain) { domain != AF_VSOCK }, personality(persona) { persona == PER_LINUX || persona == PER_LINUX32 || persona == UNAME26 || persona == (PER_LINUX32 | UNAME26) || persona == 0xffffffff }, '
        arch=$( uname -m ) # kafel has an »ON« syntax as conditional for architectures, but that does not work. Do that manually:
        # This forbids clone with the creation of new namespaces. Not sure that is important in this scenario.
        if [[ $arch != s390* ]] ; then # CLONE_NEWNS|CLONE_NEWUTS|CLONE_NEWIPC|CLONE_NEWPID|CLONE_NEWNET|CLONE_NEWUSER|CLONE_NEWCGROUP == 0x7e0000000
            allow+='clone(arg0, arg1) { (arg0 & 0x7e0000000) == 0 }, '
        else
            allow+='clone(arg0, arg1) { (arg1 & 0x7e0000000) == 0 }, '
        fi
        if [[ $arch == ppc64le ]] ; then allow+='sync_file_range2, swapcontext, ' ; fi
        if [[ $arch == arm* || $arch == aarch64 ]] ; then allow+='arm_fadvise64_64, arm_sync_file_range, sync_file_range2, breakpoint, cacheflush, set_tls, ' ; fi
        if [[ $arch == x86_64 || $arch == amd64 || $arch == x32 ]] ; then allow+='arch_prctl, ' ; fi
        if [[ $arch == x86_64 || $arch == amd64 || $arch == x32 || $arch == i*86 ]] ; then allow+='modify_ldt, ' ; fi
        if [[ $arch == s390* ]] ; then allow+='s390_pci_mmio_read, s390_pci_mmio_write, s390_runtime_instr, ' ; fi
        if [[ $arch == riscv64 ]] ; then allow+='riscv_flush_icache, ' ; fi
        seccomp_string=${allow%, }'}'$'\n'
        if [[ ${args[seccomp-fallback]:-} != ALLOW || ${args[seccomp-fallback]:-} != LOG ]] ; then
            defines+='#define clone3 435'$'\n'
            seccomp_string+='ERRNO(38) { clone3 }'$'\n' # Operation not supported (the idea bing that the application/library falls back to using clone/clone2)
        fi
        seccomp_string=$defines$seccomp_string
        # spellchecker: enable
    fi
    if [[ ${args[seccomp-fallback]:-} ]] ; then
        seccomp_string+="DEFAULT ${args[seccomp-fallback]:-} "
    fi
    seccomp+=( --seccomp_string "${seccomp_string% }" )
fi


## Network Filtering

if [[ ${args[host-net]:-} || ${args[dry-run]:-} ]] ; then
    linearize || exit ; launch ; exit
fi

if [[ ${args[nsjail]:-} ]] ; then
    abort "»--nsjail« is only implemented with »--host-net«." $invalidArgs
    # nsjail directly supports »pasta« (which does basically the same as »slirp4netns«), but the firewall rules would need to be set up.
fi

# »firejail« has a »--netfilter« option, but that is currently ignored by firejail on NixOS (https://github.com/netblue30/firejail/issues/6637).

# So we combine bwrap with slirp4netns.
# Need to: start but pause bwrap, attach slirp4netns to the bwrap child, configure iptables, resume the bwrap child

exec {json_status_fd}<> <(:)
bwrap+=( --json-status-fd $json_status_fd )
exec {bwrap_wait_fd}<> <(:)
bwrap+=( --block-fd $bwrap_wait_fd )
linearize || exit ; launch & bwrap_pid=$!
prepend_trap '[[ ! $bwrap_pid ]] || kill $bwrap_pid 2>/dev/null || true' EXIT

# Read JSON status line by line until we find child-pid
child_pid= ; while read -r line <&${json_status_fd}; do
    child_pid=$( echo "$line" | jq -r '."child-pid"' 2>/dev/null )
    # { "child-pid", "cgroup-namespace", "ipc-namespace", "mnt-namespace", "net-namespace", "pid-namespace", "uts-namespace" }
    if [[ $child_pid && $child_pid != "null" ]]; then break ; fi
done

beLoud=/dev/null ; if [[ ${args[trace]:-} ]] ; then beLoud=/dev/stdout ; fi
slirp4netns=(
    "@{pkgs.slirp4netns!getExe}"
    --configure # configure interfaces in the sandbox (10.0.2.100/24, with gateway/host at 10.0.2.2, and DNS at 10.0.2.3)
    --mtu=65520 # why?
    --disable-host-loopback # do not allow the NAT on the host to connect to localhost (other than for DNS)
    $child_pid tap0
)
"${slirp4netns[@]}" &>$beLoud & slirp_pid=$!
prepend_trap 'kill $slirp_pid 2>/dev/null || true' EXIT

ip4rules="
*filter
:OUTPUT ACCEPT [0:0]
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -d 10.0.2.0/24 -j ACCEPT $( : allow access to slirp4netns gateway and DNS )
# localhost / 127.0.0.0/8 is private
-A OUTPUT -d 10.0.0.0/8 -j REJECT
-A OUTPUT -d 172.16.0.0/12 -j REJECT
-A OUTPUT -d 192.168.0.0/16 -j REJECT
-A OUTPUT -d 169.254.0.0/16 -j REJECT
-A OUTPUT -d 100.64.0.0/10 -j REJECT $( : carrier-grade NAT )
COMMIT
"
if [[ ! ${args[ipv6]:-} ]] ; then ip6rules="
*filter
:OUTPUT DROP [0:0]
COMMIT
" ; else ip6rules="
*filter
:OUTPUT ACCEPT [0:0]
-A OUTPUT -d ::1/128 -j REJECT
-A OUTPUT -d fc00::/7 -j REJECT
-A OUTPUT -d fe80::/10 -j REJECT
COMMIT
" ; fi # could also reject everything but 2000::/3 (publicly routable IPv6)

"@{pkgs.util-linux}"/bin/nsenter -t $child_pid -U --preserve-credentials -n bash -c "
    @{pkgs.iptables}/bin/iptables-restore  ${args[trace]+-v} <<<$( printf '%q' "$ip4rules" ) || exit
    @{pkgs.iptables}/bin/ip6tables-restore ${args[trace]+-v} <<<$( printf '%q' "$ip6rules" ) || exit
" || exit

echo go >&${bwrap_wait_fd} # let bwrap continue
wait $bwrap_pid ; exit_code=$? ; bwrap_pid= ; exit $exit_code
