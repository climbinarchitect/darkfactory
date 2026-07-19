# darkfactory — Journal de projet

> Journal de bord continu : décisions, pivots, incidents, et le *pourquoi* au moment
> où c'est décidé. Une entrée peut pointer vers `rd-journal.md` (jamais l'inverse).

---

## 2026-07-06 — Naissance du projet (session de design, Claude Fable)

### Cadrage
- Objectifs : **5x l'output de code** + **démo c.v.** (thèse combinée avec Archy :
  génération gouvernée de documents ↔ livraison gouvernée de logiciel).
- Méthode : interview + challenge. Décisions consignées ci-dessous avec leurs raisons.

### Décisions structurantes
- **Delta assumé du projet = gouvernance + mémoire + intake**, couche mince au-dessus
  de Hermes (loop) et Claude Code (dev). Le 5x vient du parallélisme et du découplage
  présence/exécution, pas d'une génération "plus vite". Risque structurel nommé :
  Anthropic mange le gap async — ne jamais investir dans une capacité que le vendor
  annonce. Corollaire : pipeline multi-agents (PO/architect/tester) **refusé en v1** ;
  un rôle s'ajoute seulement sur mode d'échec documenté.
- **Infra : VPS Hetzner, pas le Pi.** Les deux arguments pro-Pi tombent (Tailscale rend
  le "déjà sur mon réseau" caduc ; un VPS est plus always-up qu'un Pi sur SD). Argument
  décisif : ne jamais co-localiser un agent autonome expérimental avec KaosFleet qui
  contrôle du chauffage physique. Circularité interdite (la factory déploie *vers* le
  Pi, jamais *depuis*).
- **Intake : Telegram, channel-agnostic par design.** UI web custom + OAuth2 rejetée
  (2-4 semaines qui ne sont pas la factory ; OAuth2 mono-utilisateur derrière
  Tailscale = théâtre de sécurité).
- **Modèles : orchestration Hermes sur sub OpenAI (hypothèse à valider, spike #2 ;
  échec ⇒ sub annulée, fallback Claude API plafonnée) ; dev via Claude Code headless
  sur sub Claude.** Budget-guard v1 obligatoire : les caps hebdo de sub protègent
  l'humain d'abord.
- **v1 = une ligne (kaos-fleet-manager), un benchmark : les golden tests du thermal
  controller** (dette connue du repo kaos, scope fermé, valeur réelle).
- **Wiki = markdown + git + Obsidian en couches** (rien from scratch, la mémoire Hermes
  n'est pas un wiki). Journal personnel : repo séparé, hors de portée des lignes.
- **Conventions** : code/commentaires FR (identifiants sans accents, pas de
  sur-francisation), docs techniques EN, comm/journaux FR. **Deux journaux** : celui-ci
  (continu) et `rd-journal.md` (ouvert seulement en présence d'incertitude
  technologique réelle — intrant des demandes de R&D).

### Pivot infra : VM Hyper-V → VPS direct
- Plan initial : spikes en local (VM Hyper-V, x86_64), VPS seulement au passage en mode
  autonome. **Fait nouveau** : l'host laptop n'a pas la marge RAM (VM à 4 Go, démarrage
  déjà pénible ; 8 Go inatteignables). Décision : provisionner le CX32 tout de suite
  (facturation horaire), le temps de soirée vaut plus que ~8 $/mois. Portabilité
  assurée par l'état-fichiers (`~/.hermes/`) + `setup.sh` scripté dès le jour 1 —
  jamais par la conteneurisation de Hermes (Docker-in-Docker / montage du socket =
  root à l'agent, interdit).

### Architecture (doc/architecture.md) — calls opinionated actés
- **Gate timeout = pause forever, re-ping périodique.** Jamais de défaut-ouvert.
- **Merge gate non-abaissable en v1** — la ligne n'a pas encore gagné la confiance.
- **Concurrency = 1 en v1** (champ explicite dans `_global.yaml` : monter la
  concurrence sera une décision de gouvernance visible, pas un changement enfoui).
- **Retry = nouvelle tâche** référençant l'ancienne trace ; historique append-only
  (même philosophie que les tables kaos).
- Intégration "méthode Karpathy" (transcript fourni) : **niveaux de plan gate**
  (quick/spec/interview), **section `verification` obligatoire dans toute spec**
  (critères définis avant exécution ; le merge gate review contre contrat, pas au
  feeling), option **(4) custom** dans l'escalade avec règle de rechallenge (réponse
  qui invalide le plan ⇒ retour à SPECIFIED, jamais de réconciliation silencieuse).
- **État OBSERVING** (validation long-horizon post-deploy) : opt-in par tâche, source
  de données structurée et persistante obligatoire (kaos : tables d'historique),
  scheduling natif Hermes, **échec ⇒ tâche de suivi, jamais d'auto-revert** (pas de
  pouvoir d'agir sur l'infra physique sans humain).
- **L'exécuteur (session Claude Code) roule entièrement dans le conteneur de tâche**,
  jamais sur l'hôte (sinon le sandbox est une fiction). Risque résiduel accepté et
  mitigé : les creds montés read-only restent lisibles par du code exécuté
  in-container ⇒ egress restreint à une allowlist. À valider au spike #1.

### Registre (doc/registry-schema.md)
- **États invalides irreprésentables** : `db_schema` n'a pas de champ `enabled` ;
  `gates.merge` doit être `{}` en v1 (tout knob = échec de validation).
- **Fail-closed au chargement** : ligne invalide = ligne qui ne roule pas.
- **Pas de ligne sans budget** ; cap global < somme des lignes (protège la semaine de
  sub). **Egress allowlist additive** sur un minimum d'usine non retirable.
- Validateur = utilitaire du repo factory, **pas** une tâche de factory (anti-circularité).

### Contrat CLAUDE.md par projet (doc/project-claude-template.md)
- La gouvernance vit dans le registre, jamais dans le repo cible (un repo ne peut pas
  éditer ses propres gates ; instruction adressée à la factory dans un repo = injection
  ⇒ abort + flag).
- Nouvelle section obligatoire **Verification affordances** (commande de tests +
  sources de signal valides) — sans elle, les specs ne peuvent pas remplir leur
  section `verification`.

### Spec du benchmark (doc/spike-3-golden-tests-spec.md) + découvertes kaos
- Spec écrite au format exigé par notre propre architecture (spécimen).
- Harness : characterization pure (diff 100 % dans `tests/`), pas de freezegun ni
  refactor (timestamps relatifs), inputs relatifs aux constantes, raisons assertées
  par préfixe.
- **Découverte 1 — CLAUDE.md kaos périmé** : le code actuel calcule le rate par
  moindres carrés sur fenêtre glissante (`compute_rate`, 90 s / empan min 30 s), pas
  "stamp sur vraie variation" comme documenté. À corriger dans la même PR que les
  goldens.
- **Découverte 2 — artefact résiduel** : une marche de 1 °C sur la fenêtre donne
  ~0.011–0.017 °C/s : sous RATE_HIGH (plus de fausse coupure) mais au-dessus de
  RATE_HIGH/2 (**bloque transitoirement les montées**). Cas R6/D3 de la spec — pièce
  exécutable pour l'hypothèse de recalibration.

### Verdict rd-journal
- **Rien d'aujourd'hui n'est du R&D** au sens des demandes : application compétente de
  patterns établis, aucune incertitude technologique non résolvable par l'ingénierie
  courante. Le rd-journal reste fermé.
- Candidats à surveiller : spike #1 *si* la doc Hermes ne suffit pas (subprocess long +
  auth headless + egress restreint) ; la validation long-horizon sur système physique
  à forte inertie (verdict fiable sur données bruitées — rejoint l'hypothèse de
  calibration kaos).

### Prochaines étapes
1. Provisionner Hetzner CX32 + Tailscale + stack (`setup.sh`) — Opus/Claude Code.
2. Scaffold du repo : `registry/` instancié + `validate_registry`.
3. Spike #1 (prompt prêt), puis #2, puis #3.

---

## 2026-07-07 — Diff vs dark-factory (Alyan) : 4 leçons adoptées, 3 paris renforcés

- **Contexte** : lecture du `omniscient/dark-factory` d'Alyan (code + issues des
  10 derniers jours). Sa factory est ~6 mois devant en exécution (prod, self-repair,
  ~60 fichiers de tests sur elle-même) — mais **sur Claude Max comme nous**, et son
  historique récent documente des douleurs qui valident nos choix structurants.
  Analyse complète : `doc/darkfactory-alyan-diff.md`.
