{ nodejs
, sqlite
, pkg-config
, autoconf
, automake
, libtool
, python3
, jq
, moreutils
}:
{
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
}
