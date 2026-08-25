# Stack IA — installation

Prérequis :
1. **Invitation GitHub acceptée** (mail / https://github.com/sofalost/stack-hugo/invitations).
2. **Docker Desktop** installé sur Windows, avec Settings → Resources → WSL Integration → « Integrate with my default WSL distro » activé.

## Installation (une seule fois)

Ouvre le terminal WSL Ubuntu, puis :

```bash
mkdir -p ~/stack && cd ~/stack
nano install-stack.sh    # colle le contenu d'install-stack.txt, puis Ctrl+O Entrée Ctrl+X
chmod +x install-stack.sh
./install-stack.sh
```

Ou, si tu as déjà la CLI GitHub (`gh auth login` fait) :

```bash
gh repo clone sofalost/stack-hugo ~/stack
cd ~/stack && ./install-stack.sh
```

Pendant l'exécution, le script demande :
- le **mot de passe sudo** une seule fois (ensuite plus jamais) ;
- une **connexion GitHub** dans le navigateur (pour cloner les skills — repo privé) ;
- la **clé API 9router** à la fin : crée-la sur la page http://127.0.0.1:20128 (Dashboard → Keys) et colle-la.

## Après

```bash
exec bash      # recharge le shell
sofalost       # update complet + menu de lancement (1-6)
```
