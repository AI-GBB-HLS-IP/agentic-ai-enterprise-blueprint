import { endpointMatrixValid, nonEmptyStringField, referenceValid, dnsHostnameValid, normalizeSelectedHostnames, customHostnamesValid, selectedEndpoints, endpointBindingsValid, endpointEvidenceValid, endpointEvidencePassed } from '../../../infra/modules/apim/endpoints.bicep'

var hostnames = {
  gateway: 'api.example.com'
  developerPortal: 'developer.example.com'
  management: 'management.example.com'
}
var serviceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.ApiManagement/service/example'
var evidence = {
  validationType: 'apim-endpoint-access'
  status: 'pass'
  owner: 'network-owner'
  scope: 'apim-foundation'
  approvalReference: 'approval-generic-001'
  evidenceSummary: 'Selected endpoint checks and approved route retained.'
  timestampUtc: '2026-10-11T00:00:00Z'
  apimServiceId: serviceId
  endpointMode: 'custom'
  endpointAccessPath: 'direct-private'
  selectedHostnames: hostnames
  validationReference: 'validation-record-001'
}
var corporateEvidence = union(evidence, {
  endpointAccessPath: 'corporate-routed'
  routingApprovalReference: 'route-approval-001'
})
var endpoints = selectedEndpoints('custom', 'example', hostnames)
var bindings = [
  { type: 'Proxy', hostName: 'API.Example.com' }
  { type: 'DeveloperPortal', hostName: 'developer.example.com' }
  { type: 'Management', hostName: 'management.example.com' }
]
var fields = [
  'validationType'
  'status'
  'owner'
  'scope'
  'approvalReference'
  'evidenceSummary'
  'timestampUtc'
  'apimServiceId'
  'endpointMode'
  'endpointAccessPath'
  'validationReference'
  'selectedHostnames'
]
var invalidStringValues = ['', ' ', 1, true, {}, [], null]
var missingRecords = map(fields, field => toObject(filter(items(evidence), entry => entry.key != field), entry => entry.key, entry => entry.value))
var badRecords = flatten(map(fields, field => map(invalidStringValues, bad => shallowMerge([evidence, toObject([field], key => key, key => bad)]))))

assert validMatrix = endpointMatrixValid('built-in', 'direct-private', 'blueprint') && endpointMatrixValid('built-in', 'direct-private', 'external') && endpointMatrixValid('custom', 'direct-private', 'external') && endpointMatrixValid('custom', 'corporate-routed', 'external')
assert invalidMatrix = !endpointMatrixValid('custom', 'direct-private', 'blueprint') && !endpointMatrixValid('custom', 'corporate-routed', 'blueprint') && !endpointMatrixValid('built-in', 'corporate-routed', 'external') && !endpointMatrixValid('unknown', 'direct-private', 'external') && !endpointMatrixValid('custom', 'unknown', 'external')
assert standardHasFive = length(selectedEndpoints('built-in', 'example', {})) == 5
assert customHasThree = length(endpoints) == 3
assert customHasNoBuiltInNames = empty(filter(endpoints, endpoint => endsWith(endpoint.hostname, '.azure-api.net')))
assert validCustomHostnames = customHostnamesValid(hostnames)
assert lowercaseNormalization = normalizeSelectedHostnames(union(hostnames, { gateway: ' API.Example.com ' })) == hostnames
assert invalidHostsRejected = empty(filter(['https://api.example.com', 'api.example.com:443', 'api.example.com/path', '*.example.com', 'x', '.example.com', 'a..example.com', '-a.example.com', 'a-.example.com', 'a_.example.com', 'example.azure-api.net', '127.0.0.1'], host => dnsHostnameValid(host)))
assert missingRoleRejected = !customHostnamesValid({ gateway: 'api.example.com', management: 'management.example.com' })
assert wrongRoleTypeRejected = !customHostnamesValid(union(hostnames, { management: 7 }))
assert extraRoleRejected = !customHostnamesValid(union(hostnames, { scm: 'scm.example.com' }))
assert validRoleBindings = endpointBindingsValid(endpoints, bindings)
assert missingBindingRejected = !endpointBindingsValid(endpoints, take(bindings, 2))
assert wrongBindingTypeRejected = !endpointBindingsValid(endpoints, [
  bindings[0]
  bindings[1]
  { type: 'Proxy', hostName: 'management.example.com' }
])
assert matchingDirectEvidence = endpointEvidencePassed(evidence, serviceId, 'custom', 'direct-private', hostnames)
assert matchingCorporateEvidence = endpointEvidencePassed(corporateEvidence, serviceId, 'custom', 'corporate-routed', hostnames)
assert absentEvidenceCannotAdvance = !endpointEvidencePassed({}, serviceId, 'custom', 'direct-private', hostnames)
assert everyMissingFieldRejected = empty(filter(missingRecords, record => endpointEvidenceValid(record, serviceId, 'custom', 'direct-private', hostnames)))
assert everyEmptyOrWrongTypeRejected = empty(filter(badRecords, record => endpointEvidenceValid(record, serviceId, 'custom', 'direct-private', hostnames)))
assert nonPassCannotAdvance = empty(filter(['fail', 'blocked', 'invalid', ''], status => endpointEvidencePassed(union(evidence, { status: status }), serviceId, 'custom', 'direct-private', hostnames)))
assert wrongServiceRejected = !endpointEvidencePassed(evidence, '${serviceId}-other', 'custom', 'direct-private', hostnames)
assert wrongPathRejected = !endpointEvidencePassed(evidence, serviceId, 'custom', 'corporate-routed', hostnames)
assert wrongHostnamesRejected = !endpointEvidencePassed(evidence, serviceId, 'custom', 'direct-private', union(hostnames, { gateway: 'other.example.com' }))
assert wrongGateRejected = !endpointEvidencePassed(union(evidence, { validationType: 'dns' }), serviceId, 'custom', 'direct-private', hostnames)
assert wrongCorporateOwnerRejected = !endpointEvidencePassed(union(corporateEvidence, { owner: 'dns-owner' }), serviceId, 'custom', 'corporate-routed', hostnames)
assert missingCorporateApprovalRejected = !endpointEvidencePassed(union(evidence, { endpointAccessPath: 'corporate-routed' }), serviceId, 'custom', 'corporate-routed', hostnames)
assert badCorporateApprovalRejected = empty(filter(invalidStringValues, bad => endpointEvidencePassed(shallowMerge([corporateEvidence, { routingApprovalReference: bad }]), serviceId, 'custom', 'corporate-routed', hostnames)))
assert placeholderReferencesRejected = empty(filter(['<validation-record>', 'placeholder', 'replace-me', 'todo', 'tbd'], value => referenceValid(value)))
assert timestampAliasCannotReplaceRequiredField = !endpointEvidencePassed(union(missingRecords[6], { timestamp: evidence.timestampUtc, validationTimestamp: evidence.timestampUtc }), serviceId, 'custom', 'direct-private', hostnames)
assert numericIsNotString = !nonEmptyStringField({ value: 1 }, 'value')
assert booleanIsNotString = !nonEmptyStringField({ value: true }, 'value')
