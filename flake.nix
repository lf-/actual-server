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
            final: prev:
              {
                actual-server = final.callPackage ./nix/package.nix { };
              }
          );
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
          dockerImage =
            let
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
                  "5006/tcp" = { };
                };
                Env = [
                  "NODE_ENV=production"
                ];
                WorkingDir = "/data";
                Volumes = {
                  "/data" = { };
                };
              };
            };
        in
        {
          inherit overlay dockerImage;
          packages = { inherit (pkgs) actual-server; };
          defaultPackage = pkgs.actual-server;
          checks = self.packages;
          inherit pkgs;
          devShell = with pkgs; mkShell {
            buildInputs = [
              yarn
            ];
          };
        }
      )
    );
}
