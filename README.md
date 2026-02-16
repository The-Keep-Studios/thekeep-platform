# Resolve + Ansible bootstrap (Linux Mint 22)

This repo bootstraps Ansible on a fresh Mint 22 machine, then uses Ansible to install DaVinci Resolve Studio
via MakeResolveDeb (so you get a proper .deb install you can cleanly uninstall).

## What you must do manually

Download the official Blackmagic installer for Linux:

- `DaVinci_Resolve_Studio_20.3.2_Linux.run`

Place it in:

- `./files/DaVinci_Resolve_Studio_20.3.2_Linux.run`

Blackmagic's licensing requires you fetch this yourself; this repo doesn't redistribute it.

## Quick start

```bash
chmod +x bootstrap.sh
./bootstrap.sh
ansible-playbook -K site.yml
```

Launch Resolve:

```bash
resolve
```

## LocalAI on k3s (Mint host)

How to use:

1) Bootstrap Ansible:

```bash
./bootstrap.sh
```

2) Install k3s + LocalAI:

```bash
ansible-playbook -K site.yml --tags k3s,localai
```

3) Check the pod:

```bash
kubectl -n localai get pods
```

4) Call LocalAI:

- In-cluster: `http://localai.localai.svc.cluster.local:8080`
- NodePort (if enabled): `http://<host-ip>:30880`

Note: Vulkan support is enabled with `USE_VULKAN=true`.

## Notes

- If you are on Wayland, Resolve may crash. Prefer an Xorg session ("Linux Mint on Xorg").
- Mint 22 / Ubuntu 24.04 often needs libssl1.1; this playbook installs it from Ubuntu's pool.
