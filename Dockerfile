FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=America/Sao_Paulo
USER root
RUN set -ex \
    && sed -i "s/archive.ubuntu.com/br.archive.ubuntu.com/g" /etc/apt/sources.list \
    && echo '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d \
    && echo "postfix postfix/mailname string example.com" | debconf-set-selections \
    && echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections \
    && apt-get update \
    && apt-get -y install --only-upgrade \
        $( apt-get --just-print upgrade | awk 'tolower($4) ~ /.*security.*/ || tolower($5) ~ /.*security.*/ {print $2}' | sort | uniq ) \
    && apt-get -y install --no-install-recommends tzdata dovecot-core dovecot-imapd postfix mailutils supervisor iproute2 telnet \
    && rm -rf /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin /var/lib/apt/lists/* || true

RUN set -ex \
    && echo '[supervisord] \n\
user = root \n\
nodaemon = true \n\
[program:postfix] \n\
command = /usr/sbin/postfix start-fg \n\
auto_start = true \n\
autorestart = true \n\
startsecs=2 \n\
startretries=3 \n\
stopsignal=TERM \n\
stopwaitsecs=2 \n\
redirect_stderr=true \n\
stdout_logfile = /dev/stdout \n\
stdout_logfile_maxbytes = 0 \n\
[program:dovecot] \n\
command = /usr/sbin/dovecot -F \n\
auto_start = true \n\
autorestart = true \n\
startsecs=2 \n\
startretries=3 \n\
stopsignal=TERM \n\
stopwaitsecs=2 \n\
redirect_stderr=true \n\
stdout_logfile = /dev/stdout \n\
stdout_logfile_maxbytes = 0' > /etc/supervisor/conf.d/postfix.conf \
    && ln -sf /proc/self/fd/1 /var/log/supervisor/supervisord.log

RUN set -ex \
    && postconf -e "maillog_file = /dev/stdout" \
    && postconf -e "mynetworks = 127.0.0.0/8, 10.0.0.0/8" \
    && postconf -e "inet_interfaces = all" \
    && postconf -e "inet_protocols = ipv4" \
    && postconf -e "mydestination = localhost.localdomain, localhost" \
    && postconf -e "home_mailbox = Maildir/" \
    && postconf -e "myhostname = localhost" \
    && postconf -e "smtpd_sasl_type = dovecot" \
    && postconf -e "smtpd_sasl_path = private/auth" \
    && postconf -e "smtpd_sasl_auth_enable = yes" \
    && postconf -e "smtpd_sasl_security_options = noanonymous" \
    && postconf -e "smtpd_sasl_local_domain = $myhostname" \
    && postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_auth_destination, permit_sasl_authenticated, reject"

RUN set -ex \
    && echo 'listen = *' > /etc/dovecot/conf.d/99-custom.conf \
    && echo "disable_plaintext_auth = no" >> /etc/dovecot/conf.d/99-custom.conf \
    && echo "auth_mechanisms = plain login" >> /etc/dovecot/conf.d/99-custom.conf \
    && echo "mail_location = maildir:~/Maildir" >> /etc/dovecot/conf.d/99-custom.conf \
    && echo 'service auth {' >> /etc/dovecot/conf.d/99-custom.conf \
    && echo '  unix_listener /var/spool/postfix/private/auth {' >> /etc/dovecot/conf.d/99-custom.conf \
    && echo '    mode = 0666' >> /etc/dovecot/conf.d/99-custom.conf \
    && echo '    user = postfix' >> /etc/dovecot/conf.d/99-custom.conf \
    && echo '    group = postfix' >> /etc/dovecot/conf.d/99-custom.conf \
    && echo '  }' >> /etc/dovecot/conf.d/99-custom.conf \
    && echo '}' >> /etc/dovecot/conf.d/99-custom.conf \
    && echo "log_path = /dev/stdout" >> /etc/dovecot/conf.d/99-custom.conf \
    && echo "info_log_path = /dev/stdout" >> /etc/dovecot/conf.d/99-custom.conf \
    && echo "debug_log_path = /dev/stdout" >> /etc/dovecot/conf.d/99-custom.conf

RUN set -ex \
    && useradd -s /bin/bash -d /home/user1 -m user1 \
    && echo "user1:pass" | chpasswd \
    && useradd -s /bin/bash -d /home/user2 -m user2 \
    && echo "user2:pass" | chpasswd

RUN set -ex \
    && postconf -e "sender_dependent_default_transport_maps = hash:/etc/postfix/sender_transport_maps" \
    && echo 'noreply@example.com smtp:[10.10.10.210]:25' > /etc/postfix/sender_transport_maps \
    && echo 'noreply@example.com.br smtp:[10.10.10.210]:25' >> /etc/postfix/sender_transport_maps \
    && postmap /etc/postfix/sender_transport_maps

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/postfix.conf"]

STOPSIGNAL SIGTERM
EXPOSE 25