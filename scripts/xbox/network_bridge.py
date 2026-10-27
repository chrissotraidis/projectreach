"""HaloPad network policy v1: OpenCE's network version through two host calls.

OpenCE refuses every host whose network version differs from its own. The app
(port/ios/HaloPadXboxNetworkPolicy.h)
verifies a signed compatibility policy and answers two questions for the guest:
which version to announce, and whether a host's version may be joined. Without a
policy both answers are upstream's exact rule.

Four sites use the number (OpenCE build 157 to 160): the LAN advertisement, the
join check, and the internet lobby's listing and filter. Each edit is anchored on
the exact upstream statement, and any other use of HALO_PORT_NETWORK_VERSION in
code fails the build: a partial bridge could announce one version and filter by
another.

Build244 also counts newer games to explain an empty browser. Its extra check
uses the same policy as the filter, so an accepted game is not hidden first.
Build294 adds browser sorting, labels and a join gate, and separates the
client's rejection explanation. Dedicated-server diagnostics are compiled out
of the Android guest; their exact sources and compile guard are checked below.
"""
import hashlib
import pathlib
import re

CLIENT = pathlib.Path('source/networking/network_client_manager.c')
SERVER = pathlib.Path('source/networking/network_server_message_handler.c')
LOBBY = pathlib.Path('port/linux/src/p2p_lobby.c')
IMPORTS = pathlib.Path('port/android/host_imports.list')
LIMITS = pathlib.Path('port/linux/include/halo_port_limits.h')
MENU = pathlib.Path('port/linux/game/menu_functions.c')
SERVER_MODE_HEADER = pathlib.Path('port/linux/src/server_mode.h')
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
LOBBY_NEWER = b'listing.version > HALO_PORT_NETWORK_VERSION && !(listing.flags & _listing_closed)'
LOBBY_NEWER_REPLACE = (b'listing.version > halopad_network_announced() && '
                       b'!halopad_network_accepts(listing.version) && !(listing.flags & _listing_closed)')
IMPORT = b''.join(b'\n' + name.encode() for name in NAMES) + b'\n'

# Build294 keeps listing_make as a wrapper: the helpers must precede the
# token-taking function that now writes the advertised version.
LOBBY_TOKEN_DEFINE = b'static int listing_make_token(unsigned char *bytes, int flags, const unsigned char *token)\n'
CLIENT_TELL = (b'void network_game_client_tell_version(\n\tunsigned int theirs,\n\tboolean distributed)\n'
               b'{\n\tunsigned int ours = HALO_PORT_NETWORK_VERSION;\n\tchar message[400];\n')
LOBBY_SORT_EDITS = (
    (b'\t\tint other_version = game.network_version != HALO_PORT_NETWORK_VERSION;\n',
     b'\t\tint other_version = !halopad_network_accepts(game.network_version);\n'),
    (b'\t\t\tint before_other = before->network_version != HALO_PORT_NETWORK_VERSION;\n',
     b'\t\t\tint before_other = !halopad_network_accepts(before->network_version);\n'),
)
MENU_DEFINE = b'static void lobby_browser_game_lines(struct p2p_listing const *game, wchar_t *players, wchar_t *rules, short size)\n'
MENU_EDITS = (
    (b'\trules[0] = 0;\n\tif (game->network_version != HALO_PORT_NETWORK_VERSION)\n',
     b'\trules[0] = 0;\n\tif (!halopad_network_accepts(game->network_version))\n'),
    (b'\t\ttext_append_word(rules, size, game->network_version > HALO_PORT_NETWORK_VERSION ?\n',
     b'\t\ttext_append_word(rules, size, game->network_version > halopad_network_announced() ?\n'),
    (b'\t\tother_version = game->network_version != HALO_PORT_NETWORK_VERSION;\n',
     b'\t\tother_version = !halopad_network_accepts(game->network_version);\n'),
    (b'\t\t\tbrowser_word(game->network_version > HALO_PORT_NETWORK_VERSION ? _browser_word_newer : _browser_word_older,\n',
     b'\t\t\tbrowser_word(game->network_version > halopad_network_announced() ? _browser_word_newer : _browser_word_older,\n'),
    (b'\tgame = &lobby_browser.games[index];\n\tif (game->network_version != HALO_PORT_NETWORK_VERSION)\n',
     b'\tgame = &lobby_browser.games[index];\n\tif (!halopad_network_accepts(game->network_version))\n'),
)
# These eight uses only print the actual dedicated-server build in CLI/log/API
# diagnostics. Every one is inside HALO_SERVER_BUILD, which server_mode.h sets
# to zero for HALO_ANDROID. Hash the exact reviewed files, not a server_* glob
# or a count-only exemption: moving a use outside the guard must fail too.
SERVER_ONLY = {
    pathlib.Path('port/linux/game/server_commands.c'): (2, '7e01419aeadf2f1c41182bb765b72aef067f5375a3b80f950c5087c7b5444ee3'),
    pathlib.Path('port/linux/game/server_director.c'): (1, '686d440fc91d11d066ad6bf5d09da5003f6679b41d7b21bd1024e44781ef1b33'),
    pathlib.Path('port/linux/game/server_status.c'): (1, 'ee3885dc1202b0c122e2dd6c80e13b4a67039d11d4ca0e5231cb80071d5d0d8e'),
    pathlib.Path('port/linux/src/server_http.c'): (2, 'b37c6e1c100aae6840c04cde2920754343db960ef2539f43e760fdae3fa4763f'),
    pathlib.Path('port/linux/src/server_mode.c'): (2, 'af057778225a8bd7a12f24b608f7f5bcd8aaea3aa11be62da0ba49f9380d9f43'),
}
SERVER_MODE_SHA256 = 'ea40953710a15a62166310462e28278a4168416bc48f6515bb554faeccaea429'

