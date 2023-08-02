{ autoconf
, automake
, fetchYarnDeps
, jq
, lib
, libtool
, mkYarnPackage
, moreutils
, nodejs
, nodejs-slim
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
  disallowedReferences = [ nodejs ];

  distPhase = ''
    # redundant symlink that introduces a 150mb runtime dep
    # on the actual-server-modules derivation
    rm $out/libexec/actual-sync/deps/actual-sync/node_modules

    # .. and replace it with a symlink referencing the output package so the
    # server can find its web files, since that was broken also
    ln -s $out/libexec/actual-sync/node_modules $out/libexec/actual-sync/deps/actual-sync/node_modules


    sed -i '1c #!${nodejs-slim}/bin/node' "$(readlink -f "$out/bin/actual-server")"

    find "$out" -type f -executable -exec remove-references-to -t ${nodejs} '{}' ';'
  '';

  pkgConfig = {
    better-sqlite3 = {
      postInstall = ''
        export CPPFLAGS="-I${nodejs}/include/node"
        patch -p1 -i ${./patches/0001-Badly-patch-in-shared-lib-linking.patch}
        npm run install --build-from-source -j$NIX_BUILD_CORES --nodedir=${nodejs}/include/node --sqlite3=${sqlite.dev}/include --sqlite3-systemlib=true

        # throw away some size by getting rid of all the
        # intermediate build artifacts
        mv build/Release/better_sqlite3.node .
        rm -rf build/
        mkdir build
        mv better_sqlite3.node build
      '';
      nativeBuildInputs = [
        libtool
        autoconf
        automake
        pkg-config
        python3
      ];
      buildInputs = [
        sqlite
      ];
    };
    bcrypt = {
      postInstall = ''
        export CPPFLAGS="-I${nodejs}/include/node"

        # node-pre-gyp is broken in nix for "god knows why",
        # so just patch in what it does.
        jq '.scripts.install = "node-gyp rebuild -- -Dmodule_name=bcrypt_lib -Dmodule_path=./lib/binding/napi-v3"' package.json | sponge package.json
        npm run install --build-from-source -j$NIX_BUILD_CORES --nodedir=${nodejs}/include/node

        # build/ has a bunch of stuff we don't need, some
        # with undesirable references
        rm -rf build/

        rm -rf node-addon-api/*.mk
      '';
      nativeBuildInputs = [
        libtool
        autoconf
        automake
        python3
        jq
        moreutils
      ];
    };
  };
}
