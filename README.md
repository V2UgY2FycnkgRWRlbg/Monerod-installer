# Monero-installer

OpenTofu/Terraform deployment for a Monero mining container on Incus.

The default setup is now the practical mining path:

```text
XMRig -> centralized Monero pool
```

This avoids waiting for a full blockchain sync and gives smaller, more regular payouts than solo mining.

## Which Mode Should You Choose?

### Recommended: `mining_mode = "pool"`

Use this if your goal is simple, frequent, visible payouts.

```text
XMRig -> supportxmr.com / hashvault.pro / nanopool.org / another pool
```

You only need:

- your Monero wallet address
- a pool endpoint
- CPU threads to mine with

Good default:

```bash
tofu apply \
  -var="wallet_address=YOUR_XMR_ADDRESS_HERE" \
  -var="mining_mode=pool" \
  -var="pool_url=pool.supportxmr.com:3333" \
  -var="pool_password=worker1"
```

Other example pool endpoints:

```text
pool.supportxmr.com:3333
pool.hashvault.pro:443
xmr-eu1.nanopool.org:14433
```

Always confirm the correct hostname, port, TLS requirement, payout minimum, and password format on the pool's own website before deploying.

### Available but not recommended for steady payouts: `mining_mode = "solo"`

Use this if you specifically want to run your own node and mine alone.

```text
monerod -> Monero network
```

Solo mining is a lottery. With normal home CPU hashrate, it may take a very long time to find a block.

```bash
tofu apply \
  -var="wallet_address=YOUR_XMR_ADDRESS_HERE" \
  -var="mining_mode=solo"
```

This mode installs verified Monero CLI binaries, runs `monerod`, waits for full sync, then starts solo mining through the daemon RPC.

### Decentralized pool option: P2Pool

The best Monero-aligned pool setup is:

```text
XMRig -> P2Pool -> monerod -> Monero network
```

That gives pool-like payouts without a centralized pool operator. This repository does not deploy P2Pool yet; the current automated choices are direct pool mining or solo mining.

## What This Deploys

When `mining_mode = "pool"`:

1. Creates an Incus Debian 12 cloud container.
2. Pins CPU cores and limits memory.
3. Downloads the latest upstream Linux static XMRig release.
4. Installs `/usr/local/bin/xmrig`.
5. Starts `xmrig.service`.
6. Mines directly to the configured pool.

When `mining_mode = "solo"`:

1. Creates an Incus Debian 12 cloud container.
2. Pins CPU cores and limits memory.
3. Downloads and verifies Monero CLI:
   - imports the official `binaryFate` signing key
   - verifies the signed `hashes.txt`
   - downloads the latest Linux x64 CLI tarball
   - checks the SHA256 hash
4. Installs `monerod`.
5. Starts `monerod.service`.
6. Waits for sync, then starts solo mining with `monero-solo-mining.service`.

## Variables

### `mining_mode`

Default: `pool`

Allowed values:

- `pool`: direct XMRig pool mining, recommended
- `solo`: monerod full-node solo mining

### `wallet_address`

Required. Your Monero address for pool payouts or solo block rewards.

### `pool_url`

Default: `pool.supportxmr.com:3333`

Only used in `pool` mode. This is the pool stratum endpoint passed to XMRig.

### `pool_password`

Default: `monero-miner`

Only used in `pool` mode. Many pools use this as the worker name, but some pools use it for options such as email, rig ID, TLS flags, or payout settings. Check the pool documentation.

### `pool_tls`

Default: `false`

Only used in `pool` mode. Set this to `true` when the pool endpoint requires TLS, which is common on ports such as `443`.

### `mining_threads`

Default: `4`

CPU mining threads for XMRig pool mining or monerod solo mining. This is how many mining workers the miner starts inside the container.

### `xmrig_donate_level`

Default: `1`

XMRig developer donation level percentage.

### `cpu_set`

Default: `2,3,6,7`

Logical CPUs that the Incus container is allowed to use.

### `memory`

Default: `6GiB`

Container memory limit.

## Choosing CPU And Memory

There are three separate knobs:

`cpu_set` controls which host CPU threads the container may use.

`mining_threads` controls how many mining threads XMRig or monerod starts.

`memory` controls the maximum RAM the container can use.

### `cpu_set`

`cpu_set` is an Incus CPU pinning setting. It limits the container to specific logical CPUs from the host.

Example:

```bash
-var="cpu_set=2,3,6,7"
```

This means the container can only run on logical CPUs `2`, `3`, `6`, and `7`.

To see your host CPU layout:

```bash
lscpu -e
```

Useful examples:

```text
cpu_set=2,3       light mining, leaves most of the machine free
cpu_set=2,3,6,7   balanced default, often two physical cores with hyperthreads
cpu_set=0-7       aggressive, allows use of eight logical CPUs
```

