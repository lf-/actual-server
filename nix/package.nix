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
  filterPred = path: type: !(builtins.elem (baseNameOf path) [ "flake.nix" "flake.lock" ]);
in
mkYarnPackage rec {
  name = "actual-server";
  packageJSON = ../package.json;

  # workaround for https://github.com/NixOS/nix/pull/5163#issuecomment-925064325
  # we were recompiling on all flake.nix changes, even ones that don't matter
  src = lib.cleanSourceWith { filter = filterPred; src = ../.; };
  yarnLock = ../yarn.lock;

  dontStrip = true;

  # we don't need to have the full-fat nodejs with python
  # (for gyp) and so on except to build. It is undesirably
  # referenced by binaries in dependencies, and also would be
  # patchShebang'd into bin/actual-server as well if we
  # didn't disable that and do it manually.
  dontPatchShebangs = true;
  extraBuildInputs = [ removeReferencesTo ];
  disallowedReferences = [ nodejs-16_x ];

  distPhase = ''
    # manually patchelf actual-server
    sed -i '1c #!${nodejs-slim-16_x}/bin/node' "$(readlink -f "$out/bin/actual-server")"

    # redundant symlink that introduces a 150mb runtime dep
    # on the actual-server-modules derivation
    rm $out/libexec/actual-sync/deps/actual-sync/node_modules
    # .. and replace it with a relative symlink inside the
    # package so the server can find its web files
    ln -s $out/libexec/actual-sync/node_modules $out/libexec/actual-sync/deps/actual-sync/node_modules

    # break unnecessary dependency binaries
    find "$out" -type f -exec remove-references-to -t ${nodejs-16_x} '{}' +
  '';

  pkgConfig = import ./horrors-beyond-comprehension.nix {
    inherit nodejs sqlite pkg-config autoconf automake libtool python3 jq moreutils;
  };
}
