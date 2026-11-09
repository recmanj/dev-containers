# Distrobox images

Fedora images for [distrobox](https://distrobox.it/) with all tooling baked
in, so boxes don't install anything on first enter.

- `distrobox/base`: tools every box needs (git, jq, make, vim, yq)
- `distrobox/oxidian`: Ansible, OpenTofu, sops, age, uv
- `distrobox/ecmwf`: Teleport
- `distrobox/eodh`: AWS CLI, Terraform, kubectl, helm, kustomize, k9s

Use them from a `distrobox.ini`:

```ini
[eodh]
image=ghcr.io/recmanj/dev-containers/distrobox/eodh:latest
```

After an image update, recreate the boxes:

```sh
distrobox assemble create --replace
```

The Fedora base image is pinned by version and digest. Renovate bumps it, and
the nightly build picks up dnf package updates. Fedora major upgrades wait for
approval on the Dependency Dashboard, because Fedora publishes the next
release's tag before it's final.
