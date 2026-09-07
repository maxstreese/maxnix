{
  description = "maxnix — a NixOS VM for evaluating niri, Hyprland and Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
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
        inherit system;
        modules = [
          ./hosts/maxnix/configuration.nix
          ./hosts/maxnix/vm.nix
          ./modules/desktop
        ];
      };

      # Integration tests over the same machine definition.
      #
      # Run these with the *interactive* driver, not a plain `nix build` — see
      # the header of tests/desktop.nix for why:
      #   nix build .#checks.x86_64-linux.<name>.driverInteractive
      #   ./result/bin/nixos-test-driver --no-interactive -o /tmp/testout
      #
      # They all bind the same VNC port, so run them one at a time.
      checks.${system} = {
        # Compositor-agnostic: boot, greeter, sessions, GPU.
        desktop = pkgs.testers.runNixOSTest ./tests/desktop.nix;

        # One per compositor. The two differ only in how you ask them what they
        # are doing, so the test body is shared.
        niri = pkgs.testers.runNixOSTest (
          import ./tests/compositor.nix {
            name = "niri";
            session = "niri-session";
            ipcReady = "ls /run/user/1000/niri.wayland-*.sock";
            outputs = "NIRI_SOCKET=$(ls /run/user/1000/niri.wayland-*.sock | head -1) niri msg outputs";
          }
        );

        hyprland = pkgs.testers.runNixOSTest (
          import ./tests/compositor.nix {
            name = "hyprland";
            # What the session .desktop entry actually execs, rather than the
            # bare Hyprland binary, so this covers the real launch path.
            session = "start-hyprland";
            # Wait for the *command* socket, not just the instance directory.
            # The directory and .socket2.sock (events) appear well before
            # .socket.sock, so watching the directory races and hyprctl then
            # fails with "Couldn't connect ... (4)".
            ipcReady = "ls /run/user/1000/hypr/*/.socket.sock";
            # XDG_RUNTIME_DIR is required even with the instance signature:
            # hyprctl resolves its socket relative to it, and the driver's
            # backdoor is a bare root shell that has none. Without it hyprctl
            # exits 4. (Same root cause as Hyprland --version aborting.)
            outputs = "XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1) hyprctl monitors";
          }
        );
      };
    };
}
