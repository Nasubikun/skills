#!/usr/bin/env bash
# run-cursor.sh — Cursor CLI (composer) を headless 実行するラッパー
#
# Usage:
#   run-cursor.sh run <task-dir>   # <task-dir>/brief.md を新規セッションで実行
#   run-cursor.sh fix <task-dir>   # <task-dir>/feedback.md を前回セッションに --resume で送る
#
# Env (ユーザー専用。Claude は指定しない):
#   CURSOR_MODEL      モデルID (default: composer-2.5-fast)
#   CURSOR_AGENT_BIN  agent バイナリ (default: ~/.local/bin/agent)
#
# Outputs (in <task-dir>):
#   stream-<n>.log    生の stream-json NDJSON
#   stderr-<n>.log    stderr
#   result.json       {status, session_id, report, usage, ...} (最新ラウンドで上書き)
#
# Exit: 0=success / 1=failed / 2=setup_required (要 `agent login`)

set -uo pipefail

usage() {
  echo "Usage: run-cursor.sh <run|fix> <task-dir>" >&2
  exit 64
}

MODE="${1:-}"
TASK_DIR_ARG="${2:-}"
[[ "$MODE" == "run" || "$MODE" == "fix" ]] || usage
[[ -n "$TASK_DIR_ARG" && -d "$TASK_DIR_ARG" ]] || { echo "task dir not found: ${TASK_DIR_ARG:-<missing>}" >&2; exit 66; }
TASK_DIR="$(cd "$TASK_DIR_ARG" && pwd)"

AGENT_BIN="${CURSOR_AGENT_BIN:-$HOME/.local/bin/agent}"
if [[ ! -x "$AGENT_BIN" ]]; then
  AGENT_BIN="$(command -v agent || command -v cursor-agent || true)"
fi
[[ -n "$AGENT_BIN" && -x "$AGENT_BIN" ]] || { echo "cursor agent binary not found (install: curl https://cursor.com/install -fsS | bash)" >&2; exit 69; }

MODEL="${CURSOR_MODEL:-composer-2.5-fast}"

# ラウンド番号: 前回の result.json の iteration + 1
PREV_ITER=0
if [[ -f "$TASK_DIR/result.json" ]]; then
  PREV_ITER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("iteration",0))' "$TASK_DIR/result.json" 2>/dev/null || echo 0)"
fi
ITER=$((PREV_ITER + 1))

RESUME_ARGS=()
if [[ "$MODE" == "run" ]]; then
  PROMPT_FILE="$TASK_DIR/brief.md"
else
  PROMPT_FILE="$TASK_DIR/feedback.md"
  SESSION_ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("session_id") or "")' "$TASK_DIR/result.json" 2>/dev/null || true)"
  [[ -n "${SESSION_ID:-}" ]] || { echo "fix requires session_id in $TASK_DIR/result.json (run first)" >&2; exit 65; }
  RESUME_ARGS=(--resume "$SESSION_ID")
fi
[[ -f "$PROMPT_FILE" ]] || { echo "prompt file not found: $PROMPT_FILE" >&2; exit 66; }

# 作業ディレクトリ(リポジトリ)で実行される前提。成果物ディレクトリを git 管理から除外しておく
GIT_DIR="$(git rev-parse --git-dir 2>/dev/null || true)"
if [[ -n "$GIT_DIR" && -d "$GIT_DIR/info" ]]; then
  grep -qxF '.claude/cursor-impl/' "$GIT_DIR/info/exclude" 2>/dev/null \
    || echo '.claude/cursor-impl/' >> "$GIT_DIR/info/exclude"
fi

STREAM_LOG="$TASK_DIR/stream-$ITER.log"
ERR_LOG="$TASK_DIR/stderr-$ITER.log"

