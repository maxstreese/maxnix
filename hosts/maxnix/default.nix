# The ThinkPad: a Lenovo T14s Gen 2a. Composed in flake.nix from the base,
# desktop and metal roles plus this directory; ./vm.nix is added for the
# configuration the VM runs.
{ ... }:
{
  imports = [
    ./configuration.nix
    ./laptop.nix
    ./secrets.nix
  ];
}
