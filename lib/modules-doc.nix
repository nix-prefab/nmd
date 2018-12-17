{ pkgs, lib }:

{
  # Modules to include in documentation.
  modules

  # File paths to module roots.
, moduleRootPaths

  # A function taking the relative module path to an URL where the
  # module can be viewed.
  #
  # Example:
  #     mkModuleUrl = path: "https://myproject.foo/${path}"
, mkModuleUrl

  # The "typical" channel name for this module set. This will be used
  # to present a friendly path to the module defining an option.
  #
  # Example:
  #     channelName = "myproject"
, channelName
}:

with lib;

let

  evaluatedModules = evalModules { inherit modules; };

  optionsDocs =
    (map cleanUpOption
    (sort moduleDocCompare
    (filter (opt: opt.visible && !opt.internal)
    (optionAttrSetToDocList
    (evaluatedModules.options)))));

  moduleDocCompare = a: b: compareLists builtins.lessThan a.loc b.loc;

  cleanUpOption = opt:
    let
      applyOnAttr = n: f:
        optionalAttrs (hasAttr n opt) { ${n} = f opt.${n}; };
    in
      opt
      // applyOnAttr "declarations" (map mkDeclaration)
      // applyOnAttr "example" substFunction
      // applyOnAttr "default" substFunction
      // applyOnAttr "type" substFunction
      // applyOnAttr "relatedPackages" mkRelatedPackages;

  mkDeclaration = decl: rec {
    path = stripModulePathPrefixes decl;
    url = mkModuleUrl path;
    channelPath = "${channelName}/${path}";
  };

  # We need to strip references to /nix/store/* from options,
  # including any `extraSources` if some modules came from elsewhere,
  # or else the build will fail.
  #
  # E.g. if some `options` came from modules in ${pkgs.customModules}/nix,
  # you'd need to include `extraSources = [ pkgs.customModules ]`
  stripModulePathPrefixes =
    let
      prefixes = map (p: "${toString p}/") moduleRootPaths;
    in
      modulePath: fold removePrefix modulePath prefixes;

  # Replace functions by the string <function>
  substFunction = x:
    if builtins.isAttrs x then mapAttrs (name: substFunction) x
    else if builtins.isList x then map substFunction x
    else if isFunction x then "<function>"
    else x;

  # Generate some meta data for a list of packages. This is what
  # `relatedPackages` option of `mkOption` lib/options.nix influences.
  #
  # Each element of `relatedPackages` can be either
  # - a string:   that will be interpreted as an attribute name from `pkgs`,
  # - a list:     that will be interpreted as an attribute path from `pkgs`,
  # - an attrset: that can specify `name`, `path`, `package`, `comment`
  #   (either of `name`, `path` is required, the rest are optional).
  mkRelatedPackages =
    let
      unpack = p:
        if isString p then { name = p; }
        else if isList p then { path = p; }
        else p;

      repack = args:
        let
          name = args.name or (concatStringsSep "." args.path);
          path = args.path or [ args.name ];
          pkg = args.package or (
            let
              bail = throw "Invalid package attribute path '${toString path}'";
            in
              attrByPath path bail pkgs
          );
        in
          {
            attrName = "pkgs.${name}";
            packageName = pkg.meta.name;
            available = pkg.meta.available;
          }
          // optionalAttrs (pkg.meta ? description) {
            inherit (pkg.meta) description;
          }
          // optionalAttrs (pkg.meta ? longDescription) {
            inherit (pkg.meta) longDescription;
          }
          // optionalAttrs (args ? comment) {
            inherit (args) comment;
          };
    in
      map (p: repack (unpack p));

in

{
  inherit optionsDocs;

  json = import ./modules-json.nix {
    inherit pkgs lib optionsDocs;
  };

  docBook = import ./modules-docbook.nix {
    inherit pkgs lib optionsDocs mkModuleUrl channelName;
  };
}