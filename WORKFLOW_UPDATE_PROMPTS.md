# Workflow Update Prompts

After you've pushed the `gh-runners` repo and the first image build completes, use these prompts to simplify your `spinfreeze_app` workflows.

The new runner image has all dependencies baked in, so you can remove the setup actions.

---

## 1. Integration Tests (`integration-tests.yml`)

**File:** `.github/workflows/integration-tests.yml`

**Prompt:**
```
Please edit .github/workflows/integration-tests.yml to simplify the workflow since we now have a custom runner image with all dependencies baked in.

Remove these setup steps that are no longer needed:
- "Set up Java 8 (AVD tooling)" - Java 8 is pre-installed at $JAVA_HOME_8_X64
- "Set up Java 17" - Java 21 is pre-installed at $JAVA_HOME (compatible with 17)
- "Set up Android SDK" - Android SDK is pre-installed at $ANDROID_HOME
- "Accept Android licenses" - Already accepted in the image
- "Set up Flutter" - Flutter 3.35.7 is pre-installed
- "Trust Flutter SDK dir" - Already configured in the image
- "Set up Node.js" - Node.js 22 is pre-installed
- "Ensure Docker + Compose available" - Docker Compose is pre-installed

Keep these steps but simplify:
- "Get Flutter dependencies" - Keep as-is (flutter pub get)
- "Run build_runner" - Keep as-is
- "Set up Supabase for integration tests" - Simplify to use `docker compose` directly
- "Create Android Virtual Device" - Simplify since Java switching is no longer needed
- All the test execution and cleanup steps - Keep as-is

Add a verification step at the beginning:
```yaml
- name: Verify runner environment
  run: |
    echo "Flutter: $(flutter --version | head -1)"
    echo "Dart: $(dart --version)"
    echo "Java: $(java -version 2>&1 | head -1)"
    echo "Android SDK: $ANDROID_SDK_ROOT"
    echo "Node: $(node --version)"
    echo "Docker Compose: $(docker compose version)"
```

The JAVA_HOME_8_X64 and JAVA_HOME_17_X64 environment variables are already set in the runner image for the AVD creation step.
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
| Java 8 | OpenJDK | `$JAVA_HOME_8_X64` |
| Java 21 | OpenJDK | `$JAVA_HOME` / `$JAVA_HOME_21_X64` |
| Android SDK | 33, 34 | `$ANDROID_HOME` / `$ANDROID_SDK_ROOT` |
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
