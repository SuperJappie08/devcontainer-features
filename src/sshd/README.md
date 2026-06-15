
# SSH server (sshd)

Adds a SSH server into a container so that you can use an external terminal, sftp, or SSHFS to interact with it.

## Example Usage

```json
"features": {
    "ghcr.io/SuperJappie08/devcontainer-features/sshd:0": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Currently unused. | string | latest |
| gatewayPorts | Enable other hosts in the same network to connect to the forwarded ports | string | no |

> [!IMPORTANT]
> THIS IS INCOMPLETE
> THIS IS BASED ON REFERENCE FEATURE

# OS Support
Only Debian-based for now


---

_Note: This file was auto-generated from the [devcontainer-feature.json](devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
