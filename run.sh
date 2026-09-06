#!/usr/bin/env bash

set -euo pipefail

# ==========================================
# CYFRIN SMART CONTRACT LAB CLI
# ==========================================

RPC_URL="http://127.0.0.1:8545"
CHAIN_ID="31337"

# Compte Anvil #0 — UNIQUEMENT pour le réseau local
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

SCRIPT="script/Counter.s.sol:CounterScript"

CONTRACT_ADDRESS=""

# ------------------------------------------
# Couleurs
# ------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------------------------------
# Helpers
# ------------------------------------------

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ------------------------------------------
# Vérifier Anvil
# ------------------------------------------

check_anvil() {
    if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
        success "Anvil est disponible sur $RPC_URL"
    else
        warning "Anvil n'est pas lancé."
        info "Démarrage d'Anvil..."

        anvil >/tmp/cyfrin-anvil.log 2>&1 &
        ANVIL_PID=$!

        sleep 2

        if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
            success "Anvil démarré — Chain ID $CHAIN_ID"
        else
            error "Impossible de démarrer Anvil."
            exit 1
        fi

        trap 'kill "$ANVIL_PID" 2>/dev/null || true' EXIT
    fi
}

# ------------------------------------------
# Build
# ------------------------------------------

build() {
    info "Compilation du projet..."

    forge build

    success "Compilation réussie."
}

# ------------------------------------------
# Tests
# ------------------------------------------

test_contract() {
    info "Exécution des tests..."

    forge test

    success "Tous les tests sont passés."
}

# ------------------------------------------
# Déploiement
# ------------------------------------------

