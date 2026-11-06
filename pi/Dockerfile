FROM ghcr.io/recmanj/dev-containers/base-agent:latest

# The installer defaults to ~/.pi/agent/install, which the wrapper script
# bind-mounts from the host at runtime and would hide the binary. Install
# elsewhere; the ~/.local/bin/pi symlink stays on PATH.
RUN curl -fsSL https://pi.dev/install.sh | PI_CODING_AGENT_DIR=/home/dev/.local/share/pi-agent sh \
    && pi --version \
    && ls -l "$(command -v pi)"

ENTRYPOINT ["pi"]
