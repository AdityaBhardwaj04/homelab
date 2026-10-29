# Architecture Overview

This page describes how the lab fits together and why it's built this way. It's based on the **October 29, 2026 inventory snapshot** ([inventory.md](../inventory.md)). Anything that may have changed since then is labelled as a snapshot observation, not current state.

How to read this page:

- **Observed:** shown in the Proxmox dashboard on the snapshot date.
- **Inferred:** my best interpretation of what I observed, not directly confirmed.
- **Unknown:** not visible from the dashboard; needs checking on the host or inside a guest.

I've deliberately left out IP addresses, VPN details, MAC addresses, disk serials, and management access instructions.

## Topology

Solid lines are relationships I observed in the Proxmox configuration. **The dashed line is unverified.** I believe guest traffic leaves the host through Wi-Fi via routing or NAT, but I haven't confirmed that from the host's network configuration.

```mermaid
flowchart TB
    subgraph host["Proxmox VE host · standalone node · repurposed laptop"]
        hw["AMD Ryzen 7 5700U · 16 logical CPUs<br/>~15 GiB RAM<br/>single ~512 GB NVMe SSD"]
        subgraph storage["LVM on the single NVMe"]
            lvm[("local-lvm<br/>LVM-Thin · VM disks")]
            local[("local<br/>directory · ISOs, backups")]
        end
        br{{"vmbr0 · Linux bridge<br/>no physical port attached"}}
        kali["VM: Kali<br/>security testing<br/>6 vCPU · 8 GiB · 200 GiB"]
        dock["VM: cy5001-docker<br/>Debian · intended Docker host<br/>1 vCPU · 1 GiB · 8 GiB"]
        wifi["Wi-Fi interface<br/>host's physical uplink"]
    end
    up(["Upstream network"])

    kali -->|virtual disk| lvm
    dock -->|virtual disk| lvm
    kali ---|VirtIO NIC| br
    dock ---|VirtIO NIC| br
    br -.->|"routing / NAT through host?<br/>UNVERIFIED"| wifi
    wifi --- up
```

## Components at a glance

| Layer | Snapshot state (Oct 29, 2026) | Status |
|---|---|---|
| Hardware | Ryzen 7 5700U, 16 logical CPUs, ~15 GiB RAM, one ~512 GB NVMe | Observed |
| Hypervisor | Proxmox VE 8.4.21 on Debian 12, single standalone node | Observed |
| Storage | LVM VG `pve`, LVM-Thin pool for VM disks, directory storage for ISOs/backups | Observed |
| Compute guests | VM 100 `Kali`, VM 101 `cy5001-docker` | Observed (config); guest OS inferred |
| Network | Linux bridge `vmbr0` with no physical port; Wi-Fi as the physical uplink | Observed |
| Guest egress path | Routed or NATed through the host | **Inferred, unverified** |
| Firewall | Datacenter firewall disabled at the snapshot | Observed (historical) |
| Backups | None visible at the snapshot | Observed (historical) |

## Design decisions and trade-offs

### A single-node hypervisor on a laptop

**What:** One standalone Proxmox node on what appears to be a repurposed laptop. The mobile CPU and the Wi-Fi interface are why I believe it's a laptop. No cluster, HA, Ceph, or replication.

**Why it works for a lab:**

- It reuses hardware I already had.
- It's quiet and low-power.
- A Ryzen 7 5700U with 16 logical CPUs is plenty for a few VMs.
- A laptop has a built-in screen and keyboard. That gives me local console access if remote access breaks, which matters for the upgrade and firewall work on the [roadmap](../roadmap.md).

**What it costs:**

- **No redundancy.** One host, one disk, one network interface. Any hardware fault takes the whole lab down. HA and live migration aren't possible.
- **Laptop constraints.** It has limited RAM and little room for extra internal disks, and the only physical network interface in the inventory is Wi-Fi. Laptop thermals and power management weren't designed for a host that's always on.
- **Single-node simplicity is also a benefit.** There's no quorum or cluster networking to manage, so there's less to break while I'm learning.

This is fine for learning and coursework. It's not a design I'd run anything important on.

### CPU and RAM allocation

**Observed:** Guests were assigned about 7 of 16 logical CPUs (Kali 6, Docker VM 1) and about 9 of ~15 GiB RAM (Kali 8 GiB, Docker VM 1 GiB). Host memory usage was about 72% (10.8 GiB). CPU usage was about 1%, and swap usage was 0%.

**Trade-offs:**

- **CPU isn't overcommitted.** The 7 assigned vCPUs fit within 16 logical CPUs, and load was negligible. There's room for more guests on the CPU side.
- **Memory is the real constraint.** About 15 GiB is usable, and 9 GiB was already assigned. At the snapshot that left roughly 4 GiB free for the host and any new guests. The next VM will be limited by memory, not CPU.
- **The allocation is lopsided.** Kali gets most of the resources, which suits interactive security tooling. The Docker VM got 1 GiB and was at about 88% memory use. That's tight for Docker. Raising it is [roadmap item 6](../roadmap.md#6-right-size-memory-for-vm-101).
- **CPU types differ.** Kali uses Proxmox's default CPU model. The Docker VM uses `host`, which passes the physical CPU's full feature set through. `host` gives the best compatibility and performance but ties a guest to this CPU model. With a single node and no migration, that's a cost I don't pay.

