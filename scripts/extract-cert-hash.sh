#!/bin/bash
# Extract certificate hash from signed APK for exclusive Thor Pisu Manager authorization
# This script reads the actual signing certificate from the built APK and calculates its SHA-256

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <apk_path> <output_header>"
    echo "Example: $0 manager/app/build/outputs/apk/release/ThorPisuManager_*.apk kernel/manager/cert_hash.h"
    exit 1
fi

APK_PATH="$1"
OUTPUT_HEADER="$2"

if [ ! -f "$APK_PATH" ]; then
    echo "Error: APK not found at $APK_PATH"
    exit 1
fi

# Temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract the central directory offset from EOCD
cd_offset=$(xxd -l 4 -s $(($(stat -f%z "$APK_PATH" 2>/dev/null || stat -c%s "$APK_PATH") - 22)) "$APK_PATH" | awk '{print $2$3}' | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/')
cd_offset=$((0x$cd_offset))

# Extract signature block size and find the APK Sig Block 42
file_size=$(stat -f%z "$APK_PATH" 2>/dev/null || stat -c%s "$APK_PATH")
sig_block_end=$((file_size - cd_offset - 24))

# Use Python to extract certificate hash
python3 << 'PYTHON_EOF'
import sys
import struct
import hashlib

apk_path = sys.argv[1]
output_header = sys.argv[2]

try:
    with open(apk_path, 'rb') as f:
        # Seek to end
        f.seek(0, 2)
        file_size = f.tell()
        
        # Find EOCD (End of Central Directory)
        f.seek(file_size - 22)
        eocd = f.read(22)
        cd_offset = struct.unpack('<I', eocd[16:20])[0]
        
        # Find APK Sig Block 42
        f.seek(cd_offset - 24)
        block_data = f.read(24)
        sig_block_size = struct.unpack('<Q', block_data[0:8])[0]
        magic = block_data[8:24]
        
        if magic != b'APK Sig Block 42':
            print("Error: Invalid APK signature block", file=sys.stderr)
            sys.exit(1)
        
        # Parse signature block to find v2 signature
        f.seek(cd_offset - sig_block_size - 8)
        sig_block = f.read(sig_block_size)
        
        # Find ID 0x7109871a (v2 signature)
        pos = 8
        while pos < len(sig_block):
            size = struct.unpack('<Q', sig_block[pos:pos+8])[0]
            pos += 8
            if pos + 4 > len(sig_block):
                break
            sig_id = struct.unpack('<I', sig_block[pos:pos+4])[0]
            pos += 4
            
            if sig_id == 0x7109871a:
                # Found v2 signature, extract certificate
                # Structure: signers -> first signer -> signed data -> digests -> certificates
                inner_pos = 0
                
                # Skip to certificates section
                signers_len = struct.unpack('<I', sig_block[pos+inner_pos:pos+inner_pos+4])[0]
                inner_pos += 4 + signers_len
                
                # Read certificates length
                if pos + inner_pos + 4 <= len(sig_block):
                    certs_len = struct.unpack('<I', sig_block[pos+inner_pos:pos+inner_pos+4])[0]
                    inner_pos += 4
                    
                    if pos + inner_pos + 4 <= len(sig_block):
                        cert_size = struct.unpack('<I', sig_block[pos+inner_pos:pos+inner_pos+4])[0]
                        inner_pos += 4
                        
                        if pos + inner_pos + cert_size <= len(sig_block):
                            cert_data = sig_block[pos+inner_pos:pos+inner_pos+cert_size]
                            cert_hash = hashlib.sha256(cert_data).hexdigest()
                            
                            # Write header
                            with open(output_header, 'w') as out:
                                out.write('#ifndef THOR_PISU_CERT_HASH_H\n')
                                out.write('#define THOR_PISU_CERT_HASH_H\n\n')
                                out.write(f'#define THOR_PISU_CERT_HASH "{cert_hash}"\n')
                                out.write(f'#define THOR_PISU_CERT_SIZE {cert_size}\n\n')
                                out.write('#endif\n')
                            
                            print(f"Certificate hash extracted: {cert_hash}")
                            print(f"Certificate size: {cert_size}")
                            print(f"Header written to: {output_header}")
                            sys.exit(0)
                break
            else:
                pos += size
        
        print("Error: Could not find v2 signature in APK", file=sys.stderr)
        sys.exit(1)

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)

PYTHON_EOF

exit $?