For a desktop or server doing other work, do not give the miner every CPU. Leave at least one or two cores free for the host.

### `mining_threads`

`mining_threads` should usually be less than or equal to the number of logical CPUs in `cpu_set`.

Example:

```bash
-var="cpu_set=2,3,6,7" \
-var="mining_threads=4"
```

That allows four logical CPUs and starts four mining threads.

Rule of thumb:

```text
mining_threads <= CPUs listed in cpu_set
```

For Monero RandomX, physical cores usually matter more than hyperthreads. On a CPU with 4 physical cores and 8 logical threads, start with `mining_threads=4`, then test `6` or `8` only if temperatures and responsiveness are acceptable.

If the machine becomes slow, reduce `mining_threads` first.

### `memory`

`memory` is the container RAM limit.

Pool mining with XMRig does not need the full Monero blockchain, so it needs much less memory than solo mining. RandomX still benefits from having enough RAM available.

Recommended starting points:

```text
Pool mining, light:      memory=4GiB
Pool mining, balanced:   memory=6GiB
Solo monerod mining:     memory=6GiB or more
```

If the container is killed, XMRig crashes, or the host logs show out-of-memory errors, increase `memory`.

### Example Profiles

Light profile:

```bash
tofu apply \
  -var="wallet_address=YOUR_XMR_ADDRESS_HERE" \
  -var="cpu_set=2,3" \
  -var="mining_threads=2" \
  -var="memory=4GiB"
```

Balanced profile:

```bash
tofu apply \
  -var="wallet_address=YOUR_XMR_ADDRESS_HERE" \
  -var="cpu_set=2,3,6,7" \
  -var="mining_threads=4" \
  -var="memory=6GiB"
```

Aggressive profile:

```bash
tofu apply \
  -var="wallet_address=YOUR_XMR_ADDRESS_HERE" \
  -var="cpu_set=0-7" \
  -var="mining_threads=6" \
  -var="memory=6GiB"
```

Use the aggressive profile only if the machine is dedicated to mining or you are comfortable with higher CPU usage, heat, fan noise, and power consumption.

## Usage

```bash
tofu init
tofu apply -var="wallet_address=YOUR_XMR_ADDRESS_HERE"
```

That deploys the default pool-mining setup using `pool.supportxmr.com:3333`.

To choose a different pool:

```bash
tofu apply \
  -var="wallet_address=YOUR_XMR_ADDRESS_HERE" \
  -var="pool_url=pool.hashvault.pro:443" \
  -var="pool_tls=true" \
  -var="pool_password=worker1"
```

Use `terraform` instead of `tofu` if you prefer Terraform.

## Pool Terms

`PPLNS`: common Monero pool payout method. Best for miners who stay connected. Payouts depend on your shares in the recent window when the pool finds blocks.

`PPS+`: more predictable payouts, often with higher fees because the pool takes more risk.

`PROP`: proportional payout for the current round. Usually less attractive than PPLNS for steady mining.

`SOLO`: pool infrastructure, but you only get paid if your miner finds a block. Avoid this for regular payouts.

`+ XTM`: the pool may support merge-mining Tari/XTM while mining Monero.

`0.6%`, `1%`, etc: pool fee.

`GH/s`, `MH/s`, `KH/s`: total pool hashrate. Larger pools find blocks more often, but too much hashrate on one pool is worse for Monero decentralization.

## Verification

### Check cloud-init

```bash
incus exec monero-miner -- cloud-init status --long
```

### Check provisioning logs

```bash
incus exec monero-miner -- sudo tail -n 200 /var/log/monero-provision.log
```

### Pool mode: check XMRig

```bash
incus exec monero-miner -- sudo systemctl status xmrig --no-pager -l
```

```bash
incus exec monero-miner -- sudo journalctl -u xmrig -n 100 --no-pager
```

You should see accepted shares after the miner connects and starts working.

### Solo mode: check monerod

```bash
incus exec monero-miner -- sudo systemctl status monerod --no-pager -l
```

```bash
incus exec monero-miner -- bash -lc \
'curl -s http://127.0.0.1:18081/get_info | egrep "\"height\"|\"target_height\"|\"synchronized\"|\"busy_syncing\""'
```

You want to eventually see:

```text
"synchronized": true
```

### Solo mode: check mining status

```bash
incus exec monero-miner -- bash -lc \
'curl -s http://127.0.0.1:18081/mining_status | egrep "\"active\"|\"threads_count\"|\"address\"|\"speed\"|\"status\""'
```

## Security Notes

- In pool mode, XMRig is downloaded from the upstream GitHub release. This is convenient, but it is not verified as strongly as the Monero CLI path.
- In solo mode, Monero CLI binaries are verified with the `binaryFate` signer fingerprint, signed hash list, and SHA256 check.
- No RPC port is exposed outside the container by default.

For stronger anonymity while running a node, see: https://monero.fail/opsec
