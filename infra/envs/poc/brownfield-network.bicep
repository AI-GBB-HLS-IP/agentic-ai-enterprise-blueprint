targetScope = 'resourceGroup'

// Network-owner entry point for brownfield deployments: adds the 5 purpose-keyed subnets (and
// their NSGs) to an admin-provided existing VNet. This deployment MUST be run scoped to the
// existing VNet's own resource group (same subscription) so subnet writes land alongside their
// parent VNet; it never creates, modifies, or deletes the VNet resource itself.
//
// Fast-POC-pass scope (see issue #48): this entry point performs no independent overlap,
// containment, or ownership/adoption validation of its own — the supplied CIDRs and NSG
// resource IDs must already be admin-approved out of band before this template is deployed.
// The deferred discovery/capacity-calculator scripts and fail-closed preflight validator
// (specs/00-network-foundation/tasks.md T030-T033, T035-T039) will add that safety net in a
// follow-up.

@description('Name of the existing (admin-provided) VNet. Not created, modified, or deleted by this template.')
param existingVnetName string

@description('Resource group containing the existing VNet. This template must be deployed scoped to this resource group.')
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

@description('APIM NSG name, used only when reuseExistingNsgs is false.')
param apimNsgName string = 'hybrid-nsg-agent-blueprint-${toLower(replace(location, ' ', ''))}-apim'

@description('Compute NSG name, used only when reuseExistingNsgs is false.')
param computeNsgName string = 'hybrid-nsg-agent-blueprint-${toLower(replace(location, ' ', ''))}-compute'

@description('Set true to reuse pre-approved existing NSGs instead of creating new blueprint-owned ones. When true, existingApimNsgId and existingComputeNsgId must both be supplied and are associated as-is (this template never modifies a referenced existing NSG).')
param reuseExistingNsgs bool = false

@description('Existing APIM NSG resource ID. Required when reuseExistingNsgs is true.')
param existingApimNsgId string = ''

@description('Existing compute NSG resource ID. Required when reuseExistingNsgs is true.')
param existingComputeNsgId string = ''

module nsg '../../modules/network/nsg.bicep' = if (!reuseExistingNsgs) {
  scope: resourceGroup(existingVnetResourceGroupName)
  name: 'brownfield-nsg'
  params: {
    location: location
    apimNsgName: apimNsgName
    computeNsgName: computeNsgName
    apimSubnetPrefix: apimSubnetPrefix
  }
}

// The ternary below always resolves to a defined branch (either the conditional module's
// output or the caller-supplied existing ID) based on the same reuseExistingNsgs flag that
// gates the module, so the "possibly not deployed" warning does not indicate a real risk here.
#disable-next-line BCP318
var apimNsgIdResolved = reuseExistingNsgs ? existingApimNsgId : nsg.outputs.apimNsgId
#disable-next-line BCP318
var computeNsgIdResolved = reuseExistingNsgs ? existingComputeNsgId : nsg.outputs.computeNsgId

module subnets '../../modules/network/subnets.bicep' = {
  scope: resourceGroup(existingVnetResourceGroupName)
  name: 'brownfield-subnets'
  params: {
    vnetName: existingVnetName
    subnets: [
      {
        name: foundrySubnetName
        addressPrefix: foundrySubnetPrefix
        delegationServiceName: 'Microsoft.App/environments'
      }
      {
        name: apimSubnetName
        addressPrefix: apimSubnetPrefix
        nsgId: apimNsgIdResolved
      }
      {
        name: privateEndpointsSubnetName
        addressPrefix: privateEndpointsSubnetPrefix
        privateEndpointNetworkPolicies: 'Disabled'
      }
      {
        name: computeSubnetName
        addressPrefix: computeSubnetPrefix
        nsgId: computeNsgIdResolved
      }
      {
        name: cicdAgentsSubnetName
        addressPrefix: cicdAgentsSubnetPrefix
      }
    ]
  }
}

output vnetName string = existingVnetName
output existingVnetResourceGroupName string = existingVnetResourceGroupName
output subnetIds array = subnets.outputs.subnetIds
output apimNsgId string = apimNsgIdResolved
output computeNsgId string = computeNsgIdResolved