# Historical live sites; 294 also has the exact reviewed cases above.
KNOWN_USES = {CLIENT: 1, SERVER: 2, LOBBY: 3}
TOKEN = re.compile(rb'\bHALO_PORT_NETWORK_VERSION\b')
COMMENT = re.compile(rb'/\*.*?\*/|//[^\n]*', re.S)


def recipe(newer=False, browser=False):
    original = b''.join((CLIENT_ANCHOR, CLIENT_INSERT, SERVER_ANCHOR, SERVER_REPLACE, LOBBY_DEFINE_ANCHOR,
                     LOBBY_DEFINE, LOBBY_LISTING, LOBBY_LISTING_REPLACE, LOBBY_FILTER,
                     LOBBY_FILTER_REPLACE, IMPORT))
    if newer or browser:
        original += LOBBY_NEWER + LOBBY_NEWER_REPLACE
    if browser:
        original += LOBBY_TOKEN_DEFINE + CLIENT_TELL + CLIENT_INSERT + MENU_DEFINE + LOBBY_DEFINE
        original += b''.join(before + after for before, after in (*LOBBY_SORT_EDITS, *MENU_EDITS))
        original += str(SERVER_MODE_HEADER).encode() + SERVER_MODE_SHA256.encode()
        original += b''.join(str(path).encode() + str(count).encode() + digest.encode()
                             for path, (count, digest) in sorted(SERVER_ONLY.items()))
    return original


def code_uses(source):
    return len(TOKEN.findall(COMMENT.sub(b'', source)))


def check_uses(engine):
    """Every use must be bridged or in an exact reviewed server-only source."""
    unexpected = []
    browser = LOBBY_TOKEN_DEFINE in (engine / LOBBY).read_bytes()
    known = dict(KNOWN_USES)
    if browser:
        known.update({CLIENT: 2, LOBBY: 6, MENU: 5})
        known.update({path: count for path, (count, _) in SERVER_ONLY.items()})
        for path, expected in ((SERVER_MODE_HEADER, SERVER_MODE_SHA256),
                               *((path, digest) for path, (_, digest) in SERVER_ONLY.items())):
            if not (engine / path).is_file() or hashlib.sha256((engine / path).read_bytes()).hexdigest() != expected:
                unexpected.append(f'{path} (unreviewed dedicated-server source/guard)')
    for folder in ('source', 'port'):
        for path in sorted((engine / folder).rglob('*')):
            if path.suffix not in ('.c', '.h') or not path.is_file():
                continue
            relative = path.relative_to(engine)
            if relative == LIMITS:
                continue
            source = path.read_bytes()
            count = code_uses(source)
            expected = known.get(relative, 0)
            if not browser and relative == LOBBY and source.count(LOBBY_NEWER) == 1:
                expected += 1
            if count != expected:
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
        result = _replace(original, CLIENT_ANCHOR, CLIENT_ANCHOR + CLIENT_INSERT, 'join check')
        if code_uses(original) == 2:
            result = _replace(result, CLIENT_TELL, CLIENT_TELL + CLIENT_INSERT, 'join rejection explanation')
        return result
    if path == SERVER:
        return _replace(original, SERVER_ANCHOR, SERVER_REPLACE, 'LAN advertisement')
    if path == LOBBY:
        browser = LOBBY_TOKEN_DEFINE in original
        define = LOBBY_TOKEN_DEFINE if browser else LOBBY_DEFINE_ANCHOR
        result = _replace(original, define, LOBBY_DEFINE + define, 'lobby helpers')
        result = _replace(result, LOBBY_LISTING, LOBBY_LISTING_REPLACE, 'lobby listing')
        if browser or LOBBY_NEWER in result:
            result = _replace(result, LOBBY_NEWER, LOBBY_NEWER_REPLACE, 'newer-game count')
        result = _replace(result, LOBBY_FILTER, LOBBY_FILTER_REPLACE, 'lobby filter')
        if browser:
            for before, after in LOBBY_SORT_EDITS:
                result = _replace(result, before, after, 'lobby compatibility sort')
        return result
    if path == MENU:
        result = _replace(original, MENU_DEFINE, LOBBY_DEFINE + MENU_DEFINE, 'browser helpers')
        for before, after in MENU_EDITS:
            result = _replace(result, before, after, 'browser compatibility display/join')
        return result
    raise ValueError(f'not a network bridge source: {path}')


def changes(engine):
    check_uses(engine)
    result = []
    browser = LOBBY_TOKEN_DEFINE in (engine / LOBBY).read_bytes()
    for path in (CLIENT, SERVER, LOBBY, IMPORTS, *((MENU,) if browser else ())):
        original = (engine / path).read_bytes()
        result.append((engine / path, original, adapt(path, original)))
    return result
