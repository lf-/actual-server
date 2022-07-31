{
  description = "Actual Budget server";
  inputs = {
    nixpkgs.url = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils, nixpkgs }:
    (
      flake-utils.lib.eachDefaultSystem (
        system:
          let
            overlay = (
              final: prev: let
                inherit (final) runCommand nodejs python3 fetchYarnDeps stdenv;

              in
                {
                  actual-server = prev.mkYarnPackage rec {
                    name = "actual-server";
                    packageJSON = ./package.json;
                    src = ./.;
                    yarnLock = ./yarn.lock;

                    # we don't need to have the full-fat nodejs with python
                    # (for gyp) and so on to execute, which is referenced by
                    # binaries from dependencies, and also will be
                    # patchShebang'd into bin/actual-server as well (which we
                    # will manually do instead)
                    dontPatchShebangs = true;
                    extraBuildInputs = [ final.removeReferencesTo ];
                    disallowedReferences = [ final.nodejs-16_x ];

                    distPhase = ''
                      # manually patchelf actual-server
                      sed -i '1c #!${final.nodejs-slim-16_x}/bin/node' "$(readlink -f "$out/bin/actual-server")"

                      # redundant symlink that introduces a 150mb runtime dep
                      # on the actual-server-modules derivation
                      rm $out/libexec/actual-sync/deps/actual-sync/node_modules

                      # break unnecessary dependency binaries
                      find "$out" -type f -exec remove-references-to -t ${final.nodejs-16_x} '{}' +
                    '';

                    pkgConfig = {
                      better-sqlite3 = {
                        postInstall = ''
                          export CPPFLAGS="-I${nodejs}/include/node"
                          npm run install --build-from-source -j$NIX_BUILD_CORES --nodedir=${nodejs}/include/node

                          rm -rf build/
                        '';
                        nativeBuildInputs = [
                          final.libtool
                          final.autoconf
                          final.automake
                          final.python3
                        ];
                      };
                      bcrypt = {
                        postInstall = ''
                          export CPPFLAGS="-I${nodejs}/include/node"

                          # node-pre-gyp is broken for "god knows why", so just
                          # patch in what it does.
                          jq '.scripts.install = "node-gyp rebuild -- -Dmodule_name=bcrypt_lib -Dmodule_path=./lib/binding/napi-v3"' package.json | sponge package.json
                          npm run install --build-from-source -j$NIX_BUILD_CORES --nodedir=${nodejs}/include/node

                          rm -rf build/
                        '';
                        nativeBuildInputs = [
                          final.libtool
                          final.autoconf
                          final.automake
                          final.python3
                          final.jq
                          final.moreutils
                        ];
                      };
                    };
                  };
                }
            );
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ overlay ];
            };
            dockerImage = pkgs.dockerTools.buildImage {
              name = "actual-server";
              config = {
                Cmd = [ "${pkgs.actual-server}/bin/actual-server" ];
                ExposedPorts = {
                  "5006/tcp" = {};
                };
                Env = [
                  "NODE_ENV=production"
                ];
                WorkingDir = "/data";
                Volumes = {
                  "/data" = {};
                };
              };
            };
          in
            {
              inherit overlay dockerImage;
              packages = { inherit (pkgs) actual-server; };
              defaultPackage = pkgs.actual-server;
              checks = self.packages;
              devShell = with pkgs; mkShell {
                buildInputs = [
                  yarn
                ];
              };
            }
      )
    );
}
