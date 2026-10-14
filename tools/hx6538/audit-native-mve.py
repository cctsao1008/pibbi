#!/usr/bin/env python3
"""Read-only native MVE opcode audit of GNU objdump text (Python 3.8+).

Optional LLVM/Clang cross-decoding reconstructs only the original instruction
halfwords in a temporary object. No firmware build, flash or device I/O.
"""
import argparse
import collections
import hashlib
import json
import pathlib
import re
import subprocess
import tempfile

INSN = re.compile(r'^\\s*([0-9a-fA-F]{8}):\\s+((?:[0-9a-fA-F]{4,8}\\s+){1,2})\\s+([A-Za-z][A-Za-z0-9.]*)\\s*(.*)$')
QREG = re.compile(r'(?<![A-Za-z0-9])q[0-7](?!\\d)', re.I)
SUSPECT = {'cdp', 'cdp2', 'ldc', 'ldc2', 'stc', 'stc2'}


def parse(text, start, end):
    rows = []
    for line in text.splitlines():
        m = INSN.match(line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        if not start <= addr < end:
            continue
        words = m.group(2).split()
        if not (len(words) == 1 and len(words[0]) == 4 or
                len(words) == 2 and all(len(x) == 4 for x in words)):
            raise ValueError('Unexpected opcode halfwords: ' + line)
        rows.append({'address': addr, 'halfwords': words,
                     'gnu_op': m.group(3).lower(),
                     'gnu_args': m.group(4).split('@')[0].strip()})
    if not rows or rows[0]['address'] != start:
        raise ValueError('Missing kernel start 0x{:08X}'.format(start))
    return rows


def decode(candidates, clang, llvm):
    source = ['.syntax unified', '.thumb', '.text']
    for index, item in enumerate(candidates):
        source.extend(['.global mve_{}'.format(index),
                       '.type mve_{},%function'.format(index),
                       '.thumb_func', 'mve_{}:'.format(index)])
        source.extend('.hword 0x' + x for x in item['halfwords'])
        source.append('.hword 0xbf00')
    with tempfile.TemporaryDirectory(prefix='pibbi-mve-') as tmp:
        s = pathlib.Path(tmp) / 'decode.s'
        o = pathlib.Path(tmp) / 'decode.o'
        s.write_text('\\n'.join(source) + '\\n', encoding='ascii')
        subprocess.run([clang, '-target', 'thumbv8.1m.main-none-eabi',
                        '-march=armv8.1-m.main+mve.fp', '-mfloat-abi=hard',
                        '-c', str(s), '-o', str(o)], check=True,
                       capture_output=True, text=True)
        run = subprocess.run([llvm, '-d', '--triple=thumbv8.1m.main-none-eabi',
                              '--mattr=+mve,+mve.fp', str(o)], check=True,
                             capture_output=True, text=True)
    seen = {}
    lines = run.stdout.splitlines()
    for i, line in enumerate(lines):
        found = re.search(r'<mve_(\\d+)>:', line)
        if not found:
            continue
        index = int(found.group(1))
        if i + 1 >= len(lines):
            raise ValueError('Missing LLVM decode line')
        opcode = re.match(r'^\\s*[0-9a-f]+:\\s+(?:[0-9a-f]{4}\\s+){1,2}\\s*([a-z][a-z0-9.]*)\\s*(.*)$', lines[i + 1])
        if not opcode or not opcode.group(1).startswith('v'):
            raise ValueError('Non-MVE cross-decode at index {}'.format(index))
        seen[index] = (opcode.group(1), opcode.group(2))
    if len(seen) != len(candidates):
        raise ValueError('LLVM decode incomplete: {}/{}'.format(len(seen), len(candidates)))
    for index, item in enumerate(candidates):
        item['llvm_op'], item['llvm_args'] = seen[index]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--disassembly', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--start', type=lambda s: int(s, 0), default=0x1001A4C8)
    parser.add_argument('--end', type=lambda s: int(s, 0), default=0x1001AA60)
    parser.add_argument('--clang', help='Optional MVE-capable clang executable')
    parser.add_argument('--llvm-objdump', help='Optional matching llvm-objdump')
    args = parser.parse_args()
    if bool(args.clang) != bool(args.llvm_objdump):
        parser.error('Both --clang and --llvm-objdump are required for cross-decoding')
    source = pathlib.Path(args.disassembly)
    raw = source.read_bytes()
    rows = parse(raw.decode('utf-8', errors='replace'), args.start, args.end)
    candidates = [x for x in rows if x['gnu_op'] in SUSPECT]
    if args.clang:
        decode(candidates, args.clang, args.llvm_objdump)
    resolved = [x for x in candidates if 'llvm_op' in x]
    q_count = sum(bool(QREG.search(x['gnu_args'])) for x in rows)
    report = {
        'scope': 'read-only static Native disassembly, not a runtime benchmark',
        'original_text_sha256': hashlib.sha256(raw).hexdigest(),
        'kernel_start': '0x{:08X}'.format(args.start),
        'kernel_end_exclusive': '0x{:08X}'.format(args.end),
        'instruction_lines': len(rows),
        'explicit_q_register_instruction_sites': q_count,
        'gnu_coprocessor_renderings': len(candidates),
        'cross_decoded_mve_instruction_sites': len(resolved),
        'identified_vector_instruction_sites_lower_bound': q_count + len(resolved),
        'cross_decoded_mnemonics': dict(sorted(collections.Counter(
            x['llvm_op'] for x in resolved).items())),
        'low_overhead_loops': [
            {'address': '0x{:08X}'.format(x['address']), 'op': x['gnu_op']}
            for x in rows if x['gnu_op'] in ('dls', 'le')],
        'predicated_tail_instructions': [
            {'address': '0x{:08X}'.format(x['address']), 'op': x['gnu_op']}
            for x in rows if x['gnu_op'].startswith(('vctp', 'vpst', 'vpt'))],
        'cross_decoded_sites': [
            {'address': '0x{:08X}'.format(x['address']),
             'halfwords': ' '.join(x['halfwords']),
             'gnu': x['gnu_op'] + ' ' + x['gnu_args'],
             'llvm': x.get('llvm_op', 'UNRESOLVED') + ' ' + x.get('llvm_args', '')}
            for x in candidates],
        'limits': [
            'This tool reconstructs halfwords from objdump text, not an independent original ELF byte dump.',
            'Count is of static sites, not executed dynamic instruction count or cycles.',
            'With no optional LLVM tools, coprocessor-rendered MVE sites remain unresolved.',
            'Actual Watcher boot, memory safety, MVE speedup and NPU throughput remain unverified.',
        ],
    }
    dest = pathlib.Path(args.output)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(report, indent=2) + '\\n', encoding='utf-8')
    print('Explicit Q {}, GNU candidates {}, LLVM decoded {}, identified lower bound {}'.format(
        q_count, len(candidates), len(resolved), q_count + len(resolved)))
    print('Report:', dest)


if __name__ == '__main__':
    main()
