#!/usr/bin/env bash
# Run an ejected Sigil example on your Claude Code login (the `claude-cc` route):
# every model call is a headless `claude -p`, billed to your Claude subscription.
# No ANTHROPIC_API_KEY needed (and one in your env is withheld from `claude`).
#
#   cd examples/csv-clean
#   ../run-on-claude.sh csv-clean.jac messy.csv
#
#   cd examples/writing-plans
#   ../run-on-claude.sh writing-plans.jac "Add per-API-key rate limiting to ..."
#
#   SIGIL_MODEL=claude-cc/sonnet ../run-on-claude.sh ...   # default: claude-cc/haiku
#
# Run it from the folder where the example's output should land (cleaned.csv,
# plan_file.out, ...). Why this exists: an ejected .jac only knows plain litellm
# model names, and `claude-cc` is a provider Sigil registers at runtime. This does
# what Sigil's own skill driver does (src/sigil_runtime.jac, _DRIVER): register
# the provider, then call the module's run().
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
art="${1:?usage: run-on-claude.sh <example.jac> \"<task>\"}"
shift
[ -f "$art" ] || { echo "run-on-claude: no such file: $art" >&2; exit 1; }
task="$*"
[ -n "$task" ] || { echo "run-on-claude: give the task (for csv-clean: the CSV path)" >&2; exit 1; }

# A module name can't contain '-', so the example is imported from a copy.
# A stable directory per example keeps jac's compile cache warm between runs.
# The copy sits ALONE in its own folder and is named agent.jac on purpose: on
# import, an ejected module copies every file beside it into the current folder
# (_ensure_path in the artifact), skipping only a few names, agent.jac among them.
name="$(basename "$art" .jac)"
work="${XDG_CACHE_HOME:-$HOME/.cache}/sigil-run-on-claude/${name//-/_}"
mkdir -p "$work/mod"
cp "$art" "$work/mod/agent.jac"
cat > "$work/driver.jac" <<'EOF'
import from agent { run }
import from jaclang.byllm.lib { Model }
import sigil_claude_cc;
import os;

with entry:__main__ {
    model_name: str = str(os.getenv("SIGIL_MODEL", "claude-cc/haiku"));
    cfg: dict[str, any] = {};
    if sigil_claude_cc.is_claude_cc(model_name) {
        sigil_claude_cc.install();
        cfg = {"native_tools": False};
    }
    m = Model(model_name=model_name, config=cfg);
    print(run(str(os.getenv("SIGIL_TASK", "")), m, ""));
}
EOF

export SIGIL_MODEL="${SIGIL_MODEL:-claude-cc/haiku}"
export SIGIL_TASK="$task"
export JACPATH="$work/mod:$REPO/src${JACPATH:+:$JACPATH}"
exec "${SIGIL_JAC:-jac}" run --no-serve "$work/driver.jac"
