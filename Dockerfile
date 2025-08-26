FROM archlinux:latest

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm base-devel git sudo fakeroot which gnupg && \
    pacman -Scc --noconfirm

RUN useradd -m -G wheel -s /bin/bash builder && \
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-wheel-nopasswd && \
    chmod 0440 /etc/sudoers.d/99-wheel-nopasswd

RUN mkdir -p /opt/upload /opt/packages /build

COPY build-aur.sh /usr/local/bin/build-aur.sh
RUN chmod +x /usr/local/bin/build-aur.sh

VOLUME ["/opt/upload", "/opt/packages"]

WORKDIR /build
ENTRYPOINT ["/usr/local/bin/build-aur.sh"]