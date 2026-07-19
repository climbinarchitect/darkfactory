# SPIKE #1b — Bascule du backend terminal `local` → `docker`

> À coller dans Claude Code sur le VPS, au moment d'attaquer le spike. Écrit
> 2026-07-XX. Lire CLAUDE.md + doc/architecture.md §7 + doc/project-journal.md
> (entrées spike #1 et issue #300) avant de commencer.

## Contexte (pourquoi ce spike existe)

Le spike #1 a prouvé empiriquement que le backend `local` fait exécuter du code
à l'orchestrateur Hermes **directement sur l'hôte VPS** (pytest + venv lancés hors
conteneur). Ça viole la trust boundary §7. Ce spike ferme le trou : tout code
généré/exécuté doit vivre dans un conteneur Docker jetable, jamais sur l'hôte.

C'est le dernier spike d'infra avant de pouvoir faire tourner du vrai code kaos
en sécurité. Ne PAS faire le benchmark kaos avant que ce spike passe.

## Hypothèse à valider

Hermes, avec `terminal.backend: docker`, peut exécuter une session `claude -p`
dans un conteneur jetable qui : (a) authentifie Claude Code correctement,
(b) travaille sur le repo monté de la tâche, (c) ne peut sortir que vers l'egress
allowlist, (d) est détruit après la tâche, (e) n'a JAMAIS fait toucher l'hôte par
du code exécuté.

## Discipline de spike

- Timebox ~3h. Blocage > 45 min sur une étape = documenter et s'arrêter, ne pas
  contourner en profondeur.
- **Changer une variable à la fois.** La baseline (spike #1, backend local) marche
  déjà — tout échec ici est donc imputable à la bascule Docker, à condition de ne
  pas empiler les changements. Bascule le backend d'abord, valide, PUIS ajoute
  l'egress, PUIS le durcissement. Pas tout en bloc.
- Ouvrir doc/rd-journal.md UNIQUEMENT si un blocage résiste à la doc (candidat
  probable : l'auth dans le conteneur). Sinon, project-journal.md.

## Changements de config (registry/config — appliquer PROGRESSIVEMENT, pas en bloc)

Dans ~/.hermes/config.yaml, section `terminal:` :
1. `backend: local` → `docker`
2. `container_persistent: true` → `false`   (jetable, 1 par tâche)
3. `docker_mount_cwd_to_workspace: false` → `true`   (Claude Code voit le vrai repo)
4. `timeout` / `lifetime_seconds` : réévaluer SELON le comportement Docker observé
   (ne pas pré-régler à l'aveugle — mesurer d'abord).

Redémarrer le gateway après chaque changement significatif et re-tester.

## LE point délicat : l'auth Claude Code dans le conteneur

C'est le cœur du spike et son point d'échec le plus probable. Un conteneur neuf
n'a pas `/home/inverted/.claude` où vit l'auth OAuth de la sub.

Étapes de diagnostic (dans l'ordre) :
1. Identifier ce dont `claude` a besoin pour s'authentifier en headless : quel(s)
   fichier(s) sous `~/.claude`, quelles variables d'env (HOME, etc.).
2. Déterminer comment Hermes (backend docker) monte les volumes et passe l'env au
   conteneur — lire la config/le code du backend docker de Hermes, ne pas deviner.
3. Monter le répertoire d'auth **en lecture seule** dans le conteneur
   (cf. architecture §7 : creds read-only + egress allowlist = exfiltration sans
   destination).
4. Si le montage read-only ne suffit pas (ex. claude veut écrire un cache/refresh),
   documenter précisément ce qu'il tente d'écrire AVANT de choisir une alternative —
   ne pas ouvrir les permissions par réflexe.

Signature d'échec d'auth à reconnaître : `claude` qui hang (attend un login
interactif) ou retourne une erreur d'auth. À distinguer d'un échec de subprocess.

## Vigilances issu de omniscient#300 (leçon "completion inferred, not proven")

- **Jamais de `|| true` / `2>/dev/null` masquant sur la capture du résultat.** Le
  code qui récupère la sortie de `claude -p` doit vérifier exit code + `subtype`
  du JSON, fail-closed. Un stdout vide / exit≠0 / JSON malformé = échec explicite,
  jamais un succès silencieux.
- **`0` et `unmeasured` sont des états distincts** dans toute trace produite.
- **Monter le workdir de la tâche, JAMAIS un volume d'état partagé** (son bug
  secondaire : tests en conteneur polluant le runs.jsonl de prod via volume monté).
  Le conteneur jetable ne doit avoir accès qu'au repo de sa tâche.

## Egress allowlist (après que la bascille de base marche)

Restreindre l'egress du conteneur de tâche à : api.anthropic.com, github.com,
pypi.org, files.pythonhosted.org (cf. registry executor.egress_allowlist).
Vérifier concrètement : depuis le conteneur, un accès à un domaine hors-liste doit
échouer, un accès à api.anthropic.com doit passer.

## Critère de PASS (tous requis)

Rejouer la tâche calc.py du spike #1, mais 100% en conteneur :
- [ ] `claude -p` s'authentifie et s'exécute DANS le conteneur (pas sur l'hôte)
- [ ] calc.py + test_calc.py créés dans le repo monté ; pytest passe DANS le conteneur
- [ ] Hermes récupère le résultat structuré (JSON, subtype: success)
- [ ] le conteneur est détruit après la tâche (jetable confirmé)
- [ ] egress hors-allowlist bloqué, egress allowlist OK
- [ ] vérification post-run : AUCUN artefact de la tâche sur l'hôte hors du repo
      monté (pas de venv/pytest sur l'hôte comme au spike #1)
- [ ] la capture de résultat est fail-closed (tester : un `claude` qui échoue doit
      produire un échec explicite, pas un succès silencieux)

## Livrables

- doc/spike-1b-findings.md (EN) : le mécanisme de montage d'auth retenu (commande/
  config exacte reproductible), la config docker finale, les frictions, et la
  recommandation pour le task-runner. Noter ce que ça résout des [SPIKE #1] markers
  de architecture.md.
- Mise à jour project-journal.md : PASS/FAIL/PARTIAL + découvertes.
- Une fois PASS : c'est le moment de solder la dette de doc architecture.md
  (§4 resume, §5 budget par-tâche, §7 conteneurisation vérif + trust boundary
  durcie) — en UN passage, maintenant qu'on sait comment le conteneur se comporte.

## Interdits

- Ne PAS utiliser `--dangerously-skip-permissions` ni `--bare` (cf. spike #1
  findings : auto-approbation totale / force API key hors sub).
- Ne PAS monter le socket Docker dans un conteneur de tâche.
- Ne PAS faire tourner de vrai code kaos tant que ce spike n'est pas PASS.
- Ne PAS pré-régler les timeouts à l'aveugle : mesurer le comportement Docker
  d'abord.
- Incertitude sur un choix structurant → demander, ne pas décider seul.