- **Leçons adoptées** (appliquées le jour même, un commit chacune) :
  1. La fenêtre/cap épuisé est un échec d'*environnement*, pas de tâche — son
     issue #35 (21 runs grillés en une nuit) est le mode d'échec exact que notre
     budget-guard designait à froid. Signature à observer au spike #1.
  2. Write bar + distinction invalidé/supersédé dans le jardinage du wiki (volés
     à son contrat mémoire).
  3. Logique de factory en Python testé dès le jour 1, bash = glue — son épic
     #187 (refactoring de son scheduler bash de 50 Ko) est le contre-exemple payé.
  4. Frontière contexte-vs-gouvernance nommée au registre : ce qui aide l'agent à
     *lire* le repo peut vivre côté cible ; ce qui contraint ses *droits*, jamais.
- **Paris renforcés, on ne change rien** : moteur emprunté (son issue #33 évalue…
  les patterns Hermes — il converge vers notre point de départ) ; budget-guard qui
  protège l'humain d'abord ; gouvernance hors du repo cible ; merge humain
  (même lui livre en draft PR). Trade-off pause-forever vs fail-open désormais
  documenté comme choix conscient (architecture §3).
- **Fait clé** : il token-budgète *sur Max* — pas pour les dollars, pour étirer la
  fenêtre 5h/hebdo. Trigger de réévaluation de notre unité coarse (sessions) :
  saturation de fenêtre observée, pas un éventuel passage API.
