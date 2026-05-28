terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "0.2.0"
    }
  }
}

provider "incus" {}

variable "mining_mode" {
  type        = string
  default     = "pool"
  description = "Mining mode: pool = XMRig directly to a centralized pool; solo = monerod full node solo mining."

  validation {
    condition     = contains(["pool", "solo"], var.mining_mode)
    error_message = "mining_mode must be either pool or solo."
  }
}

variable "wallet_address" {
  type        = string
  description = "Monero address used for pool payouts or solo block rewards. Replace the default value."
  default     = "REPLACE_WITH_YOUR_XMR_ADDRESS"

  validation {
    condition     = var.wallet_address != "REPLACE_WITH_YOUR_XMR_ADDRESS"
    error_message = "You must edit wallet_address and replace REPLACE_WITH_YOUR_XMR_ADDRESS."
  }
}

variable "pool_url" {
  type        = string
  default     = "pool.supportxmr.com:3333"
  description = "Centralized pool stratum endpoint used when mining_mode = pool. Examples: pool.supportxmr.com:3333, pool.hashvault.pro:443, xmr-eu1.nanopool.org:14433."
}

variable "pool_password" {
  type        = string
  default     = "monero-miner"
  description = "Pool password / worker label used by XMRig when mining_mode = pool. Many pools accept a worker name here."
}

variable "pool_tls" {
  type        = bool
  default     = false
  description = "Enable TLS for the XMRig pool connection when the selected pool port requires it."
}

variable "mining_threads" {
  type        = number
  default     = 4
  description = "CPU mining threads for XMRig pool mining or monerod solo mining."

  validation {
    condition     = var.mining_threads > 0
    error_message = "mining_threads must be greater than zero."
  }
}

variable "xmrig_donate_level" {
  type        = number
  default     = 1
  description = "XMRig developer donation level percentage. XMRig enforces a minimum donation level."

  validation {
    condition     = var.xmrig_donate_level >= 0 && var.xmrig_donate_level <= 100
    error_message = "xmrig_donate_level must be between 0 and 100."
  }
}

variable "cpu_set" {
  type        = string
  default     = "2,3,6,7"
  description = "Logical CPUs pinned to this container (e.g. 2,3,6,7 = two full physical cores on i7-4770)."
}

variable "memory" {
  type        = string
  default     = "6GiB"
  description = "Container memory limit."
}

