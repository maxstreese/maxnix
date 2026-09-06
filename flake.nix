{
  description = "maxnix — a NixOS VM for evaluating niri, Hyprland and Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    {
      # One machine, one source of truth.
      #
      # Evaluated normally this describes a system you could install on metal.
      # Evaluated again with nixos/modules/virtualisation/qemu-vm.nix layered on
      # top — which every NixOS config can do, via `virtualisation.vmVariant` —
      # it also yields ./result/bin/run-maxnix-vm, a script that runs on *this*
      # Ubuntu host. Being a VM is a variant of the machine, not a second
      # description of it.
      nixosConfigurations.maxnix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/maxnix/configuration.nix
          ./hosts/maxnix/vm.nix
          ./modules/desktop
        ];
      };
    };
}
