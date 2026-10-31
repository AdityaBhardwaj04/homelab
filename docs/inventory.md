# Homelab Inventory

**Snapshot date:** October 29, 2026
**Method:** Read-only inspection of the Proxmox VE web dashboard. I made no configuration changes.

> **Read this as a historical record.** Resource usage, VM status, uptime, and software versions change over time. Nothing below should be taken as the current state unless it's been re-verified and re-dated.

> **Update, evening of October 29, 2026:** Several items below have since been verified or changed: the guest egress path (now verified NAT), the firewall (now enabled and enforced per VM), SSH settings, and VM 101 (destroyed and rebuilt). The changes are listed in [Changes since the snapshot](#changes-since-the-snapshot), and the full story is in the [access and network hardening write-up](hardening/2026-10-29-access-and-network-hardening.md). I've left the sections below exactly as observed so the record stays honest.

Each section separates:

- **Observed:** shown directly in the Proxmox dashboard on the snapshot date.
- **Inferred:** a reasonable conclusion from what I observed, but not directly confirmed.
- **Unknown:** not visible from the dashboard; needs checking on the host or inside the guest.

I've left out IP addresses, MAC addresses, overlay-VPN addresses, disk serials, UUIDs, and management access details on purpose.

---

## 1. Hypervisor

### Observed

| Item | Value |
|---|---|
| Platform | Proxmox VE 8.4.21 (`pve-manager/8.4.21`) |
| Kernel | Linux 6.8.12-43-pve |
| Base OS | Debian 12 "Bookworm" (from the configured APT suites) |
| Topology | Single standalone node, no cluster |
| HA / Ceph / replication | None configured |
| Boot mode | UEFI |
| Uptime at snapshot | ~16 days |
| Package repositories | Proxmox `pve-no-subscription`, plus Debian main, updates, and security |
| Dashboard warnings | A lifecycle warning about Proxmox VE 8 |

### Lifecycle check

I checked the official [Proxmox VE FAQ](https://pve.proxmox.com/wiki/FAQ) on **October 29, 2026**. Its support table lists:

| Proxmox VE | Debian base | First release | Debian EOL | Proxmox EOL |
|---|---|---|---|---|
| 8 | Debian 12 (Bookworm) | 2023-06 | 2026-07 | 2026-08 |
| 9 | Debian 13 (Trixie) | 2025-08 | tba | tba |

Two separate facts follow from this:

- **The installed major version is past end of life.** Proxmox VE 8 reached EOL in August 2026, so the host is no longer on a supported release line. That's almost certainly what the dashboard warning refers to.
- **Newer releases exist.** The [Proxmox VE roadmap](https://pve.proxmox.com/wiki/Roadmap) lists Proxmox VE 9.2 (May 21, 2026) as the latest x86-64 release at the time of checking.

Upgrading is a roadmap item, not something I've done. Prerequisites and approach are in [roadmap.md](roadmap.md#2-plan-a-supported-proxmox-upgrade).

---

## 2. Physical host

### Observed

| Item | Value |
|---|---|
| CPU | AMD Ryzen 7 5700U |
| Sockets / logical CPUs | 1 socket, 16 logical CPUs |
| Usable RAM | ~14.97 GiB |
| Swap | 8 GiB, 0% used |
| CPU usage at snapshot | ~1% |
| Memory usage at snapshot | ~72% (10.8 of 15 GiB) |
| IO delay | 0% |
| Load average | ~0.2 |
| KSM sharing | 0 B |
| Assigned to guests | ~7 of 16 logical CPUs, ~9 of 15 GiB RAM |

### Inferred

- **8 cores / 16 threads.** This comes from AMD's specification for the 5700U. The dashboard only shows 16 logical CPUs.
- **Repurposed laptop.** I'm inferring this from the mobile CPU and the Wi-Fi network interface.

### Notes

- Guest allocations (7 vCPUs, 9 GiB) fit comfortably within the host. Most of the 72% host memory usage comes from the running VMs.
- KSM was at 0 B. That's expected with only two dissimilar guests and memory well below the KSM threshold.

---

## 3. Virtual machines

No LXC containers were present. Two QEMU/KVM VMs were configured.

### VM 100: `Kali`

| Item | Observed value |
|---|---|
| Status at snapshot | Running (~1 day uptime) |
| vCPUs | 6 (1 socket × 6 cores), default CPU type |
| RAM | 8 GiB |
| Disk | 200 GiB on `local-lvm`, VirtIO SCSI |
| Network | VirtIO NIC on `vmbr0` |
| VM firewall flag | **Off** |
| Start at boot | Enabled |
| QEMU guest agent | Not configured |
| Firmware / machine | SeaBIOS / i440fx |
| Proxmox OS type | `Other` |
| Snapshots | None |

**Inferred:** The guest is Kali Linux, based on the VM name. Its role is my security-testing workstation.

**Unknown:** The actual guest OS release and installed tooling. Proxmox's OS type is `Other` and there's no guest agent, so the dashboard can't confirm either.

### VM 101: `cy5001-docker`

| Item | Observed value |
|---|---|
| Status at snapshot | Running (~2 hours uptime) |
| vCPUs | 1, CPU type `host` |
| RAM | 1 GiB, ~88% used at snapshot |
| Disk | 8 GiB on `local-lvm`, VirtIO SCSI, iothread enabled |
| Network | VirtIO NIC on `vmbr0` |
| VM firewall flag | **On** |
| Start at boot | Disabled |
| QEMU guest agent | Not configured |
| Firmware / machine | SeaBIOS / i440fx |
| Proxmox OS type | Linux 6.x |
| Installation media | Debian 13 netinst ISO still attached |
| Snapshots | None |

**Inferred:** This is the Debian-based Docker host for my CY5001 coursework. A Debian 13 ISO was attached, and the task log showed related tasks on October 28, 2026.

**Unknown:**

- The installed guest OS version. The attached ISO suggests Debian 13 but doesn't prove what's installed.
- Whether Docker is installed and running right now, and which containers exist.
- Whether this VM is the same `cy5001-docker` machine I used for the [Apache HTTPS project](../README.md#projects). The hostname matches, but I haven't confirmed that the two are the same installation.

---

## 4. Storage

### Physical disk (observed)

| Item | Value |
|---|---|
| Device | One NVMe SSD, ~512 GB, Micron |
| Partition table | GPT |
| Partitions | 1 MB BIOS boot, 1 GB EFI system, ~511 GB LVM physical volume |
| SMART status | PASSED |
| Dashboard "Wearout" | 12% |

The Wearout figure needs checking. I haven't yet confirmed whether Proxmox derives it from the NVMe *Percentage Used* attribute (so roughly 12% of rated endurance consumed) or presents it some other way. I'll confirm with `smartctl -a` on the host before attaching a meaning to it.

### LVM (observed)

| Item | Value |
|---|---|
| Volume group | `pve`, ~511 GB |
| Logical volumes | 5 |
| VG allocated | ~97% (~17 GB free) |
| Thin pool `data` | ~374.5 GB, ~26% data used (~98 GB), ~1% metadata used |
| Root filesystem | ~93.9 GiB, ~5% used |

**Inferred:** The five logical volumes are most likely the standard `root`, `swap`, and `data` thin pool, plus one thin volume per VM disk. I didn't list them individually.

**Note on units:** The dashboard mixes GB and GiB across views, so these totals won't add up exactly.

### Proxmox storage backends (observed)

| Storage | Type | Size | Used | Content | Shared |
|---|---|---|---|---|---|
| `local` | Directory (`/var/lib/vz`) | ~101 GB | ~5% | Backups, ISO images, container templates | No |
| `local-lvm` | LVM-Thin | ~375 GB | ~26% | VM disks, container volumes | No |

- **Not present:** ZFS, Ceph, NFS, SMB/CIFS, iSCSI, extra directory storage, or Proxmox Backup Server.
- **ISO images:** one (Debian 13.7 netinst).
- **Container templates:** none.
- **Provisioning:** 208 GiB of virtual disk (200 + 8) against a ~375 GB thin pool. The pool wasn't overcommitted.

### Risk

Everything depends on one NVMe drive: the hypervisor, both VM disks, and the `local` backup target. If that drive fails, the whole lab is lost. Any backup stored on `local` would be lost with it, so backups need to go off this disk to count.

---

## 5. Networking

### Observed

| Item | Value |
|---|---|
| Bridge | `vmbr0`, Linux bridge, active, autostart |
| VLAN-aware | No |
| Bridge ports | None listed |
| Physical NIC | One Wi-Fi interface, active, autostart |
| VLAN interfaces | None |
| SDN zones / VNets | None (built-in `localnetwork` present, status OK) |
| Guest attachments | Both VMs on `vmbr0` |

### Firewall (observed October 29, 2026; not verified as current)

> These are the firewall settings shown in the dashboard on the snapshot date. They describe that moment only. I haven't re-checked them since, and they may have changed.

| Scope | State at snapshot |
|---|---|
| Datacenter firewall | **Disabled** |
| Datacenter policies | Input DROP, Output ACCEPT, Forward ACCEPT, but not enforced because the firewall is disabled |
| Datacenter rules | None |
| Node rules | None |
| VM 100 (Kali) firewall flag | Off |
| VM 101 (Docker) firewall flag | On |

The VM 101 flag only has an effect if the datacenter firewall is enabled. With the datacenter firewall disabled, I don't expect any Proxmox firewall filtering to be in effect for either VM. I still need to verify that.

### Inferred / unknown

- **Routing and NAT.** `vmbr0` has no physical port, and the only physical uplink is Wi-Fi. Wi-Fi interfaces generally can't be bridged directly, so I believe `vmbr0` is an internal network that the host routes or NATs out over Wi-Fi. The dashboard doesn't show how (or whether) that's configured. **Unverified.**
- **Management access.** I reached the web UI over a private VPN overlay, and that VPN's APT repository is present on the host. That points to VPN-based remote management, but I haven't confirmed the service's status or role from the host itself.
- **Guest addresses and services.** Unknown. Without the guest agent, Proxmox can't report them.

---

## 6. Backups and recovery (observed October 29, 2026; not verified as current)

> These findings describe what the dashboard showed on the snapshot date. They aren't a statement about current conditions. Backup jobs or archives may have been added since, or may exist somewhere the dashboard view didn't cover.

At the snapshot:

- No scheduled backup jobs.
- No backup archives on `local`.
- No backup archives for VM 100 or VM 101.
- No VM snapshots.
- No Proxmox Backup Server or off-host backup destination.
- No replication.

**On the snapshot date, I saw no recovery points at all for either VM.** If that's still true, it's the biggest gap in the lab, and it's the first item on the [roadmap](roadmap.md#1-establish-backups-and-test-recovery). I'll re-verify before describing it as the current state.

---

## 7. Other observations

- The task log showed a web shell session started on October 13, 2026 still marked as running. It's probably stale. I've left it alone for now and noted it for review.
- The Debian 13 installer ISO was still attached to VM 101 at the snapshot.

---

## Summary

Everything in this table reflects the October 29, 2026 snapshot, not verified current conditions.

| Area | State at snapshot (Oct 29, 2026) |
|---|---|
| Hypervisor | Proxmox VE 8.4.21 on Debian 12, single node, **past EOL** |
| Compute | Ryzen 7 5700U, 16 logical CPUs, ~15 GiB RAM, lightly loaded |
| Storage | Single NVMe, LVM-Thin, plenty of free capacity, **single point of failure** |
| VMs | Kali (6 vCPU / 8 GiB / 200 GiB), cy5001-docker (1 vCPU / 1 GiB / 8 GiB) |
| Network | One unsegmented bridge, Wi-Fi uplink, routing path unverified |
| Firewall | Datacenter firewall disabled, no rules |
| Backups | **None visible** |

---

## Changes since the snapshot

Verified from command output on the host and in the guests on the **evening of October 29, 2026**. Details: [access and network hardening](hardening/2026-10-29-access-and-network-hardening.md).

| Area | Snapshot (earlier Oct 29) | After the evening session |
|---|---|---|
| Guest egress | Routing/NAT inferred, unverified | **Verified:** internal bridge on a private /24, IP forwarding on, `MASQUERADE` out through Wi-Fi, `dnsmasq` for guest DHCP and DNS |
| Datacenter firewall | Disabled, no rules | Enabled, input DROP, management ports allowed only from my admin laptop |
| Overlay VPN | Inferred from its repository | Verified running on the host and on Kali. Its access policy changed from allow-all to an explicit, tested allow-list |
| VM 100 `Kali` firewall flag | Off | **On**, with an isolation policy: internet only; no host, no home LAN, no other guests |
| NAT with VM firewalls | — | Fixed: conntrack-zone rule for firewall bridges, persisted in the network config |
| Host SSH | Not visible from the dashboard | Root key-only (explicit), password authentication off |
| Kali SSH | Not visible from the dashboard | Dedicated key only; password and root login disabled |
| Kali guest OS | Unknown | Kernel `7.1.5+kali-amd64` |
| VM 101 | 1 vCPU / 1 GiB / 8 GiB, Debian 13 ISO attached, firewall flag on | **Destroyed and rebuilt:** minimal Debian 13 (no desktop), kernel `6.12.113+deb13-amd64`, firewall flag on, firewall rules file present on the host, 1 vCPU / 2 GiB / 16 GiB (verified Oct 30) |
| Backups | None visible | Unchanged on Oct 29. **On Oct 30:** verified backups of both VMs on an offline external drive, and a Kali restore tested ([write-up](backup/2026-10-30-backups-and-restore-test.md)) |
