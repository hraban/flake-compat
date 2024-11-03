# Compatibility function to allow flakes to be used by
# non-flake-enabled Nix versions. Given a source tree containing a
# 'flake.nix' and 'flake.lock' file, it fetches the flake inputs and
# calls the flake's 'outputs' function. It then returns an attrset
# containing 'defaultNix' (to be used in 'default.nix'), 'shellNix'
# (to be used in 'shell.nix').

{
  src
, system ? builtins.currentSystem or "unknown-system"
# TODO: extract this from the flake itself? No, wait, you can’t do that because
# the flake might not actually provide nixpkgs... maybe make it optional?
, pkgs
}:

let

  lockFilePath = src + "/flake.lock";

  lockFile = builtins.fromJSON (builtins.readFile lockFilePath);

  fetchTree =
    info:
    if info.type == "github" then
      { outPath = pkgs.fetchFromGitHub ({
          inherit (info) owner repo rev;
          hash = info.narHash;
        } // pkgs.lib.optionalAttrs (info ? host) {
          githubBase = info.host;
        });
        inherit (info) rev narHash lastModified;
        shortRev = builtins.substring 0 7 info.rev;
        lastModifiedDate = formatSecondsSinceEpoch info.lastModified;
      }
    else if info.type == "git" then
      { outPath =
          pkgs.fetchgit
            ({
              name = "source";
              url = info.url;
              sha256 = info.narHash;
             }
             // (
               if info ? rev then { inherit (info) rev; }
               else if info ? ref then { rev = info.ref; }
               else {})
             // (if info ? submodules then { inherit (info) submodules; } else {})
            );
        lastModified = info.lastModified;
        lastModifiedDate = formatSecondsSinceEpoch info.lastModified;
        narHash = info.narHash;
      } // (if info ? rev then {
        rev = info.rev;
        shortRev = builtins.substring 0 7 info.rev;
      } else {
      })
    else if info.type == "path" then
      { outPath = builtins.path { path = info.path; };
        narHash = info.narHash;
      }
    else if info.type == "tarball" then
      { outPath =
          pkgs.fetchzip
            ({
              inherit (info) url;
              name = "source";
            }
             // (if info ? narHash then { sha256 = info.narHash; } else {})
            );
      }
    else if info.type == "gitlab" then
      { inherit (info) rev narHash lastModified;
        outPath =
          pkgs.fetchFromGitLab ({
            inherit (info) repo owner rev;
            hash = info.narHash;
          } // pkgs.lib.optionalAttrs (info ? host) {
            domain = info.host;
          });
        shortRev = builtins.substring 0 7 info.rev;
      }
    else if info.type == "sourcehut" then
      { inherit (info) rev narHash lastModified;
        outPath =
          pkgs.fetchFromSourcehut ({
            inherit (info) owner repo rev;
            hash = info.narHash;
          } // pkgs.lib.optionalAttrs (info ? host) {
            domain = info.host;
          });
        shortRev = builtins.substring 0 7 info.rev;
      }
    else
      throw "flake input has unsupported input type '${info.type}'";

  callFlake4 = flakeSrc: locks:
    let
      flake = import (flakeSrc + "/flake.nix");

      inputs = builtins.mapAttrs (n: v:
        if v.flake or true
        then callFlake4 (fetchTree (v.locked // v.info)) v.inputs
        else fetchTree (v.locked // v.info)) locks;

      outputs = flakeSrc // (flake.outputs (inputs // {self = outputs;}));
    in
      assert flake.edition == 201909;
      outputs;

  callLocklessFlake = flakeSrc:
    let
      flake = import (flakeSrc + "/flake.nix");
      outputs = flakeSrc // (flake.outputs ({ self = outputs; }));
    in outputs;

  rootSrc = let
    # Try to clean the source tree by using fetchGit, if this source
    # tree is a valid git repository.
    tryFetchGit = src:
      if isGit && !isShallow
      then
        let res = builtins.fetchGit src;
        in if res.rev == "0000000000000000000000000000000000000000" then removeAttrs res ["rev" "shortRev"]  else res
      else {
        outPath =
          # Massage `src` into a store path.
          if builtins.isPath src
          then
            if dirOf (toString src) == builtins.storeDir
            then
              # If it's already a store path, don't copy it again.
              builtins.storePath src
            else
              "${src}"
          else
            src;
      };
    # NB git worktrees have a file for .git, so we don't check the type of .git
    isGit = builtins.pathExists (src + "/.git");
    isShallow = builtins.pathExists (src + "/.git/shallow");

  in
    { lastModified = 0; lastModifiedDate = formatSecondsSinceEpoch 0; }
      // (if src ? outPath then src else tryFetchGit src);

  # Format number of seconds in the Unix epoch as %Y%m%d%H%M%S.
  formatSecondsSinceEpoch = t:
    let
      rem = x: y: x - x / y * y;
      days = t / 86400;
      secondsInDay = rem t 86400;
      hours = secondsInDay / 3600;
      minutes = (rem secondsInDay 3600) / 60;
      seconds = rem t 60;

      # Courtesy of https://stackoverflow.com/a/32158604.
      z = days + 719468;
      era = (if z >= 0 then z else z - 146096) / 146097;
      doe = z - era * 146097;
      yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
      y = yoe + era * 400;
      doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
      mp = (5 * doy + 2) / 153;
      d = doy - (153 * mp + 2) / 5 + 1;
      m = mp + (if mp < 10 then 3 else -9);
      y' = y + (if m <= 2 then 1 else 0);

      pad = s: if builtins.stringLength s < 2 then "0" + s else s;
    in "${toString y'}${pad (toString m)}${pad (toString d)}${pad (toString hours)}${pad (toString minutes)}${pad (toString seconds)}";

  allNodes =
    builtins.mapAttrs
      (key: node:
        let
          sourceInfo =
            if key == lockFile.root
            then rootSrc
            else fetchTree (node.info or {} // removeAttrs node.locked ["dir"]);

          subdir = if key == lockFile.root then "" else node.locked.dir or "";

          outPath = sourceInfo + ((if subdir == "" then "" else "/") + subdir);

          flake = import (outPath + "/flake.nix");

          inputs = builtins.mapAttrs
            (inputName: inputSpec: allNodes.${resolveInput inputSpec})
            (node.inputs or {});

          # Resolve a input spec into a node name. An input spec is
          # either a node name, or a 'follows' path from the root
          # node.
          resolveInput = inputSpec:
              if builtins.isList inputSpec
              then getInputByPath lockFile.root inputSpec
              else inputSpec;

          # Follow an input path (e.g. ["dwarffs" "nixpkgs"]) from the
          # root node, returning the final node.
          getInputByPath = nodeName: path:
            if path == []
            then nodeName
            else
              getInputByPath
                # Since this could be a 'follows' input, call resolveInput.
                (resolveInput lockFile.nodes.${nodeName}.inputs.${builtins.head path})
                (builtins.tail path);

          outputs = flake.outputs (inputs // { self = result; });

          result =
            outputs
            # We add the sourceInfo attribute for its metadata, as they are
            # relevant metadata for the flake. However, the outPath of the
            # sourceInfo does not necessarily match the outPath of the flake,
            # as the flake may be in a subdirectory of a source.
            # This is shadowed in the next //
            // sourceInfo
            // {
              # This shadows the sourceInfo.outPath
              inherit outPath;

              inherit inputs; inherit outputs; inherit sourceInfo; _type = "flake";
            };

        in
          if node.flake or true then
            assert builtins.isFunction flake.outputs;
            result
          else
            sourceInfo
      )
      lockFile.nodes;

  result =
    if !(builtins.pathExists lockFilePath)
    then callLocklessFlake rootSrc
    else if lockFile.version == 4
    then callFlake4 rootSrc (lockFile.inputs)
    else if lockFile.version >= 5 && lockFile.version <= 7
    then allNodes.${lockFile.root}
    else throw "lock file '${lockFilePath}' has unsupported version ${toString lockFile.version}";

in
  rec {
    defaultNix =
      (builtins.removeAttrs result ["__functor"])
      // (if result ? defaultPackage.${system} then { default = result.defaultPackage.${system}; } else {})
      // (if result ? packages.${system}.default then { default = result.packages.${system}.default; } else {});

    shellNix =
      defaultNix
      // (if result ? devShell.${system} then { default = result.devShell.${system}; } else {})
      // (if result ? devShells.${system}.default then { default = result.devShells.${system}.default; } else {});
  }
