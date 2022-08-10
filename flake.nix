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

                traceId = t: builtins.trace t t;
                filterPred = path: type: !(builtins.elem (baseNameOf path) [ "flake.nix" "flake.lock" ]);
              in
                {
                  actual-server = prev.mkYarnPackage rec {
                    name = "actual-server";
                    packageJSON = ./package.json;

                    # workaround for https://github.com/NixOS/nix/pull/5163#issuecomment-925064325
                    # we were recompiling on all flake.nix changes, even ones that don't matter
                    src = prev.lib.cleanSourceWith { filter = filterPred; src = ./.; };
                    yarnLock = ./yarn.lock;

                    # we don't need to have the full-fat nodejs with python
                    # (for gyp) and so on except to build. It is undesirably
                    # referenced by binaries in dependencies, and also would be
                    # patchShebang'd into bin/actual-server as well if we
                    # didn't disable that and do it manually.
                    dontPatchShebangs = true;
                    extraBuildInputs = [ final.removeReferencesTo ];
                    disallowedReferences = [ final.nodejs-16_x ];

                    distPhase = ''
                      # manually patchelf actual-server
                      sed -i '1c #!${final.nodejs-slim-16_x}/bin/node' "$(readlink -f "$out/bin/actual-server")"

                      # redundant symlink that introduces a 150mb runtime dep
                      # on the actual-server-modules derivation
                      rm $out/libexec/actual-sync/deps/actual-sync/node_modules
                      # .. and replace it with a relative symlink inside the
                      # package so the server can find its web files
                      ln -s $out/libexec/actual-sync/node_modules $out/libexec/actual-sync/deps/actual-sync/node_modules

                      # break unnecessary dependency binaries
                      find "$out" -type f -exec remove-references-to -t ${final.nodejs-16_x} '{}' +
                    '';

                    pkgConfig = {
                      better-sqlite3 = {
                        postInstall = ''
                          export CPPFLAGS="-I${nodejs}/include/node"
                          npm run install --build-from-source -j$NIX_BUILD_CORES --nodedir=${nodejs}/include/node

                          # throw away some size by getting rid of all the
                          # intermediate build artifacts
                          mv build/Release/better_sqlite3.node .
                          rm -rf build/
                          mkdir build
                          mv better_sqlite3.node build
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

                          # node-pre-gyp is broken in nix for "god knows why",
                          # so just patch in what it does.
                          jq '.scripts.install = "node-gyp rebuild -- -Dmodule_name=bcrypt_lib -Dmodule_path=./lib/binding/napi-v3"' package.json | sponge package.json
                          npm run install --build-from-source -j$NIX_BUILD_CORES --nodedir=${nodejs}/include/node

                          # build/ has a bunch of stuff we don't need, some
                          # with undesirable references
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
            dockerImage = let
              # tailscale usage: see https://tailscale.com/kb/1132/flydotio/
              startScript = pkgs.writeShellScript "start.sh" ''
                if [[ ! -z "$TAILSCALE_AUTHKEY" ]]; then
                  ${pkgs.tailscale}/bin/tailscaled --state=/data/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
                  ${pkgs.tailscale}/bin/tailscale up --authkey=$TAILSCALE_AUTHKEY --hostname=actual
                fi
                ${pkgs.actual-server}/bin/actual-server
              '';

            in
              pkgs.dockerTools.buildLayeredImage {
                name = "actual-server";
                tag = "latest";

                contents = pkgs.buildEnv {
                  name = "image-root";
                  paths = [ pkgs.bash pkgs.coreutils ];
                  pathsToLink = [ "/bin" ];
                };

                extraCommands = ''
                  mkdir -p var/run/tailscale
                  mkdir data
                '';
                config = {
                  Entrypoint = [ "${pkgs.tini}/bin/tini" "-g" "-s" "--" startScript ];
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
