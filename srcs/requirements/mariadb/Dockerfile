FROM debian:12.15-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends mariadb-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/99-inception.cnf /etc/mysql/mariadb.conf.d/99-inception.cnf

COPY tools/init.sh /usr/local/bin/init.sh

RUN chmod 644 /etc/mysql/mariadb.conf.d/99-inception.cnf \
    && chmod 755 /usr/local/bin/init.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/init.sh"]