deploy() {
    info "Déploiement de Counter..."

    forge script "$SCRIPT" \
        --rpc-url "$RPC_URL" \
        --broadcast \
        --private-key "$PRIVATE_KEY"

    CONTRACT_ADDRESS=$(jq -r '
        .transactions[]
        | select(.transactionType == "CREATE")
        | .contractAddress
    ' broadcast/Counter.s.sol/31337/run-latest.json | tail -1)

    if [[ -z "$CONTRACT_ADDRESS" || "$CONTRACT_ADDRESS" == "null" ]]; then
        error "Impossible de récupérer l'adresse du contrat."
        exit 1
    fi

    echo
    success "Counter déployé."
    echo
    echo "Contract:"
    echo "$CONTRACT_ADDRESS"
}

# ------------------------------------------
# Adresse
# ------------------------------------------

address() {
    if [[ ! -f broadcast/Counter.s.sol/31337/run-latest.json ]]; then
        error "Aucun déploiement trouvé."
        exit 1
    fi

    CONTRACT_ADDRESS=$(jq -r '
        .transactions[]
        | select(.transactionType == "CREATE")
        | .contractAddress
    ' broadcast/Counter.s.sol/31337/run-latest.json | tail -1)

    echo "$CONTRACT_ADDRESS"
}

# ------------------------------------------
# Lecture
# ------------------------------------------

read_number() {
    CONTRACT_ADDRESS=$(address)

    info "Lecture de Counter.number()..."

    VALUE=$(cast call "$CONTRACT_ADDRESS" \
        "number()" \
        --rpc-url "$RPC_URL")

    echo
    echo "Contract : $CONTRACT_ADDRESS"
    echo "number() : $VALUE"
}

# ------------------------------------------
# Modifier
# ------------------------------------------

set_number() {
    VALUE="${1:-}"

    if [[ -z "$VALUE" ]]; then
        error "Utilisation : ./counter.sh set <valeur>"
        exit 1
    fi

    CONTRACT_ADDRESS=$(address)

    info "setNumber($VALUE)..."

    cast send "$CONTRACT_ADDRESS" \
        "setNumber(uint256)" "$VALUE" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY"

    success "Valeur modifiée."
}

# ------------------------------------------
# Increment
# ------------------------------------------

increment() {
    CONTRACT_ADDRESS=$(address)

    info "Exécution de increment()..."

    cast send "$CONTRACT_ADDRESS" \
        "increment()" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY"

    success "Counter incrémenté."
}

# ------------------------------------------
# Code du contrat
# ------------------------------------------

code() {
    CONTRACT_ADDRESS=$(address)

    info "Vérification du bytecode..."

    BYTECODE=$(cast code "$CONTRACT_ADDRESS" \
        --rpc-url "$RPC_URL")

    if [[ "$BYTECODE" == "0x" ]]; then
        error "Aucun bytecode trouvé."
        exit 1
    fi

    success "Bytecode présent."
    echo
    echo "$BYTECODE"
}

# ------------------------------------------
# Status
# ------------------------------------------

status() {
    echo
    echo "=========================================="
    echo "       CYFRIN SMART CONTRACT LAB"
    echo "=========================================="
    echo

    if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
        success "Anvil : ONLINE"

        CHAIN=$(cast chain-id --rpc-url "$RPC_URL")
        echo "Chain ID : $CHAIN"
    else
        error "Anvil : OFFLINE"
        return
    fi

    if [[ -f broadcast/Counter.s.sol/31337/run-latest.json ]]; then

        CONTRACT_ADDRESS=$(address)

        echo
        echo "Contract : $CONTRACT_ADDRESS"

        VALUE=$(cast call "$CONTRACT_ADDRESS" \
            "number()" \
            --rpc-url "$RPC_URL")

        echo "number() : $VALUE"

        CODE=$(cast code "$CONTRACT_ADDRESS" \
            --rpc-url "$RPC_URL")

        if [[ "$CODE" != "0x" ]]; then
            success "Bytecode : PRESENT"
        else
            error "Bytecode : EMPTY"
        fi

    else
        warning "Counter : NON DEPLOYE"
    fi

    echo
}

# ------------------------------------------
# Reset
# ------------------------------------------

reset() {
    warning "Le reset nécessite de redémarrer Anvil."

    if [[ -n "${ANVIL_PID:-}" ]]; then
        kill "$ANVIL_PID" 2>/dev/null || true
    fi

    pkill -f "anvil" 2>/dev/null || true

    rm -rf broadcast/Counter.s.sol/31337
    rm -rf cache/Counter.s.sol/31337

    success "Environnement réinitialisé."
}

# ------------------------------------------
# Tout exécuter
# ------------------------------------------

all() {
    echo
    echo "=========================================="
    echo "       CYFRIN LAB — FULL WORKFLOW"
    echo "=========================================="
    echo

    check_anvil

    echo
    build

    echo
    test_contract

    echo
    deploy

    echo
    read_number

    echo
    set_number 42

    echo
    read_number

    echo
    echo "=========================================="
    success "WORKFLOW TERMINÉ"
    echo "=========================================="
}

# ------------------------------------------
# Help
# ------------------------------------------

help() {
    echo
    echo "CYFRIN SMART CONTRACT LAB CLI"
    echo
    echo "Usage:"
    echo "  ./counter.sh <commande>"
    echo
    echo "Commandes:"
    echo
    echo "  start       Vérifier / démarrer Anvil"
    echo "  build       Compiler le projet"
    echo "  test        Exécuter les tests"
    echo "  deploy      Déployer Counter"
    echo "  address     Afficher l'adresse du contrat"
    echo "  read        Lire number()"
    echo "  set <n>     Définir number à n"
    echo "  increment   Exécuter increment()"
    echo "  code        Afficher le bytecode"
    echo "  status      Afficher l'état du laboratoire"
    echo "  reset       Réinitialiser l'environnement"
    echo "  all         Exécuter tout le workflow"
    echo
}

# ------------------------------------------
# Router
# ------------------------------------------

COMMAND="${1:-help}"

case "$COMMAND" in

    start)
        check_anvil
        ;;

    build)
        build
        ;;

    test)
        test_contract
        ;;

    deploy)
        check_anvil
        deploy
        ;;

    address)
        address
        ;;

    read)
        check_anvil
        read_number
        ;;

    set)
        check_anvil
        set_number "${2:-}"
        ;;

    increment)
        check_anvil
        increment
        ;;

    code)
        check_anvil
        code
        ;;

    status)
        status
        ;;

    reset)
        reset
        ;;

    all)
        all
        ;;

    help|-h|--help)
        help
        ;;

    *)
        error "Commande inconnue : $COMMAND"
        help
        exit 1
        ;;

esac
