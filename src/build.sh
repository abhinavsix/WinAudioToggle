#!/usr/bin/env bash
#
# Builds AudioTray.exe.
#
# Targets .NET Framework 4.8, which is part of Windows 10 1903+ and Windows 11,
# so the result is a single small executable with nothing to install alongside
# it. No .NET runtime download, no self-contained 150MB bundle.
#
# This script builds on Linux using Microsoft's real Roslyn compiler and real
# .NET Framework reference assemblies, both from NuGet, with Mono acting only
# as a host to run csc.exe. The output is byte-for-byte the sort of assembly a
# Windows build produces - Mono contributes nothing to the binary itself.
#
# On Windows, build it the ordinary way instead:
#     dotnet build src/AudioTray/AudioTray.csproj -c Release
#
# Requirements here: mono, curl, unzip.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src/AudioTray"
OUT="$ROOT/dist"
WORK="${BUILD_WORK_DIR:-/tmp/audiotray-build}"

ROSLYN_VERSION="4.8.0"
REFASM_VERSION="1.0.3"

mkdir -p "$WORK" "$OUT"

fetch() {
    local id="$1" version="$2"
    local lower; lower="$(echo "$id" | tr '[:upper:]' '[:lower:]')"
    if [ -d "$WORK/$lower" ]; then return; fi
    echo "  fetching $id $version"
    curl -sSfL --max-time 120 -o "$WORK/$lower.nupkg" \
        "https://api.nuget.org/v3-flatcontainer/$lower/$version/$lower.$version.nupkg"
    mkdir -p "$WORK/$lower"
    unzip -qo "$WORK/$lower.nupkg" -d "$WORK/$lower"
}

echo "Preparing toolchain..."
fetch Microsoft.Net.Compilers.Toolset "$ROSLYN_VERSION"
fetch Microsoft.NETFramework.ReferenceAssemblies.net48 "$REFASM_VERSION"

CSC="$WORK/microsoft.net.compilers.toolset/tasks/net472/csc.exe"
REF="$WORK/microsoft.netframework.referenceassemblies.net48/build/.NETFramework/v4.8"

for required in "$CSC" "$REF/mscorlib.dll"; do
    [ -f "$required" ] || { echo "missing: $required" >&2; exit 1; }
done

# The icons are embedded so the executable stands alone. A same-named .ico
# placed beside the .exe still wins at runtime, so they stay swappable.
RESOURCES=()
for name in mic-on mic-off icon1 icon2; do
    if [ -f "$ROOT/$name.ico" ]; then
        RESOURCES+=("-resource:$ROOT/$name.ico,AudioTray.$name.ico")
    else
        echo "  warning: $name.ico not found; the built-in fallback icon will be used" >&2
    fi
done

echo "Compiling..."
mono "$CSC" \
    -nologo -noconfig -nostdlib+ -optimize+ -warnaserror- \
    -target:winexe \
    -platform:anycpu \
    -out:"$OUT/AudioTray.exe" \
    -win32icon:"$ROOT/mic-on.ico" \
    -win32manifest:"$SRC/app.manifest" \
    -r:"$REF/mscorlib.dll" \
    -r:"$REF/System.dll" \
    -r:"$REF/System.Core.dll" \
    -r:"$REF/System.Drawing.dll" \
    -r:"$REF/System.Windows.Forms.dll" \
    "${RESOURCES[@]}" \
    "$SRC"/*.cs

echo
echo "Built: $OUT/AudioTray.exe"
ls -la "$OUT/AudioTray.exe"
