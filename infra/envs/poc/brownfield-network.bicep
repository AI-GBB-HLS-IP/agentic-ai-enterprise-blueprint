targetScope = 'resourceGroup'

// Network-owner entry point for brownfield deployments: adds the 5 purpose-keyed subnets (and
// their NSGs) to an admin-provided existing VNet. Deploy this template at any resource-group
// scope in the same subscription, but set existingVnetResourceGroupName to the VNet's resource
// group so subnet writes land alongside their parent VNet; it never creates, modifies, or
// deletes the VNet resource itself.
//
// Fast-POC-pass scope (see issue #48): this entry point performs no independent overlap,
// containment, or ownership/adoption validation of its own — the supplied CIDRs and NSG
// resource IDs must already be admin-approved out of band before this template is deployed.
// The deferred discovery/capacity-calculator scripts and fail-closed preflight validator
// (specs/00-network-foundation/tasks.md T030-T033, T035-T039) will add that safety net in a
// follow-up.

@description('Name of the existing (admin-provided) VNet. Not created, modified, or deleted by this template.')
param existingVnetName string

@description('Resource group containing the existing VNet. Subnet/NSG modules are deployed to this resource group in the same subscription.')
param existingVnetResourceGroupName string = resourceGroup().name

@description('Deployment location for new NSG resources.')
param location string = resourceGroup().location

@description('Foundry delegated subnet name.')
param foundrySubnetName string = 'hybridsubnet-foundry'

@description('Foundry delegated subnet CIDR. Default matches the /25 worked example in infra/modules/network/README.md; override to the admin-approved value for the real existing VNet.')
param foundrySubnetPrefix string = '10.0.0.0/26'

@description('APIM subnet name.')
param apimSubnetName string = 'hybridsubnet-apim'

@description('APIM subnet CIDR.')
param apimSubnetPrefix string = '10.0.0.64/28'

@description('Private endpoints subnet name.')
param privateEndpointsSubnetName string = 'hybridsubnet-privateendpoints'

@description('Private endpoints subnet CIDR.')
param privateEndpointsSubnetPrefix string = '10.0.0.80/28'

@description('Compute subnet name.')
param computeSubnetName string = 'hybridsubnet-compute'

@description('Compute subnet CIDR.')
param computeSubnetPrefix string = '10.0.0.96/28'

@description('CI/CD agents subnet name.')
param cicdAgentsSubnetName string = 'hybridsubnet-cicdagents'

@description('CI/CD agents subnet CIDR.')
param cicdAgentsSubnetPrefix string = '10.0.0.112/28'

// ---------------------------------------------------------------------------------------------
// NSG association. Three mutually exclusive modes, in precedence order:
//
//   1. sharedHybridNsgId set  -> "shared hybrid NSG" mode. One pre-existing, customer-owned NSG
//      (for example a centrally managed hybrid NSG such as `hybrid-nsg-<subscription>-<region>`) is associated
//      with ALL subnets created here. No NSG is created or modified by this template. This is the
//      mode required by customer network policies that mandate the hybrid NSG on every subnet.
//   2. reuseExistingNsgs true -> per-purpose existing NSGs. Associates the supplied APIM and
//      compute NSGs on those two subnets only; foundry, private endpoints, and CI/CD agents get
//      no NSG. Retained for environments without a single shared hybrid NSG.
//   3. neither                -> blueprint-owned mode. Creates the two blueprint APIM/compute
//      NSGs (distinct rule sets, per the greenfield design in infra/modules/network/README.md).
//
// The shared NSG may live in any resource group in the same subscription: subnet-to-NSG
// association is by full ARM resource ID and is inherently cross-resource-group.
// ---------------------------------------------------------------------------------------------

@description('Full ARM resource ID of a single pre-existing, customer-owned NSG to associate with EVERY subnet created by this template (e.g. the VPCx /VPCXRG NSG named hybrid-nsg-{subscription_name}-{region}). May live in a different resource group. When set, this template creates and modifies no NSG, and reuseExistingNsgs / existingApimNsgId / existingComputeNsgId are ignored.')
param sharedHybridNsgId string = ''

@description('APIM NSG name, used only in blueprint-owned mode (sharedHybridNsgId empty and reuseExistingNsgs false).')
param apimNsgName string = 'hybrid-nsg-agent-blueprint-${toLower(replace(location, ' ', ''))}-apim'