- **On ne suit pas** : epic-autopilot / self-improvement / ceiling automatique —
  points d'arrivée d'une courbe de confiance (kill-switches + données d'éval
  accumulées), pas features de départ. Cohérent avec notre anti-pattern « pas de
  rôle sans mode d'échec documenté ».
- **Collaboration** : accès write accordé à `omniscient` (Alyan) sur le repo.
  Note posée : le jour où le registre vit ici, branch protection sur `main`.

---

## 2026-07-14 — Provisioning VPS + spike #2 = PASS

- **VPS provisionné et stack validée** : Docker, Node, Claude Code installés ; compte
  utilisateur non-root dedie (`inverted`). Chaque commande passe par `setup.sh` —
  le serveur reste jetable et reconstructible (décision infra du 2026-07-06 tenue).
- **Claude Code headless validé** : `claude -p` rend du JSON propre. C'est la
  *précondition* du spike #1, pas le spike lui-même — reste à prouver que Hermes lance,
  suit et récupère proprement la session en subprocess.
- **Hermes installé, daemon systemd persistant** (linger activé) : survit à la
  déconnexion, pas de session utilisateur requise pour tourner.
- **Spike #2 = PASS.** Orchestration sur sub OpenAI via Codex (`gpt-5.6-terra`) :
  l'hypothèse de l'auth par subscription (à la Codex CLI) tenait. Conséquence de
  gouvernance : la sub OpenAI garde sa raison d'être — **le fallback Claude API plafonnée
  n'est pas déclenché**, et la sub n'est pas à annuler.
- **Intake Telegram fonctionnel**, langue réglée en français.
- **Surface de tools réduite** (moindre privilège) : browser / web / computer-use
  coupés. Cohérent avec « contexte d'un agent au strict nécessaire » — moins de surface
  = moins d'exposition prompt-injection et d'egress non désiré.
- **Verdict rd-journal** : toujours fermé. Spike #2 s'est résolu par application
  compétente (auth Codex qui tient), pas par une incertitude technologique nécessitant
  essais/mesures. Le candidat R&D reste le spike #1 *si* le subprocess long + récupération
  headless résiste à la doc Hermes.
- **Prochaine étape** : spike #1 pour de vrai (Hermes ↔ session `claude -p` de bout en
  bout), puis spike #3 (le benchmark golden tests kaos).

---

## 2026-07-14 (suite) — Spike #1 étape 1 = PASS

- **Hermes pilote `claude -p` en subprocess** via un **skill natif `claude-code`**, et
  rapporte le **JSON structuré intact sur Telegram**. La brique de base du design tient :
  l'orchestrateur lance l'exécuteur headless et récupère sa sortie sans la corrompre.
- **Non-problème confirmé : l'env du service systemd.** `HOME` correctement hérité —
  aucun souci d'auth sur la session `claude -p` lancée depuis le daemon. Le risque
  « auth headless sous systemd » qu'on surveillait au spike #1 ne s'est pas matérialisé
  sur l'étape 1.
