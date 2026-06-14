# Lab 01 — Backend de state Terraform sécurisé (bootstrap)

> **Objectif :** créer toi-même, étape par étape, le socle qui stockera l'état (state) de toute ta plateforme : un bucket S3 chiffré, versionné, privé, avec verrouillage natif S3. C'est le tout premier acte d'infrastructure de ton projet, et il doit être irréprochable côté sécurité.

**Durée estimée :** 1 h 30 – 2 h (le but est d'apprendre, pas d'aller vite).
**Prérequis :** comptes AWS configurés (✅ déjà fait), AWS CLI authentifié (`aws sts get-caller-identity` doit répondre), Terraform **≥ 1.11** installé (`terraform version`).

---

## Comment utiliser ce document avec Claude Code

Ce TP est conçu pour que **tu écrives le code**, avec Claude Code en *coach* — pas en *solveur*. Ouvre Claude Code à la racine de ton repo et lance-lui une consigne du type :

> « Sois mon coach pour le fichier `docs/labs/lab-01-state-backend.md`. Guide-moi étape par étape. **N'écris pas le code à ma place.** À chaque étape : explique-moi ce qu'on cherche, laisse-moi écrire, puis relis ce que j'ai produit et dis-moi ce qui ne va pas. Ne me montre la solution de référence que si je bloque vraiment après deux essais. »

L'idée : tu sors de ce TP en **sachant faire**, pas en ayant copié-collé.

---

## Partie 0 — Les concepts (le *pourquoi* avant le *comment*)

**Le state, c'est quoi ?** Terraform garde une « photo » de l'infra qu'il gère dans un fichier `terraform.tfstate`. C'est sa source de vérité : il compare ce fichier au code pour décider quoi créer/modifier/détruire.

**Pourquoi un backend distant ?** Par défaut, ce fichier vit en local. Trois problèmes : (1) il contient souvent des **secrets en clair** (mots de passe de BDD, clés générées) — donc jamais sur ton disque ni dans Git ; (2) à plusieurs, chacun a sa version → conflits et corruption ; (3) si tu perds ton disque, tu perds le contrôle de toute ton infra. Un backend distant (S3) règle les trois.

**Le verrouillage (locking).** Si deux `apply` tournent en même temps, ils peuvent corrompre le state. Le verrou empêche ça : le premier prend le lock, le second attend. **Nouveauté 2025 importante :** avant, on utilisait une table DynamoDB pour ce verrou. Désormais Terraform sait poser un verrou directement dans S3 (`use_lockfile = true`), grâce aux écritures conditionnelles S3. Le verrouillage par DynamoDB est **déprécié** et sera retiré. On part donc sur le verrouillage natif S3 — plus simple, une ressource de moins, et c'est la pratique recommandée par AWS aujourd'hui. (Si tu croises de vieux tutos avec `dynamodb_table`, tu sauras pourquoi on ne le fait plus — bon point à glisser en entretien.)

**Le problème de l'œuf et la poule.** Tu veux stocker ton state dans un bucket S3… mais ce bucket doit lui-même être créé. Tu ne peux pas demander à Terraform de stocker son state dans un bucket qui n'existe pas encore. **Solution :** un petit dossier `bootstrap/` séparé qui crée le bucket en utilisant un state **local** (il est minuscule et ne bouge presque jamais). On l'applique **une seule fois**. Ensuite, le reste de ton infra (`terraform/`) utilise ce bucket comme backend.

---

## La check-list de sécurité du bucket de state (apprends-la par cœur)

Un bucket de state n'est pas un bucket comme un autre : il contient les secrets de toute ta plateforme. Chaque réglage ci-dessous est **non négociable**, et tu dois savoir dire *pourquoi* :

| Réglage | Pourquoi |
|---|---|
| **Block Public Access** (les 4 options) | Une fuite de state = fuite de tous tes secrets. Aucun bucket de state ne doit jamais être public, point. |
| **Versioning activé** | Si un `apply` corrompt ou supprime le state, tu peux restaurer une version antérieure. C'est ton filet de sécurité anti-catastrophe. |
| **Chiffrement au repos (SSE)** | Le state contient des secrets : ils doivent être chiffrés sur le disque AWS. SSE-S3 (AES256) au minimum, SSE-KMS avec clé gérée en bonus. |
| **Déni du transport non-TLS** | Une politique de bucket qui refuse toute requête en HTTP (non chiffré). On ne laisse jamais transiter des secrets en clair sur le réseau. |
| **`encrypt = true` côté backend** | Côté Terraform, force le chiffrement de l'objet de state à l'écriture. |

> Mémo : **P-V-C-T** → *Privé, Versionné, Chiffré, TLS-only*.

---

## Partie 1 — Construction pas à pas

