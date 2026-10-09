"""Validate explicit app update identities before building or replacing output."""
import argparse
import re


def validate(version, build):
    # Preserve the historical two-component development version; release
    # invocations should use three components (for example 0.3.8).
    if not isinstance(version, str) or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?', version):
        raise ValueError('app version must contain two or three decimal components (for example 0.3.8)')
    if not isinstance(build, str) or not re.fullmatch(r'[1-9][0-9]{0,3}', build):
        raise ValueError('app build must be an integer from 1 to 9999')
    return version, build


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    args = parser.parse_args()
    try:
        validate(args.version, args.build)
    except ValueError as error:
        parser.error(str(error))
