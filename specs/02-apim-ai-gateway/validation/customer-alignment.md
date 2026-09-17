# External Policy Alignment Matrix

Baseline: approved external APIM and Foundry policy evidence. Source revisions are retained in the
controlled evidence location rather than embedded in repository documentation.

| External policy control | Stage | Implementation or evidence |
|---|---|---|
| APIM subnet name `apimsubnet-*` | Foundation | `apimSubnetName`; `subnetNamingExceptionReference` is required when the approved subnet differs from the convention |
| Approved hybrid NSG | Foundation | `approvedApimNsgResourceId`; live validator compares the subnet association |
| `apim-routetable-<location>` | Foundation | `approvedApimRouteTableResourceId`; when empty, `routeTableExceptionReference` must identify the active approved exception |
| Approved policy exception for a route-table and shared-NSG conflict | Foundation | Controlled external evidence records the exception; foundation requires an explicit reference and validates that no conflicting route table is attached |
| No subnet delegation | Foundation | Deployment-time assertion and live subnet check |
| Azure AD, Key Vault, SQL, Storage service endpoints | Foundation | `requiredServiceEndpoints`; deployment-time assertion and live subnet check |
| Developer or Premium APIM | Foundation | `apimSkuName`; Developer is allowed for smoke tests with capacity one and Premium remains the default |
| Internal VNet mode | Foundation | `virtualNetworkType: 'Internal'`; live endpoint checks |
| Classic-tier platform public IP | Foundation | `apimPublicIpAddressName`; existing Standard/static resource is associated to APIM |
| Corporate administrator email | Foundation | `publisherEmail` rejects placeholder and non-corporate examples |
| HTTPS backends | Foundation + integration | APIM protocol settings and integration backend URL/policy checks |
| TLS 1.2+ and weak protocols/ciphers disabled | Foundation | Explicit APIM `customProperties`; compiled-template regression check |
| `AllLogs` and `AllMetrics` | Foundation | Blueprint diagnostic setting, or policy-owned setting verified live |
| Average capacity alert above 60% | Foundation | Metric alert with `Capacity`, `Average`, threshold `60` |
| Default VNet-local private DNS | Foundation | `azure-api.net` zone, VNet link, gateway/portal/management/SCM A records |
| Enterprise custom domains and CA certificates | Conditional foundation extension | Documented in chapter/quickstart; requires enterprise DNS A records to private VIP |
| Generative AI governance approval | Integration | `genAiApprovalReference`; required non-placeholder preflight input |
| Foundry account enablement | Integration | `foundryEnablementReference`; required non-placeholder preflight input |
| Approved Foundry region | Integration | `approvedFoundryRegions`; live validator checks account location |
| Private Foundry access | Integration | Stage 2 unconditionally requires disabled public network access |
| Customer-approved model list | Integration | `approvedModels` plus `customerPolicySource`; live validator resolves each deployment |
| Least-privilege model invocation | Integration | `Cognitive Services OpenAI User` at the selected account scope |
| No shared Foundry credentials | Integration | APIM backend policy uses managed identity; static secret/key regression checks |

## Evidence Rule

Template inputs and static checks establish intent, not live compliance. Azure-owned and
policy-owned controls remain `BLOCKED` until the stage validator can read the target resources.
Historical combined evidence files are not current proof for either staged entry point.
