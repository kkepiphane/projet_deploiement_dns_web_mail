FROM postgres:15-alpine

COPY init.sql /docker-entrypoint-initdb.d/

VOLUME /var/lib/postgresql/data

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD pg_isready -U $POSTGRES_USER -d $POSTGRES_DB