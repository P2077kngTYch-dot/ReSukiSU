# Thor Pisu Manager + LKM/GKI2 Build Guide

## Overview
This is an exclusive LKM/GKI2 implementation that only authorizes the Thor Pisu Manager (com.thor.thor.pisu) with a real certificate-based signing scheme.

## Required GitHub Secrets

Configure these secrets in your GitHub repository settings (Settings > Secrets and variables > Actions):

- **THOR_PISU_KEYSTORE_BASE64**: Base64-encoded release signing keystore
  ```bash
  base64 < your-release-keystore.jks | tr -d '\n' > keystore_base64.txt
  ```

- **THOR_PISU_KEYSTORE_PASSWORD**: Password for the keystore
- **THOR_PISU_KEY_ALIAS**: Alias of the key inside the keystore
- **THOR_PISU_KEY_PASSWORD**: Password for the key

## Building Locally

### Prerequisites
- JDK 21+
- Android SDK (API 37)
- Build tools 36.1.0
- NDK (version specified in gradle.properties)
- Python 3.x
- Linux/macOS build environment
- GNU Make
- Crypto tools (openssl)

### Build Steps

1. **Create signing keystore (if needed):**
```bash
keytool -genkey -v -keystore thor_pisu.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias thorpisu -storepass yourpassword -keypass yourpassword \
  -dname "CN=Thor Pisu Manager, O=Custom, C=US"
```

2. **Build Manager APK:**
```bash
cd manager
./gradlew assembleRelease \
  -DKSU_MANAGER_PACKAGE=com.thor.thor.pisu \
  -P KEYSTORE_FILE=/path/to/thor_pisu.jks \
  -P KEYSTORE_PASSWORD=yourpassword \
  -P KEY_ALIAS=thorpisu \
  -P KEY_PASSWORD=yourpassword
```

3. **Extract Certificate Hash:**
```bash
chmod +x scripts/extract-cert-hash.sh
./scripts/extract-cert-hash.sh \
  manager/app/build/outputs/apk/release/ThorPisuManager_*.apk \
  kernel/manager/cert_hash.h
```

The generated cert_hash.h will contain:
```c
#define THOR_PISU_CERT_HASH "actual_sha256_hash_here"
#define THOR_PISU_CERT_SIZE 0x377
```

4. **Build LKM/GKI2:**
```bash
cd kernel
make -C . \
  CONFIG_KSU=m \
  CONFIG_KSU_TRACEPOINT_HOOK=y \
  CONFIG_KSU_MULTI_MANAGER_SUPPORT=n \
  CONFIG_KSU_MANAGER_PACKAGE="com.thor.thor.pisu" \
  KBUILD_EXTMOD=$(pwd) \
  -j$(nproc)
```

## Artifacts

- **Manager APK**: manager/app/build/outputs/apk/release/ThorPisuManager_*.apk
- **LKM Module**: kernel/kernelsu.ko
- **Certificate Hash Header**: kernel/manager/cert_hash.h

## Security Notes

1. **Never commit signing keys** to the repository
2. **Use GitHub Secrets** for sensitive credentials
3. **Verify certificate hash** matches actual signing certificate SHA-256
4. **Only one manager** (com.thor.thor.pisu) is authorized
5. **No multi-manager support** - exclusive mode enforced by BUILD_BUG_ON
6. **Package name validation** is mandatory - strncmp() check in apk_sign.c

## Testing Authorization

1. **Install Thor Pisu Manager** with the release signing certificate
2. **Verify kernel logs**:
   ```bash
   dmesg | grep -i "sha256:"
   dmesg | grep -i "crowning manager"
   ```
3. **Attempt to install other Managers** - they will be rejected:
   ```bash
   dmesg | grep "Failed to get package name"
   ```
4. **Check manager registration**:
   ```bash
   su -c "cat /proc/sys/kernel/ksu/*"
   ```

## Architecture Details

### Manager Authorization
- **Package Name**: com.thor.thor.pisu (exclusive, no alternatives)
- **Signature Scheme**: APK v2 only (v1 and v3 rejected)
- **Certificate Validation**: SHA-256 hash of X.509 certificate
- **Size Check**: Exact match against EXPECTED_SIZE_THOR_PISU (0x377)

### LKM/GKI2 Implementation
- **Hook Method**: Tracepoint Syscall Redirect (GKI2 compatible)
- **Supported Kernels**: 5.10+ (arm64, x86_64, armeabi-v7a)
- **Manager Support**: Exclusive mode only (CONFIG_KSU_MULTI_MANAGER_SUPPORT=n)
- **Dynamic Manager**: Disabled (no fallback mechanisms)

### Code Changes
- **kernel/manager/apk_sign.c**: Single certificate array, removed multi-manager support
- **kernel/manager/manager_sign.h**: EXPECTED_SIZE_THOR_PISU, dynamic hash via build system
- **kernel/Kconfig**: CONFIG_KSU_MULTI_MANAGER_SUPPORT forced to n
- **manager/app/build.gradle.kts**: Namespace changed to com.thor.thor.pisu

## Troubleshooting

### Certificate hash mismatch
- Verify correct keystore is used for signing
- Regenerate certificate hash after signing key change
- Check extract-cert-hash.sh script output
- Ensure APK is actually signed with release certificate

