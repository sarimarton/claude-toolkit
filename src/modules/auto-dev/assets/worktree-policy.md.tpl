## Interaktív worktree + PR-lifecycle policy (AutoDev-repókban)

> Forrás-igazság: a claude-toolkit `auto-dev` modulja telepíti (claudeMdBlocks).
> Kézzel ne szerkeszd — a modul újratelepítéskor felülírja, uninstallkor törli.
>
> Ez a policy ortogonális a GitHub-szinkron policyval: amaz a **mit dokumentálj**
> (board/issue/PR sync), ez a **hogyan strukturáld a munkát** (worktree + branch +
> PR-lifecycle + merge gate). Külön `@import`-ként települ, külön kapcsolható.
>
> Cél: (a) párhuzamos issue-k ne dolgozzanak keresztbe ugyanabban a working
> tree-ben; (b) a git history feature-blokkokra essen szét — auditálható
> „commit-buszmegálló" mintázat, ne összefonódó DAG-spagetti.

- **Feltétel (opt-in):** ugyanaz, mint a GitHub-szinkron policyé — CSAK akkor aktív, ha GitHub repositoryban vagyunk, ÉS a repóban telepítve van az **AutoDev** (detektálás: `auto-dev` GitHub-topic, másodlagosan a négy `.github/workflows/auto-dev-*.yml` jelenléte). Ha ez NEM teljesül, a policy nem alkalmazandó.

- **Mikor kötelező (gate, escape hatch-csel):** ha egy issue-höz tartozó **érdemi, többcommitos** munkába kezdesz, a lenti lifecycle KÖTELEZŐ. Triviális egysoros fixre vagy beszélgetős körre a **`wt-skip`** shorthand (escape hatch) kikapcsolja erre a körre (ilyenkor direkt main-commit megengedett) — tudatosan, ritkán használd, ne a fegyelem megkerülésére.

- **Issue-lifecycle (szemilineáris, eseményvezérelt):**
  1. **Indítás (izoláció):** issue → board **In Progress**; nyiss `git worktree`-t az issue-nak (pl. `../wt/issue-<N>`), benne `issue-<N>-<slug>` branchet. SOHA ne dolgozz párhuzamos issue-kon ugyanabban a working tree-ben — a külön worktree adja a valódi izolációt (külön fizikai könyvtár = nincs keresztbe-commitolás). A Claude Code natív `EnterWorktree`/`ExitWorktree` toolja használható erre.
  2. **Draft PR azonnal:** nyiss draft PR-t a feature-branchre a munka legelején; a PR body legyen a Done-kritériumokból generált task-lista (`- [ ]`). Innentől a GitHub-szinkron policy ide ír (részeredmény → PR body checkbox + issue-komment).
  3. **Munka a worktree-ben:** TDD-fegyelemmel (lásd a felhasználó TDD-policyját); a commitok a feature-branchre mennek, így a history feature-köré csoportosul.
  4. **Érés → review gate:** ha a feature kész, futtass **külön review-ágenst** (pl. `pr-review-toolkit` / `code-review`) MIELŐTT merge-re jelölöd.

- **Négyfeltételes merge gate (MIND teljesüljön, különben NEM mergelhető):**
  - ✅ **Review zöld** — a review-ágens nem hagyott nyitott érdemi findingot.
  - ✅ **TDD megvolt** — a determinisztikus logikára volt előbb-bukó-aztán-zöld teszt (vagy indokolt `notdd` / nem-unit-tesztelhető kivétel).
  - ✅ **Demó-instrukció kész** — a PR tartalmaz copy-paste kipróbálási példát (összhangban a GitHub-szinkron policy „használati API a kommentben" előírásával).
  - ✅ **Friss main-re rebase-elve** — a branch a legfrissebb `origin/main` tetejére van **rebase**-elve. Ha a merge blokkolt (közben más feature mergelt), a feloldás eszköze a **rebase, NEM a merge-commit**: `git fetch && git rebase origin/main` a feature worktree-jében, a **konfliktust ott old fel** (nem utólag a main-en), majd újra a gate.

- **Merge módja — `--no-ff`, SOHA nem squash:** a teljes feature-history audit célból megőrzendő (a fejlesztés evolúciója értékes információ). Tehát a sorrend:
  - **rebase friss main-re → konfliktus-feloldás → `git merge --no-ff`**. A `--no-ff` merge-commit a „buszmegálló", ami vizuálisan körberajzolja az issue határait, miközben minden feature-commit megmarad.
  - **Squash-merge TILOS** — elveszne a lépésenkénti history.
  - Sima fast-forward önmagában nem elég: a `--no-ff` garantálja a merge-commit-buszmegállót.

- **Lezárás:** merge után board → **Done**; `git worktree remove` a feature worktree-jére (a cleanup a merge szerves része — elmaradása halmozódó worktree-szemetet hagy).

- **Kötelező önellenőrző zárómondat (kiegészítés):** ha worktree+PR-lifecycle-ben dolgoztál, a board-állapot mellett egy mondatban jelezd a gate állapotát is — pl. „Gate: review ✅ · TDD ✅ · demó ✅ · rebase ⏳ (merge blokkolt, rebase szükséges)".
