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


Below is the quickest manual (CLI/API) workflow to create a Vault Enterprise namespace and let users log in to it.

Requires Vault Enterprise and a token with sudo on sys/namespaces/* (often the initial root token).

1) Create the namespace

CLI

export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="<root_or_admin_token>"

vault namespace create team-a
# Verify
vault namespace list
vault namespace lookup -namespace=team-a


API

curl -sS \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -X POST "$VAULT_ADDR/v1/sys/namespaces/team-a"

2) Target the namespace

Use the namespace header/env for all subsequent commands:

export VAULT_NAMESPACE="team-a"   # or pass -namespace=team-a to each CLI command

3) Enable an auth method inside the namespace

(Users authenticate to the auth method that lives in that namespace.)

Example: username/password (simple to demo)
vault auth enable userpass

4) Create a policy in the namespace
cat > app-admin.hcl <<'HCL'
# Example: full control of KV v2 at "secret/"
path "secret/*" {
  capabilities = ["create","read","update","delete","list"]
}
# List mounts and read self token
path "sys/mounts" { capabilities = ["read","list"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
HCL

vault policy write app-admin app-admin.hcl
5) Create users (or set OIDC/JWT mappings)
A) Userpass demo user
vault write auth/userpass/users/alice \
  password="S3cureP@ss!" \
  policies="app-admin"


Alice will log in to namespace team-a via UI or:

vault login -method=userpass username=alice password='S3cureP@ss!' -namespace=team-a

B) (Optional) OIDC/JWT/LDAP

OIDC/JWT: enable oidc/jwt, configure the provider, then create roles that map claims → policies.

LDAP: enable ldap, point to your directory, and map groups → policies.
(Flow is the same idea: mappings live inside the namespace.)

6) Enable a secrets engine (optional but typical)
vault secrets enable -path=secret kv-v2
vault kv put secret/app/config username=demo password=demo123
vault kv get secret/app/config

7) (Optional) Issue an admin token scoped to the namespace

Useful for bootstrap without sharing root token:

vault token create -policy=app-admin -orphan -display-name="team-a-admin"
How users “get access” to a namespace


You don’t “grant cross-namespace access.” Instead, you create/enable an auth method inside that namespace and assign policies in that same namespace.


Users then log in against that namespace (UI namespace picker, VAULT_NAMESPACE, or X-Vault-Namespace header). Their token is scoped there.


If you tell me which auth method you want (OIDC/JWT with GitLab, LDAP, or userpass), I’ll give you the exact commands and minimal config for that provider, plus a hardened starter policy.


Absolutely—here’s a tight, step-by-step for enabling OIDC login inside a Vault namespace and mapping users/groups to policies.

Prereqs (quick)

Vault Enterprise, TLS on your URL.

An OIDC client/app at your IdP (Okta, Azure AD, Auth0, Keycloak, etc.) with these redirect URIs:

https://vault.example.com/ui/vault/auth/oidc/oidc/callback

http://127.0.0.1:8250/oidc/callback (Vault CLI)

An admin token that can manage the target namespace (e.g., team-a).

0) Target the namespace
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="<admin_or_root_token>"
export VAULT_NAMESPACE="team-a"

1) Enable OIDC in the namespace
vault auth enable -path=oidc oidc
# path will be: auth/oidc/

2) Configure the OIDC method

Fill in your IdP values:

vault write auth/oidc/config \
  oidc_discovery_url="https://login.microsoftonline.com/<tenant_id>/v2.0" \  # EX: Azure AD
  oidc_client_id="<CLIENT_ID>" \
  oidc_client_secret="<CLIENT_SECRET>" \
  default_role="team-a-dev"   # optional; omit if you want users to always specify a role


Other common discovery URLs

Okta: https://<yourOktaDomain>/.well-known/openid-configuration

Auth0: https://<tenant>.auth0.com/.well-known/openid-configuration

Keycloak: https://idp.example.com/realms/<realm>/.well-known/openid-configuration

3) Create one or more roles (maps IdP claims → Vault policies)
A) Role with simple email → username mapping
vault write auth/oidc/role/team-a-dev \
  role_type="oidc" \
  user_claim="email" \
  groups_claim="groups" \
  oidc_scopes="openid,profile,email,groups" \
  bound_audiences="<CLIENT_ID>" \
  allowed_redirect_uris="https://vault.example.com/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://127.0.0.1:8250/oidc/callback" \
  claim_mappings=email=username \
  token_ttl="1h" \
  token_max_ttl="4h" \
  policies="app-readonly"

B) Lock role to a specific IdP group (recommended)

If your IdP returns a groups claim (GUIDs or names), you can require membership:

vault write auth/oidc/role/team-a-admin \
  role_type="oidc" \
  user_claim="email" \
  groups_claim="groups" \
  oidc_scopes="openid,profile,email,groups" \
  bound_audiences="<CLIENT_ID>" \
  allowed_redirect_uris="https://vault.example.com/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://127.0.0.1:8250/oidc/callback" \
  bound_claims='{"groups": ["vault-team-a-admins"]}' \
  token_ttl="30m" \
  token_max_ttl="4h" \
  policies="app-admin"


If Azure AD returns group object IDs, put those IDs in bound_claims. For Okta/Auth0/Keycloak, you can often map friendly names.

4) Create policies in the namespace
cat > app-admin.hcl <<'HCL'
path "secret/*" {
  capabilities = ["create","read","update","delete","list"]
}
path "sys/mounts" { capabilities = ["read","list"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
HCL

cat > app-readonly.hcl <<'HCL'
path "secret/*" {
  capabilities = ["read","list"]
}
path "auth/token/lookup-self" { capabilities = ["read"] }
HCL

vault policy write app-admin app-admin.hcl
vault policy write app-readonly app-readonly.hcl
5) (Optional) Enable a secrets engine in the namespace
vault secrets enable -path=secret kv-v2
vault kv put secret/app/config username=demo password=demo123


6) User login (two ways)
A) CLI (opens a browser)
export VAULT_NAMESPACE="team-a"
vault login -method=oidc role=team-a-dev
# Browser pops, complete IdP login → token returned in CLI

B) Web UI


In the login page, choose Namespace = team-a.


Choose OIDC as the method.


(If prompted) set Role = team-a-dev (or rely on default_role).


Authenticate via your IdP.


Verify:
vault token lookup | grep -E 'policies|path'
vault kv get secret/app/config


Provider-specific notes
Azure AD


Discovery URL: https://login.microsoftonline.com/<tenant_id>/v2.0


Ensure your app exposes the email scope or returns preferred_username claim; you can set user_claim="preferred_username" if needed.


For groups, Azure may send object IDs. Use those in bound_claims. If groups are too large, Azure may issue a _claim_names/_claim_sources reference—configure the app to emit groups in the token or rely on assigned groups.


Okta


Discovery URL usually: https://<yourOktaDomain>/.well-known/openid-configuration


Add a custom groups claim in the token (ID Token) filtered to groups that start with e.g. vault-.


Keycloak


Add a Group Membership mapper to the client to include groups in the ID token.


Discovery URL points to the realm’s .well-known.



Hardening tips


Prefer no default_role if you expose multiple roles; force users to pick.


Use bound_claims and/or bound_audiences to prevent token reuse.


Set token_ttl/token_max_ttl per role.


Enable and monitor audit devices; OIDC logins are auditable.


Keep OIDC mount path consistent (e.g., always auth/oidc) for simpler UI.



If you tell me your IdP (Azure AD, Okta, Keycloak, etc.) and your desired group → policy mapping, I’ll tailor the exact commands and claims for your setup.


Great—here’s a focused, copy-pasteable setup for Vault OIDC auth with Keycloak inside a specific namespace (e.g., team-a). I’ll show both the Keycloak side and the Vault side, plus quick tests and common fixes.

0) Prep
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="<root_or_admin_token>"
export VAULT_NAMESPACE="team-a"        # <— important: everything below happens in this namespace

1) Keycloak configuration (Admin Console)

Create a client (one client per Vault OIDC mount is fine):

Clients → Create client

Client ID: vault-team-a

Client type: OpenID Connect

Name: Vault OIDC (team-a) (optional label)

Next → Enable:

Client authentication: ON (confidential client)

Standard flow: ON (Authorization Code)

Direct access grants: OFF

Save.

Add redirect URIs (both UI and CLI):

In Client → Settings:

Valid redirect URIs:

https://vault.example.com/ui/vault/auth/oidc/oidc/callback

http://127.0.0.1:8250/oidc/callback

Web origins: + Add https://vault.example.com

(Optionally) set Front-channel logout URL to the UI base if you want clean sign-out.

Expose the right claims (ID Token):

Client → Client scopes (or “Client scopes” tab depending on Keycloak version):

Ensure the client gets email, profile, openid.

Add token mappers to the client (or to a client scope that’s assigned to the client):

Groups mapper

Mapper type: Group Membership

Token claim name: groups

Full group path: OFF (or ON if you want /team-a/admins; pick one and be consistent)

Add to ID token: ON

Add to access token: ON (optional)

(Optional) Preferred username mapper

Mapper type: User Property (property = username)

Token claim name: preferred_username

Add to ID token: ON

(Optional) Email mapper

Mapper type: User Property (property = email)

Token claim name: email

Add to ID token: ON

Create / confirm groups and membership:

Users → your users → Groups tab → add them to groups like:

vault-team-a-admins

vault-team-a-developers

Grab credentials:

Clients → vault-team-a → Credentials:

Client ID: vault-team-a

Client Secret: copy the secret

Discovery URL (per realm):

Format: https://<keycloak-host>/realms/<realm>
(Vault will call /.well-known/openid-configuration under the hood.)

2) Vault configuration (in the namespace)

Enable OIDC at a consistent path (e.g., auth/oidc)

vault auth enable -path=oidc oidc


Configure the OIDC method (Keycloak realm discovery)

vault write auth/oidc/config \
  oidc_discovery_url="https://keycloak.example.com/realms/<realm>" \
  oidc_client_id="vault-team-a" \
  oidc_client_secret="<KEYCLOAK_CLIENT_SECRET>" \
  default_role="team-a-dev"


Policies (example)

cat > app-admin.hcl <<'HCL'
path "secret/*" { capabilities = ["create","read","update","delete","list"] }
path "sys/mounts" { capabilities = ["read","list"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
HCL

cat > app-readonly.hcl <<'HCL'
path "secret/*" { capabilities = ["read","list"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
HCL

vault policy write app-admin app-admin.hcl
vault policy write app-readonly app-readonly.hcl


(Optional) Secrets engine in the namespace

vault secrets enable -path=secret kv-v2
Create roles that bind Keycloak groups → Vault policies

Admins (require Keycloak group)

bash
Copy code
vault write auth/oidc/role/team-a-admin \
  role_type="oidc" \
  user_claim="preferred_username" \
  groups_claim="groups" \
  oidc_scopes="openid,profile,email" \
  bound_audiences="vault-team-a" \
  allowed_redirect_uris="https://vault.example.com/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://127.0.0.1:8250/oidc/callback" \
  bound_claims='{"groups": ["vault-team-a-admins"]}' \
  token_ttl="30m" \
  token_max_ttl="4h" \
  policies="app-admin"
Developers (different group → readonly policy)

bash
Copy code
vault write auth/oidc/role/team-a-dev \
  role_type="oidc" \
  user_claim="preferred_username" \
  groups_claim="groups" \
  oidc_scopes="openid,profile,email" \
  bound_audiences="vault-team-a" \
  allowed_redirect_uris="https://vault.example.com/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://127.0.0.1:8250/oidc/callback" \
  bound_claims='{"groups": ["vault-team-a-developers"]}' \
  token_ttl="1h" \
  token_max_ttl="4h" \
  policies="app-readonly"
If you set default_role="team-a-dev" in auth/oidc/config, users can omit role=... during login and will land in that role by default.

3) Login tests

4) You said:
can you write a one terraform config for all this