@description('Compute NSG name, used only in blueprint-owned mode (sharedHybridNsgId empty and reuseExistingNsgs false).')
param computeNsgName string = 'hybrid-nsg-agent-blueprint-${toLower(replace(location, ' ', ''))}-compute'

@description('Set true to reuse pre-approved per-purpose existing NSGs instead of creating new blueprint-owned ones. Ignored when sharedHybridNsgId is set. When true, existingApimNsgId and existingComputeNsgId must both be supplied and are associated as-is (this template never modifies a referenced existing NSG).')
param reuseExistingNsgs bool = false

@description('Existing APIM NSG resource ID. Required when reuseExistingNsgs is true and sharedHybridNsgId is empty.')
param existingApimNsgId string = ''

@description('Existing compute NSG resource ID. Required when reuseExistingNsgs is true and sharedHybridNsgId is empty.')
param existingComputeNsgId string = ''

@description('''Private-endpoint network policy for the private endpoints subnet. Azure only enforces NSG rules on private endpoint traffic when this is `Enabled` or `NetworkSecurityGroupEnabled`; with the default `Disabled`, an associated NSG is still attached to the subnet (satisfying a policy that mandates association) but its rules are NOT applied to private endpoint traffic. Set to `NetworkSecurityGroupEnabled` if the hybrid NSG must actually filter private endpoint traffic.''')
@allowed([
  'Disabled'
  'Enabled'
  'NetworkSecurityGroupEnabled'
  'RouteTableEnabled'
])
param privateEndpointsNetworkPolicies string = 'Disabled'

var useSharedHybridNsg = !empty(sharedHybridNsgId)

module nsg '../../modules/network/nsg.bicep' = if (!useSharedHybridNsg && !reuseExistingNsgs) {
  scope: resourceGroup(existingVnetResourceGroupName)
  name: 'brownfield-nsg'
  params: {
    location: location
    apimNsgName: apimNsgName
    computeNsgName: computeNsgName
    apimSubnetPrefix: apimSubnetPrefix
  }
}

// The ternaries below always resolve to a defined branch (shared NSG ID, caller-supplied existing
// ID, or the conditional module's output) using the same flags that gate the module, so the
// "possibly not deployed" warning does not indicate a real risk here.
#disable-next-line BCP318
var apimNsgIdResolved = useSharedHybridNsg ? sharedHybridNsgId : (reuseExistingNsgs ? existingApimNsgId : nsg.outputs.apimNsgId)
#disable-next-line BCP318
var computeNsgIdResolved = useSharedHybridNsg ? sharedHybridNsgId : (reuseExistingNsgs ? existingComputeNsgId : nsg.outputs.computeNsgId)

// Only the shared-hybrid-NSG mode attaches an NSG to the foundry, private endpoints, and CI/CD
// subnets; in the other two modes these objects contribute no `nsgId` key and those subnets are
// created without an NSG.
var sharedNsgAssociation = useSharedHybridNsg ? { nsgId: sharedHybridNsgId } : {}

module subnets '../../modules/network/subnets.bicep' = {
  scope: resourceGroup(existingVnetResourceGroupName)
  name: 'brownfield-subnets'
  params: {
    vnetName: existingVnetName
    subnets: [
      union({
        name: foundrySubnetName
        addressPrefix: foundrySubnetPrefix
        delegationServiceName: 'Microsoft.App/environments'
      }, sharedNsgAssociation)
      {
        name: apimSubnetName
        addressPrefix: apimSubnetPrefix
        nsgId: apimNsgIdResolved
      }
      union({
        name: privateEndpointsSubnetName
        addressPrefix: privateEndpointsSubnetPrefix
        privateEndpointNetworkPolicies: privateEndpointsNetworkPolicies
      }, sharedNsgAssociation)
      {
        name: computeSubnetName
        addressPrefix: computeSubnetPrefix
        nsgId: computeNsgIdResolved
      }
      union({
        name: cicdAgentsSubnetName
        addressPrefix: cicdAgentsSubnetPrefix
      }, sharedNsgAssociation)
    ]
  }
}

output vnetName string = existingVnetName
output existingVnetResourceGroupName string = existingVnetResourceGroupName
output subnetIds array = subnets.outputs.subnetIds
output usingSharedHybridNsg bool = useSharedHybridNsg
output apimNsgId string = apimNsgIdResolved
output computeNsgId string = computeNsgIdResolved
