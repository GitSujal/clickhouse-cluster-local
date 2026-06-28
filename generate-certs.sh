#!/bin/bash
set -e

echo "=========================================="
echo "Generate Self-Signed TLS Certificates"
echo "=========================================="
echo ""

CERT_DIR="./certs"
mkdir -p "$CERT_DIR"

echo "Generating self-signed certificate for localhost..."
echo ""

# Generate private key
openssl genrsa -out "$CERT_DIR/server.key" 2048

# Generate certificate signing request
openssl req -new -key "$CERT_DIR/server.key" -out "$CERT_DIR/server.csr" \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=localhost"

# Generate self-signed certificate (valid for 365 days)
openssl x509 -req -days 365 \
  -in "$CERT_DIR/server.csr" \
  -signkey "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.crt" \
  -extfile <(printf "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1")

# Combine certificate and key for HAProxy
cat "$CERT_DIR/server.crt" "$CERT_DIR/server.key" > "$CERT_DIR/server.pem"

# Set proper permissions (644 for container access)
chmod 644 "$CERT_DIR/server.key" "$CERT_DIR/server.pem"
chmod 644 "$CERT_DIR/server.crt"
chmod 644 "$CERT_DIR/server.csr"

echo "✓ Certificates generated in $CERT_DIR/"
echo ""
echo "Files created:"
echo "  server.key - Private key"
echo "  server.crt - Certificate"
echo "  server.pem - Combined cert+key for HAProxy"
echo ""
echo "⚠️  WARNING: These are self-signed certificates for development only!"
echo "For production, use certificates from a trusted CA (Let's Encrypt, etc.)"
echo ""
echo "Next steps:"
echo "  1. Update docker-compose.yml to mount certificates"
echo "  2. Update haproxy.cfg to enable TLS"
echo "  3. Restart HAProxy: docker-compose restart haproxy"
echo ""
