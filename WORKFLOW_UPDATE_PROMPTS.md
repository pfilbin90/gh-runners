# Workflow Update Prompts

After you've pushed the `gh-runners` repo and the first image build completes, use these prompts to simplify your `spinfreeze_app` workflows.

The new runner image has all dependencies baked in, so you can remove the setup actions.

---

## 1. Integration Tests (`integration-tests.yml`)

**File:** `.github/workflows/integration-tests.yml`

**Prompt:**
```
Please edit .github/workflows/integration-tests.yml to dramatically simplify the workflow since we now have a custom runner image with all dependencies baked in, including the Android system image and pre-created AVD.

REMOVE these setup steps entirely (they're all pre-installed):
- "Set up Java 8 (AVD tooling)"
- "Set up Java 17"
- "Set up Android SDK"
- "Accept Android licenses"
- "Set up Flutter"
- "Trust Flutter SDK dir"
- "Set up Node.js"
- "Ensure Docker + Compose available"
- "Create Android Virtual Device (AVD)" - The AVD named "test_avd" is pre-created in the image!

SIMPLIFY "Set up Supabase for integration tests" to just:
```yaml
- name: Start Supabase
  run: |
    docker compose -f docker-compose.test.yml up -d
    echo "Waiting for Postgres..."
    for i in {1..60}; do
      if docker compose -f docker-compose.test.yml exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
        echo "Postgres is ready"
        break
      fi
      sleep 1
    done
```

SIMPLIFY "Start Android emulator" - the AVD already exists as "test_avd":
```yaml
- name: Start Android emulator
  run: |
    echo "Starting pre-configured AVD..."
    emulator -avd test_avd -no-audio -no-window -no-snapshot-load -gpu swiftshader_indirect &

    echo "Waiting for emulator to boot..."
    adb wait-for-device
    for i in {1..180}; do
      if adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
        echo "Emulator is ready"
        break
      fi
      sleep 1
    done
    adb devices
```

ADD a verification step after checkout:
```yaml
- name: Verify runner environment
  run: |
    echo "=== Runner Environment ==="
    flutter --version | head -1
    java -version 2>&1 | head -1
    echo "Android SDK: $ANDROID_SDK_ROOT"
    echo "Node: $(node --version)"
    docker compose version
    avdmanager list avd | grep -A2 "test_avd" || echo "AVD check skipped"
```

KEEP these steps as-is:
- Checkout
- Get Flutter dependencies (flutter pub get)
- Run build_runner
- Determine test device
- Run integration tests
- Stop Android emulator
- Stop Supabase
- All the artifact upload and notification steps
```

---

## 2. Flutter Main Tests (`flutter_main_tests.yml`)

**File:** `.github/workflows/flutter_main_tests.yml`

**Prompt:**
```
Please edit .github/workflows/flutter_main_tests.yml to simplify the workflow since we now have a custom runner image with all dependencies baked in.

Remove these setup steps:
- "Ensure xz is installed" - Pre-installed in runner image
- "uses: actions/setup-java@v5" - Java 21 pre-installed
- "Set up Flutter" (subosito/flutter-action) - Flutter 3.35.7 pre-installed
- "Trust Flutter SDK dir" - Already configured
- "Cache Pub" - Keep this, caching still helps
- "Cache build_runner" - Keep this, caching still helps

Keep these steps:
- Checkout
- Cache Pub (actions/cache for ~/.pub-cache)
- Cache build_runner (actions/cache for .dart_tool/build)
- "Fetch dependencies" (flutter pub get)
- "Detect if codegen is needed"
- "Generate code" (conditional)
- "Analyze"
- "Run full test suite"
- "Report test results"

Add a simple verification step after checkout:
```yaml
- name: Verify runner environment
  run: |
    flutter --version
    dart --version
```

The workflow will be much shorter and faster since we skip all the SDK downloads.
```

---

## 3. Flutter PR Fast (`flutter_pr_fast.yml`)

**File:** `.github/workflows/flutter_pr_fast.yml`

