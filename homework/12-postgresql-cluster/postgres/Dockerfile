FROM postgres:16-bookworm

RUN apt-get update \
    && apt-get install --no-install-recommends -y python3 python3-venv curl \
    && python3 -m venv /opt/patroni \
    && /opt/patroni/bin/pip install --no-cache-dir 'patroni[etcd3]==4.1.5' 'psycopg2-binary==2.9.11' \
    && mkdir -p /var/lib/postgresql/pgdata \
    && chown postgres:postgres /var/lib/postgresql/pgdata \
    && chmod 0700 /var/lib/postgresql/pgdata \
    && rm -rf /var/lib/apt/lists/*

USER postgres
ENTRYPOINT ["/opt/patroni/bin/patroni", "/etc/patroni.yml"]
