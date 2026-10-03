# jupyter-k8

JupyterLab for one user on the single-node k3s cluster `archi`, at
**https://jupyter.angora-wahoo.ts.net** (tailnet only).

The image is the upstream `quay.io/jupyter/scipy-notebook` plus the packages
in [`requirements.txt`](requirements.txt).

## How a change gets deployed

```
push to main ──► GitHub Actions job on the self-hosted runner `jupyter` (ARC, in the cluster)
                   │  buildctl ──► BuildKit (namespace buildkit)
                   │  push     ──► registry.registry.svc:5000/jupyter:<sha>
                   │  commit   ──► k8s/kustomization.yaml now names localhost:30500/jupyter:<sha>
                   ▼
                 Argo CD Application `jupyter` syncs k8s/ ──► new pod, same PVC
```

- **Add a Python package:** add a line to `requirements.txt` and push. The new
  image is running a few minutes later. The workflow fails, and nothing is
  deployed, if a package does not import.
- **Change a manifest** (`k8s/`): push. Argo CD applies it; no image is built.
- **Upgrade the base image:** change the `FROM` tag in `Dockerfile`.

## Layout

| Path | What |
|---|---|
| `Dockerfile`, `requirements.txt` | the image |
| `k8s/` | what Argo CD deploys: PVC, Deployment, Service, Ingress |
| `.github/workflows/deploy.yml` | build, push, bump the tag, wait for Argo CD |
| `cluster/` | one-time cluster setup, applied by hand (runner, RBAC, Argo CD Application) |

## Your data

All notebooks live on the PVC `jupyter-home`, mounted as `/home/jovyan`.
A new image or a pod restart does not touch it. It is protected three ways:

1. The PVC has `argocd.argoproj.io/sync-options: Prune=false,Delete=false`,
   so Argo CD never deletes it.
2. Its PV has `reclaimPolicy: Retain`, so the files stay on disk even if the
   PVC is deleted. On the host they are in
   `/var/lib/rancher/k3s/storage/pvc-c6d72666-…_jupyter_jupyter-home` (root only).
3. The Namespace is not managed by Argo CD, so it is never pruned.

`PIP_USER=1` is set, so `%pip install x` in a notebook goes to `~/.local` on
the PVC and survives restarts too. Packages in `~/.local` take priority over
the ones in the image; remove them from there if you move them to
`requirements.txt`.

## One-time setup (already done on archi)

```bash
# 1. login token - random, never printed, never in git
kubectl -n jupyter create secret generic jupyter-token \
  --from-literal=token="$(openssl rand -hex 32)"

# 2. runner identity + RBAC
kubectl apply -f cluster/runner-rbac.yaml

# 3. GitHub App credentials for the runner: a copy of the splitek Secret
#    (same app, same installation)
kubectl -n arc-runners get secret splitek-github-app -o json \
  | jq '{apiVersion, kind, type, data, metadata: {name: "jupyter-github-app", namespace: "arc-runners"}}' \
  | kubectl apply -f -

# 4. runner scale set; the release name `jupyter` is the `runs-on:` label
helm install jupyter \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2 -n arc-runners -f cluster/arc-values.yaml --wait

# 5. Argo CD
kubectl apply -f cluster/argocd-application.yaml
```

Read the login token:

```bash
kubectl -n jupyter get secret jupyter-token -o jsonpath='{.data.token}' | base64 -d; echo
```

## Security

- **Public repo, self-hosted runner.** The workflow has no `pull_request`
  trigger and runs only for `muzieh/jupyter-k8`. The repository requires
  approval before any workflow from an outside contributor runs. Never add a
  `pull_request_target` trigger.
- **No secrets in git.** The token and the GitHub App key exist only as
  Kubernetes Secrets.
- **The pod:** notebooks can run any code and open a terminal. The pod runs as
  non-root, with no privilege escalation and no Kubernetes service account
  token. Access needs tailnet membership AND the token.

## Planned: login through the Synology NAS (OIDC)

DSM's SSO Server on `superbox` as the OIDC provider, with oauth2-proxy in front
of this Service. Pods resolve `superbox.angora-wahoo.ts.net` through the static
CoreDNS entry in `~/prog/archi-cluster-infra/k8s/coredns/`.
Redirect URI to register in DSM: `https://jupyter.angora-wahoo.ts.net/oauth2/callback`.
