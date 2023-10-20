# Fixed-Output Derivation version of flake-compat

This is a fork of [flake-compat](https://github.com/edolstra/flake-compat) which uses fetchers from `nixpkgs` to create fixed-output derivations.

This flake compat fork therefore only works if you have access to a copy of nixpkgs.

## Usage

To use, add the following to your `flake.nix`:

```nix
inputs.flake-compat = {
  flake = false;
  url = "github.com:hraban/flake-compat/fixed-output";
};
```

Afterwards, create a `default.nix` file containing the following:

```nix
# Alternatively, you could lock nixpkgs in your flake.lock and fetch that, if you preferred
{ pkgs ? import <nixpkgs> {} }:
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  sourceInfo = lock.nodes.flake-compat.locked;
  flake-compat = fetchTarball {
    url = "https://github.com/${sourceInfo.owner}/${sourceInfo.repo}/archive/${sourceInfo.rev}.tar.gz";
    sha256 = sourceInfo.narHash;
  };
  flake = pkgs.callPackage flake-compat { src = ./.; }
in
flake.defaultNix
```

If you would like a `shell.nix` file, create one containing the above, replacing `defaultNix` with `shellNix`.

## Rationale

This fork was created for [`cl-nix-lite`](https://github.com/hraban/cl-nix-lite), because of the large amount of inputs, most of them being unnecessary for actual end users of the scope.

See:

- [Nix: what are fixed-output derivations and why use them?](https://bmcgee.ie/posts/2023/02/nix-what-are-fixed-output-derivations-and-why-use-them/)
- [Nixpkgs Fetchers](https://ryantm.github.io/nixpkgs/builders/fetchers/)
- [Nix Discourse thread on Fixed-Output derivations](https://discourse.nixos.org/t/using-fixed-output-paths-for-a-derivation/6338/4)
- [Nix Discourse thread on the different kinds of fetchers](https://discourse.nixos.org/t/why-is-fetchtarball-not-mentioned-in-chapter-11-fetchers-of-the-nixpkgs-manual/15319/2)
