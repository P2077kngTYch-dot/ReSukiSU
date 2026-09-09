#ifndef MANAGER_SIGN_H
#define MANAGER_SIGN_H

// Thor Pisu Manager - Exclusive Manager for this fork
// Certificate hash will be derived from the actual signing key
// at build time via extract-cert-hash.sh
#define EXPECTED_SIZE_THOR_PISU 0x377
#ifdef THOR_PISU_CERT_HASH
#define EXPECTED_HASH_THOR_PISU THOR_PISU_CERT_HASH
#else
// Placeholder - will be replaced by build system
#define EXPECTED_HASH_THOR_PISU "0000000000000000000000000000000000000000000000000000000000000000"
#endif

typedef struct {
    unsigned size;
    const char *sha256;
} apk_sign_key_t;

#endif /* MANAGER_SIGN_H */
