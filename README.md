# Resolve + Ansible bootstrap (Linux Mint 22)

This repo bootstraps Ansible on a fresh Mint 22 machine, then uses Ansible to install DaVinci Resolve Studio
via MakeResolveDeb (so you get a proper .deb install you can cleanly uninstall).

## What you must do manually

Download the official Blackmagic installer for Linux:

- `DaVinci_Resolve_Studio_20.3.2_Linux.run`

Place it in:

- `./files/DaVinci_Resolve_Studio_20.3.2_Linux.run`

Blackmagic's licensing requires you fetch this yourself; this repo doesn't redistribute it.

For macOS installs, place the Resolve Studio DMG in `./files/` (default pattern: `DaVinci_Resolve_Studio*.dmg`).

## Quick start

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

Setup full site:

```bash
ansible-playbook -K site.yml
```

Resolve only:

```bash
ansible-playbook -K site.yml --tags resolve
```

Launch Resolve:

```bash
resolve
```

macOS (local run):

```bash
ansible-playbook -K -i "localhost," -c local site.yml --tags resolve
```

Note: first launch may prompt for your Resolve Studio license activation.

## k3s workloads (Mint host)

1) Bootstrap Ansible:

```bash
./bootstrap.sh
```

2) Install k3s and workloads:

```bash
ansible-playbook -K site.yml --tags k3s,localai,wisemapping
```

3) Or install one workload:

```bash
ansible-playbook -K site.yml --tags k3s,localai
ansible-playbook -K site.yml --tags k3s,wisemapping
```

4) Check resources:

```bash
kubectl -n localai get pods,svc
kubectl -n wisemapping get pods,svc,pvc
```

5) Access services:

- LocalAI in-cluster: `http://localai.localai.svc.cluster.local:8080`
- LocalAI NodePort (if enabled): `http://<host-ip>:30880`
- Wisemapping NodePort: `http://<host-ip>:30080`

Config defaults are in `group_vars/all.yml` (`enable_k3s`, `enable_localai`, `enable_wisemapping`, service ports, storage, and image settings).

## Notes

- If you are on Wayland, Resolve may crash. Prefer an Xorg session ("Linux Mint on Xorg").
- Mint 22 / Ubuntu 24.04 often needs libssl1.1; this playbook installs it from Ubuntu's pool.
