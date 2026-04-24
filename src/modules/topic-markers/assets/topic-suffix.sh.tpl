#!/bin/bash
# Hook: UserPromptSubmit
# Adds a topic summary marker to the end of every Claude response.
# Output is injected as system-reminder context.
#
# Suppressed when:
#   1) Claude runs in pipe mode (-p / --print) — ancestor process detection
#   2) User prompt requests fixed/structured output — stdin prompt analysis

# ── Read user prompt from stdin ──────────────────────────────────────────────
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | {{jq}} -r '.prompt // empty' 2>/dev/null)

# ── 1) Pipe mode detection ───────────────────────────────────────────────────
# Walk up the ancestor process tree looking for "claude" invoked with -p/--print.
# We can't just check $PPID because Claude may spawn hooks via intermediate shells.
PID=$$

while [ "$PID" != "1" ] && [ "$PID" != "0" ] && [ -n "$PID" ]; do
  PARENT=$(ps -p "$PID" -o ppid= 2>/dev/null | tr -d ' ')
  [ -z "$PARENT" ] && break
  PARENT_CMD=$(ps -p "$PARENT" -o args= 2>/dev/null || true)

  if echo "$PARENT_CMD" | grep -q 'claude' && echo "$PARENT_CMD" | grep -qwE -- '-p|--print'; then
    exit 0
  fi
  PID="$PARENT"
done

# ── 2) Fixed format detection in user prompt ─────────────────────────────────
# Check if the prompt explicitly demands structured/machine-parseable output.
# This catches cases where pipe mode detection might miss (e.g. future wrappers).
if [ -n "$PROMPT" ]; then
  if echo "$PROMPT" | grep -qiE \
    '(output ONLY|ONLY output|NO (introductory|extra) text|nothing else|no explanations|IMPORTANT:.*output|format:.*(TICKET|JSON|CSV|YAML|XML))'; then
    exit 0
  fi
fi

# ── Output ───────────────────────────────────────────────────────────────────
cat <<'EOF'
FONTOS: Minden válaszod legvégére tegyél egy üres sort, majd EGY sorban
a session markerét a lenti formátumban.

Formátum: ($topic: <téma 5-10 szóban> | $completeness: <0-100> | $state: <waiting|done|idle>)

$topic — a session FŐ CÉLJA, a session nyelvén. NEM az aktuális lépés vagy
  a legutóbbi részfeladat, hanem a nagyobb szándék, ami köré az egész munka szerveződik.

  Alapértelmezés: a topic stabil. Csak erős indokra váltson. Ha bizonytalan vagy,
  maradjon az előző topic — inkább legyen kicsit elavult, mint érzékenyen csapongó.

  NEM topic-váltó (a főcélt szolgáló kiegészítés → topic marad):
  - Munkafolyamat-akciók: commit, push, gh issue/PR nyitása, branch váltás, rebase, merge
  - Follow-up részfeladatok: verifikáció, teszt futtatás, hibajavítás, tuning, cleanup
  - Kiegészítő munka ugyanabban a kontextusban: UI input hozzáadása a már módosított
    flow-hoz, dokumentáció frissítés a most írt kódhoz, CI config illesztése az új
    paraméterhez, stb.
  - Példa: ha a főcél "loglevel build param", és a user utána CI workflow log_level
    input-ot kér hozzá, az ugyanaz a topic — NEM lesz belőle "CI workflow input".

  CSAK AKKOR váltson a topic, ha a user érdemben új, önálló főcélt indít, ami
  egyértelműen más területre vezet (másik feature, másik probléma, másik kódrész).

$completeness — a feladat haladása 0-100 között.
  Becsüld a teljes beszélgetés alapján, beleértve:
  - A user tónusát (elégedettség, kérdezősség, megerősítés)
  - A session dinamikáját (tervezés=10-30, implementáció=40-70, tesztelés/finalizálás=70-95, kész=100)
  - Ha scope change történt, a completeness az új scope-hoz viszonyítson.

$state — mire vár a session:
  - "waiting" — user inputra/action-re vár (alapértelmezés)
  - "done" — feladat kész, session zárható (completeness=100)
  - "idle" — nincs aktív feladat

KIVÉTEL — NE tedd rá a markert, ha a user prompt bármelyikre igaz:
- Strukturált/gépi output-ot kér (JSON, CSV, YAML, XML, changelog, stb.)
- Explicit formátum-megkötést ad (pl. "only output X", "format: ...", "no extra text")
- A kontextusból egyértelmű, hogy a kimenetet más eszköz fogja feldolgozni
Ilyenkor a marker rontaná a kimenetet, ezért hagyd el.
EOF
