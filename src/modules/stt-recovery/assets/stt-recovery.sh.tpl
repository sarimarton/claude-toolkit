#!/bin/bash
# Hungarian speech-to-text correction hook for Claude Code
# Two-phase architecture:
#   Phase 1: Detect suspicious words/phrases (text-only, fast)
#   Phase 2: Per-phrase parallel subagents investigate project context

# ── Check dictation flag file (created by Karabiner on F5 press) ──
# Flag file deleted by this hook on use, or by Karabiner after 120s.
STT_FLAG="{{home}}/.config/.stt-recovery-flag"

if [ ! -f "$STT_FLAG" ]; then
  exit 0
fi

# Recursion guard: prevent infinite loop when claude -p triggers this hook
if [ -n "$DICTATION_HOOK_RUNNING" ]; then
  exit 0
fi
export DICTATION_HOOK_RUNNING=1

# File is valid — delete it and notify (Karabiner's 120s cleanup won't find it)
rm -f "$STT_FLAG"
{{hs}} -c 'hs.alert.show("🎤 STT cleanup")' 2>/dev/null &

HOOK_START=$SECONDS
DEBUGLOG={{hooks_dir}}/stt-debug.log

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | {{jq}} -r '.prompt')
CWD=$(echo "$INPUT" | {{jq}} -r '.cwd // empty')

{
  echo "=== $(date -Iseconds) ==="
  echo "PROMPT: ${PROMPT}"
  echo "PROMPT_LEN: ${#PROMPT}"
  echo "CWD: ${CWD}"
} >> "$DEBUGLOG"

