# task-runner.Dockerfile — image du conteneur de tache jetable de darkfactory.
#
# Role : fournir a Hermes (terminal.backend: docker) un conteneur ou `claude -p`
# tourne DANS le sandbox, jamais sur l'hote (cf. architecture.md §7, spike #1b).
# L'image ne contient PAS de secret : l'auth OAuth de la sub Claude est montee
# read-only au run (docker_volumes), jamais copiee dans l'image.
#
# Reconstructibilite (lecon issue #300 d'Alyan — une dep mal epinglee echoue en
# silence) : TOUT est epingle dur.
#   - Base epinglee par DIGEST sha256, pas par tag flottant (python3.11-nodejs20
#     est reconstruit en amont ; le digest, non).
#   - claude-code epingle sur une version npm exacte = celle known-good de l'hote
#     (2.1.207, celle qui a fait PASS le spike #1).
# Bump de version = changement explicite et versionne de ce fichier, jamais une
# derive silencieuse sous nos pieds.
#
# Build : voir setup.sh (l'image ne doit pas exister seulement en local sur le
# VPS — le Dockerfile vit dans le repo, le build est scripte).

# Base : nikolaik/python-nodejs:python3.11-nodejs20 (git 2.47 / python 3.11 /
# node 20 / npm — deja tout le socle dev). Epinglee par digest resolu le
# 2026-07-19.
FROM nikolaik/python-nodejs@sha256:8f958bdc1b4a422bfafd97cab4f69836401f616ae985d4b57a53d254f5bcb038

# claude-code epingle sur la version exacte known-good de l'hote.
ARG CLAUDE_CODE_VERSION=2.1.207
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    # Echec bruyant : si la version installee ne matche pas la version demandee,
    # on casse le build plutot que de livrer une image qui a glisse.
    && installed="$(claude --version | awk '{print $1}')" \
    && [ "$installed" = "${CLAUDE_CODE_VERSION}" ] \
        || { echo "FATAL: claude-code ${installed} != ${CLAUDE_CODE_VERSION} attendu"; exit 1; }

# HOME=/root existe deja dans la base. En mode conteneur jetable (Hermes
# container_persistent: false), /root est un tmpfs writable : claude y ecrit son
# cache/refresh/sessions, tout disparait a la destruction du conteneur. Seul
# /root/.claude/.credentials.json est monte read-only par-dessus au run.
