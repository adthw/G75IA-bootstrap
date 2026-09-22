# Politique de sécurité

`00-diagnostic.sh` peut être exécuté avec `sudo` afin de lire certaines informations matérielles. Un script lancé avec ces privilèges doit être considéré comme du code de confiance.

## Utilisation sûre

- Cloner ou télécharger uniquement le dépôt officiel.
- Lire les modifications avant toute mise à jour.
- Ne jamais exécuter avec `sudo` le contenu d’une branche, d’un fork ou d’une pull request non vérifiée.
- Ne pas utiliser une commande du type `curl ... | sudo bash`.
- Lancer le diagnostic depuis une session Linux Live de confiance lorsque c’est possible.
- Relire tout rapport avant de le communiquer à un tiers.
- Ne jamais ajouter `reports/`, un état de référence interne, une clé, un jeton ou un fichier `.env` au dépôt.

## Garanties de la version 0.2.0

Le script :

- n’installe aucun paquet ;
- ne monte, ne démonte, ne formate et ne repartitionne aucun volume ;
- n’écrit ni dans le firmware ni dans la configuration du système ;
- ne lance aucun test SMART, benchmark ou stress test destructif ;
- utilise un `PATH` système fixe lorsqu’il fonctionne avec `sudo` ;
- crée les rapports dans un dossier privé et imprévisible avec `umask 077` et `mktemp` ;
- minimise les champs collectés et anonymise obligatoirement les sorties ;
- n’envoie aucun rapport sur le réseau.

Sans l’option `--no-network`, les seules communications initiées par le script sont des requêtes ICMP vers `1.1.1.1` et `debian.org` afin de vérifier la connectivité IP et DNS. Utiliser `--no-network` pour un diagnostic entièrement hors ligne.

## Limites

L’anonymisation automatique réduit le risque de fuite mais ne peut pas garantir qu’un pilote, un message noyau ou un nouvel outil ne produira jamais un identifiant imprévu. Les rapports doivent donc rester locaux par défaut et être relus avant partage.

Le projet ne garantit pas l’absence de défaut sur toutes les distributions et tous les matériels. La compatibilité déclarée signifie que les commandes sont conçues en lecture seule et que l’absence d’un outil doit produire un état `UNKNOWN`, pas une action corrective.

## Signaler un problème

Un problème non sensible peut être signalé dans une issue GitHub. Ne publiez jamais de secret, de rapport brut non vérifié ni de détail permettant l’accès à une machine. Pour une vulnérabilité contenant des informations sensibles, utilisez un canal privé proposé par GitHub pour le dépôt, s’il est disponible, plutôt qu’une issue publique.