**Prompt:**
```
Please edit .github/workflows/flutter_pr_fast.yml to simplify the workflow since we now have a custom runner image with all dependencies baked in.

Remove these setup steps:
- "Install system deps" - All pre-installed
- "uses: actions/setup-java@v5" - Java 21 pre-installed
- "Clear any existing Flutter installation" - Not needed
- "Set up Flutter" (subosito/flutter-action) - Flutter 3.35.7 pre-installed
- "Trust Flutter SDK dir" - Already configured

Keep these steps:
- Checkout with fetch-depth: 0
- Cache Pub
- Cache build_runner
- "Verify Flutter/Dart versions match local" - Update to just verify without erroring
- "Fetch dependencies"
- "Detect if codegen is needed"
- "Generate code"
- "Format check"
- "Analyze"

Update the "Verify Flutter/Dart versions" step to be informational rather than failing:
```yaml
- name: Verify Flutter/Dart versions
  run: |
    echo "Runner Flutter version:"
    flutter --version
    echo ""
    echo "Runner Dart version:"
    dart --version
    echo ""
    echo "Expected: Flutter 3.35.7, Dart 3.9.2"
    echo "If versions don't match, update FLUTTER_VERSION in gh-runners/Dockerfile.runner"
```
```

---

## 4. Code Coverage (`code-coverage.yml`)

**File:** `.github/workflows/code-coverage.yml`

**Prompt:**
```
Please edit .github/workflows/code-coverage.yml to simplify the workflow since we now have a custom runner image with all dependencies baked in.

Remove these setup steps:
- "Set up Flutter" (subosito/flutter-action) - Flutter pre-installed
- "Trust Flutter SDK dir" - Already configured

In the "Generate coverage summary" step, remove the apt-get install for lcov since it's pre-installed:
```yaml
- name: Generate coverage summary
  run: |
    genhtml coverage/lcov.info -o coverage/html
    lcov --summary coverage/lcov.info 2>&1 | tee coverage/summary.txt
```

Keep all other steps as-is.
```

---

## 5. Build (`build.yml`)

**File:** `.github/workflows/build.yml`

**Prompt:**
```
Please edit .github/workflows/build.yml to simplify the sonarqube job since we now have a custom runner image with all dependencies baked in.

In the sonarqube job, remove:
- "Set up Flutter" (subosito/flutter-action) - Flutter pre-installed
- "Trust Flutter SDK dir" - Already configured

Keep the Cache Pub step and all other steps.
```

---

## Quick Reference: What's Pre-installed in the Runner

| Tool | Version | Path/Env Var |
|------|---------|--------------|
| Flutter | 3.35.7 | `$FLUTTER_HOME` (/opt/flutter) |
| Dart | 3.9.2 | Included with Flutter |
| Java 21 | OpenJDK | `$JAVA_HOME` / `$JAVA_HOME_21_X64` |
| Java 8 | OpenJDK | `$JAVA_HOME_8_X64` (legacy, rarely needed) |
| Android SDK | 33, 34 | `$ANDROID_HOME` / `$ANDROID_SDK_ROOT` |
| Android System Image | android-33;google_apis;x86_64 | Pre-downloaded (~1.5GB) |
| Android AVD | "test_avd" (Pixel 4) | Pre-created, ready to boot |
| Node.js | 22.x | Pre-installed |
| pnpm | 9.x | Pre-installed |
| Chrome | Latest stable | Pre-installed |
| ChromeDriver | Matching | /usr/local/bin/chromedriver |
| Docker CLI | Latest | Pre-installed |
| Docker Compose | v2 plugin | `docker compose` |
| lcov | Latest | Pre-installed |
| Supabase CLI | Latest | /usr/local/bin/supabase |
| firebase-tools | Latest | Global npm package |

---

## After Updating Workflows

1. **Test one workflow first** - Run `selfhosted-smoke.yml` to verify runners work
2. **Update one workflow at a time** - Start with `flutter_pr_fast.yml` (most frequently run)
3. **Monitor run times** - You should see significant speedups (no more SDK downloads)
4. **Check for issues** - If a tool is missing, add it to `Dockerfile.runner` and rebuild
