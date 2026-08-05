#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Build a signed Android App Bundle for Google Play.

Usage:
  tooling/build_play_store.sh [options]

Options:
  --build-number NUMBER  Use an explicit build number instead of incrementing it.
  --version-name VERSION Use an explicit version name instead of keeping the current one.
  --skip-checks          Skip flutter analyze and flutter test.
  --dry-run              Validate inputs and print the next version without changing files.
  -h, --help             Show this help message.

By default, the script increments the build number in pubspec.yaml by one,
runs validation, builds a signed release AAB, verifies it, and writes a
versioned copy under build/app/outputs/bundle/release/.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
pubspec_path="${project_dir}/pubspec.yaml"
key_properties_path="${project_dir}/android/key.properties"
explicit_build_number=""
explicit_version_name=""
skip_checks=false
dry_run=false

while (($# > 0)); do
  case "$1" in
    --build-number)
      (($# >= 2)) || fail "--build-number requires a value."
      explicit_build_number="$2"
      shift 2
      ;;
    --version-name)
      (($# >= 2)) || fail "--version-name requires a value."
      explicit_version_name="$2"
      shift 2
      ;;
    --skip-checks)
      skip_checks=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

[[ -f "${pubspec_path}" ]] || fail "pubspec.yaml was not found."
[[ -f "${key_properties_path}" ]] || fail "android/key.properties was not found."

for property_name in storePassword keyPassword keyAlias storeFile; do
  grep -q "^${property_name}=" "${key_properties_path}" \
    || fail "${property_name} is missing from android/key.properties."
done

store_file="$(awk -F= '$1 == "storeFile" { sub(/^[^=]*=/, ""); print; exit }' "${key_properties_path}")"
[[ -n "${store_file}" ]] || fail "storeFile is empty in android/key.properties."

if [[ "${store_file}" = /* ]]; then
  keystore_path="${store_file}"
else
  keystore_path="${project_dir}/android/app/${store_file}"
fi
[[ -f "${keystore_path}" ]] || fail "Signing keystore was not found at ${keystore_path}."

current_version="$(awk '
  /^[[:space:]]*version:[[:space:]]*/ {
    sub(/^[[:space:]]*version:[[:space:]]*/, "")
    print
    exit
  }
' "${pubspec_path}")"

if [[ ! "${current_version}" =~ ^([^+[:space:]]+)\+([0-9]+)$ ]]; then
  fail "Expected pubspec version in VERSION+BUILD format; found '${current_version}'."
fi

current_version_name="${BASH_REMATCH[1]}"
current_build_number="${BASH_REMATCH[2]}"
version_name="${explicit_version_name:-${current_version_name}}"
build_number="${explicit_build_number:-$((10#${current_build_number} + 1))}"

[[ "${version_name}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "Version name must use MAJOR.MINOR.PATCH format."
[[ "${build_number}" =~ ^[0-9]+$ ]] || fail "Build number must be a positive integer."
((10#${build_number} > 10#${current_build_number})) \
  || fail "Build number ${build_number} must be greater than current build number ${current_build_number}."

flutter_command="$(command -v flutter || true)"
if [[ -z "${flutter_command}" ]]; then
  local_properties_path="${project_dir}/android/local.properties"
  [[ -f "${local_properties_path}" ]] || fail "Flutter is not on PATH and android/local.properties is missing."
  flutter_sdk="$(awk -F= '$1 == "flutter.sdk" { sub(/^[^=]*=/, ""); print; exit }' "${local_properties_path}")"
  flutter_command="${flutter_sdk}/bin/flutter"
fi
[[ -x "${flutter_command}" ]] || fail "Flutter executable was not found at ${flutter_command}."

printf 'Current version: %s+%s\n' "${current_version_name}" "${current_build_number}"
printf 'Next version:    %s+%s\n' "${version_name}" "${build_number}"
printf 'Signing file:    %s\n' "${keystore_path}"

if [[ "${dry_run}" == true ]]; then
  printf 'Dry run completed; no files were changed.\n'
  exit 0
fi

backup_path="$(mktemp "${TMPDIR:-/tmp}/career-path-pubspec.XXXXXX")"
updated_pubspec=false
temporary_pubspec=""

cleanup() {
  status=$?
  trap - EXIT
  if ((status != 0)) && [[ "${updated_pubspec}" == true ]]; then
    cp "${backup_path}" "${pubspec_path}"
    printf 'Build failed; restored the previous pubspec version.\n' >&2
  fi
  [[ -z "${temporary_pubspec}" ]] || rm -f "${temporary_pubspec}"
  rm -f "${backup_path}"
  exit "${status}"
}
trap cleanup EXIT

cp "${pubspec_path}" "${backup_path}"
temporary_pubspec="$(mktemp "${project_dir}/pubspec.yaml.tmp.XXXXXX")"
awk -v replacement="version: ${version_name}+${build_number}" '
  BEGIN { updated = 0 }
  /^[[:space:]]*version:[[:space:]]*/ {
    if (updated) {
      print "Multiple version entries found in pubspec.yaml." > "/dev/stderr"
      exit 2
    }
    print replacement
    updated = 1
    next
  }
  { print }
  END {
    if (!updated) {
      print "No version entry found in pubspec.yaml." > "/dev/stderr"
      exit 3
    }
  }
' "${pubspec_path}" > "${temporary_pubspec}"
mv "${temporary_pubspec}" "${pubspec_path}"
temporary_pubspec=""
updated_pubspec=true

cd "${project_dir}"
if [[ "${skip_checks}" == false ]]; then
  "${flutter_command}" analyze
  "${flutter_command}" test
fi

"${flutter_command}" build appbundle --release

release_dir="${project_dir}/build/app/outputs/bundle/release"
generated_bundle="${release_dir}/app-release.aab"
versioned_bundle="${release_dir}/career-path-${version_name}+${build_number}.aab"
[[ -s "${generated_bundle}" ]] || fail "Flutter did not produce ${generated_bundle}."

packaged_manifest="${project_dir}/build/app/intermediates/packaged_manifests/release/processReleaseManifestForPackage/AndroidManifest.xml"
if [[ -f "${packaged_manifest}" ]]; then
  grep -q "android:versionCode=\"${build_number}\"" "${packaged_manifest}" \
    || fail "Packaged Android version code does not match ${build_number}."
  grep -q "android:versionName=\"${version_name}\"" "${packaged_manifest}" \
    || fail "Packaged Android version name does not match ${version_name}."
fi

[[ ! -e "${versioned_bundle}" ]] || fail "Output already exists: ${versioned_bundle}"
cp "${generated_bundle}" "${versioned_bundle}"

if command -v jarsigner >/dev/null 2>&1; then
  jarsigner -verify "${versioned_bundle}" >/dev/null
fi
if command -v unzip >/dev/null 2>&1; then
  unzip -tq "${versioned_bundle}" >/dev/null
fi

printf '\nPlay Store bundle created:\n%s\n' "${versioned_bundle}"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "${versioned_bundle}"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${versioned_bundle}"
fi