À chaque étape : **Pourquoi → Ta mission → Indice → Vérifie-toi**. Essaie d'écrire le code avant de regarder l'indice. Ne regarde la « solution de référence » qu'après un vrai essai.

### Étape 1 — La structure du dossier `bootstrap/`

**Pourquoi :** isoler la création du bucket (state local) du reste de l'infra (state distant).

**Ta mission :** crée cette arborescence à la racine du repo :

```
bootstrap/
├── versions.tf      # contraintes terraform + provider
├── providers.tf     # provider AWS (région)
├── main.tf          # le bucket et son durcissement
├── variables.tf     # nom du bucket, région
├── outputs.tf       # affiche le nom du bucket à la fin
└── .gitignore       # IGNORER le state local !
```

**Vérifie-toi :** ton `bootstrap/.gitignore` doit au minimum contenir `*.tfstate`, `*.tfstate.*` et `.terraform/`. Le state local du bootstrap **ne doit jamais** partir sur GitHub.

---

### Étape 2 — `versions.tf` et `providers.tf`

**Pourquoi :** verrouiller les versions garantit que ton code se comporte pareil chez toi, en CI et dans 6 mois. `use_lockfile` exige Terraform ≥ 1.11.

**Ta mission :** déclare la version minimale de Terraform et le provider AWS, puis configure la région.

**Indice :** bloc `terraform { required_version = ... required_providers { aws = { source = "hashicorp/aws", version = ... } } }`, puis un bloc `provider "aws" { region = var.aws_region }`.

**Vérifie-toi (référence — à consulter après essai) :**

```hcl
# versions.tf
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # ou la dernière majeure dispo sur le registry
    }
  }
}
```

```hcl
# providers.tf
provider "aws" {
  region = var.aws_region
}
```

---

### Étape 3 — Le bucket (création nue d'abord)

**Pourquoi :** on crée d'abord la coquille, puis on empile la sécurité par-dessus, couche par couche. Tu verras littéralement le bucket passer de « non sécurisé » à « durci ».

**Note importante sur le provider AWS 5.x :** la configuration du bucket est **éclatée en plusieurs ressources** (versioning, chiffrement, accès public sont des ressources séparées, plus des arguments du bucket). C'est voulu : chaque aspect est explicite et auditable.

**Ta mission :** déclare une ressource `aws_s3_bucket` avec un nom unique (les noms S3 sont **globaux** sur tout AWS).

**Indice :** `resource "aws_s3_bucket" "state" { bucket = var.bucket_name }`. Pour le nom, pense à quelque chose comme `tf-state-landingzone-<tonidentifiant>` pour l'unicité.

**Vérifie-toi :** à ce stade, ne fais pas encore `apply`. Si tu lances `terraform validate` dans `bootstrap/`, ça doit passer.

---

### Étape 4 — Activer le versioning

**Pourquoi :** ton filet anti-catastrophe. Si le state est corrompu, tu restaures.

**Ta mission :** ajoute une ressource qui active le versioning sur le bucket de l'étape 3.

**Indice :** ressource `aws_s3_bucket_versioning`, qui référence `aws_s3_bucket.state.id`, avec un bloc `versioning_configuration { status = "Enabled" }`.

**Vérifie-toi (après apply, étape 8) :**
```bash
aws s3api get-bucket-versioning --bucket <ton-bucket>
# doit afficher "Status": "Enabled"
```

---

### Étape 5 — Chiffrement au repos (SSE)

**Pourquoi :** le state contient des secrets ; ils doivent être chiffrés sur disque.

**Ta mission :** ajoute la configuration de chiffrement côté serveur.

**Indice :** ressource `aws_s3_bucket_server_side_encryption_configuration`, bloc `rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }`. (SSE-S3 = `AES256`. Pour aller plus loin : `aws:kms` avec une clé KMS gérée par toi — note-le comme amélioration future.)

**Vérifie-toi (après apply) :**
```bash
aws s3api get-bucket-encryption --bucket <ton-bucket>
```

---

### Étape 6 — Bloquer tout accès public

**Pourquoi :** le réglage le plus critique. Un bucket de state public = catastrophe totale.

**Ta mission :** ajoute le blocage d'accès public, les **quatre** options à `true`.

**Indice :** ressource `aws_s3_bucket_public_access_block` avec `block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets` — tous à `true`.

**Vérifie-toi (après apply) :**
```bash
aws s3api get-public-access-block --bucket <ton-bucket>
# les 4 valeurs doivent être true
```

---

### Étape 7 — (Bonus) Refuser le transport non chiffré

**Pourquoi :** garantir qu'aucune requête en HTTP clair ne touche ce bucket. Niveau « top 1 % ».

**Ta mission :** attache une politique de bucket qui **refuse** toute action si `aws:SecureTransport` est `false`.