- **Découverte à explorer** : le skill `claude-code` est peut-être *le* mécanisme
  d'intégration qu'on cherchait, plutôt qu'un pilotage subprocess maison. Question
  ouverte avant d'en dépendre : gère-t-il les **sessions longues**, le **resume**, la
  **capture** ? Si oui, c'est de la plomberie qu'on n'écrit pas (cohérent avec le
  garde-fou « ne pas réimplémenter ce que Hermes/Claude Code fournit »).
- **Reste du spike #1** :
  - **Étape 2** — tâche de ~5 min. **Risque anticipé** : bute probablement sur le
    **timeout 180 s / lifetime 300 s** ; c'est exactement le mode d'échec « fenêtre
    épuisée = échec d'environnement » qu'on veut voir en vrai.
  - **Étape 3** — backend Docker (conteneur de tâche jetable), soit le **spike #1b**.

---

## 2026-07-15 — Spike #1 : PASS de bout en bout (gateway) + découvertes d'architecture

### Résultat
- **Spike #1 = PASS.** Le pilotage de Claude Code par Hermes fonctionne des deux façons :
  - **En direct** (`claude -p` lancé à la main sur le VPS) : tâche multi-étapes
    (calc.py + test_calc.py + venv + pytest 5/5) en **26s**, `subtype: success`.
  - **Via le gateway** (message Telegram → orchestrateur → skill claude-code →
    subprocess) : même tâche livrée, résultat rapporté proprement sur Telegram.
- Les trois piliers du design tiennent : intake asynchrone → orchestration →
  délégation à Claude Code → résultat rapporté.

### Le skill `claude-code` EST le mécanisme d'intégration (question ouverte tranchée)
- Skill natif Hermes v2.2.0 (`skills/autonomous-ai-agents/claude-code/`), mûr.
- Fournit nativement ce qu'on comptait gérer : `--output-format json`, reprise de
  session (`--resume <session_id>`, `--session-id <uuid>` imposable, `--fork-session`),
  détection d'erreur structurée (`subtype: success|error_max_turns|error_budget`),
  budget par-tâche (`--max-budget-usd`), permissions exécutables (`--allowedTools`,
  `--permission-mode plan`, `deny:["Read(.env)"]`).
- **Conséquence** : on ne code pas de pilotage subprocess maison (garde-fou respecté).
  Le mode print (`-p`) est préféré ; le mode tmux (multi-turn interactif) est de la
  plomberie fragile à éviter en v1.
- Interdits confirmés : `--dangerously-skip-permissions` (auto-approbation totale,
  antithèse de la gouvernance) et `--bare` (force ANTHROPIC_API_KEY = facturation API,
  or on est sur sub OAuth).

### Découverte 1 — le backend `local` fait exécuter du code à l'orchestrateur SUR L'HÔTE
- Preuve empirique (pas théorique) : via le gateway, l'orchestrateur a lui-même lancé
  `pytest -q` puis `python3 -m venv .venv` **sur le VPS**, en plus du travail déjà fait
  par Claude Code dans sa session. L'orchestrateur tourne sur l'hôte (backend `local`)
  → il exécute du code hors de tout conteneur de tâche.
- **Viole la trust boundary §7** (l'exécution de code doit vivre dans le conteneur de
  tâche). Confirme que le **spike #1b (bascule backend Docker) n'est pas optionnel** —
  démontré par observation, pas par principe.

### Découverte 2 — dédoublement d'exécution orchestrateur/exécuteur
- Claude Code fait déjà tourner les tests dans sa session (venv + pytest 5/5, visible
  dans son JSON). L'orchestrateur les **re-exécute** de son côté.
- Coûts : temps (le run via gateway a pris bien plus longtemps que les 26s directes,
  en partie à cause de ce dédoublement), et exécution hors sandbox (cf. découverte 1).
- **À raffiner (design)** : l'orchestrateur devrait *lire le verdict* de l'exécuteur
  (le JSON contient déjà le résultat des tests), pas re-exécuter. Frontière de
  responsabilité à préciser : l'exécuteur exécute et prouve ; l'orchestrateur lit,
  juge, rapporte.

