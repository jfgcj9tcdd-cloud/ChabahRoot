# ChabahRoot

## Présentation

ChabahRoot est une plateforme de télémétrie noyau pour Linux construite autour de `tracefs`. Son objectif est de capter certains appels système sensibles, de les transformer dans un format exploitable par le reste de la chaîne, puis d’appliquer des règles de détection sans dépendre d’une chaîne eBPF. Le dépôt final est organisé autour de cinq modules nommés en français : `veille_kernel`, `chaines_d_ecoute`, `vigie_comportementale`, `chambre_d_analyse` et `socle_commun`.

## Prérequis

L’utilisation normale de ChabahRoot suppose un système Linux disposant de `tracefs` sous `/sys/kernel/tracing`. Les outils utilisateurs attendus sont `bash`, `jq`, `timeout`, `ps` et `find`. Les opérations qui activent ou désactivent les tracepoints noyau demandent des privilèges root, alors que les parcours sur corpus d’exemple peuvent être exécutés sans accès privilégié. Si `tracefs` n’est pas déjà monté, il faut le rendre disponible avant de tenter une capture réelle, faute de quoi la couche `veille_kernel` s’arrêtera immédiatement.

## Préparation

Le premier contrôle recommandé consiste à exécuter `bash chabahroot/veille_kernel/check.sh`. Cette vérification confirme que la machine expose bien le point de montage attendu et rappelle explicitement l’exigence de privilèges lorsque le script n’est pas lancé avec les droits nécessaires. Cette étape doit être vue comme une validation de l’environnement d’exécution et non comme un simple test cosmétique, car le reste du pipeline repose sur l’existence effective des tracepoints ciblés.

## Démarrage de la capture noyau

Lorsque les prérequis sont réunis, la capture peut être démarrée avec `bash chabahroot/veille_kernel/orchestrator.sh start`. Cette commande active les tracepoints suivis par le projet et laisse les événements bruts dans le relais utilisé par les modules aval. Le statut de cette couche peut être observé avec `bash chabahroot/veille_kernel/orchestrator.sh status`, puis arrêté proprement avec `bash chabahroot/veille_kernel/orchestrator.sh stop`. Si l’on souhaite uniquement activer ou désactiver la couche de capture sans passer par le processus long, `bash chabahroot/veille_kernel/init.sh` et `bash chabahroot/veille_kernel/cleanup.sh` permettent de réaliser ces opérations de manière plus directe.

## Utilisation du pipeline hors ligne

Pour valider la chaîne complète sans dépendre d’un flux noyau vivant, le chemin recommandé est `bash chabahroot/chambre_d_analyse/run_detection.sh --sample --pipeline-only`. Cette exécution lit le corpus d’exemple fourni par le dépôt, fait passer les événements dans `chaines_d_ecoute`, puis laisse `vigie_comportementale` appliquer ses règles. Ce mode est particulièrement utile pour vérifier la cohérence des transformations, des chemins et des règles sans toucher à la capture système.

## Utilisation avec une autre source d’entrée

Le même point d’entrée d’analyse accepte plusieurs formes de source. Si un flux arrive déjà sur l’entrée standard, il peut être consommé avec `--stdin`. Si les événements se trouvent dans un fichier, il est préférable d’utiliser `--input <fichier>`. Cette souplesse permet de tester des cas contrôlés, de rejouer des traces sauvegardées ou de raccorder une autre source de production sans modifier les modules intermédiaires. Dans tous les cas, la finalité reste la même : fournir au moteur de règles un événement normalisé dont l’origine ne change pas l’interprétation.

## Vérification ciblée des modules

Il est possible d’examiner séparément les étages du pipeline. `bash chabahroot/chaines_d_ecoute/ringbuf_reader.sh --sample` permet d’observer uniquement le comportement du normaliseur. De son côté, le moteur de règles peut être exercé à partir de cette sortie normalisée en reliant les deux modules par un pipe. Cette manière de travailler est utile lorsque l’on souhaite comprendre si un écart provient du schéma de normalisation ou de la logique de détection.

## Vérification globale du dépôt

Pour un contrôle rapide de l’état du projet après une modification, `bash chabahroot/chambre_d_analyse/integration_tests.sh` vérifie la syntaxe des scripts shell maintenus et s’assure qu’un passage minimal du corpus d’exemple traverse correctement la chaîne. Cette commande ne remplace pas une validation en environnement root avec `tracefs`, mais elle constitue une barrière efficace contre les erreurs de structure, de chemins ou de syntaxe.