### LVM-Thin storage on a single NVMe

**Observed:** One ~512 GB NVMe holds a GPT layout with EFI and BIOS boot partitions and an LVM physical volume. The `pve` volume group carries the root filesystem (`local` directory storage) and a ~374.5 GB thin pool (`local-lvm`) for VM disks. The thin pool was about 26% used and not overcommitted. 208 GiB of virtual disk was provisioned.

**Why LVM-Thin:** It's the Proxmox installer's default storage layout when ZFS isn't selected. It thin-provisions, so a 200 GiB virtual disk only uses what the guest has written. It also supports snapshots, which Proxmox uses for snapshot-mode backups.

**Trade-offs:**

- **Thin provisioning can overcommit.** It wasn't overcommitted at the snapshot. But if virtual disks are later allowed to exceed the pool and the pool fills up, writes fail for every guest at once. Pool usage needs watching as the lab grows.
- **No ZFS.** ZFS would add checksumming and send/receive replication, but it needs more RAM, and RAM is already the tightest resource. With a single disk it would detect corruption but couldn't repair it.
- **A single disk is a single point of failure.** The hypervisor, both VM disks, and the `local` storage that holds backups all sit on one drive. A backup kept on `local` protects against a bad change, but not against losing the drive.

### VM roles

| VM | Role | Observed | Inferred / unknown |
|---|---|---|---|
| 100 `Kali` | Security-testing workstation | 6 vCPU, 8 GiB, 200 GiB, firewall flag off, starts at boot, OS type `Other` | Kali Linux is inferred from the name. Guest release and tooling unknown. |
| 101 `cy5001-docker` | Docker host for coursework | 1 vCPU (`host`), 1 GiB, 8 GiB, firewall flag on, doesn't start at boot, Debian 13 ISO attached | Installed OS version and Docker state unknown. Whether this is the same machine I used for the Apache project is unconfirmed. |

**Trade-offs and observations:**

- **Separate VMs per role.** Keeping security tooling apart from service workloads means a messy test environment doesn't contaminate the Docker host. That separation only holds at the VM level, though, because both share one network bridge (see below).
- **Start-at-boot is the opposite of what I'd expect.** The security-testing VM starts automatically and the service VM doesn't. For a lab this may be deliberate, but it's worth reviewing. A testing VM usually doesn't need to run unattended.
- **Legacy virtual hardware.** Both VMs use SeaBIOS and the i440fx machine type, which are Proxmox defaults. They're broadly compatible. OVMF (UEFI) and q35 are the more modern choice and would be needed for features like Secure Boot or a virtual TPM. Changing this on an existing VM isn't a simple toggle, so I'd consider it for new VMs rather than retrofit it.
- **No guest agent.** Without the QEMU guest agent, Proxmox can't report guest IPs, shut guests down cleanly, or freeze filesystems for consistent backups. See [roadmap item 7](../roadmap.md#7-enable-the-qemu-guest-agent).

### A shared bridge with a Wi-Fi uplink

**Observed:** Both VMs attach to `vmbr0`, a Linux bridge with no physical port. It isn't VLAN-aware, and there are no VLANs or SDN zones. The host's physical uplink is a Wi-Fi interface.

**Inferred (unverified):** Standard Wi-Fi client connections generally can't be added to a Linux bridge the way a wired NIC can. So I believe `vmbr0` is an internal network, and the host routes or NATs guest traffic out over Wi-Fi. I haven't confirmed this from the host's network configuration.

**Trade-offs:**

- **Wi-Fi is convenient but limited.** It needs no cabling. But it's less stable and slower than wired Ethernet, and it rules out simple bridged networking where guests sit directly on the upstream LAN.
- **If guests are behind NAT, that's a mild security benefit.** They wouldn't be directly reachable from the upstream network. But I can't count on that until it's verified, and NAT isn't a firewall.
- **One flat bridge means no segmentation.** The security-testing VM and the service VM share the same layer-2 segment, so nothing at the network level separates them. Separating attack traffic from services is [roadmap item 4](../roadmap.md#4-verify-routingnat-and-segment-the-network).

More detail is in [networking/overview.md](../networking/overview.md).

### Backup and recovery gap

**Observed at the snapshot (not verified as current):** no backup jobs, no backup archives, no VM snapshots, no off-host backup target, and no replication.

**Why it matters more here than usual:** With one disk and no recovery points, a disk failure, a bad upgrade, or a mistake inside a guest would be unrecoverable. It also blocks the Proxmox 8 → 9 upgrade, because the official upgrade guide requires a valid, tested backup first.

**Direction:** Back up to a target that isn't on this NVMe, then prove a restore works. This is [roadmap item 1](../roadmap.md#1-establish-backups-and-test-recovery). The details are in [infrastructure/proxmox/README.md](../../infrastructure/proxmox/README.md#backup-and-recovery).

## What this architecture is and isn't

**It is** a working single-host lab for learning virtualization, Linux administration, containers, and security testing on hardware I control.

**It isn't** production-ready or hardened. At the snapshot:

- The hypervisor was past end of life.
- The firewall wasn't enforced.
- The network wasn't segmented.
- No backups were visible.

I'm documenting these gaps on purpose. Closing them is the point of the [roadmap](../roadmap.md).
