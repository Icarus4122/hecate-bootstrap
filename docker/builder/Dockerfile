# Ubuntu 24.04 - matches the host OS, gives access to the full
# Ubuntu package ecosystem for native and cross-compilation toolchains
# without pulling in the larger Kali metapackage surface.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ── System packages from manifest ─────────────────────────────────
COPY docker/builder/apt-packages.txt /tmp/apt-packages.txt
RUN apt-get update \
    && sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/apt-packages.txt \
       | xargs apt-get install -y --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/apt-packages.txt

WORKDIR /opt/lab
CMD ["/bin/bash"]
