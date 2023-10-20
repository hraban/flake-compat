# Fixed-Output Derivation version of flake-compat

This is a fork of [flake-compat](https://github.com/edolstra/flake-compat) which uses fetchers from `nixpkgs` to create fixed-output derivations.

This flake compat fork therefore only works if you have access to a copy of nixpkgs.

A compatibility shim to use Nix flakes with versions of Nix that don't have native flake support.

Given a source tree containing `flake.nix` and `flake.lock`, it fetches the flake inputs and calls the flake's `outputs` function. This allows you to use flake-based projects with:

- Stable Nix without `experimental-features = nix-command flakes`
- Nix versions before 2.4 (insecure, please upgrade)
- Tooling that doesn't support flakes natively

The flake-compat function returns
- `defaultNix` for use in `default.nix`,
- `shellNix` for `shell.nix`) attributes,
- `outputs` for simple access to the flake outputs.

This project was originally at `edolstra/flake-compat` and is now maintained at `NixOS/flake-compat`.

## Usage

To use, add the following to your `flake.nix`:

```nix
inputs.flake-compat = {
  url = "github:hraban/flake-compat/fixed-output";
  flake = false;
};
```

Afterwards, create a `default.nix` file containing the following:

```nix
# Alternatively, you could lock nixpkgs in your flake.lock and fetch that, if you preferred
{ pkgs ? import <nixpkgs> {} }:
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  nodeName = lock.nodes.root.inputs.flake-compat;
  sourceInfo = lock.nodes.${nodeName}.locked;
  flake-compat = fetchTarball {
    url = "https://github.com/${sourceInfo.owner}/${sourceInfo.repo}/archive/${sourceInfo.rev}.tar.gz";
    sha256 = sourceInfo.narHash;
  };
  flake = pkgs.callPackage flake-compat { src = ./.; }
in
flake.defaultNix
```

If you would like a `shell.nix` file, create one containing the above, replacing `defaultNix` with `shellNix`.

You can access any flake output via the `outputs` attribute returned by `flake-compat`, e.g.

```nix
(import ... { src = ./.; }).outputs.packages.x86_64-linux.default
```

## Contributing

Improvements are welcomed. Some tips to make that a success:

- Check the issue tracker.

- Chat in the [Nix Package Manager development](https://matrix.to/#/#nix-dev:nixos.org) matrix channel.

- We're writing a test suite, `tests.nix`.
  Science shows that PRs with tests are more likely to be merged!

- Update the documentation.

## Support the project

`flake-compat` is part of the Nix/NixOS community, which is supported by the NixOS Foundation.

Here's how you can [help out financially](https://nixos.org/donate/).

## Rationale

This fork was created for [`cl-nix-lite`](https://github.com/hraban/cl-nix-lite), because of the large amount of inputs, most of them being unnecessary for actual end users of the scope.

See:

- [Nix: what are fixed-output derivations and why use them?](https://bmcgee.ie/posts/2023/02/nix-what-are-fixed-output-derivations-and-why-use-them/)
- [Nixpkgs Fetchers](https://ryantm.github.io/nixpkgs/builders/fetchers/)
- [Nix Discourse thread on Fixed-Output derivations](https://discourse.nixos.org/t/using-fixed-output-paths-for-a-derivation/6338/4)
- [Nix Discourse thread on the different kinds of fetchers](https://discourse.nixos.org/t/why-is-fetchtarball-not-mentioned-in-chapter-11-fetchers-of-the-nixpkgs-manual/15319/2)