### Règle actée — l'orchestrateur n'exécute JAMAIS de code (exécution ni vérification)
- Ferme proprement la découverte 1. La re-exécution de *vérification* garde une valeur
  de gouvernance (second regard contre un exécuteur qui mentirait sur son JSON), mais
  elle **doit vivre dans un conteneur, jamais sur l'orchestrateur**.
- Formulation dure : **l'orchestrateur ne fait jamais tourner de code — ni pour
  exécuter, ni pour vérifier.** Il lit des verdicts, juge, rapporte. Toute exécution de
  code (travail *ou* re-vérification) est déléguée à un conteneur de tâche jetable.
- Conséquence : la re-vérification au merge gate (piste retenue en découverte 2) n'est
  pas une exception à la trust boundary — c'est une **tâche conteneurisée de plus**, pas
  un `pytest` sur l'hôte. À câbler au moment du spike #1b, pas après.

### Découverte 3 — le modèle n'est pas homogène dans une session
- `--model sonnet` demandé, mais `modelUsage` montre `claude-sonnet-5` ET
  `claude-haiku-4-5` dans la même session (Claude Code route en interne).
- **Conséquence budget-guard / traces** : "une session = un modèle" est faux. Le coût
  agrégé (`total_cost_usd`) reste la bonne unité ; ne pas présumer l'homogénéité.
- Coûts observés : "pong" 0,055 $ ; micro-tâche calc 0,126 $ (surtout du cache_read).
  Extrapolation : une vraie tâche kaos = quelques dizaines de cents à ~1 $. Mesurer
  sur une vraie tâche kaos avant de figer les caps par ligne.

### Découverte 4 — timeouts à ajuster avant le spike #3
- `terminal.timeout: 180` et `lifetime_seconds: 300` (config Hermes) non déclenchés sur
  la micro-tâche (~26s), mais une tâche golden-tests kaos (lire le thermal controller,
  ~30-40 turns à ~4s/turn) les dépassera. À monter avant le spike #3.

