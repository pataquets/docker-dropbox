FROM debian:stretch

ARG DEBIAN_FRONTEND=noninteractive

# Following 'How do I add or remove Dropbox from my Linux repository?' - https://www.dropbox.com/en/help/246
RUN \
  apt-get update \
  && apt-get -y install ca-certificates gnupg \
  && apt-key adv --keyserver hkps://keyserver.ubuntu.com --recv-keys \
    1C61A2656FB57B7E4DE0F4C1FC918B335044912E \
  && . /etc/os-release \
  && echo "deb http://linux.dropbox.com/debian ${VERSION_CODENAME} main" \
    | tee /etc/apt/sources.list.d/dropbox.list \
  # Perform image clean up.
  && apt-get purge -y gnupg --autoremove \
  && apt-get -y clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN \
  apt-get update && \
  # Install needed packages not depended on by 'dropbox' package.
  apt-get -y install ca-certificates curl python-gpgme \
    libglapi-mesa libxcb-glx0 libxxf86vm1 \
  && \
  apt-get -y install dropbox && \
  apt-get -y clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create service account and set permissions.
RUN \
  groupadd dropbox \
  && useradd -m -d /dbox -c "Dropbox Daemon Account" \
             -s /usr/sbin/nologin -g dropbox dropbox

# Dropbox is weird: it insists on downloading its binaries itself via 'dropbox
# start -i'. So we switch to 'dropbox' user temporarily and let it do its thing.
USER dropbox
RUN mkdir -vp \
    /dbox/.dropbox \
    /dbox/.dropbox-dist \
    /dbox/Dropbox \
    /dbox/base \
    && echo y | dropbox start -i

# Switch back to root, since the run script needs root privs to chmod to the user's preferrred UID
USER root

# Dropbox has the nasty tendency to update itself without asking. In the processs it fills the
# file system over time with rather large files written to /dbox and /tmp. The auto-update routine
# also tries to restart the dockerd process (PID 1) which causes the container to be terminated.
RUN mkdir -vp /opt/dropbox \
    # Prevent dropbox to overwrite its binary
    && mv /dbox/.dropbox-dist/dropbox-lnx* /opt/dropbox/ \
    && mv /dbox/.dropbox-dist/dropboxd /opt/dropbox/ \
    && mv /dbox/.dropbox-dist/VERSION /opt/dropbox/ \
    && rm -rf /dbox/.dropbox-dist \
    && install -dm0 /dbox/.dropbox-dist \
    # Prevent dropbox to write update files
    && chmod -v u-w /dbox \
    && chmod -v o-w /tmp \
    && chmod -v g-w /tmp \
    # Prepare for command line wrapper
    && mv /usr/bin/dropbox /usr/bin/dropbox-cli

# Install init script and dropbox command line wrapper
COPY run /root/
COPY dropbox /usr/bin/dropbox

WORKDIR /dbox/Dropbox
EXPOSE 17500
VOLUME [ "/dbox/.dropbox", "/dbox/Dropbox" ]
ENTRYPOINT [ "/root/run" ]
