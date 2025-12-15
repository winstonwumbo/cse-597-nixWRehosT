{ deviceName ? null
, device ? (import ./qemu/boards/${deviceName})
, rehost-config ? <rehost-config>
, image ? null
, imageType ? "primary"
}:

let
  overlay = final: prev:
    let
      isCross = final.stdenv.buildPlatform != final.stdenv.hostPlatform;
      crossOnly = pkg: amendFn: if isCross then (amendFn pkg) else pkg;
      extraPkgs = import ./qemu/qemu-deps/pkgs/default.nix {
        inherit (final) lib callPackage;
      };
      inherit (final) fetchpatch lib;

      luaHost =
        let
          l = prev.lua5_3.overrideAttrs (o: {
            name = "lua-tty";
            preBuild = ''
              makeFlagsArray+=(PLAT="posix" SYSLIBS="-Wl,-E -ldl"  CFLAGS="-O2 -fPIC -DLUA_USE_POSIX -DLUA_USE_DLOPEN")
            '';
            makeFlags = builtins.filter (x: (builtins.match "(PLAT|MYLIBS).*" x) == null) o.makeFlags;
          });
        in
        l.override {
          self = l;
          packageOverrides = lua-final: lua-prev:
            let openssl = final.opensslNoThreads; in
            {
              cqueues = lua-prev.cqueues.overrideAttrs (_: {
                externalDeps = [
                  { name = "CRYPTO"; dep = openssl; }
                  { name = "OPENSSL"; dep = openssl; }
                ];
              });
              luaossl = lua-prev.luaossl.overrideAttrs (o: {
                externalDeps = [
                  { name = "CRYPTO"; dep = openssl; }
                  { name = "OPENSSL"; dep = openssl; }
                ];
                name = "${o.name}-218";
                patches = [
                  (fetchpatch {
                    url = "https://patch-diff.githubusercontent.com/raw/wahern/luaossl/pull/218.patch";
                    hash = "sha256-2GOliY4/RUzOgx3rqee3X3szCdUVxYDut7d+XFcUTJw=";
                  })
                ];
              });
            };
        };

      s6 = prev.s6.overrideAttrs (o:
        let
          patch = fetchpatch {
            url = "https://github.com/skarnet/s6/commit/ddc76841398dfd5e18b22943727ad74b880236d3.patch";
            hash = "sha256-fBtUinBdp5GqoxgF6fcR44Tu8hakxs/rOShhuZOgokc=";
          };
          patch_needed = builtins.compareVersions o.version "2.11.1.2" <= 0;
        in {
          configureFlags =
            (builtins.filter (x: (builtins.match ".*shared.*" x) == null) o.configureFlags)
            ++ [ "--disable-allstatic" "--disable-static" "--enable-shared" ];
          hardeningDisable = [ "all" ];
          stripAllList = [ "sbin" "bin" ];
          patches = (if o ? patches then o.patches else [ ])
            ++ (if patch_needed then [ patch ] else [ ]);
        }
      );
    in
    extraPkgs // {
      lim = {
        parseInt = s: (builtins.fromTOML "r=${s}").r;
        orEmpty = x: if x != null then x else [ ];
      };

      btrfs-progs = crossOnly prev.btrfs-progs (d: d.override { udevSupport = false; udev = null; });

      chrony =
        let chrony' = prev.chrony.overrideAttrs (_: {
          configureFlags = [
            "--chronyvardir=$(out)/var/lib/chrony"
            "--sbindir=$(out)/bin"
            "--chronyrundir=/run/chrony"
            "--disable-readline"
            "--disable-editline"
          ];
        }); in
        chrony'.override {
          gnutls = null; libedit = null; libseccomp = null; libcap = null; texinfo = null;
        } // lib.optionalAttrs (lib.versionOlder lib.version "24.10") {
          nss = null; nspr = null; readline = null;
        };

      clevis = crossOnly prev.clevis (d:
        let c = d.overrideAttrs (_: {
          outputs = [ "out" ];
          preConfigure = ''
            rm -rf src/luks
            sed -i -e '/luks/d' src/meson.build
          '';
        }); in
        c.override { asciidoc = null; cryptsetup = null; luksmeta = null; tpm2-tools = null; }
      );

      dnsmasq =
        let d = prev.dnsmasq.overrideAttrs (_: { preBuild = '' makeFlagsArray=("COPTS=") ''; }); in
        d.override { dbusSupport = false; nettle = null; };

      dropbear = crossOnly prev.dropbear (d: d.overrideAttrs (o: rec {
        version = "2024.85";
        src = final.fetchurl {
          url = "https://matt.ucc.asn.au/dropbear/releases/dropbear-${version}.tar.bz2";
          sha256 = "sha256-hrA2xDOmnYnOUeuuM11lxHc4zPkNE+XrD+qDLlVtpQI=";
        };
        patches =
          let passPath = final.runCommand "pass-path" { } ''
            sed < ${builtins.head o.patches} -e 's,svr-chansession.c,src/svr-chansession.c,g' > $out
          ''; in
          [ (if (lib.versionOlder o.version "2024") then passPath else (builtins.head o.patches))
            ./qemu/qemu-deps/pkgs/dropbear/add-authkeyfile-option.patch
          ];
        postPatch = ''
          (echo '#define DSS_PRIV_FILENAME "/run/dropbear/dropbear_dss_host_key"'
           echo '#define RSA_PRIV_FILENAME "/run/dropbear/dropbear_rsa_host_key"'
           echo '#define ECDSA_PRIV_FILENAME "/run/dropbear/dropbear_ecdsa_host_key"'
           echo '#define ED25519_PRIV_FILENAME "/run/dropbear/dropbear_ed25519_host_key"') > localoptions.h
        '';
      }));

      elfutils = crossOnly prev.elfutils (d:
        let e = d.overrideAttrs (o: { configureFlags = o.configureFlags ++ [ "ac_cv_has_stdatomic=no" ]; }); in
        e.override { enableDebuginfod = false; }
      );

      hostapd =
        let
          config = [
            "CONFIG_DRIVER_NL80211=y" "CONFIG_IAPP=y" "CONFIG_IEEE80211AC=y" "CONFIG_IEEE80211AX=y"
            "CONFIG_IEEE80211N=y" "CONFIG_IEEE80211W=y" "CONFIG_INTERNAL_LIBTOMMATH=y"
            "CONFIG_INTERNAL_LIBTOMMATH_FAST=y" "CONFIG_IPV6=y" "CONFIG_LIBNL32=y"
            "CONFIG_PKCS12=y" "CONFIG_RSN_PREAUTH=y" "CONFIG_TLS=internal"
          ];
          h = prev.hostapd.overrideAttrs (o: {
            extraConfig = "";
            configurePhase = ''
              cat > hostapd/defconfig <<EOF
              ${builtins.concatStringsSep "\n" config}
              EOF
              ${o.configurePhase}
            '';
          });
        in h.override { openssl = null; sqlite = null; };

      iproute2 = crossOnly prev.iproute2 (d: d.override { db = null; });

      kexec-tools-static = prev.kexec-tools.overrideAttrs (o: {
        LDFLAGS = "-static";
        patches = o.patches ++ [
          (fetchpatch {
            url = "https://patch-diff.githubusercontent.com/raw/horms/kexec-tools/pull/3.patch";
            hash = "sha256-MvlJhuex9dlawwNZJ1sJ33YPWn1/q4uKotqkC/4d2tk=";
          })
          qemu/qemu-deps/pkgs/kexec-map-file.patch
        ];
      });

      libadwaita = prev.libadwaita.overrideAttrs (_: { doCheck = false; });
      lua = luaHost;

      mtdutils = (prev.mtdutils.overrideAttrs (_: {
        src = final.fetchgit {
          url = "git://git.infradead.org/mtd-utils.git";
          rev = "77981a2888c711268b0e7f32af6af159c2288e23";
          hash = "sha256-pHunlPOuvCRyyk9qAiR3Kn3cqS/nZHIxsv6m4nsAcbk=";
        };
        patches = [ ./qemu/qemu-deps/pkgs/mtdutils/0001-mkfs.jffs2-add-graft-option.patch ];
      })).override { util-linux = final.util-linux-small; };

      nftables = prev.nftables.overrideAttrs (_: {
        configureFlags = [ "--disable-debug" "--disable-python" "--with-mini-gmp" "--without-cli" ];
      });

      opensslNoThreads = prev.openssl.overrideAttrs (o: with final; {
        pname = "${o.pname}-nothreads";
        preConfigure =
          let
            arch = if stdenv.hostPlatform.gcc ? arch then "-march=${stdenv.hostPlatform.gcc.arch}" else "";
            soft = if arch == "-march=24kc" then "-msoft-float" else "";
          in '' configureFlagsArray+=(no-threads no-asm CFLAGS="${arch} ${soft}") '';
        postInstall = o.postInstall + "rm $bin/bin/c_rehash\n";
      });

      pppBuild = prev.ppp;

      qemuLim =
        let
          q = prev.qemu.overrideAttrs (o: {
            patches = o.patches ++ [
              ./qemu/qemu-deps/pkgs/qemu/arm-image-friendly-load-addr.patch
              (final.fetchpatch {
                url = "https://lore.kernel.org/qemu-devel/20220322154658.1687620-1-raj.khem@gmail.com/raw";
                hash = "sha256-jOsGka7xLkJznb9M90v5TsJraXXTAj84lcphcSxjYLU=";
              })
            ];
            image = image;
            buildInputs = o.buildInputs ++ [ final.libslirp ];
          });
          overrides = {
            hostCpuTargets = map (f: "${f}-softmmu") [ "arm" "aarch64" "mips" "mipsel" ];
            sdlSupport = false; numaSupport = false; seccompSupport = false; usbredirSupport = false;
            libiscsiSupport = false; tpmSupport = false; uringSupport = false; capstoneSupport = false;
          }
          // lib.optionalAttrs (lib.versionOlder lib.version "24.10") { texinfo = null; nixosTestRunner = true; }
          // lib.optionalAttrs (lib.versionAtLeast lib.version "25.04") { minimal = true; };
        in q.override overrides;

      rsyncSmall =
        let r = prev.rsync.overrideAttrs (o: { configureFlags = o.configureFlags ++ [ "--disable-openssl" ]; });
        in r.override { openssl = null; };

      inherit s6;
      s6-linux-init = prev.s6-linux-init.override { skawarePackages = prev.skawarePackages // { inherit s6; }; };
      s6-rc = prev.s6-rc.override { skawarePackages = prev.skawarePackages // { inherit s6; }; };

      strace = prev.strace.override { libunwind = null; };

      ubootQemuAarch64 = final.buildUBoot {
        defconfig = "qemu_arm64_defconfig";
        extraMeta.platforms = [ "aarch64-linux" ];
        filesToInstall = [ "u-boot.bin" ];
      };

      ubootQemuArm = final.buildUBoot {
        defconfig = "qemu_arm_defconfig";
        extraMeta.platforms = [ "armv7l-linux" ];
        filesToInstall = [ "u-boot.bin" ];
        extraConfig = ''
          CONFIG_CMD_UBI=y
          CONFIG_CMD_UBIFS=y
          CONFIG_BOOTSTD=y
          CONFIG_BOOTMETH_DISTRO=y
          CONFIG_LZMA=y
          CONFIG_CMD_LZMADEC=y
          CONFIG_SYS_BOOTM_LEN=0x1000000
        '';
      };

      ubootQemuMips = final.buildUBoot {
        defconfig = "malta_defconfig";
        extraMeta.platforms = [ "mips-linux" ];
        filesToInstall = [ "u-boot.bin" ];
        extraPatches = [ ./qemu/qemu-deps/pkgs/u-boot/0002-virtio-init-for-malta.patch ];
        image = image;
        extraConfig = ''
          CONFIG_SYS_PROMPT="=> "
          CONFIG_VIRTIO=y
          CONFIG_AUTOBOOT=y
          CONFIG_DM_PCI=y
          CONFIG_VIRTIO_PCI=y
          CONFIG_VIRTIO_NET=y
          CONFIG_VIRTIO_BLK=y
          CONFIG_VIRTIO_MMIO=y
          CONFIG_QFW_MMIO=y
          CONFIG_FIT=y
          CONFIG_LZMA=y
          CONFIG_CMD_LZMADEC=y
          CONFIG_SYS_BOOTM_LEN=0x1000000
          CONFIG_SYS_MALLOC_LEN=0x400000
          CONFIG_MIPS_BOOT_FDT=y
          CONFIG_OF_LIBFDT=y
          CONFIG_OF_STDOUT_VIA_ALIAS=y
        '';
      };

      libusb1 = crossOnly prev.libusb1 (d:
        let u = d.overrideAttrs (_: { preConfigure = "sed -i.bak /__atomic_fetch_add_4/c\\: configure.ac"; }); in
        u.override { enableUdev = false; withDocs = false; }
      );

      util-linux-small = prev.util-linux.override {
        ncursesSupport = false; pamSupport = false; systemdSupport = false; nlsSupport = false;
        translateManpages = false; capabilitiesSupport = false;
      };

      xl2tpd = prev.xl2tpd.overrideAttrs (_: { patches = [ ./qemu/qemu-deps/pkgs/xl2tpd-exit-on-close.patch ]; });
    };

  pkgs = import <nixpkgs> (
    device.system // {
      overlays = [ overlay ];
      config = {
        allowUnsupportedSystem = true;
        permittedInsecurePackages = [
          "python-2.7.18.6"
          "python-2.7.18.7"
        ];
      };
    }
  );

  eval = pkgs.lib.evalModules {
    specialArgs = { modulesPath = builtins.toString ./qemu/qemu-deps/modules; };
    modules = [
      { _module.args = { inherit pkgs; inherit (pkgs) lim; }; }
      ./qemu/qemu-deps/modules/hardware.nix
      ./qemu/qemu-deps/modules/base.nix
      ./qemu/qemu-deps/modules/busybox.nix
      ./qemu/qemu-deps/modules/hostname.nix
      ./qemu/qemu-deps/modules/kernel
      ./qemu/qemu-deps/modules/logging.nix
      ./qemu/qemu-deps/modules/klogd.nix
      device.module
      rehost-config
      ./qemu/qemu-deps/modules/s6
      ./qemu/qemu-deps/modules/users.nix
      ./qemu/qemu-deps/modules/outputs.nix
      { boot.imageType = imageType; }
    ];
  };

  config = eval.config;

  nixwrehostInitQemu =
    ((import <nixpkgs/nixos/lib/eval-config.nix>) {
      system = builtins.currentSystem;
      modules = [
        { nixpkgs.overlays = [ (final: prev: {
            go-l2tp = final.callPackage ./qemu/qemu-deps/pkgs/go-l2tp { inherit image; };
            tufted  = final.callPackage ./qemu/qemu-deps/pkgs/tufted  { inherit image; };
          }) ]; }
        (import ./src/nixwrehost-init.nix)
      ];
    }).config.system;

in {
  outputs = config.system.outputs // {
    default = config.system.outputs.${config.hardware.defaultOutput};
    optionsJson =
      let o = import ./src/extract-options.nix { inherit pkgs eval; lib = pkgs.lib; };
      in pkgs.writeText "options.json" (builtins.toJSON o);
  };

  inherit pkgs;

  buildEnv = pkgs.mkShell {
    packages = with pkgs.pkgsBuildBuild; [
      tufted
      routeros.routeros
      routeros.ros-exec-script
      run-nixwrehost-vm
      nixwrehostInitQemu.build.vm
      go-l2tp
      min-copy-closure
      fennelrepl
      lzma
      lua
    ];
  };
}
