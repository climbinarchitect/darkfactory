#!/usr/bin/env bash
# setup.sh — provisioning de base du VPS darkfactory (Hetzner CX33, Ubuntu 26.04).
#
# Portée : socle reproductible SEULEMENT (Docker, Node LTS, git, user non-root,
# Claude Code CLI). L'install de Hermes elle-même appartient au spike #1 (prérequis
# inconnus à découvrir), pas au provisioning.
#
# Idempotent autant que possible : re-rouler ne casse rien.
# À lancer en root sur le VPS :  bash setup.sh
# Tailscale + lockdown firewall sont supposés DÉJÀ faits (étape manuelle validée).

set -euo pipefail

NONROOT_USER="inverted"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\n\033[1;36m[setup]\033[0m $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "À lancer en root." >&2
  exit 1
fi

# --- 1. Base système -------------------------------------------------------
log "Mise à jour du système + paquets de base"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y \
  ca-certificates curl gnupg git ufw ripgrep jq unzip \
  build-essential python3 python3-pip python3-venv

# --- 2. User non-root ------------------------------------------------------
if id "$NONROOT_USER" &>/dev/null; then
  log "User $NONROOT_USER existe déjà"
else
  log "Création du user non-root : $NONROOT_USER"
  adduser --disabled-password --gecos "" "$NONROOT_USER"
fi
usermod -aG sudo "$NONROOT_USER"
# Propager l'accès SSH par clé (et Tailscale SSH couvre déjà l'accès identité-tailnet)
if [[ -f /root/.ssh/authorized_keys ]]; then
  install -d -m 700 -o "$NONROOT_USER" -g "$NONROOT_USER" "/home/$NONROOT_USER/.ssh"
  install -m 600 -o "$NONROOT_USER" -g "$NONROOT_USER" \
    /root/.ssh/authorized_keys "/home/$NONROOT_USER/.ssh/authorized_keys"
fi

# --- 3. Docker (dépôt officiel) --------------------------------------------
if command -v docker &>/dev/null; then
  log "Docker déjà installé : $(docker --version)"
else
  log "Installation de Docker (script officiel)"
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
fi
# Le user non-root pilote Docker (Hermes lancera les conteneurs de tâches).
# Note sécurité : appartenir au groupe docker ≈ root sur l'hôte. Acceptable ici
# car c'est le user qui EST l'opérateur de la factory ; à ne jamais accorder à
# du code exécuté dans un conteneur de tâche.
usermod -aG docker "$NONROOT_USER"
systemctl enable --now docker

# --- 4. Node LTS (NodeSource) ----------------------------------------------
if command -v node &>/dev/null; then
  log "Node déjà présent : $(node --version)"
else
  log "Installation de Node LTS via NodeSource"
  curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource_setup.sh
  bash /tmp/nodesource_setup.sh
  apt-get install -y nodejs
fi
log "Node : $(node --version) / npm : $(npm --version)"

# --- 5. Claude Code CLI -----------------------------------------------------
# Installé au niveau système ; l'AUTH se fait ensuite en tant que $NONROOT_USER
# (login OAuth interactif, hors script — voir note finale).
if command -v claude &>/dev/null; then
  log "Claude Code déjà installé : $(claude --version 2>/dev/null || echo '?')"
else
  log "Installation de Claude Code CLI"
  npm install -g @anthropic-ai/claude-code
fi

# --- 5b. Image du conteneur de tache jetable (task-runner) -----------------
# L'exécuteur (claude -p) tourne DANS ce conteneur, jamais sur l'hôte
# (architecture.md §7, spike #1b). L'image est épinglée dur (base par digest +
# claude-code par version exacte) dans docker/task-runner.Dockerfile — voir ce
# fichier pour le pourquoi (leçon issue #300). Build ici pour que l'image ne vive
# pas seulement en local : Dockerfile versionné + build scripté = reconstructible.
# Idempotent : le cache de build rend un re-run quasi gratuit.
log "Build de l'image task-runner (conteneur de tâche jetable)"
docker build \
  -f "$SCRIPT_DIR/docker/task-runner.Dockerfile" \
  -t darkfactory-task-runner:claude-2.1.207 \
  "$SCRIPT_DIR"

# --- 6. Arbo de travail ----------------------------------------------------
log "Création de l'arbo de travail sous /home/$NONROOT_USER"
install -d -o "$NONROOT_USER" -g "$NONROOT_USER" "/home/$NONROOT_USER/darkfactory"

log "Provisioning de base terminé."
cat <<EOF

────────────────────────────────────────────────────────────
Étapes manuelles restantes (hors script, volontairement) :

  1. Passer sur le user non-root :   su - $NONROOT_USER
  2. Authentifier Claude Code :      claude
       → suivre l'URL OAuth, la coller dans le navigateur Windows,
         récupérer le code. Vérifier ensuite en headless :
         claude -p "réponds juste: pong" --output-format json
  3. SPIKE #1 : installer Hermes (prérequis à découvrir) et valider
     qu'il pilote 'claude -p' en subprocess. Prompt déjà rédigé.
────────────────────────────────────────────────────────────
EOF
