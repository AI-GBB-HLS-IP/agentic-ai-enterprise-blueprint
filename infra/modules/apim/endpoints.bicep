@export()
func endpointMatrixValid(mode string, path string, dnsOwner string) bool => (mode == 'built-in' && path == 'direct-private' && contains(['blueprint', 'external'], dnsOwner)) || (mode == 'custom' && dnsOwner == 'external' && contains(['direct-private', 'corporate-routed'], path))

@export()
func nonEmptyStringField(value object, key string) bool => contains(value, key) && (value[?key] ?? '') == string(value[?key] ?? '') && !empty(trim(string(value[?key] ?? '')))

@export()
func referenceValid(value string) bool => !empty(trim(value)) && !contains(value, '<') && !contains(value, '>') && !contains(toLower(value), 'placeholder') && !contains(toLower(value), 'replace-me') && !contains(['todo', 'tbd'], toLower(trim(value)))

@export()
func dnsLabelValid(label string) bool => length(label) >= 1 && length(label) <= 63 && !startsWith(label, '-') && !endsWith(label, '-') && empty(filter(range(0, length(label)), index => !contains('abcdefghijklmnopqrstuvwxyz0123456789-', substring(label, index, 1))))

@export()
func dnsHostnameValid(host string) bool => length(host) <= 253 && length(split(host, '.')) >= 2 && empty(filter(split(host, '.'), label => !dnsLabelValid(label))) && !empty(filter(range(0, length(host)), index => contains('abcdefghijklmnopqrstuvwxyz', substring(host, index, 1)))) && !endsWith(host, '.azure-api.net')

@export()
func normalizeSelectedHostnames(hostnames object) object => {
  gateway: toLower(trim(string(hostnames.?gateway ?? '')))
  developerPortal: toLower(trim(string(hostnames.?developerPortal ?? '')))
  management: toLower(trim(string(hostnames.?management ?? '')))
}

@export()
func customHostnamesValid(hostnames object) bool => length(items(hostnames)) == 3 && empty(filter(['gateway', 'developerPortal', 'management'], role => !nonEmptyStringField(hostnames, role) || !dnsHostnameValid(toLower(trim(string(hostnames[?role] ?? ''))))))

@export()
func selectedEndpoints(mode string, serviceName string, hostnames object) array => mode == 'custom'
  ? [
      { role: 'gateway', type: 'Proxy', hostname: hostnames.gateway }
      { role: 'developerPortal', type: 'DeveloperPortal', hostname: hostnames.developerPortal }
      { role: 'management', type: 'Management', hostname: hostnames.management }
    ]
  : [
      { role: 'gateway', type: 'Proxy', hostname: '${serviceName}.azure-api.net' }
      { role: 'developerPortal', type: 'DeveloperPortal', hostname: '${serviceName}.developer.azure-api.net' }
      { role: 'legacyPortal', type: 'Portal', hostname: '${serviceName}.portal.azure-api.net' }
      { role: 'management', type: 'Management', hostname: '${serviceName}.management.azure-api.net' }
      { role: 'scm', type: 'Scm', hostname: '${serviceName}.scm.azure-api.net' }
    ]

@export()
func endpointBindingsValid(endpoints array, bindings array) bool => empty(filter(endpoints, endpoint => empty(filter(bindings, binding => toLower(string(binding.?type ?? '')) == toLower(endpoint.type) && toLower(string(binding.?hostName ?? '')) == endpoint.hostname))))

@export()
func endpointEvidenceValid(evidence object, serviceId string, mode string, path string, hostnames object) bool => empty(filter(['validationType', 'status', 'owner', 'scope', 'approvalReference', 'evidenceSummary', 'timestampUtc', 'apimServiceId', 'endpointMode', 'endpointAccessPath', 'validationReference'], key => !nonEmptyStringField(evidence, key))) && (evidence.?validationType ?? '') == 'apim-endpoint-access' && contains(['pass', 'fail', 'blocked'], evidence.?status ?? '') && toLower(string(evidence.?apimServiceId ?? '')) == toLower(serviceId) && (evidence.?endpointMode ?? '') == mode && (evidence.?endpointAccessPath ?? '') == path && (evidence.?selectedHostnames ?? {}) == hostnames && referenceValid(string(evidence.?validationReference ?? '')) && (path != 'corporate-routed' || ((evidence.?owner ?? '') == 'network-owner' && nonEmptyStringField(evidence, 'routingApprovalReference') && referenceValid(string(evidence.?routingApprovalReference ?? ''))))

@export()
func endpointEvidencePassed(evidence object, serviceId string, mode string, path string, hostnames object) bool => endpointEvidenceValid(evidence, serviceId, mode, path, hostnames) && (evidence.?status ?? '') == 'pass'

@export()
func endpointHandoffValid(handoff object, serviceId string, mode string, path string, hostnames object, endpoints array) bool => empty(handoff) ? (mode == 'built-in' && path == 'direct-private') : (toLower(string(handoff.?apimServiceId ?? '')) == toLower(serviceId) && (handoff.?endpointMode ?? '') == mode && (handoff.?endpointAccessPath ?? '') == path && (handoff.?selectedHostnames ?? {}) == hostnames && (handoff.?endpoints ?? []) == endpoints && (handoff.?selectedGatewayHostname ?? '') == endpoints[0].hostname && (handoff.?selectedGatewayUrl ?? '') == 'https://${endpoints[0].hostname}' && (handoff.?excludedClientChecks ?? []) == (mode == 'custom' ? ['legacyPortal', 'scm'] : []) && (mode != 'custom' || endpointEvidencePassed(handoff.?endpointValidationEvidence ?? {}, serviceId, mode, path, hostnames)))
