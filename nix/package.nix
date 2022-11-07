{ autoconf
, automake
, fetchYarnDeps
, jq
, lib
, libtool
, mkYarnPackage
, moreutils
, nodejs
, nodejs-16_x
, nodejs-slim-16_x
, pkg-config
, python3
, removeReferencesTo
, runCommand
, sqlite
, stdenv
}:
let
  filterPred = path: type: !(builtins.elem (baseNameOf path) [ "flake.nix" "flake.lock" "nix" ]);
in
mkYarnPackage rec {
  name = "actual-server";
  packageJSON = ../package.json;

  # workaround for https://github.com/NixOS/nix/pull/5163#issuecomment-925064325
  # we were recompiling on all flake.nix changes, even ones that don't matter
  src = lib.cleanSourceWith { filter = filterPred; src = ../.; };
  yarnLock = ../yarn.lock;

  dontStrip = true;

  dontPatchShebangs = true;
  extraBuildInputs = [ removeReferencesTo ];
  disallowedReferences = [ nodejs-16_x ];

  distPhase = ''
    # redundant symlink that introduces a 150mb runtime dep
    # on the actual-server-modules derivation
    rm $out/libexec/actual-sync/deps/actual-sync/node_modules

    # .. and replace it with a symlink referencing the output package so the
    # server can find its web files, since that was broken also
    ln -s $out/libexec/actual-sync/node_modules $out/libexec/actual-sync/deps/actual-sync/node_modules


    sed -i '1c #!${nodejs-slim-16_x}/bin/node' "$(readlink -f "$out/bin/actual-server")"

    find "$out" -type f -executable -exec remove-references-to -t ${nodejs-16_x} '{}' ';'
  '';

  pkgConfig = import ./horrors-beyond-comprehension.nix {
    inherit nodejs sqlite pkg-config autoconf automake libtool python3 jq moreutils;
  };
}
