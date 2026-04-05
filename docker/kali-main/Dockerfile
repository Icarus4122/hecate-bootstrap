FROM kalilinux/kali-rolling:latest

ENV DEBIAN_FRONTEND=noninteractive

# ── System packages from manifest ─────────────────────────────────
COPY docker/kali-main/apt-packages.txt /tmp/apt-packages.txt
RUN apt-get update \
    && sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/apt-packages.txt \
       | xargs apt-get install -y --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/apt-packages.txt

# ── pipx packages from manifest ───────────────────────────────────
COPY docker/kali-main/pipx-packages.txt /tmp/pipx-packages.txt
RUN while IFS= read -r pkg; do \
        case "$pkg" in ""|\#*) continue ;; esac; \
        pipx install "$pkg"; \
    done < /tmp/pipx-packages.txt \
    && rm -f /tmp/pipx-packages.txt

# ── Shell config (overwrites default /root/.bashrc) ───────────────
COPY docker/kali-main/rootfs/ /

# ── tmux: repo config is bind-mounted at /etc/tmux.d/ at runtime ──
RUN ln -sf /etc/tmux.d/.tmux.conf /root/.tmux.conf

# ── Ensure pipx-installed tools are on PATH ───────────────────────
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /opt/lab
CMD ["/bin/bash"]
