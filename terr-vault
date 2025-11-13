You’ll use the Vault Terraform provider and the vault_namespace resource to create namespaces.

Here’s a clean, working example you can adapt.

1. Provider config (with or without root namespace)
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.3" # or latest that you're using
    }
  }
}

provider "vault" {
  address = "https://vault.example.com"

  # Use a root / admin token that has permission to manage namespaces
  token   = var.vault_token
}

variable "vault_token" {
  type      = string
  sensitive = true
}


You can pass TF_VAR_vault_token via environment variable instead of hardcoding.

2. Create a top-level namespace
resource "vault_namespace" "team_a" {
  path        = "team-a"       # final namespace path
  description = "Namespace for Team A"
}


This will create a namespace like: team-a/ under the root.

3. Create a child namespace (optional)

If you want nested namespaces:

resource "vault_namespace" "team_a_dev" {
  # parent is another namespace resource's path
  namespace   = vault_namespace.team_a.path
  path        = "dev"
  description = "Dev environment for Team A"
}


Resulting effective path: team-a/dev/

4. Using the namespace in other Vault resources

When you create other resources (kv, auth methods, policies, etc.) inside that namespace, you pass the namespace in the resource or via an aliased provider.

Option A – Aliased provider per namespace
provider "vault" {
  alias   = "team_a"
  address = "https://vault.example.com"
  token   = var.vault_token

  # use the full namespace path
  namespace = vault_namespace.team_a.path
}

resource "vault_kv_secret_v2" "team_a_example" {
  provider = vault.team_a

  mount = "secret"
  name  = "app/config"

  data_json = jsonencode({
    username = "test-user"
    password = "P@ssw0rd!"
  })
}

Option B – Namespace argument in the resource (if supported)

Some resources accept a namespace argument directly:

resource "vault_kv_secret_v2" "team_a_example2" {
  mount     = "secret"
  name      = "app/config2"
  namespace = vault_namespace.team_a.path

  data_json = jsonencode({
    api_key = "abc123"
  })
}

5. Recommended minimal main.tf template

You can literally start with:

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.3"
    }
  }
}

variable "vault_token" {
  type      = string
  sensitive = true
}

provider "vault" {
  address = "https://vault.example.com"
  token   = var.vault_token
}

resource "vault_namespace" "project_ns" {
  path        = "project-x"
  description = "Project X namespace"
}


Then run:

export TF_VAR_vault_token="<root_or_admin_token>"
terraform init
terraform plan
terraform apply


If you tell me:

your Vault version

whether you already use namespaces in your provider block

and if you want multiple envs (dev/test/prod)

I can turn this into a full multi-namespace layout for you (with providers and examples for secrets, auth, etc.).
