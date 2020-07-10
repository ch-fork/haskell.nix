# This overlay helps accessing common executable components.
# Typically we want to make these available in a nix-shell
# created with shellFor.  In most cases the package name
# will be the same as the executable, but we have a
# `toolPackageName` and `packageToolName` mapping to help
# when it is not.
#
# To get a single tool:
#   haskell-nix.tool "ghc883" "cabal" "3.2.0.0"
#
# This does the same thing as:
#   (haskell-nix.hackage-package {
#     compiler-nix-name = "ghc883";
#     name = "cabal-install"
#     version = "3.2.0.0"
#   }).components.exes.cabal
#
# To get an attr set containing multiple tools:
#   haskell-nix.tools "ghc883" { cabal = "3.2.0.0"; hlint = "2.2.11"; }
#
# To add tools to a shell:
#   shellFor { tools = { cabal = "3.2.0.0"; hlint = "2.2.11"; }; }
#
# When used in shellFor the tools will be compiled with the same version
# of ghc used in the shell (the build ghc in the case of cross compilation).
#
# To get tools for use with project `p` without using shellFor:
#   p.tool "cabal" "3.2.0.0"
#   p.tools { cabal = "3.2.0.0"; hlint = "2.2.11"; }
# (the ghc version used to build it will match the one used in the project)
#
# Instead of a version string we can use an attr set containing
# arguments that will be passed to `cabalProject`.
#
# For instance to add haskell.nix modules. Use:
#   haskell-nix.tool "ghc883" "cabal" {
#      version = "3.2.0.0";
#      modules = [ ... ];
#   }
#
final: prev:
let
  inherit (final) lib;

in { haskell-nix = prev.haskell-nix // {

  # Some times the package name in hackage is not the same as tool name.
  # Tools better known by their exe name.
  toolPackageName = {
    cabal = "cabal-install";
  };

  # Packages that are better known by their package name.  We are not
  # reusing toolPackageName here as perhaps the more one package
  # will have the same exe name.
  packageToolName = {
    cabal-install = "cabal";
  };

  hackage-tool = { name, ... }@args':
    let
      args = { caller = "hackage-tool"; } // args';
    in
      (final.haskell-nix.hackage-package
        (args // { name = final.haskell-nix.toolPackageName.${name} or name; }))
          .components.exes."${final.haskell-nix.packageToolName.${name} or name}";

  tool = compiler-nix-name: name: versionOrArgs:
    let
      args' = final.haskell-nix.haskellLib.versionOrArgsToArgs versionOrArgs;
      args = { inherit compiler-nix-name; } // args';
    in
      (if final.haskell-nix.custom-tools ? "${name}"
          && final.haskell-nix.custom-tools."${name}" ? "${args.version}"
        then final.haskell-nix.custom-tools."${name}"."${args.version}"
        else final.haskell-nix.hackage-tool) (args // { inherit name; });

  tools = compiler-nix-name: lib.mapAttrs (final.haskell-nix.tool compiler-nix-name);

  # Like `tools` but allows default ghc to be specified
  toolsForGhc = ghcOverride: toolSet:
    final.haskell-nix.tools (
      lib.mapAttrs (name: versionOrArgs:
        let args = final.haskell-nix.haskellLib.versionOrArgsToArgs versionOrArgs;
        in
          # Add default ghc if not specified in the args
          (lib.optionalAttrs (!(args ? "compiler-nix-name" || args ? "ghc"))
            { inherit ghcOverride; }
          ) // args
      ) toolSet
    );

  # Tools not in hackage yet
  custom-tools = {
    ghcide.object-code = args:
        (final.haskell-nix.cabalProject (args // {
          name = "ghcide";
          src = final.fetchFromGitHub {
            owner = "mpickering";
            repo = "ghcide";
            rev = "706c59c97c25c66798815c1dc3ee6885a298918a";
            sha256 = "0d158xifwvz0y69ah98ckxakzqpz229mq7rpf2bpbmwhnpw3jmm6";
          };
          modules = [({config, ...}: {
            packages.ghcide.configureFlags = lib.optional (!final.stdenv.targetPlatform.isMusl)
                                              "--enable-executable-dynamic";
            nonReinstallablePkgs = [ "Cabal" "array" "base" "binary" "bytestring" "containers" "deepseq"
                                     "directory" "filepath" "ghc" "ghc-boot" "ghc-boot-th" "ghc-compact"
                                     "ghc-heap" "ghc-prim" "ghci" "haskeline" "hpc" "integer-gmp"
                                     "libiserv" "mtl" "parsec" "pretty" "process" "rts" "stm"
                                     "template-haskell" "terminfo" "text" "time" "transformers" "unix"
                                     "xhtml"
                                   ];
          })];
          pkg-def-extras = [
                 (hackage: {
              packages = {
                "alex" = (((hackage.alex)."3.2.5").revisions).default;
                "happy" = (((hackage.happy)."1.19.12").revisions).default;
              };
            })
          ];
        })).ghcide.components.exes.ghcide;
  };
}; }