{ inputs, ... }:
{
  flake-file.inputs.git-hooks-nix = {
    inputs.nixpkgs.follows = "nixpkgs";
    url = "github:cachix/git-hooks.nix";
  };

  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem = {
    pre-commit = {
      check.enable = true;
      settings.hooks = {
        deadnix = {
          enable = true;
          settings.edit = true;
        };
        treefmt.enable = true;
      };
    };
  };
}
