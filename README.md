# Monerod-installer

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

CPU mining threads for XMRig pool mining or monerod solo mining.

### `xmrig_donate_level`

Default: `1`

XMRig developer donation level percentage.

### `cpu_set`

Default: `2,3,6,7`

Logical CPUs pinned to the container.

### `memory`

Default: `6GiB`

Container memory limit.

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
