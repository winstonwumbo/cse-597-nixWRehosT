let
  nixpkgs = <nixpkgs>;

  rehostConfig =
    { config, pkgs, ... }:
    let
      inherit (pkgs.nixwrehost.services) target;
      svc = config.system.service;
    in
    rec {
      imports = [
        ./qemu/qemu-deps/modules/wlan.nix
        ./qemu/qemu-deps/modules/network
        ./qemu/qemu-deps/modules/ntp
        ./qemu/qemu-deps/modules/vlan
        ./qemu/qemu-deps/modules/dhcp4c
      ];

      services.dhcpv4 =
        let
          iface = svc.network.link.build { ifname = "eth1"; };
        in
        svc.dhcp4c.client.build { interface = iface; };

      services.defaultroute4 = svc.network.route.build {
        via = "$(output ${services.dhcpv4} ip)";
        target = "default";
        dependencies = [ services.dhcpv4 ];
      };

      services.packet_forwarding =
        svc.network.forward.build { };

      services.ntp =
        config.system.service.ntp.build {
          pools = {
            "pool.ntp.org" = [ "iburst" ];
          };
        };

      boot.tftp = {
        serverip = "192.168.8.148";
        ipaddr = "192.168.8.251";
      };

      defaultProfile.packages = [ pkgs.hello ];
    };

  nixwrehost =
    import ./default.nix {
      device = import ./qemu;
      rehost-config = rehostConfig;
    };

  here = builtins.toString ./.;

in
nixwrehost.buildEnv.overrideAttrs (o: {
  nativeBuildInputs =
    o.nativeBuildInputs ++ [
      (import nixpkgs { }).sphinx
    ];

  FENNEL_PATH =
    "${here}/qemu/qemu-deps/pkgs/?/init.fnl;${here}/qemu/qemu-deps/pkgs/?.fnl";
})
