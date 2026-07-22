dirname: inputs: let
    lib = inputs.self.lib.__internal__;
in {
    stdenv, libkafel,
}: stdenv.mkDerivation (finalAttrs: {
    name = "kafel-cli"; # unversioned

    src = ./kafel-cli.c;

    nativeBuildInputs = [ libkafel ];

    unpackPhase = ''
        runHook preUnpack
        runHook postUnpack
    '';
    buildPhase = ''
        runHook preBuild
        gcc -std=gnu11 -O2 -I${libkafel}/include -o kafel-cli ${finalAttrs.src} ${libkafel}/lib/libkafel.a
        runHook postBuild
    '';
    installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp kafel-cli $out/bin/
        runHook postInstall
    '';

    meta = {
        description = "CLI tool to compile kafel seccomp policies to raw binary cBPF (for bwrap --seccomp)";
        mainProgram = "kafel-cli";
        license = lib.licenses.asl20;
        platforms = lib.platforms.linux;
    };
})

