FROM stalwartlabs/stalwart:v0.16

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY stalwart-cli /usr/local/bin/stalwart-cli
RUN chmod +x /usr/local/bin/stalwart-cli

RUN mkdir -p /etc/stalwart-bootstrap
COPY plan-bootstrap.ndjson /etc/stalwart-bootstrap/plan-bootstrap.ndjson
COPY plan-config.ndjson /etc/stalwart-bootstrap/plan-config.ndjson
COPY entrypoint.sh /usr/local/bin/stalwart-bootstrap-entrypoint.sh
RUN chmod +x /usr/local/bin/stalwart-bootstrap-entrypoint.sh

USER stalwart

ENTRYPOINT ["/usr/local/bin/stalwart-bootstrap-entrypoint.sh"]
