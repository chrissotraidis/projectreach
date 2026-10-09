/* xg_network_policy.h: HaloPad network policy v1, the host half of
 * scripts/xbox/network_bridge.py. OpenCE joins only hosts of its own network
 * version. A verified compatibility policy (port/ios/HaloPadXboxNetworkPolicy.h)
 * may widen that for this engine's version: announce a newer compatible
 * version, and join hosts in a range that always includes our own. The policy
 * is set before the game starts and only read afterwards. Without one, both
 * answers are upstream's exact rule. */
#ifndef XG_NETWORK_POLICY_H
#define XG_NETWORK_POLICY_H

struct xg_network_policy
{
	unsigned int engine, announce, minimum, maximum;
	int set;
};

/* 1 if the row is usable: minimum <= engine <= announce <= maximum, within
 * OpenCE's 16-bit versions. Anything else clears the policy. */
static inline int xg_network_policy_set(struct xg_network_policy *policy, unsigned int engine,
	unsigned int announce, unsigned int minimum, unsigned int maximum)
{
	int valid = engine >= 1 && maximum <= 0xFFFF && minimum <= engine && engine <= announce &&
		announce <= maximum;
	policy->set = valid;
	policy->engine = valid ? engine : 0;
	policy->announce = valid ? announce : 0;
	policy->minimum = valid ? minimum : 0;
	policy->maximum = valid ? maximum : 0;
	return valid;
}

/* the version to advertise; built_in is the guest's HALO_PORT_NETWORK_VERSION,
 * so a policy for another engine never applies */
static inline unsigned int xg_network_policy_announce(const struct xg_network_policy *policy, unsigned int built_in)
{
	return policy->set && policy->engine == built_in ? policy->announce : built_in;
}

static inline int xg_network_policy_accepts(const struct xg_network_policy *policy, unsigned int built_in,
	unsigned int theirs)
{
	return theirs == built_in || (policy->set && policy->engine == built_in &&
		theirs >= policy->minimum && theirs <= policy->maximum);
}

#endif