# Cursor CLI は起動時に ~/.cursor/cli-config.json を同一の .tmp ファイル経由で
# 書き換えるため、複数プロセスの同時起動で rename が ENOENT になるレースがある。
# 起動ジッター + 「セッション未作成のまま失敗」した場合のみリトライで回避する。
sleep $((RANDOM % 3))
START_TS="$(date +%s)"
ATTEMPT=1
MAX_ATTEMPTS=3
while :; do
  "$AGENT_BIN" -p --force --trust \
    --output-format stream-json \
    --model "$MODEL" \
    ${RESUME_ARGS[@]+"${RESUME_ARGS[@]}"} \
    < "$PROMPT_FILE" > "$STREAM_LOG" 2> "$ERR_LOG"
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 && $ATTEMPT -lt $MAX_ATTEMPTS ]] \
    && ! grep -q 'session_id' "$STREAM_LOG" \
    && grep -Eq 'ENOENT|EBUSY|EEXIST|rename' "$ERR_LOG"; then
    ATTEMPT=$((ATTEMPT + 1))
    sleep $((ATTEMPT * 2 + RANDOM % 3))
    continue
  fi
  break
done
WALL_MS=$(( ($(date +%s) - START_TS) * 1000 ))

TASK_DIR="$TASK_DIR" STREAM_LOG="$STREAM_LOG" ERR_LOG="$ERR_LOG" \
EXIT_CODE="$EXIT_CODE" MODEL="$MODEL" MODE="$MODE" ITER="$ITER" WALL_MS="$WALL_MS" \
python3 <<'PY'
import json, os, re

task_dir = os.environ["TASK_DIR"]
exit_code = int(os.environ["EXIT_CODE"])

session_id = None
result_event = None
assistant_texts = []

def extract_text(ev):
    msg = ev.get("message")
    if isinstance(msg, dict):
        content = msg.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return "".join(p.get("text", "") for p in content
                           if isinstance(p, dict) and p.get("type") == "text")
    if isinstance(ev.get("text"), str):
        return ev["text"]
    return ""

with open(os.environ["STREAM_LOG"], encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(ev, dict):
            continue
        if session_id is None and isinstance(ev.get("session_id"), str):
            session_id = ev["session_id"]
        if ev.get("type") == "result":
            result_event = ev
        elif ev.get("type") == "assistant":
            text = extract_text(ev)
            # 同一メッセージのスナップショット重複を除去
            if text and (not assistant_texts or assistant_texts[-1] != text):
                assistant_texts.append(text)

with open(os.environ["ERR_LOG"], encoding="utf-8", errors="replace") as f:
    stderr_text = f.read()

if re.search(r"Authentication required|cursor-agent login|CURSOR_API_KEY", stderr_text):
    status, reason = "setup_required", "cursor CLI not authenticated"
elif exit_code != 0:
    status, reason = "failed", f"exit code {exit_code}"
elif result_event is None:
    status, reason = "failed", "no result event in stream output"
elif result_event.get("is_error"):
    status, reason = "failed", "agent reported is_error"
else:
    status, reason = "success", None

report = ""
if result_event and isinstance(result_event.get("result"), str) and result_event["result"].strip():
    report = result_event["result"]
elif assistant_texts:
    # stream-json の最終 result が空になる既知問題への対策
    report = "\n".join(assistant_texts)

result = {
    "status": status,
    "reason": reason,
    "mode": os.environ["MODE"],
    "iteration": int(os.environ["ITER"]),
    "model": os.environ["MODEL"],
    "session_id": session_id,
    "report": report,
    "usage": (result_event or {}).get("usage"),
    "duration_ms": (result_event or {}).get("duration_ms", int(os.environ["WALL_MS"])),
    "exit_code": exit_code,
    "stream_log": os.environ["STREAM_LOG"],
    "stderr_log": os.environ["ERR_LOG"],
}
with open(os.path.join(task_dir, "result.json"), "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(f"=== cursor-impl {result['mode']} #{result['iteration']}: {status}"
      f" (model={result['model']}, session={session_id}) ===")
if reason:
    print(f"reason: {reason}")
if stderr_text.strip() and status != "success":
    print("--- stderr (tail) ---")
    print("\n".join(stderr_text.strip().splitlines()[-20:]))
print("--- worker report ---")
print(report if report.strip() else "(empty report)")
PY

# result.json の status を終了コードへ反映
STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])' "$TASK_DIR/result.json" 2>/dev/null || echo failed)"
case "$STATUS" in
  success) exit 0 ;;
  setup_required) exit 2 ;;
  *) exit 1 ;;
esac
