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

  pkgConfig = import ./horrors-beyond-comprehension.nix {
    inherit nodejs sqlite pkg-config autoconf automake libtool python3 jq moreutils;
  };
}
