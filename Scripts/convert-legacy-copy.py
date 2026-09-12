#!/usr/bin/env python3
"""Create a separate experimental .screenplay copy, or verify one already created."""
import argparse
import json
import sys

sys.dont_write_bytecode = True
from legacy_copy import CopyFailure, read_copy, write_copy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    convert = commands.add_parser('convert')
    convert.add_argument('source')
    convert.add_argument('destination')
    verify = commands.add_parser('verify')
    verify.add_argument('package')
    args = parser.parse_args()
    try:
        result = write_copy(args.source, args.destination) if args.command == 'convert' else read_copy(args.package)
        print(json.dumps(result, indent=2))
        return 0
    except CopyFailure as error:
        print(json.dumps({'success': False, 'phase': error.phase, 'retained_path': error.recovery_path,
                          'published': error.published, 'cause': error.cause,
                          'message': 'Retained output may be incomplete. Verify it before use; the source was not written.'}), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, ImportError) as error:
        print(json.dumps({'success': False, 'cause': type(error).__name__,
                          'message': 'Input or destination could not be validated; no success is claimed.'}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
