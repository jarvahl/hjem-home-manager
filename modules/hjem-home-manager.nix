{ inputs, ... }:
let
  hjemModule =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      hmLib = lib.extend (_: _: { hm = inputs.home-manager.lib.hm; });

      types = hmLib.types;
      mkOpt = type: default: hmLib.mkOption { inherit type default; };
      anythingAttrs = types.attrsOf types.anything;
      emptyAnythingAttrs = mkOpt anythingAttrs { };

      fileType = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              enable = mkOpt types.bool true;
              executable = mkOpt (types.nullOr types.bool) null;
              force = mkOpt types.bool false;
              source = mkOpt (types.nullOr types.path) null;
              target = mkOpt types.str name;
              text = mkOpt (types.nullOr types.lines) null;
            };
          }
        )
      );

      compatOptionsModule =
        { config, lib, ... }:
        {
          options = {
            assertions = mkOpt (types.listOf types.unspecified) [ ];
            warnings = mkOpt (types.listOf types.str) [ ];

            home = {
              activation = mkOpt (hmLib.hm.types.dagOf types.lines) { };
              file = mkOpt fileType { };
              homeDirectory = mkOpt types.str null;
              packages = mkOpt (types.listOf types.package) [ ];
              sessionVariables = emptyAnythingAttrs;
              stateVersion = mkOpt types.str "25.11";
              username = mkOpt types.str null;
            };

            launchd.agents = emptyAnythingAttrs;

            programs.home-manager.enable = mkOpt types.bool false;

            systemd.user =
              lib.genAttrs [
                "paths"
                "services"
                "sockets"
                "targets"
                "timers"
              ] (_: emptyAnythingAttrs)
              // {
                systemctlPath = mkOpt types.str null;
              };

            xdg = {
              cacheFile = mkOpt fileType { };
              cacheHome = mkOpt types.str "${config.home.homeDirectory}/.cache";
              configFile = mkOpt fileType { };
              configHome = mkOpt types.str "${config.home.homeDirectory}/.config";
              dataFile = mkOpt fileType { };
              dataHome = mkOpt types.str "${config.home.homeDirectory}/.local/share";
              stateFile = mkOpt fileType { };
              stateHome = mkOpt types.str "${config.home.homeDirectory}/.local/state";
            };
          };
        };

      hmModules = osConfig.hjem.homeManagerModules or [ ];

      defaults = {
        home.homeDirectory = lib.mkDefault config.directory;
        home.username = lib.mkDefault config.user;
        systemd.user.systemctlPath = lib.mkDefault "${pkgs.systemd}/bin/systemctl";
      };

      specialArgs = {
        inherit pkgs;
        osConfig = osConfig;
      };

      compatOptionPaths = [
        [ "_module" ]
        [ "assertions" ]
        [
          "launchd"
          "agents"
        ]
        [
          "programs"
          "home-manager"
          "enable"
        ]
        [ "warnings" ]
      ]
      ++
        map
          (name: [
            "home"
            name
          ])
          [
            "activation"
            "file"
            "homeDirectory"
            "packages"
            "sessionVariables"
            "stateVersion"
            "username"
          ]
      ++
        map
          (name: [
            "systemd"
            "user"
            name
          ])
          [
            "paths"
            "services"
            "sockets"
            "systemctlPath"
            "targets"
            "timers"
          ]
      ++
        map
          (name: [
            "xdg"
            name
          ])
          [
            "cacheFile"
            "cacheHome"
            "configFile"
            "configHome"
            "dataFile"
            "dataHome"
            "stateFile"
            "stateHome"
          ];

      removeOptionPath =
        path: attrs:
        if path == [ ] then
          attrs
        else
          let
            name = builtins.head path;
            rest = builtins.tail path;
          in
          if !(builtins.hasAttr name attrs) then
            attrs
          else if rest == [ ] then
            removeAttrs attrs [ name ]
          else
            attrs // { ${name} = removeOptionPath rest attrs.${name}; };

      optionPaths =
        prefix: attrs:
        lib.concatLists (
          lib.mapAttrsToList (
            name: value:
            if builtins.isAttrs value && value ? _type && value._type == "option" then
              [ (prefix ++ [ name ]) ]
            else if builtins.isAttrs value then
              optionPaths (prefix ++ [ name ]) value
            else
              [ ]
          ) attrs
        );

      configForOptions =
        options:
        lib.foldl' (
          acc: path:
          if lib.hasAttrByPath path config then
            lib.recursiveUpdate acc (lib.setAttrByPath path (lib.getAttrFromPath path config))
          else
            acc
        ) { } (optionPaths [ ] options);

      hmOptions = hmLib.evalModules {
        modules = [
          compatOptionsModule
          defaults
        ]
        ++ hmModules;
        inherit specialArgs;
      };

      passthroughOptions = lib.foldl' (
        acc: path: removeOptionPath path acc
      ) hmOptions.options compatOptionPaths;
      passthroughConfig = configForOptions passthroughOptions;

      hm = hmLib.evalModules {
        modules = [
          compatOptionsModule
          defaults
          { config = passthroughConfig; }
        ]
        ++ hmModules;
        inherit specialArgs;
      };

      prefixFiles =
        prefix:
        lib.mapAttrs' (
          name: file:
          let
            target = "${prefix}/${file.target or name}";
          in
          {
            name = target;
            value = file // {
              inherit target;
            };
          }
        );

      hmFiles =
        hm.config.home.file
        // prefixFiles ".cache" hm.config.xdg.cacheFile
        // prefixFiles ".config" hm.config.xdg.configFile
        // prefixFiles ".local/share" hm.config.xdg.dataFile
        // prefixFiles ".local/state" hm.config.xdg.stateFile;

      fileSource =
        name: file:
        if file.source != null then
          file.source
        else
          pkgs.writeTextFile {
            name = "home-manager-${lib.replaceStrings [ "/" ] [ "-" ] name}";
            text = file.text or "";
            executable = file.executable == true;
          };

      mapFile = name: file: {
        source = fileSource name file;
        clobber = file.force or false;
      };

      mapUnit =
        unit:
        let
          Unit = unit.Unit or { };
          Install = unit.Install or { };
        in
        {
          description = Unit.Description or null;
          requiredBy = Install.RequiredBy or [ ];
          unitConfig = removeAttrs Unit [ "Description" ];
          wantedBy = Install.WantedBy or [ ];
        }
        // lib.optionalAttrs (unit ? Path) { pathConfig = unit.Path; }
        // lib.optionalAttrs (unit ? Service) { serviceConfig = unit.Service; }
        // lib.optionalAttrs (unit ? Socket) { socketConfig = unit.Socket; }
        // lib.optionalAttrs (unit ? Timer) { timerConfig = unit.Timer; };

      activationPrelude = ''
        set -euo pipefail

        export HOME=${lib.escapeShellArg hm.config.home.homeDirectory}
        export USER=${lib.escapeShellArg hm.config.home.username}
        cd "$HOME"

        hmDriverVersion=1
        VERBOSE_ARG=""
        run() { "$@"; }
        verboseEcho() { echo "$@"; }
        warnEcho() { echo "warning: $*" >&2; }
        errorEcho() { echo "error: $*" >&2; }
        _i() { printf "$@"; printf '\n'; }
        _iNote() { printf "$@"; printf '\n'; }
        _iError() { printf "$@" >&2; printf '\n' >&2; }
      '';

      skippedActivationNodes = [
        "checkLinkTargets"
        "installPackages"
        "linkGeneration"
        "reloadSystemd"
        "writeBoundary"
      ];

      activationServiceName = name: "home-manager-${name}";

      activationServices = lib.mapAttrs' (name: node: {
        name = activationServiceName name;
        value = {
          description = "Home Manager activation ${name}";
          wantedBy = [ "default.target" ];
          after = map activationServiceName (
            builtins.filter (n: !(builtins.elem n skippedActivationNodes)) (node.after or [ ])
          );
          before = map activationServiceName (
            builtins.filter (n: !(builtins.elem n skippedActivationNodes)) (node.before or [ ])
          );
          serviceConfig.Type = "oneshot";
          script = activationPrelude + "\n" + (node.data or node.text or "");
        };
      }) (removeAttrs hm.config.home.activation skippedActivationNodes);

      mappedSystemdUnits = lib.genAttrs [
        "paths"
        "services"
        "sockets"
        "timers"
      ] (kind: lib.mapAttrs (_: mapUnit) hm.config.systemd.user.${kind});
    in
    {
      options = passthroughOptions;

      config = {
        assertions = hm.config.assertions ++ [
          {
            assertion = hm.config.launchd.agents == { };
            message = "hjem-home-manager does not support launchd agents.";
          }
          {
            assertion = !hm.config.programs.home-manager.enable;
            message = "hjem-home-manager does not support programs.home-manager.enable.";
          }
        ];

        files = lib.mapAttrs mapFile (lib.filterAttrs (_: file: file.enable) hmFiles);
        packages = hm.config.home.packages;

        systemd = mappedSystemdUnits // {
          services = mappedSystemdUnits.services // activationServices;
          targets = lib.mapAttrs (_: mapUnit) hm.config.systemd.user.targets;
        };
      };
    };
  nixosModule =
    { lib, ... }:
    {
      options.hjem.homeManagerModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "Home Manager modules evaluated for every Hjem user.";
      };

      config.hjem.extraModules = [ hjemModule ];
    };
in
{
  flake.hjemModules.default = hjemModule;
  flake.nixosModules.default = nixosModule;
}