### Reste à faire
- **Persistance du gateway (linger) : non encore éprouvée, et volontairement.** Le
  SIGTERM de 23:50 n'était pas une défaillance — arrêt délibéré parce que l'**allow-list
  egress n'a pas encore été stress-testée**. Choix de gouvernance assumé : on ne laisse
  pas tourner un agent autonome une nuit entière tant que le confinement réseau n'est pas
  prouvé. Séquence à tenir : durcir + tester l'allow-list *avant* le premier run
  overnight non surveillé (c'est ce run-là qui validera le linger).
- Spike #1b : bascule backend `local` → `docker` (priorité rehaussée par découverte 1).
- Mettre à jour architecture.md : §4 (resume via session_id natif), §5 (budget
  par-tâche via --max-budget-usd), §7 (permissions exécutables), + la frontière de
  responsabilité orchestrateur/exécuteur (découverte 2).

---

## 2026-07-19 — Spike #1b : PASS (core) — l'exécuteur tourne enfin en conteneur

> Détail technique reproductible : `doc/spike-1b-findings.md`. Interview de cadrage
> tenue avant le build (choix image + barre de PASS + gestion gateway).

### Résultat
- **PASS sur le cœur.** Hermes avec `terminal.backend: docker` lance un `claude -p`
  complet **dans un conteneur jetable** : authentifié, travaillant sur le repo monté,
  résultat JSON capturé fail-closed, **zéro code exécuté sur l'hôte**. La violation de
  trust boundary du spike #1 (orchestrateur qui lançait pytest/venv sur le VPS) est
  **fermée** — vérifiée par observation (hostname/cgroup conteneur, aucun venv/pycache
  sur `~`), pas par principe. Ferme le marqueur §7 « l'exécuteur roule dans le conteneur,
  jamais sur l'hôte ».
- **2 items durcissement documentés, non stress-testés** : teardown par-tâche et egress.

### Le point délicat (auth headless en conteneur) — résolu proprement
- Toute l'auth tient dans **un fichier** : `~/.claude/.credentials.json` (OAuth sub).
  Monté **read-only** via `docker_volumes` vers `/root/.claude/.credentials.json`. HOME
  conteneur = `/root` en tmpfs (jetable) : claude y écrit cache/session/history, tout
  disparaît à la destruction. **Read-only a suffi** (token frais, pas de refresh) —
  valide la moitié « creds read-only » de la prémisse §7.
- Le mécanisme natif de Hermes (`required_credential_files` / `terminal.credential_files`)
  **ne pouvait pas** servir : il est confiné à `~/.hermes` (anti-traversal), or l'auth
  vit dans `~/.claude`. `docker_volumes` (config opérateur trusted) est le bon chemin.

### Image task-runner épinglée dur (leçon issue #300 appliquée)
- `docker/task-runner.Dockerfile` versionné + build dans `setup.sh` (§5b) : image **pas
  seulement locale**, serveur reconstructible. Base épinglée par **digest sha256** (pas
  le tag flottant `python3.11-nodejs20`), `claude-code` épinglé sur **2.1.207** (version
  known-good de l'hôte). Le build **échoue bruyamment** si la version glisse — l'inverse
  du bug SHA silencieux d'Alyan.

### Découvertes (design deltas — cf. findings pour le détail)
1. **L'image par défaut n'a pas `claude`** → « flip le flag » était impossible tel quel ;
   d'où l'image custom. La prémisse « bascule et valide » du prompt sous-estimait ça.
2. **`backend` vs `env_type` : deux clés pour un réglage.** Le gateway lit `backend`,
   le CLI/oneshot lit `env_type`. Config avec seulement `backend: docker` → gateway en
   conteneur mais oneshot resté `local` (observé : premier test tourné sur l'hôte). Les
   deux clés sont posées. **Footgun** : le harnais de test de darkfactory doit forcer les
   `TERMINAL_*` explicitement, sinon il teste silencieusement le mauvais backend.
3. **Hermes ne détruit PAS le conteneur par tâche.** Il tourne `sleep infinity` +
   idle-reaper (~2×lifetime) + réutilisation par label (`docker_persist_across_processes`
   défaut ON). « Jetable » chez Hermes = réutilisé entre turns, reapé à l'idle — **pas**
   un conteneur par tâche tué en fin de tâche. **Contredit l'invariant §2.** Conséquence :
   **le teardown est la responsabilité de darkfactory** — `docker rm -f` par label
   `hermes-task-id` en quittant EXECUTING (teardown par label vérifié OK). Mettre aussi
   `docker_persist_across_processes: false`.
4. **Fichiers créés `root:root`** dans le repo monté (conteneur en root) → friction git/
   ownership. Trancher `docker_run_as_host_user` vs chown-au-teardown **avant** de câbler
   `git push`.
5. **Egress grand ouvert par défaut** (conteneur atteint example.com et 1.1.1.1 — vérifié).
   Firewall hôte = root-only (sudo à mot de passe, non dispo en session) + IP-allowlist
   fragile (CDN). **Primitive durable sans root vérifiée** : réseau Docker `--internal`
   bloque **tout** egress. Design retenu : `--internal` + **proxy domain-allowlist
   dual-homed** comme seule sortie (le proxy CONNECT résout aussi le DNS). Stress-test =
   item ouvert, qui **garde le gate « pas d'overnight avant allow-list testée »**.
6. **Fail-closed confirmé** : un `claude` qui échoue rend `subtype: error_max_turns`,
   `is_error: true`, `result: null`, **exit ≠ 0**. Capture qui vérifie exit + subtype
   (jamais `|| true`) = fermée. Forme concrète demandée par §5.

### État laissé
- Config gateway **laissée en `backend: docker`** (état-cible : plus sûr que `local`,
  qui était la violation même que le spike ferme). **Mais egress encore ouvert** → le
  gate du journal tient : **durcir + tester l'allow-list avant tout run overnight non
  surveillé.** Backup config : `~/.hermes/config.yaml.bak.spike1b.*`.
- Dette architecture.md soldée en un passage (§4/§5/§6/§7, ci-dessous).

### Verdict rd-journal
- **Toujours fermé.** Le spike s'est résolu par application compétente (lecture du code
  du backend docker, montage read-only, épinglage) — aucune incertitude technologique
  irréductible. Le seul candidat R&D restant est le confinement egress d'un agent
  autonome (proxy allowlist + churn CDN + compat proxy de Claude Code) *si* le stress-test
  résiste à l'ingénierie courante. À rouvrir seulement à ce moment-là.

### Prochaine étape
- Stress-tester le proxy egress (gate overnight). Puis, egress prouvé : **spike #3**, le
  benchmark golden tests kaos — la première vraie tâche de code en conteneur gouverné.
