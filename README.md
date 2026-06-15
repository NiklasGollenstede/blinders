
# Blinders -- Convenient Sandboxing for Untrusted Code/Agents with Nix

When running untrusted code from the internet, two of the main challenges are to limit information leakage and to prevent potentially malicious code from being stored where it may be executed without confinement.
These problems have been addressed by browsers for decades, but have seen less attention and practical solutions when it comes to arbitrary program execution, for example for code development projects.
In spite of repeated, high-profile incidents, communities rely on techniques to make it less likely to obtain malicious code (reviews/scanning, vulnerability databases) more so than to limit the impact of its execution.
With the advent of AI generated code, this is no longer viable, as new code is generated much more rapidly, and work flows and tooling us much less understood than before.

Tooling for strong sandboxing that prevents information leakage exists, but is hard to set up correctly for each specific use case, or does little to prevent targeted stored attacks [^git].
Blinders address these issues by providing a sandboxing interface that is restrictive by default, but has intuitive options to loosen or further tighten restrictions.
Using Nix for "system" dependencies, it can limit information exposure to a single (project) directory, it prevents local network access, and it can prevent (writing) access to local files not tracked by Git.
Blinders can be used as system-wide ad-hoc tool (on NixOS), or it can be integrated into existing Nix Flake projects with as little as a single line of code [^nix].


## Repo / Usage

See [`./pkgs/scripts/blinders.sh`](./pkgs/scripts/blinders.sh) or `nix run github:NiklasGollenstede/blinders -- --help` for an extensive description of the `blinders` command, its CLI, intended use and usage examples.

See [`./template/flake.nix`](./template/flake.nix) for a complete example integrating blinders into a Nix Flake project (and [`./lib/blinders.nix#mkBlindersInitApp`](./lib/blinders.nix) for the full description of integration options).

See [`./modules/programs/blinders.nix`](./modules/programs/blinders.nix) for how to make blinders available as a system-wide tool on NixOS.


## Out-of-scope

### Resource limits

Blinders currently does not apply any resource limits on the sandbox.
Blinders is mostly meant for interactive use, where the user would notice excessive local resource usage, but more importantly, as far as AI agents are concerned, their risk of (costly) runaway resource consumption is in the token consumption, which a local sandbox tool cannot influence anyway.

### Internet Filtering

Some AI tools try to restrict what (publicly available) content agents can load from the internet (e.g. via domain based filtering), but that is mostly because current AI is not good at distinguishing between prompt instructions and the data that the prompt should operate on (i.e, prompt injection is a thing, data gets treated as code).
As that "code" could still only operate within the sandbox, this is explicitly not a concern that blinders addresses.
Blinders instead prevents the sandbox from accessing the local, non-public, network (localhost and private IPv4 ranges).

---

[^git]: For example with dev containers, one either makes and pushes commits from inside the container, for which either SSH keys or the agent socket need to be available in the container, or makes and pushes commits outside the container, but would then probably have allowed the editor in the container to write to the .git directory (to stage files and such), which allows the sandbox to install arbitrary git hooks that are executed on actions outside the sandbox.

[^nix]: `(lib.blinders.mkBlindersInitApp { inherit inputs; devShell = "my-dev-shell"; })`
