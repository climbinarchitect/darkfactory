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
