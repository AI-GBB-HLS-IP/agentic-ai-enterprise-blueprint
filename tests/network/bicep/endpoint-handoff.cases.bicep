import { selectedEndpoints, endpointHandoffValid } from '../../../infra/modules/apim/endpoints.bicep'

var hostnames = { gateway: 'api.example.com', developerPortal: 'developer.example.com', management: 'management.example.com' }
var serviceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.ApiManagement/service/example'
var endpoints = selectedEndpoints('custom', 'example', hostnames)
var evidence = {
  validationType: 'apim-endpoint-access'
  status: 'pass'
  owner: 'network-owner'
  scope: 'apim-foundation'
  approvalReference: 'approval-generic-001'
  evidenceSummary: 'Selected endpoints validated.'
  timestampUtc: '2026-10-11T00:00:00Z'
  apimServiceId: serviceId
  endpointMode: 'custom'
  endpointAccessPath: 'direct-private'
  selectedHostnames: hostnames
  validationReference: 'validation-record-001'
}
var handoff = {
  apimServiceId: serviceId
  endpointMode: 'custom'
  endpointAccessPath: 'direct-private'
  selectedHostnames: hostnames
  endpoints: endpoints
  selectedGatewayHostname: hostnames.gateway
  selectedGatewayUrl: 'https://${hostnames.gateway}'
  excludedClientChecks: ['legacyPortal', 'scm']
  endpointValidationEvidence: evidence
}
var fields = ['validationType', 'status', 'owner', 'scope', 'approvalReference', 'evidenceSummary', 'timestampUtc', 'apimServiceId', 'endpointMode', 'endpointAccessPath', 'selectedHostnames', 'validationReference']
var missingEvidence = map(fields, field => toObject(filter(items(evidence), entry => entry.key != field), entry => entry.key, entry => entry.value))
var badEvidence = flatten(map(fields, field => map(['', ' ', null, 1, true, {}, []], bad => shallowMerge([evidence, toObject([field], key => key, key => bad)]))))

assert matchingCustomHandoff = endpointHandoffValid(handoff, serviceId, 'custom', 'direct-private', hostnames, endpoints)
assert wrongService = !endpointHandoffValid(handoff, '${serviceId}-other', 'custom', 'direct-private', hostnames, endpoints)
assert wrongPath = !endpointHandoffValid(handoff, serviceId, 'custom', 'corporate-routed', hostnames, endpoints)
assert wrongSelection = !endpointHandoffValid(handoff, serviceId, 'built-in', 'direct-private', hostnames, endpoints)
assert wrongGateway = !endpointHandoffValid(union(handoff, { selectedGatewayHostname: 'other.example.com' }), serviceId, 'custom', 'direct-private', hostnames, endpoints)
assert wrongEndpointList = !endpointHandoffValid(union(handoff, { endpoints: take(endpoints, 1) }), serviceId, 'custom', 'direct-private', hostnames, endpoints)
assert legacyDefaultAccepted = endpointHandoffValid({}, serviceId, 'built-in', 'direct-private', {}, [])
assert legacyCustomRejected = !endpointHandoffValid({}, serviceId, 'custom', 'direct-private', hostnames, endpoints)
assert legacyCorporateRejected = !endpointHandoffValid({}, serviceId, 'built-in', 'corporate-routed', {}, [])
assert missingEvidenceRejected = empty(filter(missingEvidence, record => endpointHandoffValid(shallowMerge([handoff, { endpointValidationEvidence: record }]), serviceId, 'custom', 'direct-private', hostnames, endpoints)))
assert badEvidenceRejected = empty(filter(badEvidence, record => endpointHandoffValid(shallowMerge([handoff, { endpointValidationEvidence: record }]), serviceId, 'custom', 'direct-private', hostnames, endpoints)))
assert nonPassRejected = empty(filter(['fail', 'blocked', '', 'invalid'], status => endpointHandoffValid(shallowMerge([handoff, { endpointValidationEvidence: union(evidence, { status: status }) }]), serviceId, 'custom', 'direct-private', hostnames, endpoints)))
