# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

let
  sources = import ./lon/lon.nix;
  lanzaboote = import sources.lanzaboote {
    inherit pkgs;
  };
in

{
  imports = [ 
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    lanzaboote.nixosModules.lanzaboote  
  ];

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;


  # Ne treba šifra za sudo za ovaj profil:
    security.sudo.extraRules = [
    {
      users = [ "borko" ];
      commands = [
        {
          command = "ALL";
          options = [ "SETENV" "NOPASSWD" ];
        }
      ];
    }
  ];

  # Automatsko ažuriranje sistema #######################################################
  system.autoUpgrade.enable = false; # isključeno jer ćemo ručno pokretati kroz terminal
  nix.settings.auto-optimise-store = true;

  # Garbage collection (jednom dnevno, centralno)
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 2d";
  };

  # Definišite servis
  systemd.user.services.nixos-upgrade = {
    enable = true;
    description = "NixOS Upgrade";
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      Environment = [
        "DISPLAY=:0"
        "XAUTHORITY=/home/borko/.Xauthority"
      ];
      ExecStart = 
      "${pkgs.kdePackages.konsole}/bin/konsole " +
      "-e ${pkgs.bash}/bin/bash -c '" +
      "echo \"╔══════════════════════════════════════════════════╗\"; " +
      "echo \"║               NIXOS SYSTEM UPDATE                ║\"; " +
      "echo \"╠══════════════════════════════════════════════════╣\"; " +
      "echo \"║          Pokrećem ažuriranje sistema...          ║\"; " +
      "echo \"╚══════════════════════════════════════════════════╝\"; " +
      "echo \"\"; " +
      "/run/wrappers/bin/sudo -n /run/current-system/sw/bin/nixos-rebuild switch --upgrade; " +
      "echo \"\"; " +
      "echo \"╔══════════════════════════════════════════════════╗\"; " +
      "echo \"║             ✓ AŽURIRANJE ZAVRŠENO!               ║\"; " +
      "echo \"╚══════════════════════════════════════════════════╝\"; " +
      "echo \"\"; " +
      "echo \"Prozor će se zatvoriti za 5 sekundi...\"; " +
      "sleep 5" +
      "'";
      User = "borko";
      WorkingDirectory = "/home/borko";
    };
  };

  # Definišite timer
  systemd.user.timers.nixos-upgrade = {
    enable = true;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 10:00:00"; # Svaki dan u 10:00 (bolje od "daily")
      Persistent = true; # Ako propustite, pokrene pri sledećem bootu
      RandomizedDelaySec = "10min"; # Random delay 0-10 minuta
    };
  };

  # Finalne Kernel Postavke za 16GB RAM: #########################################

  boot.kernel.sysctl = {
    # 1. AGRESIVNA RAM OPTIMIZACIJA (16GB omogućava)
    "vm.swappiness" = 1;                      # Gotovo nikad ne swapuj
    "vm.vfs_cache_pressure" = 30;             # Drži više cache-a u RAM-u
    "vm.min_free_kbytes" = 65536;             # 64MB min free za bursty video operacije
  
    # 2. VELIKI DIRTY BUFFERI za video stream
    "vm.dirty_background_ratio" = 3;          # 3% RAM-a = ~480MB
    "vm.dirty_ratio" = 10;                    # 10% RAM-a = ~1.6GB
    "vm.dirty_expire_centisecs" = 12000;      # 120s - dugo drži u RAM-u preko write
    "vm.dirty_writeback_centisecs" = 6000;    # 60s - manje čestih disk operacija
  
    # 3. CPU SCHEDULING za 4-core/8-thread
    "kernel.sched_latency_ns" = 12000000;     # 12ms - bolje za parallel render
    "kernel.sched_min_granularity_ns" = 2500000;
    "kernel.sched_wakeup_granularity_ns" = 4000000;
    "kernel.sched_migration_cost_ns" = 1000000; # Manji migration cost
    "kernel.sched_rt_runtime_us" = 950000;    # 95% CPU za Real-time (audio sync)
  
    # 4. MEMORY MANAGEMENT za video editing
    "vm.zone_reclaim_mode" = 0;               # Ne reclaimuj memory agresivno
    "vm.page-cluster" = 3;                    # Više page clustering za video IO
    "vm.laptop_mode" = 5;                     # Laptop + video editing balans
  
    # 5. KDENLIVE SPECIFIČNO
    "fs.inotify.max_user_watches" = 1048576;  # 1M watches za project monitoring
    "fs.aio-max-nr" = 262144;                 # Više async IO za MLT framework
    "kernel.msgmnb" = 65536;                  # Više IPC poruka
    "kernel.msgmax" = 65536;
  
    # 6. NETWORK za cloud assets
    "net.core.netdev_max_backlog" = 5000;
    "net.core.somaxconn" = 4096;
    "net.ipv4.tcp_max_syn_backlog" = 4096;

    # 7. Quick Fix za Stutter 
    "vm.compact_unevictable_allowed" = 1;
    "vm.compact_memory" = 1;
  };

  # Kernel parametri
  boot.kernelParams = [
    "amd_pstate=active"
    "processor.max_cstate=2"        # Shallower C-states za editing
    "radeon.dpm=1"                  # Dynamic Power Management
    "radeon.audio=1"                # HDMI/DP audio
    "mce=ignore_ce"                 # Ignore correctable errors
  ];

  # RAM Disk Setup za Proxy/Cache: #########################################

  # 8GB RAM Disk za Kdenlive cache (ostaje 8GB za sistem)
  fileSystems."/mnt/ramdisk" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=6G"                    # 6GB za proxy files
      "mode=777"
      "nr_inodes=1M"
      "noatime"
      "nodiratime"
    ];
  };

  # Link Kdenlive cache na RAM disk
  systemd.tmpfiles.rules = [
    "L /home/borko/.local/share/kdenlive/cache - - - - /mnt/ramdisk/kdenlive_cache"
    "L /tmp/kdenlive - - - - /mnt/ramdisk/kdenlive_temp"
  ];

  # AMD Ryzen 2500U Specific Optimizations: #######################################
  environment.variables = {
    # Video editing optimizacije
    MLT_NORMALISATION_CLAMP = "1";
    MLT_AUDIO_DISPATCH_DELAY = "100";
    MLT_VIDEO_DISPATCH_DELAY = "33";
    OMP_NUM_THREADS = "6";          # Ostavi 2 threada za OS
    # GPU optimizacije
    RADV_PERFTEST = "gpl";
    LIBVA_DRIVER_NAME = "radeonsi";
    VDPAU_DRIVER = "radeonsi";
    # Ryzen optimizacije
    AMD_DEBUG = "nongg,nodcc";
    ACO_DEBUG = "novskipov";
  };

  # Power & Thermal Management daemons ###############################################

  services.power-profiles-daemon.enable = false;

  #services.thermald.enable = false;

  #services.auto-cpufreq.enable = true;
  #services.auto-cpufreq.settings = {
  #  battery = {
  #    governor = "powersave";
  #    turbo = "never";
  #  };
  #  charger = {
  #    governor = "performance";
  #  };
  #};

  # Tuned umjesto power-profiles-daemon (Dodaje Performance u Power Mode)
  services.tlp.enable = false;
  services.tuned.enable = true;
  services.tuned.settings.dynamic_tuning = true;

  #####################################################################

  # Virt-manager
  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = ["borko"];
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # Bootloader.
  #boot.loader.systemd-boot.enable = true;
  #boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot = {
  enable = lib.mkForce false;
  configurationLimit = 3;
  };
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  # Enable plymouth (boot animacija)
  boot.plymouth.enable = true;

  # Enable networking
  networking.networkmanager.enable = true;
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Set your time zone.
  time.timeZone = "Europe/Sarajevo";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "bs_BA.UTF-8";
    LC_IDENTIFICATION = "bs_BA.UTF-8";
    LC_MEASUREMENT = "bs_BA.UTF-8";
    LC_MONETARY = "bs_BA.UTF-8";
    LC_NAME = "bs_BA.UTF-8";
    LC_NUMERIC = "bs_BA.UTF-8";
    LC_PAPER = "bs_BA.UTF-8";
    LC_TELEPHONE = "bs_BA.UTF-8";
    LC_TIME = "bs_BA.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Default DE
  #services.displayManager.defaultSession = "plasma";  # plasma ili cinnamon ili gnome

  # Enable the GNOME Desktop Environment.
  #services.displayManager.gdm.enable = false;
  #services.desktopManager.gnome.enable = true;
  #services.gnome.games.enable = false;

  #Enable Cinnamon
  #services.xserver.desktopManager.cinnamon.enable = true;
  #services.cinnamon.apps.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "ba";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable support for SANE scanners
  hardware.sane.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.borko = {
    isNormalUser = true;
    description = "Borko";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      kdePackages.kate
    #  thunderbird
    ];
  };

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "borko";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable Flatpak:
  services.flatpak.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "gtk";

  # Enable common container config files in /etc/containers
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Paketi ##########################################################################
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [

  ## ======================
  ## Sistem alati / CLI alati
  ## ======================
    android-tools # flešovanje romova
    bash
    fastfetch # info o sistemu
    fortune
    htop # Interactive process viewer
    ignition # Startup aplikacija
    inspector # Informacije o sistemu
    libnotify # za notifikacije o automatskom ažuriranju
    nix # Nix package manager
    python3Minimal
    vulkan-tools # Vulkan dijagnostika (potrebno za Bottles / Flatpak GPU podršku)
    unzip
    dconf-editor

  ## ======================
  ## Podman
  ## ======================
    dive # look into docker image layers
    podman-tui # status of containers in the terminal
    docker-compose # start group of containers for dev
    #podman-compose # start group of containers for dev

  ## ======================
  ## Secure Boot / Firmware
  ## ======================
    lon # Lock & update Nix dependencies
    niv # Easy dependency management for Nix projects
    sbctl # Secure Boot key manager

  ## ======================
  ## Razvoj / alati
  ## ======================
    git # Distributed version control system
    kdePackages.kcalc # Digitron
    lua # scripting language
    kdePackages.dolphin-plugins

  ## ======================
  ## AppImage / disk alati
  ## ======================
    appimage-run # pokretanje AppImage
    impression # pisanje image-a na disk
    kdePackages.filelight # Statistika iskorišćenosti diskova
    kdePackages.partitionmanager # Uređivač particija

  ## ======================
  ## Multimedija / Grafika
  ## ======================
    audacity # audio obrada
    ffmpeg-full # audio/video alati
    gimp3 # raster grafika
    haruna # Open source video player built with Qt/QML and libmpv
    image_optim # Command line tool to optimize images
    inkscape # vektorska grafika
    kdePackages.isoimagewriter # Program to write hybrid ISO files onto USB disks
    kdePackages.kamoso # Kamera
    kdePackages.kcolorchooser # Birač boja
    kdePackages.kdenlive # program za video montažu
    krita # digital painting
    losslesscut-bin # Swiss army knife of lossless video/audio editing
    upscayl # AI Image Upscaler
    vlc # multimedijalni plejer

  ## ======================
  ## Igre
  ## ======================
    kdePackages.kmahjongg # Mahjongg Solitaire
    kdePackages.kmines # KMines is the classic Minesweeper game
    kdePackages.knavalbattle # ship sinking game
    kdePackages.kpat # Solitaire card game

  ## ======================
  ## Kancelarija / produktivnost
  ## ======================
    kdePackages.kcharselect # Tool to select and copy special characters
    kdePackages.kompare # Graphical File Differences Tool
    kdePackages.ktouch # Touch Typing Tutor
    #libreoffice # private, free and open source office suite
    obsidian # aplikacija za vođenje bilješki
    onlyoffice-desktopeditors # OnlyOffice

  ## ======================
  ## Skeniranje
  ## ======================
    kdePackages.skanpage # aplikacija za skeniranje
    kdePackages.skanlite
    sane-backends # drajveri i biblioteke za skenere putem SANE
    simple-scan # program za skeniranje

  ## ======================
  ## Internet / komunikacija
  ## ======================
    kdePackages.kget # Menadžer preuzimanja
    ocs-url # Open Collaboration System for use with DE store websites
    telegram-desktop # Telegram
    vdhcoapp # Video DownloadHelper
    qbittorrent # BitTorrent client
    wget # preuzimanje fajlova

  ## ======================
  ## Tema / izgled
  ## ======================
    capitaine-cursors # Kursor tema
    #yaru-theme # Tema ikonica

  ## ======================
  ## GNOME
  ## ======================
    #gnome-boxes qemu_kvm qemu bridge-utils libvirt virt-manager
    #gnome-software
    #gnome-tweaks
    gnome-terminal

  ## ======================
  ## GNOME Ekstenzije
  ## ======================
    #gnomeExtensions.add-to-desktop
    #gnomeExtensions.appindicator
    #gnomeExtensions.arcmenu
    #gnomeExtensions.bing-wallpaper-changer
    #gnomeExtensions.caffeine
    #gnomeExtensions.dash-to-panel
    #gnomeExtensions.desktop-icons-ng-ding
    #gnomeExtensions.night-light-slider-updated
    #gnomeExtensions.privacy-settings-menu
    #gnomeExtensions.reboottouefi
    #gnomeExtensions.system-monitor

  ## ======================
  ## Editori
  ## ======================
    kdePackages.kate # Tekst editor
    #vim  # (Vim editor). Nano je već instaliran kao podrazumjevani.

  ## ======================
  ## CLI alati
  ## ======================
    pv # (Pipe Viewer) Prikazuje progress bar za protok podataka kroz pipe 
    rsync # Napredno kopiranje sa opcijama za resume, diff, progress.
    iotop # pokazuje koje procese najviše koriste disk: $sudo iotop

  ## ======================
  ## Skripte za dirty 
  ## ======================

  # Skripta za USB mode
  (writeShellScriptBin "usb-mode" ''
    echo 8388608 > /proc/sys/vm/dirty_background_bytes    # 8MB (umesto 20MB)
    echo 16777216 > /proc/sys/vm/dirty_bytes              # 16MB (umesto 50MB)
    echo 500 > /proc/sys/vm/dirty_writeback_centisecs     # 5s
    echo 3000 > /proc/sys/vm/dirty_expire_centisecs       # 30s
    echo "📀 USB mode: 8MB/16MB bufferi"
    echo "✅ Tačan progress bar pri kopiranju"
  '')

  # Skripta za video mode
  (writeShellScriptBin "video-mode" ''
    echo 3 > /proc/sys/vm/dirty_background_ratio          # 491MB
    echo 10 > /proc/sys/vm/dirty_ratio                    # 1.6GB
    echo 6000 > /proc/sys/vm/dirty_writeback_centisecs    # 60s
    echo 12000 > /proc/sys/vm/dirty_expire_centisecs      # 120s
    echo "🎬 Video mode: 3%/10% (491MB/1.6GB)"
    echo "✅ Optimizovano za Kdenlive editing"
  '')

  # Skripta za gaming mode
  (writeShellScriptBin "gaming-mode" ''
    echo 8 > /proc/sys/vm/dirty_background_ratio          # 1.3GB
    echo 20 > /proc/sys/vm/dirty_ratio                    # 3.2GB
    echo 8000 > /proc/sys/vm/dirty_writeback_centisecs    # 80s (umesto 100s)
    echo 16000 > /proc/sys/vm/dirty_expire_centisecs      # 160s (umesto 180s)
    echo "🎮 Gaming mode: 8%/20% (1.3GB/3.2GB)"
    echo "✅ Dobar za gaming + 4K video playback"
  '')

  # Skripta za aggressive mode
  (writeShellScriptBin "aggressive-mode" ''
    echo 10 > /proc/sys/vm/dirty_background_ratio          # 1.6GB
    echo 30 > /proc/sys/vm/dirty_ratio                     # 4.8GB
    echo 30000 > /proc/sys/vm/dirty_writeback_centisecs    # 300s (5min)
    echo 60000 > /proc/sys/vm/dirty_expire_centisecs       # 600s (10min)
    echo "🔥 AGGRESSIVE mode: 10%/30% (1.6GB/4.8GB)"
    echo "⚠️ UPOZORENJE: Možeš izgubiti do 4.8GB podataka!"
    echo "Koristi SAMO za renderovanje, ne za editing!"
  '')

  # Skripta za status
  (writeShellScriptBin "status-mode" ''
    echo ""
    echo "=== DIRTY PAGES STATUS ==="
    echo "Background bytes: $(cat /proc/sys/vm/dirty_background_bytes)"
    echo "Dirty bytes: $(cat /proc/sys/vm/dirty_bytes)"
    echo "Background ratio: $(cat /proc/sys/vm/dirty_background_ratio)"
    echo "Dirty ratio: $(cat /proc/sys/vm/dirty_ratio)"
    echo "Writeback centisecs: $(cat /proc/sys/vm/dirty_writeback_centisecs)"
    echo "Expire centisecs: $(cat /proc/sys/vm/dirty_expire_centisecs)"
    echo ""
    echo "=== CURRENT VALUES ==="
    grep -E "Dirty:|Writeback:" /proc/meminfo
    echo ""
    echo "=== Dostupne opcije ==="
    echo "usb-mode           dbb8388608 db16777216 wr500 ex3000"
    echo "video-mode         dbr3 dr10 wr6000 ex12000"
    echo "gaming-mode        dbr8 dr20 wr8000 ex16000"
    echo "aggressive-mode    dbr10 dr30 wr30000 ex60000"
  '')

  ];
 
  # Deinstalacija pojedinih paketa
  #environment.gnome.excludePackages = with pkgs; [ ];
  services.xserver.excludePackages = with  pkgs; [ xterm ];

  # Firefox ####################################################

  programs = {
    firefox = {
      enable = true;
      languagePacks = [ "sr" ];

      /* ---- POLICIES ---- */
      # Check about:policies#documentation for options.
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        EnableTrackingProtection = {
          Value= true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };
        DisablePocket = true;
        DisableFirefoxAccounts = false;
        DisableAccounts = false;
        DisableFirefoxScreenshots = true;
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        DontCheckDefaultBrowser = true;
        DisplayBookmarksToolbar = "never"; # alternatives: "always" or "newtab"
        DisplayMenuBar = "never"; # alternatives: "always", "never" or "default-on"
        SearchBar = "unified"; # alternative: "separate"

        /* ---- EXTENSIONS ---- */
        # Check about:support for extension/add-on ID strings.
        # Valid strings for installation_mode are "allowed", "blocked",
        # "force_installed" and "normal_installed".
        ExtensionSettings = {
          "*".installation_mode = "blocked"; # blocks all addons except the ones specified below
          # uBlock Origin:
          "uBlock0@raymondhill.net" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            installation_mode = "force_installed";
          };
          # AdGuard AdBlocker
          "adguardadblocker@adguard.com" = {
             install_url = "https://addons.mozilla.org/firefox/downloads/latest/adguard-adblocker/latest.xpi";
             installation_mode = "force_installed";
          };
          # Privacy Badger:
          "jid1-MnnxcxisBPnSXQ@jetpack" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/latest.xpi";
            installation_mode = "force_installed";
          };
          # Video DownloadHelper
          "{b9db16a4-6edc-47ec-a1f4-b86292ed211d}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/video-downloadhelper/latest.xpi";
            installation_mode = "force_installed";
          };
          # Bitwarden
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
            installation_mode = "force_installed";
          };
          # Bitdefender TrafficLight
          "trafficlight@bitdefender.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/trafficlight/latest.xpi";
            installation_mode = "force_installed";
          };
          # Live Stream Downloader
          "{2ea2bfef-af69-4427-909c-34e1f3f5a418}" = {
            install_url = "http://addons.mozilla.org/firefox/downloads/latest/live-stream-downloader/latest.xpi";
            installation_mode = "force_installed";
          };
          # TWP - Translate Web Pages
          "{036a55b4-5e72-4d05-a06c-cba2dfcc134a}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/traduzir-paginas-web/latest.xpi";
            installation_mode = "force_installed";
          };
          # Plasma Integration
          "plasma-browser-integration@kde.org" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/plasma-integration/latest.xpi";
            installation_mode = "force_installed";
          };
        };
      };
    };
  };

  # Za brži KDE ###################################################################################
  nixpkgs.overlays = lib.singleton (final: prev: {
    kdePackages = prev.kdePackages // {
      plasma-workspace = let

        # the package we want to override
        basePkg = prev.kdePackages.plasma-workspace;

        # a helper package that merges all the XDG_DATA_DIRS into a single directory
        xdgdataPkg = pkgs.stdenv.mkDerivation {
          name = "${basePkg.name}-xdgdata";
          buildInputs = [ basePkg ];
          dontUnpack = true;
          dontFixup = true;
          dontWrapQtApps = true;
          installPhase = ''
            mkdir -p $out/share
            ( IFS=:
              for DIR in $XDG_DATA_DIRS; do
                if [[ -d "$DIR" ]]; then
                  cp -r $DIR/. $out/share/
                  chmod -R u+w $out/share
                fi
              done
            )
          '';
        };

        # undo the XDG_DATA_DIRS injection that is usually done in the qt wrapper
        # script and instead inject the path of the above helper package
        derivedPkg = basePkg.overrideAttrs {
          preFixup = ''
            for index in "''${!qtWrapperArgs[@]}"; do
              if [[ ''${qtWrapperArgs[$((index+0))]} == "--prefix" ]] && [[ ''${qtWrapperArgs[$((index+1))]} == "XDG_DATA_DIRS" ]]; then
                unset -v "qtWrapperArgs[$((index+0))]"
                unset -v "qtWrapperArgs[$((index+1))]"
                unset -v "qtWrapperArgs[$((index+2))]"
                unset -v "qtWrapperArgs[$((index+3))]"
              fi
            done
            qtWrapperArgs=("''${qtWrapperArgs[@]}")
            qtWrapperArgs+=(--prefix XDG_DATA_DIRS : "${xdgdataPkg}/share")
            qtWrapperArgs+=(--prefix XDG_DATA_DIRS : "$out/share")
          '';
        };

      in derivedPkg;
    };
  });

  #############################################################################################

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
    networking.firewall.allowedTCPPorts = [ 
    8888 
    3129 
    ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
