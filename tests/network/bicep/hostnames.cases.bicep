import { resolveHostnames, retainExistingHostnames, expandDeclaredHostnames, countDefaultSslBindings, existingHostnamesMissing } from '../../../infra/modules/apim/hostnames.bicep'

var existing = [
  { type: 'Proxy', hostName: 'old.example.com', keyVaultId: 'kv1', defaultSslBinding: true }
  { type: 'Management', hostName: 'mgmt-old.example.com', keyVaultId: 'kv2' }
  { type: 'DeveloperPortal', hostName: 'portal.example.com', keyVaultId: 'kv3' }
]
var certs = {
  gw: { encodedCertificate: 'AAA', certificatePassword: 'p' }
  mg: { encodedCertificate: 'BBB', certificatePassword: 'q' }
}

var gatewayDefault = { type: 'Proxy', hostName: 'api.example.com', certificateKey: 'gw', defaultSslBinding: true }
var gatewayDefaultExpanded = {
  type: 'Proxy'
  hostName: 'api.example.com'
  defaultSslBinding: true
  negotiateClientCertificate: false
  encodedCertificate: 'AAA'
  certificatePassword: 'p'
}

assert expandInjectsCertificateAndDefaults = expandDeclaredHostnames([gatewayDefault], certs) == [gatewayDefaultExpanded]
assert expandKeepsKeyVaultId = expandDeclaredHostnames([{ type: 'Scm', hostName: 's.example.com', keyVaultId: 'kv9' }], certs) == [
  { type: 'Scm', hostName: 's.example.com', defaultSslBinding: false, negotiateClientCertificate: false, keyVaultId: 'kv9' }
]

// preserve: existing only, declared input is ignored
assert preserveReturnsExistingOnly = resolveHostnames('preserve', existing, [gatewayDefault], certs) == existing
assert preserveWithNoExistingIsEmpty = resolveHostnames('preserve', [], [], {}) == []

// replace: declared only; an empty declaration removes everything
assert replaceReturnsDeclaredOnly = resolveHostnames('replace', existing, [gatewayDefault], certs) == [gatewayDefaultExpanded]
assert replaceEmptyRemovesAll = resolveHostnames('replace', existing, [], {}) == []

// merge: declared Proxy claims the default, so the retained Proxy is demoted
assert mergeDemotesRetainedDefaultBinding = resolveHostnames('merge', existing, [gatewayDefault], certs) == [
  { type: 'Proxy', hostName: 'old.example.com', keyVaultId: 'kv1', defaultSslBinding: false }
  { type: 'Management', hostName: 'mgmt-old.example.com', keyVaultId: 'kv2' }
  { type: 'DeveloperPortal', hostName: 'portal.example.com', keyVaultId: 'kv3' }
  gatewayDefaultExpanded
]

// merge: a declared Proxy without the default leaves the retained default untouched
assert mergeKeepsRetainedDefaultWhenNotClaimed = retainExistingHostnames(
  existing,
  expandDeclaredHostnames([{ type: 'Proxy', hostName: 'extra.example.com', certificateKey: 'gw' }], certs)
)[0] == existing[0]

// merge: same type and hostName matches case-insensitively, so the declared entry wins
assert mergeReplacesSameHostnameCaseInsensitively = resolveHostnames('merge', existing, [{ type: 'Proxy', hostName: 'OLD.Example.com', certificateKey: 'gw' }], certs) == [
  { type: 'Management', hostName: 'mgmt-old.example.com', keyVaultId: 'kv2' }
  { type: 'DeveloperPortal', hostName: 'portal.example.com', keyVaultId: 'kv3' }
  { type: 'Proxy', hostName: 'OLD.Example.com', defaultSslBinding: false, negotiateClientCertificate: false, encodedCertificate: 'AAA', certificatePassword: 'p' }
]

// merge: a declared non-Proxy type supersedes the retained entry of that type (APIM allows one per type)
assert mergeNonProxyTypeReplacesRetainedType = resolveHostnames('merge', existing, [{ type: 'Management', hostName: 'mgmt-new.example.com', certificateKey: 'mg' }], certs) == [
  { type: 'Proxy', hostName: 'old.example.com', keyVaultId: 'kv1', defaultSslBinding: true }
  { type: 'DeveloperPortal', hostName: 'portal.example.com', keyVaultId: 'kv3' }
  { type: 'Management', hostName: 'mgmt-new.example.com', defaultSslBinding: false, negotiateClientCertificate: false, encodedCertificate: 'BBB', certificatePassword: 'q' }
]

// merge with nothing declared behaves like preserve
assert mergeWithNothingDeclaredKeepsExisting = resolveHostnames('merge', existing, [], {}) == existing

// default-binding rejection predicate: one default is fine, two Proxy defaults are rejected by main.bicep
assert oneDefaultBindingAccepted = countDefaultSslBindings(resolveHostnames('merge', existing, [gatewayDefault], certs)) == 1
assert twoDeclaredDefaultsCounted = countDefaultSslBindings(resolveHostnames('replace', [], [
  gatewayDefault
  { type: 'Proxy', hostName: 'api2.example.com', certificateKey: 'gw', defaultSslBinding: true }
], certs)) == 2
assert preserveCanCarryTwoDefaultsAndIsCounted = countDefaultSslBindings([
  { type: 'Proxy', hostName: 'a.example.com', defaultSslBinding: true }
  { type: 'Proxy', hostName: 'b.example.com', defaultSslBinding: true }
]) == 2

// fail-closed guard: preserve and merge require the captured JSON, replace does not, an explicit [] counts as provided
assert preserveRequiresCapture = existingHostnamesMissing('preserve', '')
assert mergeRequiresCapture = existingHostnamesMissing('merge', '   ')
assert replaceDoesNotRequireCapture = !existingHostnamesMissing('replace', '')
assert explicitEmptyArrayAccepted = !existingHostnamesMissing('preserve', '[]')
assert capturedListAccepted = !existingHostnamesMissing('merge', '[{"type":"Proxy"}]')
