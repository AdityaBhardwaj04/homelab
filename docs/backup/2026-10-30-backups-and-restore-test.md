# Backups and Restore Test (October 30, 2026)

On **October 30, 2026**, I set up the lab's first real backups, verified them, and proved one restores. This closes the main part of [roadmap item 1](../roadmap.md#1-establish-backups-and-test-recovery), which had been the biggest gap since the [October 29 inventory](../inventory.md#6-backups-and-recovery-observed-october-29-2026-not-verified-as-current) found no recovery points at all.

Labels used below:

- **Verified:** confirmed from command output during this session.
- **Pending:** planned or started, but not yet confirmed.

As in the rest of this repository, I've left out drive serial numbers, UUIDs, email addresses, and credentials.

---

## Summary

| Item | Result |
|---|---|
| Backup target | Dedicated ext4 partition on an external USB SSD, mounted only while backing up |
| VM 101 (`cy5001-docker`) | Backed up in snapshot mode: 1.0 GB archive, verified |
| VM 100 (`Kali`) | Backed up in stop mode: 39.6 GB archive, verified |
| Restore test | Kali restored to a temporary VM, booted with its data intact, then deleted |
| Retention | Last 3 backups per VM, pruned automatically |
| Routine | Weekly and manual, using the [`homelab-backup`](../../infrastructure/proxmox/scripts/homelab-backup) script |
| Alerts | Proxmox notifications delivered by email through an authenticated SMTP relay; test message received |

---

## Design

### Why an external drive, kept offline

The host has a single NVMe drive. Backups on Proxmox's `local` storage would share that drive with the VMs, so a drive failure would take the backups with it. An external SSD survives that.

The drive is plugged in only while a backup runs, then unmounted and unplugged. While it's disconnected, the backups are out of reach of anything that goes wrong on the host: ransomware, an accidental delete, a bad script, or a power surge.

| Decision | Benefit | Cost |
|---|---|---|
| External USB SSD | Survives loss of the host's only disk | It's in the same place as the host, so it doesn't protect against fire or theft |
| Offline between runs | Protected from host compromise and mistakes | Backups depend on remembering to plug the drive in |
| Weekly, manual | Simple; no always-attached drive | Up to a week of changes can be lost |
| `keep-last=3` | Three weeks of history; old archives pruned automatically | Older restore points aren't kept |

### Why ext4, not NTFS

The SSD originally had two Windows (NTFS) partitions. The first plan was to back up to one of them without reformatting. Linux's `ntfs3` driver refused to mount it:

```text
ntfs3: sda2: Mark volume as dirty due to NTFS errors
ntfs3: sda2: Failed to load $BadClus (-22).
```

Windows `chkdsk` then found **no problems and no bad sectors** on that partition, so the failure was the Linux driver's strictness, not damage. A backup target should be the most predictable part of the system, so I reformatted the other partition (after copying off the little data it held) as **ext4** instead of relying on a filesystem Linux only partially supports.

### Proxmox configuration

| Setting | Value | Why |
|---|---|---|
| Filesystem | ext4, labelled `pve-backup`, 1% reserved blocks | Native Linux filesystem; frees space a backup disk doesn't need reserved |
| Mount | By filesystem UUID in `/etc/fstab`, with `nofail` and a 10-second device timeout | The host boots normally when the drive is unplugged |
| Proxmox storage | Directory storage `pve-backup`, content type `backup` | |
| `is_mountpoint` | Set to the mount path | If the drive isn't mounted, Proxmox marks the storage offline instead of silently writing backups to the host's own disk |
| Retention | `prune-backups keep-last=3` | Enforced by `vzdump` after each run |
| Compression | zstd | Fast, with a good ratio |

---

## First backups

### VM 101: snapshot mode

| Metric | Value |
|---|---|
| Disk | 16 GiB, about 87% zeros |
| Archive | 1013 MB |
| Duration | 9 seconds |
| Guest downtime | None (snapshot mode) |

### VM 100: stop mode

I used **stop** mode for Kali's first backup, so the image would be fully consistent, not a running-system snapshot.

| Metric | Value |
|---|---|
| Disk | 200 GiB, 112.7 GiB (56%) of it zeros |
| Archive | 39.63 GB |
| Data transfer | about 6 minutes |
| Total job time | 15 min 41 s |
| Guest downtime | about 9.5 minutes, almost all of it waiting for the guest to shut down |

