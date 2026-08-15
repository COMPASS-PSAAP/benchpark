#!/bin/sh
set -eu

# benchpark is layout-dependent, not a Python distribution: bin/benchpark does
# Path(__file__).resolve().parents[1] and then runs lib/main.py, and lib/
# reads repos/, systems/, experiments/, modifiers/, var/ and the top-level
# YAML files relative to that same root. So install the tree intact.

BENCHPARK_ROOT="$PREFIX/share/benchpark"
mkdir -p "$BENCHPARK_ROOT" "$PREFIX/bin"

for d in bin lib common-resources config experiments modifiers repos systems var; do
    cp -R "$SRC_DIR/$d" "$BENCHPARK_ROOT/"
done

for f in checkout-versions.yaml remote-urls.yaml taxonomy.yaml spack.yaml \
         pyproject.toml requirements.txt README.rst LICENSE NOTICE COPYRIGHT; do
    cp "$SRC_DIR/$f" "$BENCHPARK_ROOT/"
done

find "$BENCHPARK_ROOT" -name '__pycache__' -type d -prune -exec rm -rf {} +
find "$BENCHPARK_ROOT" -name '*.pyc' -delete

# Stamp the recipe version into the installed copy of main.py. Upstream
# hard-codes __version__ there and declares dynamic = ["version"] in
# pyproject.toml without ever wiring up a source, so this is the only place
# `benchpark --version` reads from. Done on the copy under $BENCHPARK_ROOT, not
# in $SRC_DIR, so a cached source checkout is never mutated.
_main_py="$BENCHPARK_ROOT/lib/main.py"
sed -E 's/^__version__[[:space:]]*=[[:space:]]*".*"[[:space:]]*$/__version__ = "'"$PKG_VERSION"'"/' \
    "$_main_py" > "$_main_py.stamped"
mv "$_main_py.stamped" "$_main_py"

# Fail loudly rather than silently shipping the upstream version: if the
# assignment is ever reformatted or moved out of main.py, the sed above becomes
# a no-op and nothing else would notice.
grep -q "^__version__ = \"$PKG_VERSION\"\$" "$_main_py" || {
    echo "ERROR: failed to stamp version $PKG_VERSION into $_main_py" >&2
    echo "Current __version__ line(s):" >&2
    grep -n '__version__' "$_main_py" >&2 || echo "  (none found)" >&2
    exit 1
}

chmod +x "$BENCHPARK_ROOT/bin/benchpark" "$BENCHPARK_ROOT/bin/benchpark-python"

# Launchers. Resolved relative to their own location rather than a baked-in
# $PREFIX, so the package survives relocation without prefix rewriting.
# Passing the real script path (not a symlink) keeps parents[1] pointing at
# $PREFIX/share/benchpark after .resolve().
for cmd in benchpark benchpark-python; do
    cat > "$PREFIX/bin/$cmd" <<EOF
#!/bin/sh
here=\$(cd -- "\$(dirname -- "\$0")" && pwd -P)
exec "\$here/python" "\$here/../share/benchpark/bin/$cmd" "\$@"
EOF
    chmod +x "$PREFIX/bin/$cmd"
done
