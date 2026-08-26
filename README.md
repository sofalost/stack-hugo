# Stack IA — installation

Une seule commande, dans le terminal WSL Ubuntu (clean install OK) :

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sofalost/stack-hugo/master/install-stack.sh)
```

Prérequis :
1. **Docker Desktop** installé sur Windows, avec Settings → Resources → WSL Integration → « Integrate with my default WSL distro » activé.
2. `curl` ou `git` absent ? Pas grave — le script les installe (mot de passe sudo demandé).

Pendant l'exécution, le script demande :
- le **mot de passe sudo** une seule fois (ensuite plus jamais) ;
- la **clé API 9router** à la fin : crée-la sur la page http://127.0.0.1:20128 (Dashboard → Keys) et colle-la.

## Après

```bash
exec bash      # recharge le shell
sofalost       # update complet + menu de lancement (1-6)
```
