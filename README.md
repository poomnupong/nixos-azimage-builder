# nixos-azure-builder

> **Non-Profit / Reference Use.**  
> This repository is provided as a reference implementation for building
> customised NixOS VHD images for Microsoft Azure.  It is intended for
> educational, non-commercial, and personal use.  You are free to fork it and
> adapt it to your own needs under the terms of the [MIT License](LICENSE).

---

## What this does

The **Weekly Forge** pipeline uses [Nix Flakes](https://nixos.wiki/wiki/Flakes)
and [nixos-generators](https://github.com/nix-community/nixos-generators) to
build a ready-to-deploy NixOS `.vhd` image every Saturday at 00:00 US Central
Standard Time (06:00 UTC).  The resulting image is uploaded as a GitHub Release
tagged with the build timestamp (`YYYYMMDD-HHMM`).

---

## Image features

Out of the box the generated VHD gives you:

* **Azure-ready boot.** Built with the nixos-generators `azure` format, which
  configures the kernel, bootloader and disk layout for Azure's Hyper-V host
  and ships the **Microsoft Azure Linux Agent (`waagent`)** so the VM
  provisions correctly (hostname, SSH keys, resource disk, serial console,
  heartbeat / health to the Azure fabric).
* **Hardened OpenSSH.** `services.openssh` is enabled with
  `PasswordAuthentication = false` and `PermitRootLogin = no` — the only way
  in is via the SSH public keys you add in `core_pulse.nix`.
* **Ready-to-use default user.** A `nixos` user in the `wheel` and
  `networkmanager` groups with passwordless `sudo` (handy for
  automation / CI/CD), pinned to your SSH keys.
* **Sensible base toolchain.** `git`, `curl`, `wget`, `htop` and `vim` are
  preinstalled; extend the list in `core_pulse.nix` with anything else you
  need.
* **UTC / en_US.UTF-8 defaults** for predictable log timestamps and locale
  behaviour in automation.
* **Reproducible, pinned builds.** The Nix flake pins
  `nixpkgs` to `nixos-unstable`, so every weekly release is fully
  reproducible from the tagged commit.
* **Automated weekly releases.** The `weekly_forge` GitHub Actions workflow
  rebuilds the image every Saturday and publishes a gzip-compressed VHD as a
  GitHub Release (`YYYYMMDD-HHMM`).
* **Optional Azure CI safety net.** If you run the one-time Azure bootstrap
  (see below), the `azure-smoke-test` and `azure-janitor` workflows will
  deploy the latest VHD end-to-end and sweep stale run resource groups. Forks
  that skip the bootstrap simply skip these workflows — the image itself
  builds and releases without any Azure credentials.

> Additional agents such as the **Azure Monitor Agent**, Log Analytics
> extensions, or other VM extensions are not baked into the image; install
> them either as Azure VM extensions at deploy time (recommended — see
> [Observability (optional)](#observability-optional) below) or by adding
> the corresponding NixOS modules / packages to `core_pulse.nix` before
> building.

---

## Azure compliance & provisioning model

The image is configured to match Microsoft's
[Prepare a Linux VHD for Azure](https://learn.microsoft.com/azure/virtual-machines/linux/create-upload-generic)
checklist out of the box — you should not normally need to add anything to
`core_pulse.nix` for it to be Azure-compliant.

| Checklist item | Where it comes from |
|---|---|
| **Azure Linux Agent (`waagent`) — the VM guest agent Azure requires** | `services.waagent.enable = true` in upstream `azure-common.nix` |
| **cloud-init** enabled for provisioning (SSH host keys, user injection, network) | `services.cloud-init.enable = true` in upstream `azure-common.nix` |
| Serial console on `ttyS0` @ 115200 baud | kernel params in `azure-common.nix` |
| Hyper-V kernel modules (`hv_vmbus`, `hv_netvsc`, `hv_utils`, `hv_storvsc`) in initrd | `boot.initrd.kernelModules` in `azure-common.nix` |
| Non-predictable interface names + systemd-networkd (safe to clone) | `networking.usePredictableInterfaceNames = false` |
| Hostname sourced from Azure metadata | `networking.hostName = lib.mkDefault ""` |
| Resource-disk handling deferred to cloud-init | waagent `Provisioning.Enable = !cloud-init.enable` default |

**Provisioning split.** On this image, **cloud-init** performs first-boot
provisioning (SSH host keys, user injection, network config) and **waagent**
handles the Azure-specific side (heartbeat to the fabric, extension
execution, Azure metadata integration). This is the modern Microsoft-endorsed
pattern for Linux images on Azure; waagent auto-disables its own provisioning
path (`Provisioning.Enable` defaults to `!cloud-init.enable`) so the two
don't collide. If you need to opt out of cloud-init (rare — typically only
for offline/air-gapped builds), override with
`services.cloud-init.enable = lib.mkForce false;` in `core_pulse.nix`; waagent
will then do provisioning itself.

---

## Observability (optional)

The **Azure Monitor Agent (AMA)** is frequently confused with the VM guest
agent, but they are different things:

* **waagent** is the *guest agent* Azure requires. It's already in the image
  (see above) — you don't need to do anything.
* **AMA** is a *VM extension* for metrics/logs ingestion into Log Analytics.
  It is **not** baked into this image on purpose: VM extensions auto-update
  out-of-band, which would defeat the deterministic-image goal.

The recommended deterministic way to install AMA is to declare it at deploy
time with a **pinned `typeHandlerVersion`** and
**`autoUpgradeMinorVersion: false`**, so you decide when to roll a new
version, e.g. as part of your ARM/Bicep/Terraform template:

```json
{
  "type": "Microsoft.Compute/virtualMachines/extensions",
  "apiVersion": "2023-09-01",
  "name": "[concat(parameters('vmName'), '/AzureMonitorLinuxAgent')]",
  "location": "[parameters('location')]",
  "properties": {
    "publisher": "Microsoft.Azure.Monitor",
    "type": "AzureMonitorLinuxAgent",
    "typeHandlerVersion": "1.33",
    "autoUpgradeMinorVersion": false,
    "enableAutomaticUpgrade": false,
    "settings": {}
  }
}
```

The same pattern applies to other Microsoft-published extensions (Custom
Script, Dependency Agent, Disk Encryption, etc.).

---

## Repository layout

```
nixos-azure-builder/
├── flake.nix                        # Nix Flake entry-point — defines the azureImage output
├── core_pulse.nix                   # ← YOUR customisation module (packages, users, SSH keys)
├── get_version.sh                   # Generates the YYYYMMDD-HHMM version / release tag
├── scripts/
│   ├── bootstrap-azure-ci.sh        # One-time Azure + GitHub OIDC bootstrap (run locally)
│   └── azure/
│       └── empty-rg.json            # Empty ARM template used to empty a run RG
├── docs/
│   └── ci-azure.md                  # Azure CI architecture & operations guide
├── .github/
│   └── workflows/
│       ├── weekly_forge.yml         # Weekly VHD build + GitHub Release
│       ├── azure-smoke-test.yml     # Deploys the VHD to Azure and tears the RG down
│       └── azure-janitor.yml        # Daily cleanup safety net for stuck run RGs
├── LICENSE                          # MIT
└── README.md                        # This file
```

---

## How to customise the image

1. **Fork** this repository.
2. **Edit `core_pulse.nix`** — this is the only file you normally need to
   touch:

   ```nix
   # core_pulse.nix
   { pkgs, ... }:
   {
     environment.systemPackages = with pkgs; [
       git curl wget htop vim
       # Add your tools here ↓
       tmux python3 awscli2
     ];

     users.users.alice = {
       isNormalUser = true;
       extraGroups = [ "wheel" ];
       openssh.authorizedKeys.keys = [
         "ssh-ed25519 AAAA... alice@myhost"
       ];
     };
   }
   ```

3. **Push to `main`**.  The workflow will pick it up, build a fresh image, and
   publish a GitHub Release automatically.

---

## Building locally

You need [Nix](https://nixos.org/download) with flakes enabled.

```bash
# Build the Azure VHD
nix build .#azureImage

# The image will be available at ./result/
ls result/
```

---

## Deploying to Azure

1. Upload the `.vhd` from the GitHub Release to an **Azure Storage Account**.
2. Create a **Managed Image** from the blob.
3. Launch a VM from that image.

The default `core_pulse.nix` disables password authentication; make sure you
have added your SSH public key before building.

---

## Azure CI setup (one-time bootstrap)

The weekly build always runs in GitHub Actions, but the **smoke-test** and
**janitor** workflows need to talk to Azure. To keep client secrets out of the
repo, authentication is done via **GitHub OIDC federation** to a Microsoft
Entra ID (formerly Azure AD) service principal. The `scripts/bootstrap-azure-ci.sh` helper provisions
everything in Azure and prints the values you need to paste into GitHub.

> Run this **once, locally**, as a user with **Owner** on the target
> subscription. Do not run it from CI — CI's own service principal must not be
> able to grant itself new permissions.

### Prerequisites

* An Azure subscription you own (or have `Owner` on).
* [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed
  and logged in: `az login`.
* Your GitHub repository (fork) already pushed to `github.com`.
* `bash` (the script is POSIX-ish `bash`, tested on Linux and macOS).

### Preparing the parameters

Gather these values before running the script — they are what wire up the
OIDC trust between GitHub and Azure:

| Flag | What it is | How to get it |
|------|------------|---------------|
| `--subscription` | The Azure subscription ID the RGs will live in. | `az account show --query id -o tsv` |
| `--location` | Azure region for the resource groups (e.g. `southeastasia`, `eastus`). | Pick any region close to you; it only affects the RG metadata and where the smoke-test VM will run. |
| `--github-repo` | Your GitHub repo in `owner/name` form. **Must match exactly** — it becomes the `sub` claim the OIDC token is validated against. | e.g. `poomnupong/nixos-azure-builder` (or `yourname/your-fork`). |
| `--budget-email` | Email address for the Layer-4 budget alert (80% of monthly spend). | Any mailbox you check. |
| `--run-rg-count` *(optional)* | How many run resource groups to create (default `2`). | Two is enough; increase only if smoke tests overlap. |
| `--control-rg` *(optional)* | Name of the shared control RG (default `rg-nixos-ci-control`). | |
| `--run-rg-prefix` *(optional)* | Prefix for the run RG names (default `rg-nixos-ci-run`, yielding `rg-nixos-ci-run-01`, `-02`, …). | |
| `--sp-name` *(optional)* | Display name of the service principal (default `sp-nixos-azure-builder-ci`). | |
| `--budget-amount` *(optional)* | Monthly budget in USD (default `10`). | |

The script is **idempotent** — re-running it reconciles state instead of
creating duplicates.

### Running the bootstrap

```bash
./scripts/bootstrap-azure-ci.sh \
  --subscription <sub-id> \
  --location southeastasia \
  --github-repo <your-gh-user>/nixos-azure-builder \
  --budget-email you@example.com
```

What it does:

1. Creates the control RG and `N` run RGs.
2. Creates a Microsoft Entra ID application + service principal with **federated
   credentials** trusting tokens from GitHub Actions for:
   * `ref:refs/heads/main` (weekly build + smoke test)
   * `environment:azure-janitor` (daily janitor)
3. Grants the SP `Contributor` on each run RG and `Reader` on the control RG.
4. Creates a monthly subscription budget with an email notification (Layer 4
   backstop).
5. Prints the GitHub Secrets / Variables you need to configure.

### Wiring the output into GitHub

After the script finishes, configure these under **Settings → Secrets and
variables → Actions** in your repo:

**Secrets**

* `AZURE_CLIENT_ID` — the app registration's `appId` (printed by the script).
* `AZURE_TENANT_ID` — your Microsoft Entra ID tenant ID (printed by the script).
* `AZURE_SUBSCRIPTION_ID` — the subscription ID you passed in.

**Variables**

* `AZURE_LOCATION` — e.g. `southeastasia`.
* `AZURE_CONTROL_RG` — e.g. `rg-nixos-ci-control`.
* `AZURE_RUN_RGS` — space-separated list, e.g. `rg-nixos-ci-run-01 rg-nixos-ci-run-02`.

**Environment**

Create an Actions environment named **`azure-janitor`** (Settings →
Environments → New environment). Its name appears in the federated credential
subject the janitor workflow uses to obtain an OIDC token, so the name must
match exactly.

For deeper architectural details (why RBAC survives run-RG teardown, the four
cleanup layers, what to do when an RG is stuck) see
[`docs/ci-azure.md`](docs/ci-azure.md).

---

## Version format

Releases are tagged `YYYYMMDD-HHMM` (UTC), e.g. `20260324-0000`.  
The tag is generated by `get_version.sh`:

```bash
./get_version.sh   # → 20260324-0426
```

---

## License

[MIT](LICENSE) © 2026 Poom Nupong
