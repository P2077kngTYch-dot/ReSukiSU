#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <apk_path> <output_header>" >&2
    exit 1
fi

APK_PATH="$1"
OUTPUT_HEADER="$2"

if [ ! -f "$APK_PATH" ]; then
    echo "Error: APK not found: $APK_PATH" >&2
    exit 1
fi

python3 - "$APK_PATH" "$OUTPUT_HEADER" <<'PYTHON_EOF'
import sys
import struct
import hashlib
import os

apk_path = sys.argv[1]
output_header = sys.argv[2]

def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]

def u64(data, offset):
    return struct.unpack_from("<Q", data, offset)[0]

try:
    with open(apk_path, "rb") as f:
        f.seek(0, 2)
        file_size = f.tell()

        # Find EOCD.
        search_size = min(file_size, 65557)
        f.seek(file_size - search_size)
        tail = f.read(search_size)

        eocd_pos = tail.rfind(b"PK\x05\x06")
        if eocd_pos < 0:
            raise RuntimeError("EOCD record not found")

        cd_offset = u32(tail, eocd_pos + 16)

        if cd_offset < 24:
            raise RuntimeError("Invalid central directory offset")

        # APK Signing Block footer.
        f.seek(cd_offset - 24)
        footer = f.read(24)

        if len(footer) != 24:
            raise RuntimeError("Could not read APK Signing Block footer")

        sig_block_size = u64(footer, 0)

        if footer[8:24] != b"APK Sig Block 42":
            raise RuntimeError("APK Signing Block 42 not found")

        if sig_block_size < 24:
            raise RuntimeError("Invalid APK Signing Block size")

        total_size = sig_block_size + 8
        block_start = cd_offset - total_size

        if block_start < 0:
            raise RuntimeError("Invalid APK Signing Block start")

        f.seek(block_start)
        signing_block = f.read(total_size)

        if len(signing_block) != total_size:
            raise RuntimeError("Incomplete APK Signing Block")

        # Parse ID/value pairs.
        pos = 8
        pairs_end = total_size - 24
        v2_value = None

        while pos < pairs_end:
            if pos + 8 > pairs_end:
                raise RuntimeError("Malformed signing block pair")

            pair_size = u64(signing_block, pos)
            pos += 8

            if pair_size < 4 or pos + pair_size > pairs_end:
                raise RuntimeError("Invalid signing block pair size")

            pair_id = u32(signing_block, pos)

            if pair_id == 0x7109871A:
                v2_value = signing_block[pos + 4:pos + pair_size]
                break

            pos += pair_size

        if v2_value is None:
            raise RuntimeError("APK v2 signature not found")

        # v2 structure:
        # signers -> signer -> signed-data -> digests -> certificates
        signers_len = u32(v2_value, 0)
        signers_start = 4
        signers_end = signers_start + signers_len

        if signers_end > len(v2_value):
            raise RuntimeError("Malformed signers sequence")

        signer_len = u32(v2_value, signers_start)
        signer_start = signers_start + 4
        signer_end = signer_start + signer_len

        if signer_end > signers_end:
            raise RuntimeError("Malformed signer")

        signed_data_len = u32(v2_value, signer_start)
        signed_data_start = signer_start + 4
        signed_data_end = signed_data_start + signed_data_len

        if signed_data_end > signer_end:
            raise RuntimeError("Malformed signed-data")

        signed_data = v2_value[signed_data_start:signed_data_end]

        digests_len = u32(signed_data, 0)
        certs_offset = 4 + digests_len

        certs_len = u32(signed_data, certs_offset)
        certs_start = certs_offset + 4
        certs_end = certs_start + certs_len

        if certs_end > len(signed_data):
            raise RuntimeError("Malformed certificate sequence")

        cert_len = u32(signed_data, certs_start)
        cert_start = certs_start + 4
        cert_end = cert_start + cert_len

        if cert_end > certs_end:
            raise RuntimeError("Malformed certificate")

        cert_data = signed_data[cert_start:cert_end]

        if not cert_data:
            raise RuntimeError("Empty certificate")

        cert_hash = hashlib.sha256(cert_data).hexdigest()
        cert_size = len(cert_data)

        if cert_hash == "0" * 64:
            raise RuntimeError("Zero certificate hash is forbidden")

        os.makedirs(
            os.path.dirname(os.path.abspath(output_header)),
            exist_ok=True
        )

        with open(output_header, "w", encoding="utf-8") as out:
            out.write("#ifndef THOR_PISU_CERT_HASH_H\n")
            out.write("#define THOR_PISU_CERT_HASH_H\n\n")
            out.write(f'#define THOR_PISU_CERT_HASH "{cert_hash}"\n')
            out.write(f"#define THOR_PISU_CERT_SIZE {cert_size}\n\n")
            out.write("#endif /* THOR_PISU_CERT_HASH_H */\n")

        print("Certificate SHA-256:", cert_hash)
        print("Certificate DER size:", cert_size)
        print("Header written to:", output_header)

except Exception as e:
    print("Error:", e, file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
