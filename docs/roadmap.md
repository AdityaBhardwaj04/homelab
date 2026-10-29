# Roadmap

These are the improvements I plan to make, ordered by priority. Each one comes from a gap in the [October 29, 2026 inventory](inventory.md).

**Everything on this page is planned work, not completed work.** When I finish an item, I'll mark it done, date it, and link to the write-up.

Before starting most items, I need to re-check the current state, because the inventory is a snapshot.

| # | Item | Priority | Status |
|---|---|---|---|
| 1 | [Establish backups and test recovery](#1-establish-backups-and-test-recovery) | Critical | Planned |
| 2 | [Plan a supported Proxmox upgrade](#2-plan-a-supported-proxmox-upgrade) | High | Planned |
| 3 | [Review firewall policy safely](#3-review-firewall-policy-safely) | High | Planned |
| 4 | [Verify routing/NAT and segment the network](#4-verify-routingnat-and-segment-the-network) | High | Planned |
| 5 | [Verify guest OS versions and Docker state](#5-verify-guest-os-versions-and-docker-state) | Medium | Planned |
| 6 | [Right-size memory for VM 101](#6-right-size-memory-for-vm-101) | Medium | Planned |
| 7 | [Enable the QEMU guest agent](#7-enable-the-qemu-guest-agent) | Medium | Planned |
| 8 | [Clean up the attached ISO and stale shell session](#8-clean-up-the-attached-iso-and-stale-shell-session) | Low | Planned |
| 9 | [Reproducible build for the Apache HTTPS project](#9-reproducible-build-for-the-apache-https-project) | Medium | Planned |
| 10 | [Monitoring, logging, scanning, and automation](#10-monitoring-logging-scanning-and-automation) | Ongoing | Planned |

---

## 1. Establish backups and test recovery

**Why:** At the snapshot there were no backup jobs, archives, or snapshots, and everything sits on one NVMe drive. One bad upgrade or disk failure would lose the whole lab. This also blocks item 2: the Proxmox upgrade guide requires a valid, tested backup first.

**Plan:**

1. Confirm the current state. Are there still no jobs or archives?
2. Choose an off-host target. Options include an external USB drive, a NAS share, or Proxmox Backup Server on separate hardware. Backups on `local` share the same disk as the VMs, so they're only useful for rollback, not for disaster recovery.
3. Configure scheduled `vzdump` backups (snapshot mode, zstd) with a retention policy.
4. Back up the host configuration too (`/etc/pve`, network config, storage config).
5. **Test a restore.** Restore a VM to a new VM ID, boot it, and confirm it works. I'll write up the procedure and the result.

**Done when:** Both VMs have regular off-host backups, and I've completed and documented at least one test restore.

## 2. Plan a supported Proxmox upgrade

**Why:** The host runs Proxmox VE 8.4.21. According to the [official Proxmox FAQ](https://pve.proxmox.com/wiki/FAQ) (checked October 29, 2026), Proxmox VE 8 reached end of life in August 2026, a month after its Debian 12 base. The current release line is Proxmox VE 9 (Debian 13), with 9.2 as the latest at the time of checking.

**Prerequisites** (from the official [Upgrade from 8 to 9](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9) guide):

- Be on the latest Proxmox VE 8.4 packages. 8.4.1 or newer is required, and 8.4.21 meets that, but I'll update within 8.4 first.
- Have a **valid, tested backup** of every guest. That's why item 1 comes first.
- Run the `pve8to9 --full` checklist and resolve any warnings. It doesn't change anything by default.
- Have at least 5 GB free on the root filesystem, ideally more than 10 GB. The snapshot showed about 5% of ~94 GiB used.
- Have console access that doesn't depend on the system being upgraded. For this laptop, that means working at the physical machine or in a `tmux` session, not the web UI shell.

**Approach options:**

- **In-place upgrade with apt,** following the official step-by-step guide. This is the least disruptive option for a single node.
- **Fresh Proxmox VE 9 install and restore from backup.** This is cleaner, but it wipes the host, so a verified off-host backup is mandatory.

**Lab-specific risk:** The host's only physical uplink is Wi-Fi, and I may be managing it over a VPN. If networking breaks during the upgrade, I could lose remote access. I'll plan to do this at the machine and record the network configuration beforehand.

**Done when:** I've chosen and documented an approach, finished the prerequisites, completed the upgrade during a planned window, and verified the guests afterwards. **I won't upgrade before item 1 is done.**

## 3. Review firewall policy safely

**Why:** At the snapshot, the datacenter firewall was disabled with no rules. The VM 101 firewall flag was on, but it has no effect without the datacenter firewall. The input policy was set to DROP, so enabling the firewall carelessly could block web UI and SSH access.

**Plan:**

1. Write down exactly which management paths I need to keep (web UI, SSH, and VPN).
2. Add explicit allow rules for those paths first. I'll test them with a console session open as a fallback.
3. Enable the datacenter firewall, then the node firewall, then per-VM firewalls with deliberate rules.
4. Decide on a default policy for the Kali VM's traffic toward other guests.

I'll only publish a summary of the policy here, not the full ruleset.

## 4. Verify routing/NAT and segment the network

**Why:** `vmbr0` has no physical port, and the uplink is Wi-Fi. I believe the host routes or NATs guest traffic, but I haven't confirmed it. Both the security-testing VM and the service VM share that one flat bridge.

**Plan:**

1. Read the host's network configuration (interfaces, IP forwarding, NAT rules) to confirm how guest traffic leaves the host. Then update the architecture diagram, turning the dashed edge solid if confirmed.
2. Design segmentation, for example a separate bridge or VLAN for attack and testing traffic, so Kali can't reach service VMs by default.
3. Confirm whether the VPN service on the host is running and what role it plays.

## 5. Verify guest OS versions and Docker state

**Why:** The dashboard can't see inside the guests. I need to confirm what's actually installed.

**Plan:** Record the OS release and kernel for each VM. On VM 101, record the Docker Engine version, `docker ps -a`, and the local images. Confirm whether this is the same `cy5001-docker` installation I used for the Apache project.

## 6. Right-size memory for VM 101

**Why:** 1 GiB of RAM was ~88% used at the snapshot. Docker workloads on that little memory risk OOM kills and swapping.

**Plan:** Watch memory usage inside the guest under a typical workload, then raise the allocation (probably to 2 GiB) or enable ballooning. The host has headroom: ~9 of ~15 GiB was assigned at the snapshot.

## 7. Enable the QEMU guest agent

**Why:** Without the agent, Proxmox can't report guest IPs or OS details, can't shut guests down cleanly, and can't freeze filesystems for consistent backups.

**Plan:** Install `qemu-guest-agent` in each guest, enable the agent option on the VM, and confirm it reports correctly. Do this before setting up scheduled backups if possible.

## 8. Clean up the attached ISO and stale shell session

**Why:** At the snapshot, VM 101 still had its Debian 13 installer ISO attached, and a web shell session from October 13, 2026 still showed as running in the task log.

**Plan:** Detach the ISO once I've confirmed the VM boots from disk. Look into the shell task. If it's stale, close it deliberately rather than leaving an open session.

## 9. Reproducible build for the Apache HTTPS project

**Why:** I built the original image interactively and captured it with `docker commit`. That works, but nobody can rebuild it or audit it from source.

**Plan:** Replace the manual process with a Dockerfile and explicit Apache configuration. The certificate is generated at build or run time and never committed. Then document the differences from the original process.

## 10. Monitoring, logging, scanning, and automation

These are longer-term additions that will come after the basics above:

- **Monitoring:** host and guest metrics, plus disk health. SMART alerts matter on a single-disk host.
- **Logging:** centralized logs from the host and guests.
- **Vulnerability scanning:** scan container images and guests. Only my own systems, from inside the lab.
- **Automation:** capture VM and service configuration as code (for example Ansible, or Terraform with a Proxmox provider) so I can rebuild the lab from this repository.
