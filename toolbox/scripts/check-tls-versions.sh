#!/usr/bin/env bash
#
# check-tls-versions.sh
# https://github.com/half0wl/dotfiles
#
# Check supported TLS versions for a domain.
#
# Usage:
#
#   ./check-tls-versions.sh domain.com [port]
#
# Example Output:
#
#   ./check-tls-versions.sh railway.com
#   Checking TLS Versions for railway.com:443...
#   ✗ SSLv3: Not Supported or Connection Failed
#   ✗ TLSv1.0: Not Supported
#   ✗ TLSv1.1: Not Supported
#   ✓ TLSv1.2: Supported (Cipher: ECDHE-ECDSA-CHACHA20-POLY1305)
#   ✓ TLSv1.3: Supported (Cipher: TLS_AES_256_GCM_SHA384)
#
#   Negotiated connection (highest available):
#     Protocol: TLSv1.3
#     Cipher: TLS_AES_256_GCM_SHA384
#     Certificate Subject:
#       subject=CN=railway.com

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$1" ]; then
  echo "Usage: $0 domain.com [port]"
  echo "Example: $0 google.com 443"
  exit 1
fi

DOMAIN=$1
PORT=${2:-443}

echo ""
echo "Checking TLS Versions for $DOMAIN:$PORT..."
echo ""

declare -a TLS_VERSIONS=(
  "ssl3:SSLv3"
  "tls1:TLSv1.0"
  "tls1_1:TLSv1.1"
  "tls1_2:TLSv1.2"
  "tls1_3:TLSv1.3"
)

check_tls_version() {
  local version_flag=$1
  local version_name=$2

  output=$(timeout 5 openssl s_client -connect "$DOMAIN:$PORT" -$version_flag 2>&1 </dev/null)

  if echo "$output" | grep -q "CONNECTED"; then
    if echo "$output" | grep -q "Cipher is (NONE)"; then
      echo -e "${RED}✗ $version_name   : Not Supported${NC}"
    elif echo "$output" | grep -q "no protocols available"; then
      echo -e "${RED}✗ $version_name   : Not Supported${NC}"
    elif echo "$output" | grep -q "wrong version number"; then
      echo -e "${RED}✗ $version_name   : Not Supported${NC}"
    elif echo "$output" | grep -q "handshake failure"; then
      echo -e "${RED}✗ $version_name   : Not Supported${NC}"
    else
      cipher=$(
        echo \
          "$output" |
          grep "Cipher" |
          grep -v "Cipher is (NONE)" |
          head -n1 |
          awk '{print $NF}'
      )
      if [ ! -z "$cipher" ]; then
        echo -e "${GREEN}✓ $version_name   : Supported${NC} (Cipher: $cipher)"
      else
        echo -e "${GREEN}✓ $version_name   : Supported${NC}"
      fi
    fi
  else
    echo -e "${RED}✗ $version_name     : Not Supported${NC}"
  fi
}

for version_info in "${TLS_VERSIONS[@]}"; do
  IFS=':' read -r flag name <<<"$version_info"
  check_tls_version "$flag" "$name"
done

echo ""
echo "Negotiated connection details (highest available):"
output=$(timeout 5 openssl s_client -connect "$DOMAIN:$PORT" 2>&1 </dev/null)

protocol=$(echo "$output" | grep "Protocol" | head -n1 | awk '{print $NF}')
if [ ! -z "$protocol" ]; then
  echo "  Protocol: $protocol"
fi

cipher=$(echo "$output" | grep "Cipher" | grep -v "Cipher is (NONE)" | head -n1 | awk '{print $NF}')
if [ ! -z "$cipher" ]; then
  echo "  Cipher: $cipher"
fi

subject=$(echo "$output" | grep "subject=" | head -n1)
if [ ! -z "$subject" ]; then
  echo "  Certificate Subject:"
  echo "    $subject"
fi

echo ""
