#!/usr/bin/env bash
# vibecode-anywhere — repository audit (run in CI and before every release):
#   - no secret-looking strings anywhere in git history
#   - no secret / personal-config files ever committed (hub.conf, .env, keys, bundles)
#   - no unreplaced template placeholders outside templates/
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0
bad() { printf '  FAIL %s\n' "$*"; FAIL=1; }

echo "== files ever committed"
git log --all --name-only --pretty=format: | sort -u | grep -v '^$' > /tmp/va-files.$$
if grep -E '(^|/)(hub\.conf|rules\.extra\.md|\.env(\..*)?|.*\.enc|.*\.pem|.*\.key|id_rsa.*|id_ed25519.*|\.vibecode-pass|auth\.json|\.credentials\.json)$' /tmp/va-files.$$ \
   | grep -vE '(^|/)\.env\.(example|sample|template)$'; then
  bad "sensitive file(s) above were committed at some point"
fi
rm -f /tmp/va-files.$$

echo "== secret patterns in history"
# The patterns are split so this file does not match itself.
P1='gh''p_[A-Za-z0-9]{36}'; P2='github_''pat_[A-Za-z0-9_]{40,}'; P3='sk-''[A-Za-z0-9]{32,}'
P4='AK''IA[0-9A-Z]{16}'; P5='xox''[abp]-[0-9]{6,}'; P6='-----BEGIN [A-Z ]*PRIV''ATE KEY-----'
if git log --all -p --no-color | grep -nE "$P1|$P2|$P3|$P4|$P5|$P6" | head -5 | grep .; then
  bad "secret-looking string(s) in git history"
fi

echo "== placeholders"
if grep -rn '{{[A-Z_]*}}' --include='*.sh' --include='*.md' --include='*.ps1' . | grep -v '^./templates/' | grep -v 'scripts/render-rules.sh' | grep -v '^./tests/'; then
  bad "unreplaced {{PLACEHOLDER}} outside templates/"
fi

[ "$FAIL" -eq 0 ] && echo "audit OK"
exit "$FAIL"
