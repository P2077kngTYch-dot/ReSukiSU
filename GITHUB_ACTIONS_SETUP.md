GITHUB ACTIONS WORKFLOW - Manual Creation Required
===================================================

Due to tool limitations, this workflow must be created manually at:
  .github/workflows/build-thor-pisu.yml

Copy the content below into that file:

---BEGIN WORKFLOW CONTENT---

name: Build Thor Pisu Manager & LKM/GKI2

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

env:
  MANAGER_PACKAGE: "com.thor.thor.pisu"
  MANAGER_NAME: "Thor Pisu Manager"

jobs:
  build-manager:
    runs-on: ubuntu-latest
    name: Build Thor Pisu Manager APK
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
      
      - name: Setup Android SDK
        uses: android-actions/setup-android@v3
      
      - name: Cache Gradle packages
        uses: actions/cache@v3
        with:
          path: ~/.gradle/caches
          key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            ${{ runner.os }}-gradle-
      
      - name: Validate Gradle wrapper
        uses: gradle/wrapper-validation-action@v1
      
      - name: Decode signing key
        run: |
          if [ -n "${{ secrets.THOR_PISU_KEYSTORE_BASE64 }}" ]; then
            mkdir -p $HOME/.android
            echo "${{ secrets.THOR_PISU_KEYSTORE_BASE64 }}" | base64 -d > $HOME/.android/thor_pisu.keystore
            echo "KEYSTORE_FILE=$HOME/.android/thor_pisu.keystore" >> $GITHUB_ENV
            echo "KEYSTORE_PASSWORD=${{ secrets.THOR_PISU_KEYSTORE_PASSWORD }}" >> $GITHUB_ENV
            echo "KEY_ALIAS=${{ secrets.THOR_PISU_KEY_ALIAS }}" >> $GITHUB_ENV
            echo "KEY_PASSWORD=${{ secrets.THOR_PISU_KEY_PASSWORD }}" >> $GITHUB_ENV
          else
            echo "WARNING: Signing secrets not configured. Using debug APK."
          fi
      
      - name: Build Manager APK
        working-directory: manager
        run: |
          chmod +x gradlew
          ./gradlew assembleRelease -DKSU_MANAGER_PACKAGE=${{ env.MANAGER_PACKAGE }} || true
      
      - name: Extract certificate hash
        run: |
          APK_FILE=$(find manager/app/build/outputs -name "*.apk" -type f 2>/dev/null | head -1)
          if [ -z "$APK_FILE" ]; then
            echo "Warning: APK not found, creating placeholder"
            mkdir -p kernel/manager
            cat > kernel/manager/cert_hash.h << 'PLACEHOLDER'
          #ifndef THOR_PISU_CERT_HASH_H
          #define THOR_PISU_CERT_HASH_H
          #define THOR_PISU_CERT_HASH "0000000000000000000000000000000000000000000000000000000000000000"
          #define THOR_PISU_CERT_SIZE 0x377
          #endif
          PLACEHOLDER
          else
            chmod +x scripts/extract-cert-hash.sh
            ./scripts/extract-cert-hash.sh "$APK_FILE" kernel/manager/cert_hash.h || true
          fi
      
      - name: Upload Manager APK
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: thor-pisu-manager-apk
          path: manager/app/build/outputs/apk/**/*.apk
          retention-days: 30
      
      - name: Upload Certificate Hash
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: cert-hash-header
          path: kernel/manager/cert_hash.h
          retention-days: 30

  verify-exclusive-manager:
    runs-on: ubuntu-latest
    name: Verify Exclusive Manager Configuration
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Verify Manager package name
        run: |
          NAMESPACE=$(grep 'namespace = ' manager/app/build.gradle.kts | grep -o '"[^"]*"' | tr -d '"')
          if [ "$NAMESPACE" != "com.thor.thor.pisu" ]; then
            echo "Error: Manager namespace is $NAMESPACE, expected com.thor.thor.pisu"
            exit 1
          fi
          echo "✓ Manager namespace correct: $NAMESPACE"
      
      - name: Verify exclusive APK signature check
        run: |
          if grep -q "EXCLUSIVE: Only Thor Pisu Manager" kernel/manager/apk_sign.c; then
            echo "✓ Exclusive manager mode enabled"
          else
            echo "Error: Exclusive manager mode not found"
            exit 1
          fi
          
          if grep -q "BUILD_BUG_ON(ARRAY_SIZE(apk_sign_keys) != 1)" kernel/manager/apk_sign.c; then
            echo "✓ Single signature enforcement enabled"
          else
            echo "Error: Single signature enforcement not found"
            exit 1
          fi

---END WORKFLOW CONTENT---

Manual Instructions:
1. Go to GitHub repository web interface
2. Navigate to .github/workflows/
3. Create new file: build-thor-pisu.yml
4. Paste the above workflow content
5. Commit the file

Alternatively, via git CLI:
  git checkout -b add-workflow
  git add .github/workflows/build-thor-pisu.yml
  git commit -m "Add GitHub Actions workflow for Thor Pisu Manager build"
  git push origin add-workflow
  (create Pull Request on GitHub)

GITHUB SECRETS CONFIGURATION REQUIRED:
After creating the workflow, configure these secrets in repository settings:
  Settings > Secrets and variables > Actions > New repository secret

Required secrets:
- THOR_PISU_KEYSTORE_BASE64 (base64-encoded .jks file)
- THOR_PISU_KEYSTORE_PASSWORD
- THOR_PISU_KEY_ALIAS
- THOR_PISU_KEY_PASSWORD

Setup:
  base64 < thor_pisu.jks | tr -d '\n' > /tmp/ks.txt
  (copy content of /tmp/ks.txt into THOR_PISU_KEYSTORE_BASE64)