**Indice :** ressource `aws_s3_bucket_policy` ; la politique a un `Effect = "Deny"`, `Principal = "*"`, `Action = "s3:*"`, sur le bucket et son contenu (`/*`), avec une `Condition { Bool = { "aws:SecureTransport" = "false" } }`. Construis le JSON avec `data "aws_iam_policy_document"` plutôt qu'à la main (plus lisible, et c'est ce qu'on attend d'un pro).

---

### Étape 8 — `init`, `plan`, `apply`

**Ta mission :** depuis `bootstrap/`, dans l'ordre :
```bash
terraform fmt -recursive   # garde tout propre (ta CI te remerciera)
terraform init
terraform validate
terraform plan
terraform apply            # relis le plan AVANT de taper "yes"
```

**Vérifie-toi :** l'`apply` doit créer le bucket et tes ressources de durcissement. Récupère le nom du bucket via tes `outputs.tf`. Puis déroule les commandes de vérification des étapes 4, 5, 6.

> **Garde-fou coût :** ce bucket est quasi gratuit (et plus de DynamoDB = plus rien à payer pour le verrou). Ne le détruis **pas** tant que ta plateforme l'utilise comme backend.

---

### Étape 9 — Brancher le backend dans la config principale

**Pourquoi :** maintenant que le bucket existe, ton infra principale (`terraform/`) peut l'utiliser. C'est ici qu'on active le **verrouillage natif S3**.

**Ta mission :** dans `terraform/providers.tf`, ajoute (ou décommente) le bloc backend.

**Indice / référence :**
```hcl
terraform {
  backend "s3" {
    bucket       = "tf-state-landingzone-<tonidentifiant>"
    key          = "landing-zone/prod.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true # verrouillage natif S3 (remplace DynamoDB, déprécié)
  }
}
```

Puis :
```bash
cd terraform
terraform init   # Terraform détecte le backend et propose de MIGRER le state local -> S3 : accepte
```

**Vérifie-toi :** après `init`, un objet `landing-zone/prod.tfstate` doit apparaître dans ton bucket :
```bash
aws s3 ls s3://<ton-bucket>/landing-zone/
```

---

### Étape 10 — Prouver que le verrou fonctionne

**Pourquoi :** vérifier, pas supposer. C'est un réflexe d'ingénieur.

**Ta mission :** lance un `terraform plan` dans un terminal et, pendant qu'il tourne, observe : un fichier `.tflock` (verrou) apparaît brièvement dans le bucket. Tu peux aussi lancer deux opérations en parallèle : la seconde doit afficher un message indiquant que le state est verrouillé.

---

## Auto-évaluation (réponds sans regarder)

1. Pourquoi le dossier `bootstrap/` garde-t-il un state **local** alors qu'on prêche le state distant partout ailleurs ?
2. Que se passe-t-il si deux `apply` tournent en même temps **sans** verrouillage ?
3. Cite les 4 réglages de sécurité non négociables d'un bucket de state, et le risque que chacun couvre.
4. Pourquoi n'utilise-t-on plus DynamoDB pour le verrouillage ?
5. Pourquoi ne **jamais** committer `terraform.tfstate` ?

Si tu sais répondre à ces 5 questions à l'oral, tu es prêt à en parler en entretien.

---

## Pièges courants

Le nom de bucket n'est pas unique mondialement → erreur `BucketAlreadyExists` : ajoute un suffixe (identifiant, date). Oublier `use_lockfile = true` → aucun verrou, risque de corruption à plusieurs ou en CI. La région du backend diffère de celle du bucket → `init` échoue. Committer par accident le state ou un `.tfvars` contenant des secrets → c'est exactement ce que gitleaks attrapera dans ta CI (et un recruteur le verra dans l'historique). Lancer le bootstrap avec un backend déjà configuré → tu recrées le problème de l'œuf et la poule.

---

## Comment en parler en entretien

> « J'ai séparé un module `bootstrap` qui provisionne le backend de state — un bucket S3 versionné, chiffré, en accès public bloqué, avec une politique qui refuse le transport non-TLS. Pour le verrouillage, j'utilise le lock natif S3 via `use_lockfile`, pas DynamoDB, qui est déprécié depuis Terraform 1.11. Le versioning me sert de filet de sécurité en cas de corruption du state. »

Cette phrase, dite avec assurance, te place immédiatement au-dessus du candidat moyen : tu montres que tu sécurises *les fondations*, pas juste les ressources visibles, et que tu es à jour sur les pratiques.

---

## Et après ?

Une fois ce backend en place et le state migré, tu attaques le **module réseau** (Lab 02) : VPC + flow logs → subnets (3 tiers × 2 AZ) → routing (tier data sans route Internet) → NACLs + SG → VPC endpoints → outputs. Chaque brique = un commit, et ta CI scanne à chaque push.
