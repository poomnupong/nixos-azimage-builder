# Azure CI — architecture and operations

This document describes the Azure side of the **nixos-azure-builder** CI:
the resource-group layout, why RBAC survives between runs, how teardown
failures are handled, and the one-time setup.

## Resource-group layout

We use **one control RG + a small pool of dedicated run RGs**:

```
subscription
├── rg-nixos-ci-control       ← perpetual; shared state (future: staging
│                                storage, budget action group, etc.)
├── rg-nixos-ci-run-01        ← perpetual *container*; emptied after each run
└── rg-nixos-ci-run-02        ← perpetual *container*; emptied after each run
```

The run RGs are **never deleted**. Each CI run picks one from the pool,
uses it, and then empties it. See "Why RBAC survives" below.

Using a small pool (not a single RG) means a slow teardown on one run
does not block the next run — the smoke-test workflow will pick a
different slot.

## Why RBAC survives between runs

Azure role assignments are child resources of the scope they target.
A `Contributor` role assignment on
`/subscriptions/<sub>/resourceGroups/rg-nixos-ci-run-01` lives *inside*
that RG's ARM scope.

* `az group delete rg-nixos-ci-run-01` deletes the RG **and every role
  assignment scoped to it**. Recreating the RG by the same name gives
  you an empty RG with no RBAC — the SP loses access.
* Emptying the RG (deleting its *contents* but leaving the RG itself)
  leaves the role assignments intact because their scope still exists.

So the CI workflow empties the RG with a **complete-mode ARM
deployment of an empty template** (`scripts/azure/empty-rg.json`).
ARM reads the template, sees "desired state = no resources", and
deletes everything currently in the RG — in the correct dependency
order (disks before the VM that references them, NICs before the VNet,
etc.). We don't have to order anything by hand.

## Four layers of cleanup safety

Teardown fails in roughly 20% of runs due to transient ARM errors,
dependency-ordering races, soft-delete protections, stray locks, etc.
The design handles that with four independent layers:

| Layer | Where | Catches |
|-------|-------|---------|
| 1. In-workflow retry | `azure-smoke-test.yml` | Transient ARM errors, throttling, brief ordering races. Up to 3 attempts, 60s backoff. |
| 2. Post-teardown verification | `azure-smoke-test.yml` | Anything still present after layer 1. Fails the job → GitHub notifies you by email. |
| 3. Daily janitor | `azure-janitor.yml` | Everything layer 2 missed, or cases where the smoke-test workflow itself didn't run. Re-attempts teardown on every run RG in the pool; opens/updates a GitHub issue labelled `azure-cleanup` when an RG stays stuck. |
| 4. Azure budget alert | Subscription, created by bootstrap | The ultimate backstop. If all three workflow layers fail silently (revoked token, disabled workflow, etc.), a forgotten VM will trip the budget within days and email you. |

Layer 3 runs on a different schedule than layer 1, so a scheduler
outage on Saturday doesn't prevent detection on Sunday.

## One-time setup

Run the bootstrap script **locally, once**, as a subscription Owner:

```bash
./scripts/bootstrap-azure-ci.sh \
  --subscription <sub-id> \
  --location southeastasia \
  --github-repo poomnupong/nixos-azure-builder \
  --budget-email you@example.com
```

The script:

1. Creates the control RG and `N` run RGs (default 2).
2. Creates a service principal with **federated credentials** for
   GitHub OIDC — no client secrets ever land in the repo.
3. Grants the SP `Contributor` on each run RG and `Reader` on the
   control RG.
4. Creates a monthly subscription budget with an email action group
   (Layer 4).
5. Prints the GitHub secrets and variables you need to set.

### Required GitHub configuration

**Secrets** (Settings → Secrets and variables → Actions → Secrets):

* `AZURE_CLIENT_ID`
* `AZURE_TENANT_ID`
* `AZURE_SUBSCRIPTION_ID`

**Variables** (same page, Variables tab):

* `AZURE_LOCATION` — e.g. `southeastasia`
* `AZURE_CONTROL_RG` — e.g. `rg-nixos-ci-control`
* `AZURE_RUN_RGS` — space-separated list, e.g.
  `rg-nixos-ci-run-01 rg-nixos-ci-run-02`

**Environment**: create a GitHub Actions environment called
`azure-janitor`. Its subject is referenced by the SP's federated
credential, so the janitor workflow can obtain an OIDC token.

## What happens when an RG is stuck

1. The smoke-test workflow goes red — you get a notification from
   GitHub.
2. The next janitor run (within 24h) re-attempts teardown. If it
   also fails, it opens or updates an issue labelled `azure-cleanup`
   listing the stuck resources.
3. Investigate the resources listed in the issue (locks? leases?
   backup items with soft-delete?). Fix the underlying cause and
   close the issue. The janitor will re-open on the next failure.

## Not in scope for this PR

The smoke-test workflow currently contains a placeholder for the
actual "deploy VHD + SSH smoke test" step. Writing that requires
decisions about VHD staging (storage account vs shared image
gallery), VM size, and network topology, all of which belong in a
follow-up change. The teardown safety net — the actual ask — is
complete and useful on its own.