### LKM compilation errors
- Ensure kernel headers match target kernel version
- Verify GKI2 support (kernel 5.10+)
- Check CONFIG_KSU_TRACEPOINT_HOOK availability
- Validate architecture (arm64, x86_64)

### Manager not recognized
- Confirm APK signed with release certificate matching cert_hash.h
- Check exact package name matches: com.thor.thor.pisu
- Verify kernel module loaded: `lsmod | grep kernelsu`
- Inspect kernel logs: `dmesg | tail -50`

### Signature verification failed
- APK must be v2-signed only (no v1 or v3)
- Certificate must be in DER format
- SHA-256 must be lowercase hex string

## Implementation Status

### Completed Changes

#### 1. Manager Rebranding (✓)
- Package name: `com.thor.thor.pisu`
- Namespace in build.gradle.kts updated
- AndroidManifest.xml references updated
- Build artifacts renamed to ThorPisuManager

#### 2. Exclusive Manager Authorization (✓)
- **kernel/manager/apk_sign.c**: 
  - Removed all multi-manager support
  - Single EXPECTED_SIZE_THOR_PISU / EXPECTED_HASH_THOR_PISU
  - BUILD_BUG_ON enforces exactly 1 certificate
  - Removed dynamic manager fallback
  
- **kernel/manager/manager_sign.h**:
  - Only defines THOR_PISU_CERT_* macros
  - Other Manager certificates removed
  - Support for dynamic hash via build system

#### 3. Configuration Lockdown (✓)
- **kernel/Kconfig**:
  - CONFIG_KSU_MULTI_MANAGER_SUPPORT forced to n (default)
  - Comment explains exclusive Thor Pisu mode

#### 4. Certificate Extraction (✓)
- **scripts/extract-cert-hash.sh**:
  - Reads actual signing certificate from APK
  - Calculates real SHA-256 digest
  - Generates kernel/manager/cert_hash.h
  - No manual or fake hashes

#### 5. Build Integration (⚠️ Pending GitHub Actions)
- Certificate extraction happens post-build
- Hash automatically supplied to LKM build
- Secure secrets handling via GitHub Actions

### Files Modified

1. **manager/app/build.gradle.kts**
   - Changed namespace to com.thor.thor.pisu
   - Updated archivesName to ThorPisuManager

2. **manager/app/src/main/AndroidManifest.xml**
   - Changed zygotePreloadName to com.thor.thor.pisu.magica.*
   - Updated receiver action to com.thor.thor.pisu.*

3. **kernel/manager/apk_sign.c**
   - Single certificate array (EXPECTED_SIZE_THOR_PISU, EXPECTED_HASH_THOR_PISU)
   - Removed multi-manager support code
   - BUILD_BUG_ON(ARRAY_SIZE(apk_sign_keys) != 1)
   - Removed dynamic manager fallback
   - Updated is_manager_apk() to enforce exact package match

4. **kernel/manager/manager_sign.h**
   - Only EXPECTED_SIZE_THOR_PISU and EXPECTED_HASH_THOR_PISU
   - Removed all other Manager definitions
   - Placeholder for dynamic hash

5. **kernel/Kconfig**
   - CONFIG_KSU_MULTI_MANAGER_SUPPORT default changed to n
   - Added comment "DISABLED FOR EXCLUSIVE THOR PISU MANAGER"

6. **scripts/extract-cert-hash.sh**
   - New certificate extraction tool
   - Parses APK v2 signature
   - Generates cert_hash.h header

### Next Steps: GitHub Actions

To complete the implementation:

1. **Manually create** `.github/workflows/build-thor-pisu.yml` (tool has permission issue)
   - File content provided in BUILD_INSTRUCTIONS.md
   - Implements manager build → cert extraction → LKM build pipeline

2. **Configure GitHub Secrets** in repository settings:
   - THOR_PISU_KEYSTORE_BASE64
   - THOR_PISU_KEYSTORE_PASSWORD
   - THOR_PISU_KEY_ALIAS
   - THOR_PISU_KEY_PASSWORD

3. **Set up release signing keystore** (local):
   ```bash
   keytool -genkey -v -keystore thor_pisu.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias thorpisu -storepass password -keypass password \
     -dname "CN=Thor Pisu Manager"
   ```

## Verification Checklist

- [x] Manager package name: com.thor.thor.pisu
- [x] Namespace updated in build.gradle.kts
- [x] AndroidManifest.xml updated
- [x] APK signing configured
- [x] Single certificate enforcement (BUILD_BUG_ON)
- [x] Multi-manager support disabled (Kconfig)
- [x] No dynamic manager fallback
- [x] Package name validation mandatory (strncmp)
- [x] Certificate hash extraction script
- [x] No private keys committed
- [x] GitHub Secrets documentation
- [ ] GitHub Actions workflow (manual creation needed)
- [ ] Release signing keystore (user creates locally)
- [ ] Certificate hash generation (build-time)

## LKM/GKI2 Only

This implementation is **LKM/GKI2 only**. It does NOT:
- Modify kernel source code permanently
- Require kernel recompilation
- Change kernel configuration options (beyond CONFIG_KSU_*)
- Affect unrelated kernel functionality

The LKM can be loaded/unloaded independently with standard `insmod` / `rmmod`.