**What went wrong:** in stop mode, Proxmox asks the guest to shut down by sending an ACPI power-button event. Kali didn't act on it. Without the QEMU guest agent, Proxmox has no other way to request a clean shutdown, so it waited. After the guest was shut down from inside, the backup ran normally, and `vzdump` started the VM again automatically. Installing the guest agent in Kali is [roadmap item 7](../roadmap.md#7-enable-the-qemu-guest-agent). It would make stop-mode shutdowns reliable and let snapshot-mode backups freeze the guest's filesystem.

---

## Verification

Both archives passed a full decompression test with `zstd -t`:

| Archive | Decompressed size | Result |
|---|---|---|
| VM 101 | about 2.07 GB | OK |
| VM 100 | about 93.7 GB | OK |

A decompression test proves the archive isn't corrupt. It doesn't prove the VM inside works, which is what the restore test is for.

---

## Restore test

The Kali backup was restored to a temporary VM ID (900):

| Step | Detail |
|---|---|
| Restore | `qmrestore` to `local-lvm` with `--unique 1`, which gives the copy a new MAC address. Took about 21 minutes to read all 200 GiB. |
| Isolation before boot | Network link set to **down** (`link_down=1`) and start-at-boot disabled, *before* first boot |
| Boot | The restored VM booted normally |
| Data | The home directory and its contents were present |
| Network | `eth0` was down, and the overlay VPN interface had no overlay address, so the copy never joined the network |
| Disk | Filesystem showed 55 GB used, consistent with the source VM |
| Clean-up | VM stopped and destroyed with `--purge`; only VMs 100 and 101 remain |

**Why isolate the copy:** a restored clone has the same overlay-VPN identity and the same IP configuration as the original. If it had joined the network, it would have clashed with the real Kali. A restore test should never disturb production.

---

## Notifications

Proxmox reported "notified via target `mail-to-root`" after each backup, but no email ever arrived. That target hands mail to the host's local mail system, which can't deliver from a residential connection.

I added an **SMTP notification target** that sends through an authenticated mail account using an app-specific password (STARTTLS on port 587), and routed the default notification matcher to it. A test message from Proxmox was received. The credential lives only in Proxmox's root-only configuration.

**Remaining gap:** Proxmox notifications fire only when `vzdump` runs. If the backup script stops before that, for example because the drive isn't connected, no email is sent. Relaying the host's local mail through the same account would let the script report its own failures. That's **pending**.

---

## The backup script

[`infrastructure/proxmox/scripts/homelab-backup`](../../infrastructure/proxmox/scripts/homelab-backup) wraps the routine:

1. Refuses to run unless the drive labelled `pve-backup` is connected. It matches by label, not by device name.
2. Mounts the drive and confirms it really is a mountpoint, and that the Proxmox storage is active.
3. Backs up VMs 100 and 101 (snapshot mode by default, `--stop` for stop mode).
4. Verifies each new archive with `zstd -t`.
5. Unmounts and ejects the drive, including when a step fails.
6. Logs to `/var/log/homelab-backup.log` and holds a lock, so two runs can't overlap.

**Status:** the script passes `bash -n` and ShellCheck. It **hasn't yet been run end-to-end**. The October 30 backups above were made by running `vzdump` directly.

---

## Still to do

| Item | Status |
|---|---|
| First end-to-end run of `homelab-backup` | Pending |
| Back up host configuration (`/etc/pve`, network and storage config) | Pending |
| Install the QEMU guest agent in Kali | Pending ([roadmap item 7](../roadmap.md#7-enable-the-qemu-guest-agent)) |
| Script failure alerts via local mail relay | Pending |
| A second copy in a different location (3-2-1) | Not started. Both copies are currently in the same place |
| Repeat the restore test periodically, and after the Proxmox upgrade | Planned |

---

## Lessons learned

- **A backup isn't real until it's been restored.** The decompression test caught nothing wrong, but only booting the restored VM proved the backup is usable.
- **Isolate restore tests.** A clone carries the original's network and VPN identity. Disconnecting it before first boot avoided an address or identity clash.
- **Stop mode depends on the guest.** Without a guest agent, a desktop guest may ignore the ACPI shutdown request and stall the job.
- **Choose the boring filesystem for backups.** NTFS on Linux failed in a way Windows didn't. ext4 removed that variable.
- **Guard against the missing-drive failure mode.** `is_mountpoint` and the script's checks stop backups from silently landing on the disk they're meant to protect.
- **"Notified" doesn't mean delivered.** The default mail target reported success while nothing arrived. Only an end-to-end test message proved alerts work.
