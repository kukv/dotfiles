# Throwaway Ubuntu with systemd as PID 1, for exercising mise bootstrap without
# touching a real machine. Targets:
#   base: nothing preinstalled (end-to-end test of bootstrap/init.sh)
#   dev:  mise + shellcheck (iterating on the bootstrap config)
FROM ubuntu:26.04@sha256:f144425ff09be612d6d9ad965196e9cdc23dae1f42110a8a11a3e9a8198759f7 AS base

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        systemd systemd-sysv systemd-resolved dbus sudo curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# The image ships an "ubuntu" user at uid 1000; replace it with tech (uid 1000)
# to match the real machines. The test-only sudoers file is named so that
# init.sh still creates /etc/sudoers.d/tech itself.
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -m -u 1000 -s /bin/bash tech && \
    echo 'tech ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/00-test && \
    chmod 0440 /etc/sudoers.d/00-test

# Test user has no password; let chsh (used by mise's [bootstrap.user]) through. Test image only.
RUN sed -i '1i auth sufficient pam_permit.so' /etc/pam.d/chsh

CMD ["/sbin/init"]

FROM base AS dev
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends git shellcheck && \
    rm -rf /var/lib/apt/lists/*
USER tech
RUN curl -fsSL https://mise.run | sh
USER root
