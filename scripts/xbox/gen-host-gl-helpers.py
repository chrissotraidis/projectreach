#!/usr/bin/env python3
"""Reuse new upstream GL helpers behind the documented scalar/guest-pointer ABI.

Keep HaloPad's existing overrides. New portable helpers are compiled from the
selected upstream source, not reimplemented here. Reject unsupported signatures.
"""
import argparse
from pathlib import Path
import re

TOKENS = re.compile(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)
SCALAR = {'int': 'int32_t', 'unsigned int': 'uint32_t',
          'long long': 'int64_t', 'unsigned long long': 'uint64_t'}
POINTER = re.compile(r'(?:const )?(?:void|char|unsigned char|int|unsigned int|long long|unsigned long long)\*')
PROTOTYPE = re.compile(r'^([\w \t*]+?)\b(host_gl_\w+)\s*\(([^;{}]*)\)\s*;', re.M)
DEFINITION = r'(?m)^[\w \t*]+\b%s(host_gl_\w+)\s*\([^;{}]*\)\s*\{'


def code_only(source):
    # Preserve offsets while hiding braces and function names in comments/strings.
    return TOKENS.sub(lambda m: re.sub(r'[^\n]', ' ', m.group()), source)


def function_source(source, name):
    masked = code_only(source)
    for match in re.finditer(DEFINITION % '', masked):
        if match[1] == name:
            start, depth = match.end() - 1, 0
            for end in range(start, len(masked)):
                depth += (masked[end] == '{') - (masked[end] == '}')
                if depth == 0:
                    body = masked[start + 1:end]
                    if re.search(r'\b(?:static|extern|host_\w+)\b|^\s*#', body, re.M):
                        raise ValueError(f'{name}: stateful or dependent helper needs an explicit implementation')
                    return source[match.start():end + 1]
    raise ValueError(f'{name}: incomplete implementation')


def generate(source, header, imports, implemented):
    required = {s.strip() for s in code_only(imports).splitlines() if s.strip().startswith('host_gl_')}
    overrides = set(re.findall(DEFINITION % 'xh_', code_only(implemented)))
    missing = sorted(required - overrides)
    if not missing:
        return '/* All upstream GL helpers have HaloPad overrides. */\n'
    declarations = {name: (ret.strip(), params.strip())
                    for ret, name, params in PROTOTYPE.findall(code_only(header))}
    definitions = set(re.findall(DEFINITION % '', code_only(source)))
    wrappers, bodies = [], []
    for name in missing:
        if name not in declarations or name not in definitions:
            raise ValueError(f'{name}: no portable implementation and guest declaration')
        bodies.append(function_source(source, name))
        ret, params = declarations[name]
        if ret != 'void' and ret not in SCALAR:
            raise ValueError(f'{name}: unsupported return type {ret}')
        args, calls = [], []
        for index, param in enumerate([] if params in ('', 'void') else params.split(',')):
            match = re.fullmatch(r'(.+?[\s*])([A-Za-z_]\w*)', param.strip())
            if not match or index >= 8:
                raise ValueError(f'{name}: unsupported parameter {param}')
            kind = re.sub(r'\s*\*\s*', '*', ' '.join(match[1].split()))
            if kind in SCALAR:
                args.append(f'{SCALAR[kind]} a{index}')
                calls.append(f'a{index}')
            elif POINTER.fullmatch(kind):
                args.append(f'uint32_t a{index}')
                calls.append(f'({kind})GP(a{index})')
            else:
                raise ValueError(f'{name}: unsupported parameter type {kind}')
        wrappers.append(f'{SCALAR.get(ret, ret)} xh_{name}({", ".join(args) or "void"})\n'
                        '{\n\t' + ('' if ret == 'void' else 'return ') +
                        f'hp_upstream_{name}({", ".join(calls)});\n}}\n')
    # Compile only the new functions. Do not copy upstream's globals or existing
    # helpers: that could create separate state from HaloPad's overrides. An
    # undeclared dependency fails compilation instead of silently diverging.
    source = '\n'.join(bodies)
    lines = ['/* Generated from the selected upstream GL helper source. */',
             '#include "xg_host.h"', '#include <GLES3/gl32.h>', '#include <string.h>',
             'void *xg_gl_proc(const char *name);']
    for name in sorted(set(re.findall(r'\b(gl[A-Z]\w*)\s*\(', code_only(source)))):
        kind = f'PFN{name.upper()}PROC'
        lines += [f'static {kind} hp_proc_{name}(void) {{', f'\tstatic {kind} p;',
                  f'\tif (!p) p = ({kind})xg_gl_proc("{name}");',
                  f'\tif (!p) xg_fatal("Missing GL helper function: {name}");',
                  '\treturn p;', '}', f'#define {name} hp_proc_{name}()']
    lines += [f'#define {name} hp_upstream_{name}' for name in missing]
    return '\n'.join(lines) + '\n' + source + '\n' + '\n'.join(wrappers)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'header', 'imports', 'implemented', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        output = generate(*(getattr(args, name).read_text() for name in
                            ('source', 'header', 'imports', 'implemented')))
        args.out.write_text(output)
    except (OSError, ValueError) as error:
        parser.exit(1, f'GL helper ABI check failed: {error}\n')


if __name__ == '__main__':
    main()
