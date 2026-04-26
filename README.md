# Resolve + K3s Bootstrap

The repository currently supports two tracks:
- **1-hour Leantime demo** (current priority; architecture in `designdoc.md`)
- **Original Resolve + optional K3s workloads** (legacy functionality kept working)

## 1-hour demo (recommended path)

This is the fastest path to validate Leantime UX on a single machine.

```bash
./bootstrap.sh
```

Then open:

- `https://localhost`
- `http://localhost:30082` (Mailpit inbox for demo emails)

When done:

```bash
./teardown-cluster.sh
```

What this path does:
- Creates isolated `k3s-admin` management user/group
- Installs single-node K3s
- Generates self-signed TLS cert for `localhost`
- Deploys Leantime + in-cluster MariaDB + ingress
- Deploys Mailpit so invite/reset emails work in the demo

## Original Ansible functionality (still supported)

### Resolve Studio install

Download Blackmagic installer manually (license requirement):

- Linux: `DaVinci_Resolve_Studio_20.3.2_Linux.run` -> `./files/`
- macOS: `DaVinci_Resolve_Studio*.dmg` -> `./files/`

Install Resolve role:

```bash
ansible-playbook -K site.yml --tags resolve
```

Launch Resolve:

```bash
resolve
```

### K3s + workload roles

```bash
ansible-playbook -K site.yml --tags k3s,localai,wisemapping
```

Or individually:

```bash
ansible-playbook -K site.yml --tags k3s,localai
ansible-playbook -K site.yml --tags k3s,wisemapping
```

Service defaults:
- Leantime demo NodePort: `30080` (plus ingress `https://localhost`)
- Mailpit inbox NodePort: `30082`
- Wisemapping NodePort: `30081`
- LocalAI service: `ClusterIP` on `8080` by default

Configuration is manifest-first. Edit:
- `kubernetes/apps/leantime/demo-standalone.yaml`
- `kubernetes/apps/localai/standalone.yaml`
- `kubernetes/apps/wisemapping/standalone.yaml`

## Notes

- If you use Wayland, Resolve is often less stable than Xorg.
- Mint 22 / Ubuntu 24.04 may require `libssl1.1`; the role installs it from Ubuntu pool packages.

## Troubleshooting (Leantime onboarding)

If setup redirects to login before you set a password:

1. Open Mailpit at `http://localhost:30082` and use the invite/reset email link.
2. If needed, print the current invite link directly from DB:

```bash
sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config \
  kubectl exec deploy/leantime-mariadb -- \
  mariadb -uleantime -pleantime-pass leantime -Nse \
  "SELECT CONCAT('https://localhost/auth/userInvite/', pwReset) FROM zp_user WHERE id=1;"
```
