{ ... }:
{
  perSystem = { config, pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        deadnix
        just
        mdsh
      ];

      shellHook = ''
        ${config.pre-commit.shellHook}
      '';
    };
  };
}
