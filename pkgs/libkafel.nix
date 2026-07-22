dirname: inputs: let
    lib = inputs.self.lib.__internal__;
in {
    stdenv,
    fetchFromGitHub,
    flex, bison,
}: stdenv.mkDerivation (finalAttrs: {
    pname = "libkafel";
    version = "2026-04-04";

    src = fetchFromGitHub {
        owner = "google"; repo = "kafel";
        rev = "18f207428068a50f2c35706c5d0b21f53c769016";
        sha256 = "sha256-KK4bSKLaDtVbGAGti4rYKI094RMLpOdu4YtBeHhxlc8=";
    };

    nativeBuildInputs = [ flex bison ];

    enableParallelBuilding = true;

    installPhase = ''
        mkdir -p $out/lib $out/include
        cp libkafel.so* $out/lib/
        cp libkafel.a $out/lib/
        cp include/kafel.h $out/include/
    '';

    meta = {
        description = "Language and library for specifying syscall filtering policies";
        homepage = "https://github.com/google/kafel";
        license = lib.licenses.asl20;
        maintainers = [ ];
        platforms = lib.platforms.linux;
    };
})

# Created mostly by DeepSeek V4 Flash in VSCode Copilot with prompt: "Complete the nix expression to package the kafel library (https://github.com/google/kafel/). Use the last commit date as version."