# Skip very short prompts (greetings, yes/no answers)
if [ ${#PROMPT} -lt 20 ]; then
  echo "EXIT: short prompt (<20 chars), skipping analysis" >> "$DEBUGLOG"
  echo "" >> "$DEBUGLOG"
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[speech-to-text] This prompt was dictated in Hungarian via speech-to-text (short prompt, skipped analysis). Interpret intent generously."}}'
  exit 0
fi

# ── Phase 1: Detect suspicious words/phrases (no tools, fast) ────────────────

PHASE1=$({{claude}} -p --no-session-persistence --model sonnet "You are a Hungarian speech-to-text artifact detector. A developer dictates prompts in Hungarian to a coding assistant. Hungarian STT garbles English tech terms into phonetically similar nonsense.

Your task: identify words/phrases that are suspicious — likely NOT what the speaker intended.

CRITICAL — Hungarian agglutination on English words is NOT an error:
Hungarian is an agglutinative language. Developers routinely attach Hungarian grammatical suffixes to English tech terms. This is intentional code-switching, NOT a transcription error. Do NOT flag these. Do NOT \"correct\" them by stripping the suffix. Examples:
- Accusative -t/-ot/-et/-öt: \"pr-t\" (the PR [as object]), \"uiert\" (the UI [as object])
- Sublative -re/-ra: \"mainre\" (onto main), \"branchre\" (onto branch)
- Imperative -d/-eld/-old/-öld/-jad/-jed: \"rebase-eld\" (do a rebase), \"pushold\" (do a push), \"commitold\" (do a commit), \"mergeld\" (do a merge)
- Adjectival -s/-es/-os/-ös: \"534-es\" (number 534), \"reactos\" (React-related)
- Inessive -ban/-ben: \"branchben\" (in branch), \"repoban\" (in repo)
- Elative -ból/-ből: \"mainből\" (from main), \"stagingből\" (from staging)
- Instrumental -val/-vel: \"gittel\" (with git)
- Superessive -on/-en/-ön/-n: \"branchen\" (on branch)
- Infinitive -ni/-olni/-elni: \"pusholni\" (to push), \"deployolni\" (to deploy)
- Past -olt/-elt/-ölt/-t: \"mergelt\" (merged), \"pusholt\" (pushed)
- Verbal -ol/-el/-öl: \"rebaseel\" (to rebase), \"commitol\" (to commit)
These appear hyphenated (rebase-eld) or concatenated (mainre). Both forms are normal. The base English word + Hungarian suffix = perfectly clear intent. SKIP them entirely.

How to detect ACTUAL STT errors:
- Words that don't exist in Hungarian AND aren't recognizable English (even with suffixes stripped) → suspicious
- Phonetically mangled English tech terms where the BASE word is garbled (e.g. ribézel→rebase, komit→commit, pussol→push, mördzs→merge, brencs→branch, diploj→deploy, hók→hook, bild→build, vebpekk→Webpack, dzseszt→Jest, tájpszkript→TypeScript)
- IMPORTANT — Adjacent suspicious words: two or more neighboring words that individually seem wrong or out of place may be a SINGLE compound term that STT split apart and mangled. Group them as one phrase. For example, STT might turn a single Hungarian compound word into two separate nonsensical words.
- Hungarian words with missing syllables (konfliktmentes → konfliktusmentesen)
- Numbers written as words (négykilencvenest) — flag but do NOT decode
- Speech repetitions where the speaker restarts a sentence
- Do NOT flag valid Hungarian words/slang (cucc, gáz, lusta, stb.)
- Do NOT flag Hungarian-English mixed phrases where each word is individually valid (e.g. \"conflict resolve\" — both are real English words used in valid context)

For each suspicious item, assess your confidence:
- HIGH: you're confident what the correct term is AND the correction is a well-known, common term (e.g. ribézel→rebase, komit→commit, pussol→push). Only use HIGH when there's ONE obvious answer.
- LOW: anything ambiguous, anything that COULD map to multiple terms, or any word that might be a project-specific name. When in doubt, use LOW — it's always safer to investigate than to guess wrong.

CRITICAL: For LOW confidence items, output them as PHRASES (include surrounding context words if they might be part of the same mangled term). Never split adjacent suspicious words into separate unresolved items.

RESPONSE FORMAT — follow EXACTLY:
- resolved: heard→meant, heard→meant (HIGH confidence corrections)
- unresolved: \"phrase one\", \"phrase two\" (LOW confidence phrases, quoted, need context)
- numbers: yes (if number-as-word present)
- repetitions: yes (if speech repetition present)
- If nothing found: CLEAN
- NOTHING else. No markdown, no explanations.

Prompt:
${PROMPT}" 2>/dev/null)

PHASE1=$(echo "$PHASE1" | sed '/^$/d' | tr '\n' '; ' | xargs)

PHASE1_ELAPSED=$((SECONDS - HOOK_START))
echo "PHASE1_RAW: ${PHASE1}" >> "$DEBUGLOG"
echo "PHASE1_TIME: ${PHASE1_ELAPSED}s" >> "$DEBUGLOG"

# ── Check if Phase 2 is needed ───────────────────────────────────────────────

if echo "$PHASE1" | grep -qi "CLEAN"; then
  echo "EXIT: Phase 1 returned CLEAN" >> "$DEBUGLOG"
  echo "" >> "$DEBUGLOG"
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[speech-to-text] This prompt was dictated in Hungarian via speech-to-text. No obvious transcription errors detected, but minor artifacts may be present. Interpret intent generously based on conversation context. If you detect any likely misheard words, show them at the start of your response as: [speech-to-text] Értelmezés: X → Y"}}'
  exit 0
fi

# Extract resolved and unresolved (split by ; first to avoid resolved: matching inside unresolved:)
UNRESOLVED=$(echo "$PHASE1" | tr ';' '\n' | grep -i 'unresolved:' | sed 's/.*unresolved:[[:space:]]*//' | sed 's/^none$//i' | xargs)
RESOLVED_P1=$(echo "$PHASE1" | tr ';' '\n' | grep -i 'resolved:' | grep -vi 'unresolved' | sed 's/.*resolved:[[:space:]]*//' | xargs)

echo "RESOLVED_ITEMS: ${RESOLVED_P1:-(none)}" >> "$DEBUGLOG"
echo "UNRESOLVED_ITEMS: ${UNRESOLVED:-(none)}" >> "$DEBUGLOG"

if [ -z "$UNRESOLVED" ]; then
  # All resolved in Phase 1 — no investigation needed
  echo "EXIT: All resolved in Phase 1, no Phase 2 needed" >> "$DEBUGLOG"
  echo "" >> "$DEBUGLOG"
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[speech-to-text] This prompt was dictated in Hungarian. Corrections: %s\\n\\nCRITICAL: The corrections above are verified speech-to-text errors. You MUST use the corrected terms (right side of →) everywhere in your response, tool calls, and searches — NEVER use the original misheard terms (left side of →). Show corrections at the start of your response as: [speech-to-text] Értelmezés: X → Y, then proceed."}}' "$RESOLVED_P1"
  exit 0
fi

# ── Time budget check for Phase 2 ────────────────────────────────────────────

PHASE2_BUDGET=$((100 - (SECONDS - HOOK_START)))
echo "PHASE2_BUDGET: ${PHASE2_BUDGET}s" >> "$DEBUGLOG"

if [ "$PHASE2_BUDGET" -lt 25 ]; then
  echo "EXIT: No time for Phase 2 (${PHASE2_BUDGET}s left), delivering Phase 1 only" >> "$DEBUGLOG"
  echo "" >> "$DEBUGLOG"
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[speech-to-text] This prompt was dictated in Hungarian. Corrections: %s; Unresolved (no time for investigation): %s\\n\\nCRITICAL: Use the corrected terms (right side of →) everywhere. For unresolved items, use conversation context and the project to guess the intended meaning. Show corrections at the start of your response as: [speech-to-text] Értelmezés: X → Y, then proceed."}}' "$RESOLVED_P1" "$UNRESOLVED"
  exit 0
fi

# ── Phase 2: Parallel subagents per unresolved phrase ─────────────────────────

echo "ENTERING Phase 2" >> "$DEBUGLOG"

TMPDIR=$(mktemp -d)

# Parse unresolved phrases into array (comma-separated, possibly quoted)
PHRASES=()
while IFS= read -r PHRASE; do
  PHRASE=$(echo "$PHRASE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
  [ -n "$PHRASE" ] && PHRASES+=("$PHRASE")
done < <(echo "$UNRESOLVED" | tr ',' '\n')

echo "PHRASES_COUNT: ${#PHRASES[@]}" >> "$DEBUGLOG"
echo "PHRASES: ${PHRASES[*]}" >> "$DEBUGLOG"
echo "TMPDIR: ${TMPDIR}" >> "$DEBUGLOG"

# Launch parallel subagents — one per unresolved phrase
for PHRASE in "${PHRASES[@]}"; do
  SAFE_NAME=$(echo "$PHRASE" | tr ' ' '_' | tr -cd '[:alnum:]_')
  echo "LAUNCHING subagent for: ${PHRASE} (file: ${SAFE_NAME}.txt)" >> "$DEBUGLOG"

  timeout "$PHASE2_BUDGET" {{claude}} -p --no-session-persistence --model sonnet \
    --allowedTools "Bash(gh:*),Bash(jq:*),Bash(cat:*),Bash(ls:*),Read,Glob,Grep" \
    --dangerously-skip-permissions \
    "You are investigating a single speech-to-text artifact from a Hungarian developer's dictated prompt.

The developer's full prompt (for context):
${PROMPT}

The suspicious phrase you must resolve: \"${PHRASE}\"

This phrase doesn't make sense in context and is likely a speech-to-text error. Your job: figure out what the developer actually meant.

Approach:
1. Phonetic analysis — sound out the phrase. Could it be an English tech term spoken with a Hungarian accent?
2. If the phrase contains multiple words, try concatenating them — STT often splits a single compound word into separate words. Read them together as one and see if it sounds like a known term. Hungarian commonly builds compounds with suffixes that STT might hear as a separate word.
3. Use the developer's prompt for clues — what are they talking about? What tools, libraries, operations do they mention? Use this to narrow down what the phrase could mean.
4. Investigate the project — you have full tool access. Use whatever makes sense: look at PRs, branches, dependencies, config files, directory structure, documentation. Let the prompt context guide WHERE you look. Don't follow a fixed checklist — think about what would help resolve this specific phrase.

CRITICAL FINAL STEP — Do this BEFORE answering:
After gathering evidence, go back and compare every term you found (branch names, PR titles, dependency names) PHONETICALLY against the suspicious phrase. Read them aloud in your mind. Does any discovered term SOUND LIKE the phrase when spoken with a Hungarian accent? STT often mishears suffixed compound words — the project evidence may contain the real term with a slightly different suffix than what STT produced. Always prefer phonetic matches from project evidence over literal dictionary translations of the misheard words.

RESPONSE FORMAT — output ONLY one line:
phrase→resolved_term (evidence: brief explanation)

If truly unresolvable:
phrase→? (unresolvable)

NOTHING else." > "${TMPDIR}/${SAFE_NAME}.txt" 2>/dev/null &

done

# Wait for all parallel agents to complete
echo "WAITING for ${#PHRASES[@]} subagents..." >> "$DEBUGLOG"
wait
echo "ALL subagents completed" >> "$DEBUGLOG"

PHASE2=""
for f in "${TMPDIR}"/*.txt; do
  [ -f "$f" ] || continue
  RESULT=$(cat "$f" | sed '/^$/d' | tr '\n' '; ' | xargs)
  FNAME=$(basename "$f" .txt)
  echo "SUBAGENT [${FNAME}]: ${RESULT}" >> "$DEBUGLOG"
  [ -n "$RESULT" ] && PHASE2="${PHASE2}${RESULT}; "
done

echo "COMBINED_PHASE2: ${PHASE2:-(empty)}" >> "$DEBUGLOG"

rm -rf "$TMPDIR"

# ── Combine Phase 1 + Phase 2 results ────────────────────────────────────────

NUMBERS=$(echo "$PHASE1" | grep -oi 'numbers: yes' || true)
REPETITIONS=$(echo "$PHASE1" | grep -oi 'repetitions: yes' || true)

COMBINED=""
[ -n "$RESOLVED_P1" ] && COMBINED="corrections: ${RESOLVED_P1}"
[ -n "$PHASE2" ] && COMBINED="${COMBINED}; context-resolved: ${PHASE2}"
[ -n "$NUMBERS" ] && COMBINED="${COMBINED}; ${NUMBERS}"
[ -n "$REPETITIONS" ] && COMBINED="${COMBINED}; ${REPETITIONS}"

echo "EXIT: Phase 2 complete" >> "$DEBUGLOG"
echo "FINAL_COMBINED: ${COMBINED:-(empty)}" >> "$DEBUGLOG"
echo "" >> "$DEBUGLOG"

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[speech-to-text] This prompt was dictated in Hungarian. Analysis: %s\\n\\nCRITICAL: The corrections above are verified speech-to-text errors. You MUST use the corrected terms (right side of →) everywhere in your response, tool calls, and searches — NEVER use the original misheard terms (left side of →). Show corrections at the start of your response as: [speech-to-text] Értelmezés: X → Y, then proceed."}}' "$COMBINED"

exit 0
