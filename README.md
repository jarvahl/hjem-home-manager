# hjem-home-manager

Small Hjem adapter for selected Home Manager modules.

## Use

```nix
{
  imports = [ inputs.hjem-home-manager.nixosModules.default ];

  hjem.homeManagerModules = [
    # Any supported Home Manager module, e.g. sops-nix:
    inputs.sops-nix.homeManagerModules.sops
  ];
}
```

Home Manager module options are exposed under each `hjem.users.<name>`.

The flake also exposes `hjemModules.default` for manual wiring if another module declares `hjem.homeManagerModules`.

## Supported mapping

- `home.packages` -> Hjem `packages`
- `home.file` and `xdg.*File` -> Hjem files
- `systemd.user.{services,sockets,timers,paths,targets}` -> Hjem user systemd
- `home.activation` entries -> user systemd oneshot services

Unsupported features fail with assertions instead of being silently ignored.
