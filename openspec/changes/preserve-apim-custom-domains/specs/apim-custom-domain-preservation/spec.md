## Purpose

Prevents APIM redeployments, such as a SKU change, from silently removing custom domains, and
lets operators add or replace domains, including PFX-backed ones, through the same deployment.

## ADDED Requirements

### Requirement: Hostname mode selects the deployed custom domains
The APIM foundation deployment SHALL accept `hostnameMode` with values `preserve`, `merge` and
`replace`, defaulting to `preserve`, and SHALL reject other values.

#### Scenario: Default mode
- **WHEN** the operator does not set `hostnameMode`
- **THEN** the deployment behaves as `preserve`

### Requirement: Preserve re-sends captured domains
In `preserve` mode the deployment SHALL configure exactly the domains supplied in
`existingHostnameConfigurations` and SHALL ignore `hostnameConfigurations`.

#### Scenario: SKU change with Key Vault-backed domains
- **WHEN** the live service has Key Vault-backed custom domains, the operator captures them and
  redeploys with a different SKU
- **THEN** the same custom domains remain configured after the deployment

### Requirement: Merge adds declared domains to captured domains
In `merge` mode the deployment SHALL configure the captured domains plus the declared domains.
A declared entry SHALL replace a captured entry with the same type and case-insensitive hostName,
and a declared non-`Proxy` entry SHALL replace any captured entry of that type, because APIM
allows one domain per non-`Proxy` type.

#### Scenario: Add a gateway domain
- **WHEN** one `Proxy` domain is captured and a different `Proxy` domain is declared
- **THEN** both domains are configured

#### Scenario: Update a management domain
- **WHEN** a `Management` domain is captured and another `Management` domain is declared
- **THEN** only the declared `Management` domain is configured

### Requirement: Replace makes declared domains authoritative
In `replace` mode the deployment SHALL configure exactly the declared domains and SHALL ignore
`existingHostnameConfigurations`; an empty declared list removes all custom domains.

#### Scenario: Remove a domain
- **WHEN** mode is `replace` and a previously configured domain is not declared
- **THEN** that domain is not configured after the deployment

### Requirement: PFX-backed domains can be declared without committing secrets
A declared domain SHALL reference either a Key Vault certificate (`keyVaultId`) or a
`certificateKey` resolved from the secure `hostnameCertificates` parameter holding the base64
PFX and password. Examples SHALL cover the gateway (`Proxy`), `DeveloperPortal` and `Management`
types with placeholder hostnames, and SHALL take certificate material from environment variables.

#### Scenario: Three PFX domains
- **WHEN** gateway, developer portal and management domains are declared with certificate keys
- **THEN** each is configured with its own certificate and the certificate values are not stored in
  any committed file

### Requirement: Live domains can be captured before deployment
The system SHALL provide a script that prints the live custom domains (excluding default
`*.azure-api.net` endpoints) as a JSON array on stdout with every live setting preserved except
read-only certificate details, prints `[]` when the service does not exist, and omits domains that
use an uploaded PFX (no Key Vault reference and not APIM-managed) while warning that they must be
declared.

#### Scenario: First deployment
- **WHEN** the APIM service does not exist
- **THEN** the script prints `[]` and exits successfully

#### Scenario: Uploaded PFX domain
- **WHEN** a live domain has no `keyVaultId` and is not APIM-managed
- **THEN** the script omits it from the output and warns on stderr

### Requirement: Operator guidance states the mandatory capture step
The deployment documentation SHALL state that the script must run before every deployment in
`preserve` or `merge` mode, that skipping it removes live domains, that PFX domains must be
declared, and that custom hostnames need separately managed private DNS records.

#### Scenario: Operator follows the runbook
- **WHEN** the operator follows the APIM deployment steps in `infra/envs/poc/README.md`
- **THEN** the capture script runs before what-if and create
