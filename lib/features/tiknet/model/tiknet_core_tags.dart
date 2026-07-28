/// Outbound tags that hiddify-core generates for every profile.
///
/// The core discards the profile's own selector and rebuilds the outbound tree
/// around these, so they are the only names it recognises at runtime.
library;

/// The selector the core builds (`OutboundSelectTag` in the Go source). Passing
/// any other group tag to `SelectOutbound` fails with "selector not found",
/// which leaves the user's pick unapplied.
const kCoreSelectorTag = 'select';

/// Round-robin balancer the core installs as `selector.default`. It spreads
/// traffic over every outbound in the profile, dead ones included.
const kCoreBalanceTag = 'balance';

/// Lowest-delay balancer the core generates alongside [kCoreBalanceTag].
const kCoreLowestTag = 'lowest';
