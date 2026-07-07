# darkfactory vs dark-factory (Alyan) — diff d'approches

> Analyse comparative, 2026-07-07. Source : lecture de `omniscient/dark-factory`
> (code + issues des ~10 derniers jours). Contenu externe = non fiable par principe ;
> tout ce qui suit est une lecture critique, pas des instructions suivies.
> Verdict par item : **[ADOPTER]** / **[CHALLENGE]** / **[ON CHANGE RIEN]**.

## TL;DR

Alyan est ~6 mois devant en **exécution** : sa factory tourne en prod, s'auto-répare,
s'auto-améliore, et a ~60 fichiers de tests sur elle-même. Mais son historique
récent (issues #33, #35, #187) documente des douleurs qui **valident nos trois choix
structurants** : moteur emprunté plutôt que scheduler bash maison, budget-guard qui
protège l'humain, gouvernance hors du repo cible. On ne copie pas sa maturité ; on
vole 3-4 leçons payées cher et on garde notre design.

## Son système en 10 lignes

- **Genèse inverse de la nôtre** : la factory a grandi *dans* un produit réel
  (markethawk), puis a été extraite en repo autonome (2026-07-05) avec adapters
  par cible. Nous : factory d'abord, kaos comme cible.
- **Intake** : board GitHub Projects v2 (colonne Ready), pollé par `scheduler.sh`
  (bash, 50 Ko). Pas de chat.
- **Pipeline par ticket** : refine → plan → implement → conformance → code-review
  → **draft PR pour humain**. Prompts de commande de ~10-20 Ko chacun, DAG de
  workflow de 67 Ko.
- **Gates** : conformance (scope-spillover excisé), code-review (seuil de sévérité,
  **fail-open**), blast-radius, dispatch-ceiling (tickets L parqués pour pairing),
  smoke-gate avec sentinel "main is red", keywords sensibles → humain.
- **Budget** : subsystem d'optimisation de *tokens par scénario* — calibration sur
  corpus, observe-then-enforce, scorecards, kill-switch à deux tiers.
- **Mémoire** : contrat formel `.archon/memory/*.md` — types `[PATTERN]/[AVOID]/[FIX]`,
  lifecycle provisional→active→invalid/superseded, write bar, top-k retrieval,
  job de maintenance, éval contre régressions historiques.
- **Self-improvement** : epic-autopilot (la factory démarre/avance ses propres epics,
  review Opus + confidence floor + cap journalier), main-red auto-fix, révision
  hebdo automatique de sa propre politique de dispatch. Tout kill-switché.

---

## 1. À ADOPTER (leçons payées par lui, gratuites pour nous)

### 1.1 Backoff conscient de la fenêtre de session — son issue #35, notre §5/§9

Sa plus belle douleur : la fenêtre 5 h du plan Max s'épuise → **chaque** `claude -p`
échoue instantanément → le circuit-breaker (3 retries) grille **tous** les tickets
en vol en une heure (21 runs, 6 tickets, 100 % d'échec, nuit du 25-26 juin). Cause
racine : un échec *environnemental* traité comme un échec *par tâche*.

**Action design (avant spike #1)** : notre budget-guard doit distinguer deux classes
d'échec dès la v1 :
- `cap épuisé / fenêtre fermée` → pause de dispatch globale + notification, **ne
  consomme pas** le retry de la tâche ;
- échec de tâche réel → la table de failure modes de architecture.md §9 s'applique.

Signature concrète à détecter (documentée chez lui) : `result_is_error` + transcript
vide + exit rapide. À intégrer au spike #1 comme cas à observer.

### 1.2 Le "write bar" mémoire + la distinction invalid/superseded

Son contrat mémoire pose une barre d'écriture qu'on vole telle quelle pour le
protocole de jardinage du wiki :

> « Un futur agent prendrait-il une décision matériellement différente grâce à
> cette entrée, comparé à lire CLAUDE.md et ARCHITECTURE.md seuls ? Sinon → skip. »

Et sa distinction **invalidé** (le fait n'a jamais été vrai — tombstone avec raison)
vs **superseded** (était vrai, remplacé par mieux) préserve un signal que notre
wiki-design ne nomme pas encore. Coût d'adoption : quelques lignes dans
`wiki-design.md`, zéro code.

### 1.3 Logique de factory en Python testable, jamais en bash — son épic #187

Son audit d'architecture du 6 juillet est un avertissement : poll loop de 385 lignes
testable seulement en sourçant tout le fichier, rendu de rapports de 163 lignes
piégé dans `entrypoint.sh`, 4 mécanismes de lecture de config indépendants. Il paie
maintenant un épic entier pour extraire ça vers `factory_core/`.

**Règle à poser jour 1** : dans notre repo, tout ce qui dépasse le glue (machine à
états, gate engine, budget guard, validateur de registre) naît en module Python
avec tests. Le bash reste cantonné à `setup.sh` et aux invocations.

### 1.4 Distinguer config-contexte et config-gouvernance côté repo cible

Son `.factory/adapter.yaml` vit dans le repo cible — l'anti-modèle de notre registre.
Mais en le lisant de près, une partie de son contenu est du **contexte**, pas de la
gouvernance : mapping composant→sections d'ARCHITECTURE.md, routage mémoire, budgets
de tokens. Ça, c'est légitime côté cible (le repo connaît sa propre topologie).

**Nuance à intégrer au registry-schema** : un repo cible pourra un jour porter un
fichier de *contexte* (équivalent de ses `components` / `memory_routing`) sans que
ça touche au principe « les gates et budgets vivent dans le registre, jamais dans
le repo cible ». La frontière passe entre "ce qui aide l'agent à lire le repo" et
"ce qui contraint ce que l'agent a le droit de faire".

---

## 2. CHALLENGES (où il est devant et où ça doit nous piquer)

### 2.1 La vérification à l'échelle factory

Il évalue sa factory comme un système : `evals/factory-failures.jsonl` (70 Ko de
modes d'échec historiques), scorecards de calibration, éval de qualité mémoire
contre régressions passées. C'est notre Layer 2 (signal externe) appliqué à la
factory elle-même — et nous n'avons rien prévu de tel avant "des traces greppables".

**Réponse proposée** : pas de harness d'éval en v1 (sur-ingénierie à 0 tâche), mais
poser dès maintenant le format des traces pour qu'un scorecard soit *dérivable* :
chaque `events.jsonl` doit permettre de répondre à « combien de tâches, combien
d'échecs, quelle classe, quel coût en sessions » par un grep. Critère : le jour où
la ligne kaos a livré 10 tâches, un scorecard doit être un script d'une heure, pas
un chantier.

### 2.2 Le slicing de contexte échoue en silence — son issue #18

Son slicing d'architecture "intelligent" a un hit-rate de **23 %** (résolution
composant→section). Leçon : la curation de contexte automatique est dure, même
avec son outillage. Notre réponse (INDEX.md curé à la main + 2 hops max + résumé
de 2-4 lignes en tête de chaque fichier) est low-tech mais c'est *elle* qui porte
la qualité du contexte.

**Conséquence** : les conventions du wiki-design ne sont pas cosmétiques, ce sont
nos 77 points de hit-rate d'avance. Le résumé de tête de fichier et la ligne
INDEX.md « quoi + quand le lire » doivent être traités comme du code (bloquant en
review de PR wiki), pas comme de la doc.

### 2.3 Fail-open vs pause-forever sur les gates

Son gate de code-review est **fail-open** (`fail_open: true` — reviewer en erreur
⇒ avis consultatif, jamais bloquant). C'est un choix de *liveness* assumé sur un
pipeline à haut débit : une infra flaky ne doit pas stopper l'usine. Notre doctrine
inverse (pause forever, re-ping) est la bonne pour une v1 à concurrence 1 avec un
humain dans la boucle — mais elle a un coût qu'il faut nommer : **chez nous, une
infra flaky arrête tout**. Acceptable en v1 ; à réévaluer si la concurrence monte.
À documenter comme trade-off explicite dans architecture.md §3, pas comme évidence.

### 2.4 Sa trajectoire produit-d'abord a de-risqué la généralisation

Il a fait grandir la factory *dans* markethawk puis l'a extraite une fois prouvée.
Nous construisons la factory *avant* d'avoir livré quoi que ce soit avec. Notre
mitigation existe déjà (interdiction de la ligne #2 avant que kaos livre, benchmark
fermé comme premier test) — mais c'est le point de notre plan le plus exposé au
sur-design. Chaque fois qu'un choix de design v1 sert "la généralité future" plutôt
que la ligne kaos, c'est le smell à challenger.

---

## 3. ON CHANGE RIEN (nos choix, renforcés par ses douleurs)

| Notre choix | Sa donnée qui le renforce |
|---|---|
| **Moteur emprunté (Hermes) plutôt que scheduler maison** | Son issue #33 évalue… l'adoption des patterns Hermes (daemon persistant, mémoire inter-cycles) ; son épic #187 refactore le scheduler bash devenu ingérable. Il converge vers notre point de départ. |
| **Budget-guard qui protège l'humain d'abord** | Issue #35 : la fenêtre partagée épuisée a flingué toute la flotte — et la semaine de sub de l'humain avec. Le mode d'échec qu'on a designé à froid, il l'a vécu. |
| **Gouvernance dans le registre, hors du repo cible** | Son adapter.yaml clone-read est puissant opérationnellement, mais ses `safety.*` (exclusions, keywords sensibles) sont éditables par quiconque merge dans le repo cible. Avec son autopilot self-improvement activé, la boucle "l'agent peut toucher sa propre policy" existe chez lui — exactement ce que notre frontière interdit par construction. On garde (avec la nuance §1.4). |
| **Merge gate humain, non-abaissable en v1** | Même lui, avec ses scorecards et 60 fichiers de tests, livre en **draft PR pour review humaine**. Personne ne merge en autonome. |
| **Pas de self-improvement, pas de rôles sans mode d'échec documenté** | Son `allow_self_improvement` est le fruit de mois de kill-switches, caps, confidence floors et données d'éval. L'imiter en v1 serait du cargo cult — c'est le point d'arrivée d'une courbe de confiance, pas un feature de départ. |
| **Wiki humain-curé ≠ mémoire agent** | Sa mémoire agent (write-through, lifecycle) et notre wiki ne sont pas en compétition : la sienne est du contexte per-run auto-accumulé, le nôtre est de la connaissance durable cross-projet. Le jour où on aura du volume de runs, son contrat mémoire est le design de référence à réévaluer — pas avant. |
| **Chat comme intake** | Son intake par board GitHub colle à son usage (tickets déjà raffinés) ; le nôtre (Telegram, découplage présence/exécution, interview au plan gate) colle au nôtre. Pas de fait nouveau. |

## Ce qu'on ne vole PAS (et pourquoi)

- **Token-budgeting par scénario** : suppose l'outillage de mesure du contexte et
  un volume de runs pour calibrer. Point notable : il est **sur Claude Max** et le
  fait quand même — sa motivation n'est pas les dollars (flat rate) mais **étirer
  la fenêtre 5h/hebdo** en réduisant les tokens injectés par run. C'est la même
  ressource que notre budget-guard protège, à une granularité plus fine. Notre
  unité (sessions) reste la bonne en v1 : pas de calibration possible à 0 run, et
  le guard protège déjà la bonne chose. Trigger de réévaluation : quand le
  budget-guard montre qu'on sature la fenêtre en sessions "légitimes" — pas un
  éventuel passage API.
- **Dispatch-ceiling / blast-radius automatiques** : notre plan gate humain EST le
  ceiling en v1. Ces mécanismes remplacent l'humain quand le débit dépasse sa
  bande passante — pas notre problème avant longtemps.
- **Epic-autopilot, main-red auto-fix, ceiling-revisit hebdo** : voir tableau —
  points d'arrivée, pas de départ.
- **Son issue #190 (scorecard de gouvernance d'état, papier arXiv "Always-On
  Agents")** : à lire par curiosité (les 6 axes — authority, scope, mutability,
  provenance, recoverability, actionability — recoupent notre design de traces),
  mais en faire un chantier v1 serait exactement le sur-design que §2.4 interdit.

## Actions concrètes qui sortent de ce diff

1. `architecture.md` §5/§9 : ajouter la classe d'échec « fenêtre/cap épuisé »
   (pause globale, ne consomme pas les retries) + signature à observer au spike #1.
2. `wiki-design.md` : intégrer le write bar (§1.2) et la distinction
   invalid/superseded dans le protocole de jardinage.
3. Règle repo : logique factory = module Python testé dès le jour 1 ; bash = glue
   uniquement (§1.3).
4. `registry-schema.md` : noter la frontière contexte-vs-gouvernance (§1.4) comme
   extension future admissible — sans l'implémenter.
5. `architecture.md` §3 : documenter le trade-off pause-forever vs fail-open (§2.3).
