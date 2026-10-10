// Pure helpers for APIM custom-domain (hostnameConfigurations) handling.
// Imported by main.bicep and exercised by tests/network/bicep/hostnames.tests.bicep.

@export()
@description('Expands declared entries: defaults flags and merges the PFX material referenced by certificateKey.')
func expandDeclaredHostnames(declared array, certificates object) array => map(declared, d => union(
  {
    type: d.type
    hostName: d.hostName
    defaultSslBinding: d.?defaultSslBinding ?? false
    negotiateClientCertificate: d.?negotiateClientCertificate ?? false
  },
  contains(d, 'keyVaultId') ? { keyVaultId: d.keyVaultId } : {},
  contains(d, 'certificateKey') ? certificates[d.certificateKey] : {}
))

@export()
@description('Existing entries that survive a merge: not redeclared (same type and hostName, case-insensitive), not superseded by a declared non-Proxy type, and demoted from the default SSL binding when a declared Proxy claims it.')
func retainExistingHostnames(existing array, expandedDeclared array) array => map(
  filter(existing, e => !contains(
    map(expandedDeclared, d => toLower('${d.type}|${d.hostName}')),
    toLower('${e.type}|${e.hostName}')
  ) && !contains(
    map(filter(expandedDeclared, d => d.type != 'Proxy'), d => d.type),
    e.type
  )),
  e => !empty(filter(expandedDeclared, d => d.type == 'Proxy' && d.defaultSslBinding)) && e.type == 'Proxy'
    ? union(e, { defaultSslBinding: false })
    : e
)

@export()
@description('Effective hostnameConfigurations for the given mode: preserve = existing only, merge = retained existing plus declared, replace = declared only.')
func resolveHostnames(mode string, existing array, declared array, certificates object) array => mode == 'preserve'
  ? existing
  : mode == 'merge'
    ? concat(retainExistingHostnames(existing, expandDeclaredHostnames(declared, certificates)), expandDeclaredHostnames(declared, certificates))
    : expandDeclaredHostnames(declared, certificates)

@export()
@description('Number of Proxy entries that set defaultSslBinding; APIM accepts at most one.')
func countDefaultSslBindings(hostnames array) int => length(filter(hostnames, h => h.type == 'Proxy' && (h.?defaultSslBinding ?? false)))

@export()
@description('True when preserve/merge mode lacks the captured existing-hostnames JSON (replace never needs it). An explicit empty array counts as provided.')
func existingHostnamesMissing(mode string, existingJson string) bool => mode != 'replace' && empty(trim(existingJson))