resource "incus_instance" "monero_miner" {
  name    = "monero-miner"
  type    = "container"
  image   = "images:debian/12/cloud"
  running = true

  config = {
    "limits.cpu"         = var.cpu_set
    "limits.memory"      = var.memory
    "limits.memory.swap" = "false"
    "boot.autostart"     = "true"

    "user.user-data" = <<EOF
#cloud-config
package_update: true
packages:
  - ca-certificates
  - wget
  - gnupg
  - bzip2
  - tar
  - gzip
  - curl
  - coreutils

write_files:
  - path: /usr/local/sbin/xmrig-install.sh
    permissions: '0755'
    content: |
      #!/bin/sh
      set -eu

      mkdir -p /opt/xmrig

      API="https://api.github.com/repos/xmrig/xmrig/releases/latest"
      URL="$(curl -fsSL "$API" | sed -n 's/.*"browser_download_url": "\(.*linux-static-x64.tar.gz\)".*/\1/p' | head -n 1)"
      [ -n "$URL" ]

      curl -fL "$URL" -o /root/xmrig-linux-static-x64.tar.gz
      tar -xzf /root/xmrig-linux-static-x64.tar.gz -C /opt/xmrig --strip-components=1
      ln -sf /opt/xmrig/xmrig /usr/local/bin/xmrig

  - path: /usr/local/sbin/xmrig-start.sh
    permissions: '0755'
    content: |
      #!/bin/sh
      set -eu

      TLS_FLAG=""
      if [ "${var.pool_tls}" = "true" ]; then
        TLS_FLAG="--tls"
      fi

      exec /usr/local/bin/xmrig \
        --coin monero \
        --url ${var.pool_url} \
        --user ${var.wallet_address} \
        --pass ${var.pool_password} \
        --threads ${var.mining_threads} \
        --donate-level ${var.xmrig_donate_level} \
        $TLS_FLAG

  - path: /usr/local/sbin/monero-install-cli.sh
    permissions: '0755'
    content: |
      #!/bin/sh
      set -eu

      # 1) Fetch binaryFate signing key and verify the expected fingerprint.
      wget -qO /root/binaryfate.asc https://raw.githubusercontent.com/monero-project/monero/master/utils/gpg_keys/binaryfate.asc
      FPR="$(gpg --with-colons --import-options show-only --import /root/binaryfate.asc | awk -F: '/^fpr:/ {print $10; exit}')"
      [ "$FPR" = "81AC591FE9C4B65C5806AFC3F0AF4D462A0BDF92" ]
      gpg --import /root/binaryfate.asc

      # 2) Download and verify hashes.txt (clearsigned).
      wget -qO /root/hashes.txt https://www.getmonero.org/downloads/hashes.txt
      gpg --verify /root/hashes.txt

      # 3) Extract (sha256, filename) for Linux x64 CLI tarball from hashes.txt.
      LINE="$(tr -d '\r' < /root/hashes.txt | grep -E '^[0-9A-Fa-f]{64}[[:space:]]+monero-linux-x64-v[0-9.]+\.tar\.bz2([[:space:]]*)$' | tail -n 1)"
      [ -n "$LINE" ]

      EXPECTED_HASH="$(echo "$LINE" | awk '{print $1}')"
      FILENAME="$(echo "$LINE" | awk '{print $2}')"
      [ -n "$EXPECTED_HASH" ] && [ -n "$FILENAME" ]

      # 4) Download the latest Linux x64 CLI tarball and save it as the expected filename.
      wget -qO "/root/$FILENAME" https://downloads.getmonero.org/cli/linux64

      # 5) Verify SHA256 of the downloaded tarball.
      ACTUAL_HASH="$(sha256sum "/root/$FILENAME" | awk '{print $1}')"
      [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]

      # 6) Install.
      mkdir -p /opt/monero /var/lib/monero
      tar -xjf "/root/$FILENAME" -C /opt/monero --strip-components=1
      ln -sf /opt/monero/monerod /usr/local/bin/monerod

  - path: /usr/local/sbin/monero-start-solo-mining.sh
    permissions: '0755'
    content: |
      #!/bin/sh
      set -eu

      RPC="http://127.0.0.1:18081"

      # Wait until daemon RPC responds.
      for i in $(seq 1 600); do
        curl -fsS "$RPC/get_info" >/dev/null 2>&1 && break
        sleep 2
      done

      # Wait for full sync before asking monerod to solo mine.
      for i in $(seq 1 7200); do
        INFO="$(curl -fsS "$RPC/get_info" || true)"
        echo "$INFO" | grep -q '"busy_syncing":[[:space:]]*false' && \
        echo "$INFO" | grep -q '"synchronized":[[:space:]]*true' && break
        sleep 5
      done

      for i in $(seq 1 600); do
        RESP="$(curl -fsS -X POST "$RPC/start_mining" \
          -H 'Content-Type: application/json' \
          -d '{"miner_address":"${var.wallet_address}","threads_count":${var.mining_threads},"do_background_mining":true,"ignore_battery":true}' \
          || true)"
        echo "$RESP" | grep -q '"status"[[:space:]]*:[[:space:]]*"OK"' && exit 0
        sleep 10
      done

      exit 1

  - path: /etc/systemd/system/xmrig.service
    permissions: '0644'
    content: |
      [Unit]
      Description=XMRig Monero pool miner
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      ExecStart=/usr/local/sbin/xmrig-start.sh
      Restart=always
      RestartSec=10
      Nice=10

      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/monerod.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Monero daemon (monerod)
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      ExecStart=/usr/local/bin/monerod --non-interactive --data-dir=/var/lib/monero --rpc-bind-ip=127.0.0.1 --rpc-bind-port=18081
      Restart=always
      RestartSec=5
      Nice=10

      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/monero-solo-mining.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Start Monero solo mining through monerod RPC
      After=monerod.service
      Wants=monerod.service

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/monero-start-solo-mining.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

runcmd:
  - |
      set -eux
      exec > /var/log/monero-provision.log 2>&1

      # Wait for systemd to be at least usable.
      for i in $(seq 1 120); do
        state="$(systemctl is-system-running 2>/dev/null || true)"
        [ "$state" = "running" ] && break
        [ "$state" = "degraded" ] && break
        sleep 1
      done

      systemctl daemon-reload

      if [ "${var.mining_mode}" = "pool" ]; then
        /usr/local/sbin/xmrig-install.sh
        systemctl enable --now xmrig.service
      elif [ "${var.mining_mode}" = "solo" ]; then
        /usr/local/sbin/monero-install-cli.sh
        systemctl enable --now monerod.service
        systemctl enable monero-solo-mining.service
        systemctl start --no-block monero-solo-mining.service
      else
        echo "Unsupported mining_mode: ${var.mining_mode}" >&2
        exit 1
      fi
EOF
  }
}
