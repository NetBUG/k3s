# __generated__ by OpenTofu
# Please review these resources and move them into your main configuration files.

# __generated__ by OpenTofu from "e14cf3ca-00b7-4c09-9ca2-bbeef80f84ef"
resource "libvirt_domain" "node01" {
  autostart         = true
  bhyve_commandline = null
  block_io_tune     = null
  bootloader        = null
  bootloader_args   = null
  clock = {
    adjustment = null
    basis      = null
    offset     = "utc"
    start      = null
    time_zone  = null
    timer = [
      {
        catch_up    = null
        frequency   = null
        mode        = null
        name        = "rtc"
        present     = null
        tick_policy = "catchup"
        track       = null
      },
      {
        catch_up    = null
        frequency   = null
        mode        = null
        name        = "pit"
        present     = null
        tick_policy = "delay"
        track       = null
      },
      {
        catch_up    = null
        frequency   = null
        mode        = null
        name        = "hpet"
        present     = "no"
        tick_policy = null
        track       = null
      },
    ]
  }
  cpu = {
    cache               = null
    check               = "none"
    deprecated_features = null
    features            = null
    match               = null
    max_phys_addr       = null
    migratable          = false
    mode                = "host-passthrough"
    model               = null
    model_fallback      = null
    model_vendor_id     = null
    numa                = null
    topology            = null
    vendor              = null
  }
  cpu_tune            = null
  create              = null
  current_memory      = 8388608
  current_memory_unit = "KiB"
  default_io_thread   = null
  description         = null
  destroy             = null
  devices = {
    audios = [
      {
        alsa       = null
        core_audio = null
        dbus       = null
        file       = null
        id         = 1
        jack       = null
        none = {
          input  = null
          output = null
        }
        oss          = null
        pipe_wire    = null
        pulse_audio  = null
        sdl          = null
        spice        = null
        timer_period = null
      },
    ]
    channels = [
      {
        acpi = null
        address = {
        }
        alias = {
          name = "channel0"
        }
        log      = null
        protocol = null
        source = {
          dbus          = null
          dev           = null
          file          = null
          nmdm          = null
          null          = false
          pipe          = null
          pty           = null
          qemu_vd_agent = null
          spice_port    = null
          spice_vmc     = false
          std_io        = false
          tcp           = null
          udp           = null
          unix = {
            mode      = "bind"
            path      = "/var/lib/libvirt/qemu/channel/target/domain-4-UbuntuK3S/org.qemu.guest_agent.0"
            reconnect = null
            sec_label = null
          }
          vc = false
        }
        target = {
          guest_fwd = null
          virt_io = {
            name  = "org.qemu.guest_agent.0"
            state = "disconnected"
          }
          xen = null
        }
      },
    ]
    consoles = [
      {
        acpi    = null
        address = null
        alias = {
          name = "serial0"
        }
        log      = null
        protocol = null
        source = {
          dbus = null
          dev  = null
          file = null
          nmdm = null
          null = false
          pipe = null
          pty = {
            path      = "/dev/pts/3"
            sec_label = null
          }
          qemu_vd_agent = null
          spice_port    = null
          spice_vmc     = false
          std_io        = false
          tcp           = null
          udp           = null
          unix          = null
          vc            = false
        }
        target = {
          port = 0
          type = "serial"
        }
        tty = "/dev/pts/3"
      },
    ]
    controllers = [
      {
        acpi = null
        address = {
        }
        alias = {
          name = "usb"
        }
        driver = null
        index  = 0
        model  = "qemu-xhci"
        nvme   = null
        pci    = null
        type   = "usb"
        usb = {
          master = null
          port   = 15
        }
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi    = null
        address = null
        alias = {
          name = "pcie.0"
        }
        driver = null
        index  = 0
        model  = "pcie-root"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model       = null
          target      = null
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.1"
        }
        driver = null
        index  = 1
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.2"
        }
        driver = null
        index  = 2
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.3"
        }
        driver = null
        index  = 3
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.4"
        }
        driver = null
        index  = 4
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.5"
        }
        driver = null
        index  = 5
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.6"
        }
        driver = null
        index  = 6
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.7"
        }
        driver = null
        index  = 7
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.8"
        }
        driver = null
        index  = 8
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.9"
        }
        driver = null
        index  = 9
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.10"
        }
        driver = null
        index  = 10
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.11"
        }
        driver = null
        index  = 11
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.12"
        }
        driver = null
        index  = 12
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.13"
        }
        driver = null
        index  = 13
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "pci.14"
        }
        driver = null
        index  = 14
        model  = "pcie-root-port"
        nvme   = null
        pci = {
          hole64      = null
          hole64_unit = null
          model = {
            name = "pcie-root-port"
          }
          target = {
          }
        }
        type           = "pci"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "ide"
        }
        driver         = null
        index          = 0
        model          = null
        nvme           = null
        pci            = null
        type           = "sata"
        usb            = null
        virt_io_serial = null
        xen_bus        = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "virtio-serial0"
        }
        driver = null
        index  = 0
        model  = null
        nvme   = null
        pci    = null
        type   = "virtio-serial"
        usb    = null
        virt_io_serial = {
          ports   = null
          vectors = null
        }
        xen_bus = null
      },
    ]
    crypto = null
    disks = [
      {
        acpi = null
        address = {
        }
        alias = {
          name = "virtio-disk0"
        }
        auth           = null
        backend_domain = null
        backing_store = {
          format = null
          index  = null
          source = {
            block          = null
            cookies        = null
            data_store     = null
            dir            = null
            encryption     = null
            file           = null
            index          = null
            network        = null
            nvme           = null
            readahead      = null
            reservations   = null
            slices         = null
            ssl            = null
            startup_policy = null
            timeout        = null
            vhost_user     = null
            vhost_vdpa     = null
            volume         = null
          }
        }
        block_io = null
        boot     = null
        device   = "disk"
        driver = {
          ats              = null
          cache            = null
          copy_on_read     = null
          detect_zeros     = null
          discard          = "unmap"
          discard_no_unref = null
          error_policy     = null
          event_idx        = null
          io               = null
          io_event_fd      = null
          io_thread        = null
          io_threads       = null
          iommu            = null
          metadata_cache   = null
          name             = "qemu"
          packed           = null
          page_per_vq      = null
          queue_size       = null
          queues           = null
          rerror_policy    = null
          type             = "qcow2"
        }
        encryption = null
        geometry   = null
        io_tune    = null
        mirror     = null
        model      = null
        product    = null
        raw_io     = null
        read_only  = false
        serial     = null
        sgio       = null
        shareable  = false
        snapshot   = null
        source = {
          block      = null
          cookies    = null
          data_store = null
          dir        = null
          encryption = null
          file = {
            fd_group  = null
            file      = "/media/DATA/.libvirt/images/UbuntuK3S.qcow2"
            sec_label = null
          }
          index          = 2
          network        = null
          nvme           = null
          readahead      = null
          reservations   = null
          slices         = null
          ssl            = null
          startup_policy = null
          timeout        = null
          vhost_user     = null
          vhost_vdpa     = null
          volume         = null
        }
        target = {
          bus           = "virtio"
          dev           = "vda"
          removable     = null
          rotation_rate = null
          tray          = null
        }
        throttle_filters = null
        transient        = null
        vendor           = null
        wwn              = null
      },
      {
        acpi = null
        address = {
        }
        alias = {
          name = "sata0-0-0"
        }
        auth           = null
        backend_domain = null
        backing_store  = null
        block_io       = null
        boot           = null
        device         = "cdrom"
        driver = {
          ats              = null
          cache            = null
          copy_on_read     = null
          detect_zeros     = null
          discard          = null
          discard_no_unref = null
          error_policy     = null
          event_idx        = null
          io               = null
          io_event_fd      = null
          io_thread        = null
          io_threads       = null
          iommu            = null
          metadata_cache   = null
          name             = "qemu"
          packed           = null
          page_per_vq      = null
          queue_size       = null
          queues           = null
          rerror_policy    = null
          type             = null
        }
        encryption = null
        geometry   = null
        io_tune    = null
        mirror     = null
        model      = null
        product    = null
        raw_io     = null
        read_only  = true
        serial     = null
        sgio       = null
        shareable  = false
        snapshot   = null
        source = {
          block      = null
          cookies    = null
          data_store = null
          dir        = null
          encryption = null
          file = {
            fd_group  = null
            file      = null
            sec_label = null
          }
          index          = null
          network        = null
          nvme           = null
          readahead      = null
          reservations   = null
          slices         = null
          ssl            = null
          startup_policy = null
          timeout        = null
          vhost_user     = null
          vhost_vdpa     = null
          volume         = null
        }
        target = {
          bus           = "sata"
          dev           = "sda"
          removable     = null
          rotation_rate = null
          tray          = null
        }
        throttle_filters = null
        transient        = null
        vendor           = null
        wwn              = null
      },
    ]
    emulator    = "/usr/bin/qemu-system-x86_64"
    filesystems = null
    graphics = [
      {
        audio        = null
        dbus         = null
        desktop      = null
        egl_headless = null
        rdp          = null
        sdl          = null
        spice        = null
        vnc = {
          auto_port = true
          connected = null
          keymap    = null
          listen    = "127.0.0.1"
          listeners = [
            {
              address = {
                address = "127.0.0.1"
              }
              network = null
              socket  = null
            },
          ]
          passwd          = null
          passwd_valid_to = null
          port            = 5905
          power_control   = null
          share_policy    = null
          socket          = null
          web_socket      = null
        }
      },
    ]
    hostdevs = null
    hubs     = null
    inputs = [
      {
        acpi = null
        address = {
        }
        alias = {
          name = "input0"
        }
        bus    = "usb"
        driver = null
        model  = null
        source = {
          ev_dev      = null
          passthrough = null
        }
        type = "tablet"
      },
      {
        acpi    = null
        address = null
        alias = {
          name = "input1"
        }
        bus    = "ps2"
        driver = null
        model  = null
        source = {
          ev_dev      = null
          passthrough = null
        }
        type = "mouse"
      },
      {
        acpi    = null
        address = null
        alias = {
          name = "input2"
        }
        bus    = "ps2"
        driver = null
        model  = null
        source = {
          ev_dev      = null
          passthrough = null
        }
        type = "keyboard"
      },
    ]
    interfaces = [
      {
        acpi = null
        address = {
        }
        alias = {
          name = "net0"
        }
        backend        = null
        backend_domain = null
        bandwidth      = null
        boot           = null
        coalesce       = null
        down_script    = null
        driver         = null
        filter_ref     = null
        guest          = null
        ip             = null
        link           = null
        mac = {
          address = "52:54:00:5c:55:98"
          check   = null
          type    = null
        }
        managed = null
        model = {
          type = "virtio"
        }
        mtu          = null
        port_forward = null
        port_options = null
        rom          = null
        route        = null
        script       = null
        source = {
          bridge   = null
          client   = null
          direct   = null
          ethernet = null
          hostdev  = null
          internal = null
          mcast    = null
          network = {
            bridge     = "virbr0"
            network    = "default"
            port_group = null
            port_id    = "1b4ad2ee-9c3c-46cc-8be3-40994f46cad8"
          }
          null       = false
          server     = null
          udp        = null
          user       = null
          vdpa       = null
          vds        = null
          vhost_user = null
        }
        target = {
          dev     = "vnet3"
          managed = null
        }
        teaming                = null
        trust_guest_rx_filters = null
        tune                   = null
        virtual_port           = null
        vlan                   = null
        wait_for_ip            = null
      },
    ]
    iommu  = null
    leases = null
    mem_balloon = {
      acpi = null
      address = {
      }
      alias = {
        name = "balloon0"
      }
      auto_deflate        = null
      driver              = null
      free_page_reporting = null
      model               = "virtio"
      stats = {
        period = 10
      }
    }
    memorydevs    = null
    nvram         = null
    panics        = null
    parallels     = null
    pstore        = null
    redir_devs    = null
    redir_filters = null
    rngs = [
      {
        acpi = null
        address = {
        }
        alias = {
          name = "rng0"
        }
        backend = {
          built_in = false
          egd      = null
          random   = "/dev/urandom"
        }
        driver = null
        model  = "virtio"
        rate   = null
      },
    ]
    serials = [
      {
        acpi    = null
        address = null
        alias = {
          name = "serial0"
        }
        log      = null
        protocol = null
        source = {
          dbus = null
          dev  = null
          file = null
          nmdm = null
          null = false
          pipe = null
          pty = {
            path      = "/dev/pts/3"
            sec_label = null
          }
          qemu_vd_agent = null
          spice_port    = null
          spice_vmc     = false
          std_io        = false
          tcp           = null
          udp           = null
          unix          = null
          vc            = false
        }
        target = {
          model = {
            name = "isa-serial"
          }
          port = 0
          type = "isa-serial"
        }
      },
    ]
    shmems     = null
    smartcards = null
    sounds     = null
    tpms       = null
    videos = [
      {
        acpi = null
        address = {
        }
        alias = {
          name = "video0"
        }
        driver = null
        model = {
          accel      = null
          blob       = null
          edid       = null
          heads      = 1
          primary    = "yes"
          ram        = null
          resolution = null
          type       = "virtio"
          vga_mem    = null
          vram       = null
          vram64     = null
        }
      },
    ]
    vsock     = null
    watchdogs = null
  }
  features = {
    acpi = true
    aia  = null
    apic = {
      eoi = null
    }
    async_teardown = null
    capabilities   = null
    ccf_assist     = null
    cfpc           = null
    gic            = null
    hap            = null
    hpt            = null
    htm            = null
    hyper_v        = null
    ibs            = null
    ioapic         = null
    kvm            = null
    msrs           = null
    nested_hv      = null
    pae            = false
    pmu            = null
    priv_net       = false
    ps2            = null
    pv_spinlock    = null
    ras            = null
    sbbc           = null
    smm            = null
    tcg            = null
    viridian       = false
    vm_core_info   = null
    vm_port        = null
    xen            = null
  }
  gen_id               = null
  hwuuid               = null
  id_map               = null
  io_thread_i_ds       = null
  io_threads           = null
  key_wrap             = null
  launch_security      = null
  lxc_namespace        = null
  maximum_memory       = null
  maximum_memory_slots = null
  maximum_memory_unit  = null
  memory               = 8388608
  memory_backing       = null
  memory_dump_core     = null
  memory_tune          = null
  memory_unit          = "KiB"
  metadata = {
    xml = "\n    <libosinfo:libosinfo>\n      <libosinfo:os id=\"http://ubuntu.com/ubuntu/25.04\"/>\n    </libosinfo:libosinfo>\n    <cockpit_machines:data>\n      <cockpit_machines:has_install_phase>false</cockpit_machines:has_install_phase>\n      <cockpit_machines:install_source_type>file</cockpit_machines:install_source_type>\n      <cockpit_machines:install_source>/media/DATA/ISO/ubuntu-26.04-live-server-amd64.iso</cockpit_machines:install_source>\n      <cockpit_machines:os_variant>ubuntu25.04</cockpit_machines:os_variant>\n    </cockpit_machines:data>\n  "
  }
  name        = "UbuntuK3S"
  numa_tune   = null
  on_crash    = "destroy"
  on_poweroff = "destroy"
  on_reboot   = "restart"
  os = {
    acpi = null
    bios = null
    boot_devices = [
      {
        dev = "hd"
      },
    ]
    boot_menu        = null
    cmdline          = null
    dtb              = null
    firmware         = null
    firmware_info    = null
    init             = null
    init_args        = null
    init_dir         = null
    init_env         = null
    init_group       = null
    init_user        = null
    initrd           = null
    kernel           = null
    loader           = null
    loader_format    = null
    loader_readonly  = null
    loader_secure    = null
    loader_stateless = null
    loader_type      = null
    nv_ram           = null
    shim             = null
    sm_bios          = null
    type             = "hvm"
    type_arch        = "x86_64"
    type_machine     = "pc-q35-6.2"
  }
  perf = null
  pm = {
    suspend_to_disk = {
      enabled = "no"
    }
    suspend_to_mem = {
      enabled = "no"
    }
  }
  qemu_capabilities = null
  qemu_commandline  = null
  qemu_deprecation  = null
  qemu_override     = null
  resource = {
    fibre_channel = null
    partition     = "/machine"
  }
  running = true
  sec_label = [
    {
      base_label  = null
      image_label = "libvirt-e14cf3ca-00b7-4c09-9ca2-bbeef80f84ef"
      label       = "libvirt-e14cf3ca-00b7-4c09-9ca2-bbeef80f84ef"
      model       = "apparmor"
      relabel     = "yes"
      type        = "dynamic"
    },
    {
      base_label  = null
      image_label = "+64055:+109"
      label       = "+64055:+109"
      model       = "dac"
      relabel     = "yes"
      type        = "dynamic"
    },
  ]
  sys_info                = null
  throttle_groups         = null
  title                   = null
  type                    = "kvm"
  update                  = null
  vcpu                    = 2
  vcpu_cpuset             = null
  vcpu_current            = null
  vcpu_placement          = "static"
  vcpus                   = null
  vmware_data_center_path = null
  xen_commandline         = null
}
