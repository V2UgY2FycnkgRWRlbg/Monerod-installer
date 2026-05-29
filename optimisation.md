# XMRig Optimisation

This guide covers two common Monero RandomX optimisations for the Incus miner container:

- huge pages
- MSR mod

These optimisations are optional. XMRig can mine without them, but hashrate is usually lower.

## Huge Pages

Huge pages reduce memory-management overhead for RandomX. This is usually a safe optimisation and often improves hashrate.

Your logs before optimisation looked like:

```text
huge pages 0% 0/4
```

After enabling huge pages, you want to see:

```text
randomx allocated 2336 MB (2080+256) huge pages 100% 1168/1168 +JIT
cpu READY threads 4/4 (4) huge pages 100% 4/4
```

## How Much Memory Do Huge Pages Need?

On Linux, normal huge pages are usually 2 MB each.

XMRig RandomX commonly allocates around:

```text
2336 MB
```

That equals:

```text
2336 MB / 2 MB = 1168 huge pages
```

So a practical minimum is:

```text
vm.nr_hugepages=1168
```

Use a small margin because the host and container may need some extra room:

```text
vm.nr_hugepages=1280
```

That reserves:

```text
1280 * 2 MB = 2560 MB
```

## Recommended Huge Page Values

For the current default miner:

```text
cpu_set=2,3,6,7
mining_threads=4
memory=6GiB
```

Use:

```text
vm.nr_hugepages=1280
limits.hugepages.2MB=2560MB
```

Suggested values:

```text
Light miner:       2 threads, 4 GiB container RAM, 1280 huge pages
Balanced miner:    4 threads, 6 GiB container RAM, 1280 huge pages
Aggressive miner:  6-8 threads, 6-8 GiB container RAM, 1280 huge pages
```

RandomX dataset memory is not multiplied by thread count, so most normal XMRig setups still use around the same huge page allocation. The per-thread scratchpad is smaller.

## Check Host Memory First

Run this on the host:

```bash
free -h
```

Check current huge page state:

```bash
grep Huge /proc/meminfo
```

Important fields:

```text
HugePages_Total
HugePages_Free
Hugepagesize
```

If `Hugepagesize` is `2048 kB`, then each huge page is 2 MB.

## Enable Huge Pages Temporarily

Run on the host:

```bash
sudo sysctl -w vm.nr_hugepages=1280
```

This works immediately but does not survive reboot.

## Enable Huge Pages Permanently

Run on the host:

```bash
echo 'vm.nr_hugepages=1280' | sudo tee /etc/sysctl.d/99-xmrig-hugepages.conf
sudo sysctl --system
```

## Allow The Incus Container To Use Huge Pages

Run on the host:

```bash
incus config set monero-miner limits.hugepages.2MB 2560MB
```

Restart the container:

```bash
incus restart monero-miner
```

Check XMRig logs:

```bash
incus exec monero-miner -- journalctl -u xmrig -n 80 --no-pager
```

Live logs:

```bash
incus exec monero-miner -- journalctl -u xmrig -f
```

## Verify Huge Pages Worked

Inside the logs, look for:

```text
huge pages 100%
```

Example:

```text
randomx allocated 2336 MB (2080+256) huge pages 100% 1168/1168 +JIT
cpu READY threads 4/4 (4) huge pages 100% 4/4
```

If it still says:

```text
huge pages 0%
```

check:

```bash
grep Huge /proc/meminfo
incus config get monero-miner limits.hugepages.2MB
```

## Huge Pages Risks And Tradeoffs

Benefits:

- usually improves RandomX hashrate
- low operational risk
- easy to revert

Costs:

- reserves host RAM for huge pages
- RAM reserved for huge pages is less available to normal applications
- too high a value can reduce memory available to the host

Revert:

```bash
sudo sysctl -w vm.nr_hugepages=0
sudo rm /etc/sysctl.d/99-xmrig-hugepages.conf
incus config unset monero-miner limits.hugepages.2MB
incus restart monero-miner
```

## MSR Mod

MSR means Model-Specific Register. XMRig can apply CPU-specific register tweaks that improve RandomX performance.

When MSR is not available, logs show:

```text
msr kernel module is not available
FAILED TO APPLY MSR MOD, HASHRATE WILL BE LOW
```

Mining still works. This warning only means one optimisation is missing.

## MSR Possible Win

MSR can improve hashrate depending on CPU, BIOS settings, kernel, and container access.

Expected result:

```text
small to moderate hashrate improvement
```

On older Intel CPUs like the i7-4770, huge pages are usually the first optimisation to do. MSR may help, but the gain can be smaller and the setup is more invasive.

## MSR Costs, Risks, And Downsides

MSR requires privileged access to CPU registers from the host kernel.

Risks and tradeoffs:

- requires loading the `msr` kernel module on the host
- may require running XMRig with elevated privileges or extra device access
- changes CPU register settings while the miner runs
- can slightly affect system behaviour under load
- may be reset after reboot or suspend
- not ideal on shared production servers
- more sensitive than huge pages from a security point of view

Security note:

```text
Huge pages are mostly a memory allocation optimisation.
MSR access is low-level CPU control.
```

So huge pages are normally safe to enable first. MSR should be treated as an advanced tuning step.

## Basic MSR Host Check

Run on the host:

```bash
lsmod | grep msr
```

If nothing appears, the module is not loaded.

Load it temporarily:

```bash
sudo modprobe msr
```

Make it persistent:

```bash
echo msr | sudo tee /etc/modules-load.d/msr.conf
```

Then restart the miner container:

```bash
incus restart monero-miner
```

Check logs:

```bash
incus exec monero-miner -- journalctl -u xmrig -n 80 --no-pager
```

## MSR In Containers

Loading `msr` on the host may not be enough for an unprivileged Incus container. The container may still not be allowed to access the MSR device.

If the logs still show:

```text
msr kernel module is not available
```

then the container does not have the required access.

At that point, choose one:

```text
Option 1: leave MSR disabled
Option 2: run XMRig directly on the host
Option 3: make the container more privileged and expose the needed device
```

For this project, the recommended conservative choice is:

```text
Enable huge pages.
Leave MSR disabled unless you are comfortable with lower-level host tuning.
```

## Recommended Order

1. Start with normal pool mining.
2. Confirm accepted shares.
3. Enable huge pages.
4. Compare 15-minute hashrate before and after.
5. Consider MSR only if you want to push performance further.

Useful command:

```bash
incus exec monero-miner -- journalctl -u xmrig -f
```

Watch for:

```text
miner speed 10s/60s/15m
accepted (.../0)
huge pages 100%
```
