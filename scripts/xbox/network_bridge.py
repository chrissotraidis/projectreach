"""HaloPad network policy v1: OpenCE's network version through two host calls.

OpenCE refuses every host whose network version differs from its own, although
its raises have so far been additive. The app (port/ios/HaloPadXboxNetworkPolicy.h)
verifies a signed compatibility policy and answers two questions for the guest:
which version to announce, and whether a host's version may be joined. Without a
policy both answers are upstream's exact rule.

Four sites use the number (OpenCE build 157 to 160): the LAN advertisement, the
join check, and the internet lobby's listing and filter. Each edit is anchored on
the exact upstream statement, and any other use of HALO_PORT_NETWORK_VERSION in
code fails the build: a partial bridge could announce one version and filter by
another.
"""
import pathlib
import re

CLIENT = pathlib.Path('source/networking/network_client_manager.c')
SERVER = pathlib.Path('source/networking/network_server_message_handler.c')
LOBBY = pathlib.Path('port/linux/src/p2p_lobby.c')
IMPORTS = pathlib.Path('port/android/host_imports.list')
LIMITS = pathlib.Path('port/linux/include/halo_port_limits.h')
NAMES = ('host_halopad_network_announce_v1', 'host_halopad_network_accepts_v1')

CLIENT_ANCHOR = b'\ttheirs = network_game_client_advertised_versions[game_index].version;\n'
CLIENT_INSERT = b'''#ifdef HALO_ANDROID
\t/* HaloPad network policy v1: a host version the app's verified policy
\tlists as compatible is joined like this machine's own. */
\t{
\t\textern unsigned int host_halopad_network_accepts_v1(unsigned int, unsigned int);
\t\tif (host_halopad_network_accepts_v1(ours, theirs))
\t\t\tours = theirs;
\t}
#endif
'''
SERVER_ANCHOR = (b'\t\t\tadvertisement.reserved[HALO_PORT_ADVERTISED_VERSION_OFFSET] = (byte)(HALO_PORT_NETWORK_VERSION & 0xFF);\n'
                 b'\t\t\tadvertisement.reserved[HALO_PORT_ADVERTISED_VERSION_OFFSET + 1] = (byte)(HALO_PORT_NETWORK_VERSION >> 8);\n')
SERVER_REPLACE = b'''#ifdef HALO_ANDROID
\t\t\t/* HaloPad network policy v1: the version the app's policy announces */
\t\t\t{
\t\t\t\textern unsigned int host_halopad_network_announce_v1(unsigned int);
\t\t\t\tunsigned int announced = host_halopad_network_announce_v1(HALO_PORT_NETWORK_VERSION);

\t\t\t\tadvertisement.reserved[HALO_PORT_ADVERTISED_VERSION_OFFSET] = (byte)(announced & 0xFF);
\t\t\t\tadvertisement.reserved[HALO_PORT_ADVERTISED_VERSION_OFFSET + 1] = (byte)(announced >> 8);
\t\t\t}
#else
''' + SERVER_ANCHOR + b'#endif\n'
LOBBY_DEFINE_ANCHOR = b'static int listing_make(unsigned char *bytes, int flags)\n'
LOBBY_DEFINE = b'''/* HaloPad network policy v1 (the app's verified compatibility policy) */
#ifdef HALO_ANDROID
unsigned int host_halopad_network_announce_v1(unsigned int);
unsigned int host_halopad_network_accepts_v1(unsigned int, unsigned int);
#define halopad_network_announced() host_halopad_network_announce_v1(HALO_PORT_NETWORK_VERSION)
#define halopad_network_accepts(version) host_halopad_network_accepts_v1(HALO_PORT_NETWORK_VERSION, (version))
#else
#define halopad_network_announced() (HALO_PORT_NETWORK_VERSION)
#define halopad_network_accepts(version) ((version) == HALO_PORT_NETWORK_VERSION)
#endif

'''
LOBBY_LISTING = (b'\tbytes[size++] = (unsigned char)(HALO_PORT_NETWORK_VERSION >> 8);\n'
                 b'\tbytes[size++] = (unsigned char)HALO_PORT_NETWORK_VERSION;\n')
LOBBY_LISTING_REPLACE = (b'\tbytes[size++] = (unsigned char)(halopad_network_announced() >> 8);\n'
                         b'\tbytes[size++] = (unsigned char)halopad_network_announced();\n')
LOBBY_FILTER = b'listing.version != HALO_PORT_NETWORK_VERSION ||'
LOBBY_FILTER_REPLACE = b'!halopad_network_accepts(listing.version) ||'
IMPORT = b''.join(b'\n' + name.encode() for name in NAMES) + b'\n'

# The sites this bridge replaces; every other code use is unreviewed.
KNOWN_USES = {CLIENT: 1, SERVER: 2, LOBBY: 3}
TOKEN = re.compile(rb'\bHALO_PORT_NETWORK_VERSION\b')
COMMENT = re.compile(rb'/\*.*?\*/|//[^\n]*', re.S)


def recipe():
    return b''.join((CLIENT_ANCHOR, CLIENT_INSERT, SERVER_ANCHOR, SERVER_REPLACE, LOBBY_DEFINE_ANCHOR,
                     LOBBY_DEFINE, LOBBY_LISTING, LOBBY_LISTING_REPLACE, LOBBY_FILTER,
                     LOBBY_FILTER_REPLACE, IMPORT))


def code_uses(source):
    return len(TOKEN.findall(COMMENT.sub(b'', source)))


def check_uses(engine):
    """Every code use of the number must be one of the bridged sites."""
    unexpected = []
    for folder in ('source', 'port'):
        for path in sorted((engine / folder).rglob('*')):
            if path.suffix not in ('.c', '.h') or not path.is_file():
                continue
            relative = path.relative_to(engine)
            if relative == LIMITS:
                continue
            count = code_uses(path.read_bytes())
            if count != KNOWN_USES.get(relative, 0):
                unexpected.append(f'{relative} ({count})')
    if unexpected:
        raise ValueError('OpenCE uses its network version in unreviewed places: ' + ', '.join(unexpected) +
                         '; review the network bridge first')


def _replace(original, anchor, replacement, what):
    if original.count(anchor) != 1:
        raise ValueError(f'Network bridge anchor changed ({what}); review upstream first')
    return original.replace(anchor, replacement)


def adapt(path, original):
    if path == IMPORTS:
        if any(name.encode() in original for name in NAMES):
            raise ValueError('Upstream already declares a HaloPad network import; review upstream first')
        return original + IMPORT
    if path == CLIENT:
        return _replace(original, CLIENT_ANCHOR, CLIENT_ANCHOR + CLIENT_INSERT, 'join check')
    if path == SERVER:
        return _replace(original, SERVER_ANCHOR, SERVER_REPLACE, 'LAN advertisement')
    if path == LOBBY:
        result = _replace(original, LOBBY_DEFINE_ANCHOR, LOBBY_DEFINE + LOBBY_DEFINE_ANCHOR, 'lobby helpers')
        result = _replace(result, LOBBY_LISTING, LOBBY_LISTING_REPLACE, 'lobby listing')
        return _replace(result, LOBBY_FILTER, LOBBY_FILTER_REPLACE, 'lobby filter')
    raise ValueError(f'not a network bridge source: {path}')


def changes(engine):
    check_uses(engine)
    result = []
    for path in (CLIENT, SERVER, LOBBY, IMPORTS):
        original = (engine / path).read_bytes()
        result.append((engine / path, original, adapt(path, original)))
    return result
