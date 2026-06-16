## GitHub-szinkron policy (AutoDev-repókban)

> Forrás-igazság: a claude-toolkit `auto-dev` modulja telepíti (claudeMdBlocks).
> Kézzel ne szerkeszd — a modul újratelepítéskor felülírja, uninstallkor törli.

- **Feltétel (opt-in):** ez a policy CSAK akkor aktív, ha GitHub repositoryban vagyunk, ÉS a repóban telepítve van az **AutoDev**. Detektálás: a repónak van `auto-dev` GitHub-topicja —
  `gh repo view --json repositoryTopics -q '.repositoryTopics[].name' | grep -qx auto-dev`
  (másodlagos, lokális jelző: négy `.github/workflows/auto-dev-*.yml` fájl jelenléte). Ha ez NEM teljesül, a policy nem alkalmazandó.

- **Mit ír elő (NEM opcionális, eseményvezérelt):** ha a feltétel teljesül, a GitHub-tracking-szinkron kötelező és KONKRÉT eseményekhez kötött — nem homályos „lehetőleg". A szinkron három felületre terjed ki: **board** (Project item-státusz), **issue** (státusz + komment), **PR** (státusz + body TODO-markup):
  - **Munka kezdetén:** amikor egy issue-höz tartozó érdemi munkába kezdesz, állítsd a board-itemet **In Progress**-re MIELŐTT dolgozni kezdesz.
  - **Eredménynél:** amikor egy lépés érdemi eredménnyel zárul (felderítés, döntés, demó, mérés, lefordult/működő kód), tedd ki az eredményt **issue-kommentbe**, ÉS állítsd a státuszt (**Done**, ha a Done-kritérium teljes; egyébként marad In Progress). Ha PR-ben dolgozol, frissítsd a **PR body TODO-markupot** is (`- [ ]` → `- [x]`).
  - **Megfogható eredmény → használati API a kommentben (KÖTELEZŐ):** ha a lépés eredménye egy futtatható artifact (CLI-szkript, parancs, endpoint, make-target, stb.), a záró issue-komment ne csak azt írja le, *mi készült*, hanem adjon **copy-paste használati példát** is, amivel a stakeholder maga ki tudja próbálni — konkrét paranccsal, a szükséges előfeltételekkel (pl. setup, paraméterek). A „mit csináltam" mellett mindig legyen „így használod te is". Általánosan fogalmazz, ne köss konkrét repóhoz.
  - **Munkabontás:** új főcélt issue-kra bontva indíts; a részeredmény issue-kommentben/PR-ban kapjon nyomot, ne csak a lokális munkafában.

- **Kötelező önellenőrző zárómondat:** minden olyan válasz végén, amelyik egy issue-höz tartozó munkát végzett (AutoDev-repóban), egy mondatban jelezd a board tényállapotát — pl. „Board: #N → In Progress" vagy „Board: nem mozdult, mert …". Ez kényszeríti ki, hogy a szinkron ne maradjon ki.
