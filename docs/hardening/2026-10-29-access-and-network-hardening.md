# Access and Network Hardening (October 29, 2026)

On the evening of **October 29, 2026**, I moved from read-only inventory to actually hardening the lab. I inspected the host's real network and firewall configuration, found two significant gaps, fixed them, broke guest connectivity along the way, diagnosed why, and fixed that too. This page is the record of that session.

It closes most of [roadmap item 3](../roadmap.md#3-review-firewall-policy-safely) and [item 4](../roadmap.md#4-verify-routingnat-and-segment-the-network).

Labels used below:

- **Verified:** I confirmed it from command output on the host or in a guest during this session.
- **Inferred:** my best explanation, not directly proven.
- **Pending:** planned or started, but I haven't confirmed the result yet.

As with the rest of this repository, I've left out IP addresses, subnets, MAC addresses, overlay-network addresses, device names, and the literal firewall rulesets. Where a command is needed to make sense of a fix, I show it with placeholders.

---

## Summary

| # | Finding | Severity | Outcome |
|---|---|---|---|
| 1 | The overlay VPN's own firewall chain accepted all tailnet traffic **before** the Proxmox firewall ran, and the tailnet policy was the default allow-all. Every tailnet device, including the Kali VM, could reach the host's SSH and web UI. | High | Fixed at the overlay layer with an explicit allow-list policy and built-in policy tests |
| 2 | The Kali VM had no VM-level firewall. It could reach the host's management services and every device on my home LAN, including the router's admin page. | High | Fixed with a per-VM firewall: internet only, no host, no LAN, no other guests |
| 3 | Enabling the VM firewall broke the guest's internet access (NAT + Proxmox firewall bridge conntrack issue). | Incident | Diagnosed and fixed with a conntrack-zone rule; persisted across reboots |
| 4 | Root SSH on the host was key-only only because of a drop-in; the base config still said `PermitRootLogin yes`. Kali accepted password logins. | Medium | Host now explicitly key-only for root; Kali key-only with a dedicated key, root login disabled |
| 5 | The previous Docker VM had lost internet access, and I'd destroyed it. | — | Most likely the same cause as #3. Rebuilt the VM after the fix; the installer reached the package mirror normally |

---

## What the host configuration actually showed

Before changing anything, I collected a read-only snapshot from the host: interfaces, routes, `/etc/network/interfaces`, listening sockets, VM network config, the Proxmox firewall files, the live `iptables` ruleset, IP forwarding, the overlay VPN status, and the effective SSH settings. The same read-only checks ran on the Kali VM.

### Guest egress path: verified

This settles the question my [networking overview](../networking/overview.md) had left open since the dashboard snapshot.

| Item | Verified state |
|---|---|
| `vmbr0` | Static address on a private /24, no physical port (`bridge-ports none`) |
| IP forwarding | Enabled (set in a `post-up` hook on `vmbr0`) |
| NAT | `MASQUERADE` for the guest subnet out through the Wi-Fi interface |
| DHCP and DNS for guests | `dnsmasq` on the host, bound to the bridge |
| Overlay VPN | Running on the host and inside Kali |

So guests sit on an internal NAT network behind the host. The dashed "unverified" edge in my diagrams is now solid.

### Proxmox firewall state: enabled, mostly right

The dashboard snapshot from earlier the same day had shown the datacenter firewall **disabled**. By this session it was **enabled**. I don't have a record of exactly when that changed, so I'm only stating what I verified at the time.

| Item | Verified state |
|---|---|
| Datacenter firewall | Enabled; input policy DROP, output ACCEPT |
| Management allow-list | An IP set containing only my admin laptop's overlay address |
| Host inbound allowed | SSH, web UI, and SPICE proxy **from the management set only**; the overlay VPN's UDP port; DNS and DHCP **from the guest bridge only** |
| Everything else inbound | Dropped (IPv4 and IPv6) |

On paper, only my laptop could reach the host. In practice, that wasn't true. See Finding 1.

---

## Finding 1: the overlay VPN bypassed the Proxmox firewall

### What I found

Reading the live `iptables` ruleset in order showed this on the host's `INPUT` chain:

```text
-A INPUT -j ts-input        # overlay VPN's chain, evaluated first
-A INPUT -j PVEFW-INPUT     # Proxmox firewall, evaluated second
...
-A ts-input -i tailscale0 -j ACCEPT
```

The overlay VPN (Tailscale) inserts its own chain ahead of the Proxmox firewall, and that chain **accepts every packet arriving on the overlay interface**. Accepted packets never reach `PVEFW-INPUT`, so my management allow-list was never consulted for overlay traffic.

The overlay's own access policy was the default: one rule allowing every device to reach every device on every port.

**Combined effect:** any device on my tailnet could reach the host's SSH and web UI. That included the **Kali VM**, which is also a tailnet node. The machine I use to run offensive tools had an unfiltered path to the hypervisor's management interfaces.

The Kali VM was also listening on SSH and RDP to the whole tailnet.

### Fix

I replaced the allow-all overlay policy with an explicit allow-list, written in the overlay's newer `grants` format:

| Source | Destination | Allowed |
|---|---|---|
| Admin laptop, tablet | Proxmox host | SSH, web UI, SPICE proxy |
| Admin laptop, tablet | Kali VM | SSH, RDP |
| Anything else | Anything | **Denied (implicit)** |

I also:

- **Added policy tests** to the policy file. They assert that the laptop *can* reach the host and Kali, and that Kali *can't* reach the host or the laptop. The admin console refuses to save a policy whose tests fail, so a typo can't silently reopen access.
- **Removed the default "Tailscale SSH" rule.** I use ordinary OpenSSH, so the overlay's own SSH server was an extra, unused way in.
- **Kept the host's own firewall rules unchanged.** They still protect the host from the home LAN and from IPv6.

I chose this fix over changing the overlay's netfilter mode because it can't lock me out: if the policy is wrong, I fix it from the overlay's web console, which doesn't depend on the lab at all.

### Residual risk

The host's Proxmox firewall **still doesn't filter overlay traffic**. Access from the overlay is controlled only by the overlay policy. For a single-user lab I'm accepting that, because the policy is enforced on every node and is tested on every save.

The defence-in-depth option is to stop the overlay VPN from inserting its accept rule (`--netfilter-mode=nodivert`) so the Proxmox rules apply to overlay traffic too. That's a real lockout risk on a remote host, so I'll only do it with local console access ready.

---

## Finding 2: the Kali VM could reach my home LAN and the host

### What I found

The Kali VM's network device had the Proxmox firewall flag **off**. With guests NATed out through the host's Wi-Fi, that meant Kali could open connections to:

- the host's management services on its bridge address;
- my home router's admin interface and every other device on the home LAN;
- any other guest on the same bridge.

For a security-testing VM, that's the wrong default. A misdirected scan or a compromised tool would have had my whole home network in reach.

### Fix

I gave Kali a VM-level firewall with this intent:

| Direction | Policy |
|---|---|
| Inbound | Default **DROP**. Allow only the overlay VPN's UDP port (for direct peer connections) and ICMP from the host. |
| Outbound to the host | Allow **DNS only**. Everything else to the bridge subnet, including other guests, is dropped. |
| Outbound to private ranges | Drop all RFC 1918 and link-local ranges (home LAN, router admin, anything else private), except the overlay VPN's UDP port to LAN peers. |
| Outbound to the internet | Allow. |

Then I turned on the VM's firewall flag. That's where things broke.

---

## Incident: enabling the VM firewall broke internet access

### Symptoms

The moment I enabled the firewall flag on Kali's network device:

1. My SSH session to Kali dropped. Re-plugging a NIC resets existing sessions, so that part was expected.
2. **New SSH connections timed out.** That wasn't expected.

### Recovery

Kali was only reachable over the overlay VPN, and that path was down. I used the **Proxmox web console** (noVNC), which goes through the host rather than the guest's network, and rolled back by turning the VM's firewall flag off. Access came back immediately.

Lesson: before changing a guest's network, I need a way into that guest that doesn't depend on that network.

### Diagnosis

From the console, with the firewall turned back on, I ran a short layer-by-layer check:

| Check | Result | What it told me |
|---|---|---|
| Interface and address | Up, with a DHCP lease | DHCP through the host worked |
| `getent hosts` for the overlay's control server | Resolved | DNS through the host's `dnsmasq` worked |
| `ping` to a public IP | **100% loss** | Traffic going **through** NAT to the internet failed |
| Overlay VPN status | `NoState` | The overlay client couldn't reach its control server, so the VM dropped off the tailnet |

Everything that terminated **on the host** worked. Everything that was **NATed through the host** failed. The firewall rules themselves allowed outbound internet traffic, so this wasn't a rule mistake.

### Cause

This is a known Proxmox behaviour with **masquerading (NAT) plus the Proxmox firewall**. When a VM's firewall flag is on, Proxmox inserts an extra firewall bridge (`fwbr…`) between the VM and `vmbr0` so it can filter that VM's traffic. The first packet of each new connection then passes through netfilter as bridged traffic before it's routed. Per the Proxmox documentation, outgoing connections can end up handled by the VM bridge's `POSTROUTING` path instead of the `MASQUERADE` rule. The connection gets no NAT mapping, its packets leave with the private source address, and no reply ever comes back.

The [Proxmox network configuration documentation](https://pve.proxmox.com/wiki/Network_Configuration) describes this case and the fix in its masquerading section: put traffic from the firewall bridges into its own conntrack zone. This mechanism is **inferred** for this lab; the confirming evidence (NAT counters, conntrack entries) wasn't captured before the fix. The full analysis is in the [Wi-Fi NAT, firewall and conntrack case study](../networking/proxmox-wifi-nat-firewall-conntrack.md).

> **Correction (October 30, 2026):** the first version of this write-up said reply packets were dropped by the VM's inbound policy. The documented mechanism, NAT not being applied on the way out, fits the evidence better.

### Fix

Applied live on the host:

```bash
iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
```

Persisted in the `vmbr0` stanza of `/etc/network/interfaces`, next to the existing NAT rule:

```text
post-up   iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
post-down iptables -t raw -D PREROUTING -i fwbr+ -j CT --zone 1
```

I re-enabled Kali's firewall flag. Internet access came back, the guest rejoined the tailnet, and SSH from my laptop worked again.

### This probably explains the lost Docker VM

My original Docker VM had lost internet access, and I'd destroyed it before this session. The [October 29 dashboard snapshot](../inventory.md#vm-101-cy5001-docker) shows that VM had its **firewall flag on**, while Kali's was off.

That matches this incident. DNS to the host would have kept working, so package mirrors resolved, but downloads through NAT would have failed with no reply. I can't prove it for a VM that no longer exists, so this is **inferred**. But the symptoms match, and the rebuilt VM (below), created with the firewall flag on after the fix, reached the Debian mirror without trouble during installation.

---

## Finding 4: SSH authentication

### Host

| Setting | Before | After |
|---|---|---|
| `PermitRootLogin` | `yes` in the base config; effective behaviour key-only only because a drop-in disabled passwords | Explicitly `prohibit-password` in the hardening drop-in |
| `PasswordAuthentication` | `no` | `no` |
| Verified with | — | `sshd -T` shows `permitrootlogin without-password` and `passwordauthentication no` |

`without-password` is the older name for `prohibit-password`; `sshd -T` still prints it that way.

I applied this with `sshd -t` (config test) before reloading, and kept an existing session open while I tested a fresh login.

### Kali VM

| Setting | Before | After |
|---|---|---|
| Authentication | Password accepted | **Key only** |
| Key | — | A dedicated Ed25519 key used only for this VM, with a passphrase. The host has its own separate key, so one key leaking doesn't open the other machine. |
| `PasswordAuthentication` | Default (yes) | `no` |
| `PermitRootLogin` | Default | `no` |

**Verified:** forcing a password-only login attempt from my laptop was refused before any password prompt:

```text
Permission denied (publickey).
```

---

## Verification

All checks below ran on October 29, 2026, after the changes.

### From the Kali VM

| Test | Expected | Result |
|---|---|---|
| HTTPS request to a public website | Succeeds | `HTTP/2 200` ✅ |
| TCP to the host's web UI on its **bridge** address | Blocked | Timed out ✅ |
| Ping to the home router | Blocked | 100% loss ✅ |
| TCP to the host's web UI on its **overlay** address | Blocked | Timed out ✅ |

### From my admin laptop

| Test | Expected | Result |
|---|---|---|
| Proxmox web UI over the overlay | Reachable | Reachable ✅ |
| SSH to Kali with its key | Succeeds | Succeeds ✅ |
| SSH to Kali with a password only | Refused | `Permission denied (publickey)` ✅ |

### On the host

| Check | Result |
|---|---|
| Effective SSH config (`sshd -T`) | Root key-only, passwords off ✅ |
| IPv6 host firewall chain | Ends in DROP, mirroring the IPv4 rules ✅ |
| Conntrack-zone rule in `/etc/network/interfaces` | Present with matching `post-up` / `post-down` ✅ |

The overlay policy tests passed on save, which independently confirms the laptop-allowed / Kali-denied behaviour at the overlay layer.

---

## Rebuilding the Docker VM

After the fix, I recreated VM 101 as a throwaway coursework VM.

**Verified:**

- Debian 13 netinst, **minimal install**: SSH server and standard system utilities only, **no desktop environment**.
- VirtIO NIC on `vmbr0` with the **firewall flag on** from creation.
- "Start after created" left off, so the VM wouldn't run before its firewall rules existed.
- During installation it got a DHCP lease from the host and downloaded packages from the Debian mirror normally. That's the practical confirmation of the conntrack fix.
- After installation it booted from disk, and the guest reported its kernel as `6.12.113+deb13-amd64`.

**Design decision: no overlay VPN on this VM.** It's disposable, so instead of joining it to the tailnet (and then needing a policy change and later clean-up), I reach it with SSH using the host as a jump host (`ssh -J`). Its firewall policy, confirmed present on the host on October 30, 2026, is:

| Direction | Policy |
|---|---|
| Inbound | Default DROP. Allow SSH **from the host only** (the jump host). |
| Outbound | Same as Kali: DNS to the host, no host, no LAN, no other guests, internet allowed. |

Container ports will be published on `127.0.0.1` inside the VM and reached through SSH port forwarding, so nothing is exposed on the bridge. Docker writes its own `iptables` rules for published ports, which bypass a guest firewall like `ufw`, so binding to localhost is the control that actually works.

**Confirmed on October 30, 2026** (read-only checks on the host):

- The VM's Proxmox firewall rules file exists and matches the policy above. (My first attempt to create it ran inside the guest, where `/etc/pve` doesn't exist; it was then created on the host.)
- Allocation: 1 vCPU, 2 GiB RAM, 16 GiB disk (`local-lvm`, iothread), VirtIO NIC on `vmbr0` with the firewall flag on.
- An SSH connection through the host as a jump host reached the VM's SSH server.

**Pending:**

- Test the rules from inside the VM: internet works; the host (except SSH from it), the home LAN, and Kali are unreachable.
- Complete a login over the jump-host path and switch the VM to key-only SSH, as on Kali.
- When the coursework is finished: destroy the VM **and delete its firewall file**, so the old rules don't silently apply to whatever VM gets ID 101 next.

---

## Follow-ups

| Item | Status |
|---|---|
| Reboot the host once and confirm guests still have internet (proves the persisted conntrack rule and NAT come back on boot) | Pending |
| Disable `rpcbind` on the host. It was listening on all interfaces; the firewall blocked it, but nothing in the lab uses it. | Pending |
| Remove the old Docker VM's stale record from the overlay network | Pending |
| Optionally enable firewall drop logging on the host so I can see what's being refused | Planned |
| Optionally make the Proxmox firewall filter overlay traffic too (`nodivert`), with local console access ready | Planned |
| Backups and a tested restore before the Proxmox 8 → 9 upgrade | Planned ([roadmap item 1](../roadmap.md#1-establish-backups-and-test-recovery)) |

---

## Lessons learned

- **Read the ruleset in evaluation order, not the config files.** The Proxmox firewall configuration was correct. The problem was another product's chain sitting ahead of it. Only `iptables -S` in order showed that.
- **A firewall is only as good as the paths that reach it.** "Only my laptop can reach the management ports" was true for the LAN and false for the overlay network.
- **Every overlay node is a network position.** Putting a security-testing VM on the same tailnet as the hypervisor, with an allow-all policy, gave it the same reach as my admin laptop.
- **Keep an out-of-band path before changing network config.** The Proxmox console saved this session. Without it, the rollback would have meant physically going to the laptop.
- **Debug by layer.** "DHCP works, DNS works, ping to the internet fails" pointed straight at NAT. Without that split, it would have looked like a broken rule or a DNS problem.
- **Test both sides of a security control.** Each change was checked for what it should allow *and* what it should deny, and the overlay policy now tests itself on every save.
- **Make access changes reversible first.** Policy tests, `sshd -t` before reload, a second SSH session before closing the first, and a one-command rollback for the VM firewall flag.
