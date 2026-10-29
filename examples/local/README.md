# Local example

Applies circuit-agentbox to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman. On a Mac, rootful Podman, the Podman machine's root connection, is what CI and the other circuits use. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` The example creates a user `dev` that logs in with the same key as root, installs `cowsay` and `semver` through `npm_packages` in place of real agents, and clones a small public repository into `~/code`. To look at the result:

```sh
ssh -p 2290 -i id_ed25519 -o UserKnownHostsFile=known_hosts dev@127.0.0.1
cowsay hello
ls ~/code
```

`up.sh` listens on `127.0.0.1:2290`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
