"""Compile the real PTQ1 kernel and inspect its PDL dependency ordering."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def kernel_bodies(ptx):
    for entry in re.finditer(r'\.entry\s+(\S*mul_mat_vec_ptq1_0_pt\S*)\s*\(', ptx):
        start = ptx.index('{', entry.end())
        depth = 1
        end = start + 1
        while depth:
            depth += (ptx[end] == '{') - (ptx[end] == '}')
            end += 1
        yield entry.group(1), ptx[start:end]


def check(ptx, needs_wait):
    kernels = list(kernel_bodies(ptx))
    if len(kernels) != 24:
        raise AssertionError(f'Expected 24 PTQ1 kernel variants, found {len(kernels)}')
    for name, body in kernels:
        waits = list(re.finditer(r'griddepcontrol\.wait\s*;', body))
        if not needs_wait:
            assert not waits, f'{name}: unexpected PDL wait on Ada'
            continue
        assert len(waits) == 1, f'{name}: expected one PDL wait'
        loads = list(re.finditer(r'\bld\.global[.\s]', body))
        assert loads, f'{name}: no global loads found; cannot verify ordering'
        assert waits[0].start() < loads[0].start(), f'{name}: global load precedes PDL wait'
        prefix = body[:waits[0].start()]
        assert not re.search(r'\b(?:bra|ret|exit)\b', prefix), f'{name}: control flow before wait'
    return len(kernels)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--arch', required=True, choices=['89', '90', '120a'])
    args = parser.parse_args()
    source = args.source.resolve()
    header = source / 'ggml/src/ggml-cuda/mmvq-ptq1_0.cuh'
    original = header.read_text(encoding='utf-8-sig')
    assert original.count('ggml_cuda_pdl_sync();') == 1
    with tempfile.TemporaryDirectory(prefix='bonsai-pdl-') as directory:
        work = Path(directory)
        probe = work / 'probe.cu'
        declarations = ['#include "mmvq-ptq1_0.cuh"']
        for columns in range(1, 9):
            rows = 4 if columns <= 4 else 2
            for fusion, gate in [('false', 'false'), ('true', 'false'), ('true', 'true')]:
                declarations.append(f'''template __global__ void mul_mat_vec_ptq1_0_pt<{columns}, {rows}, {fusion}, {gate}>(
    const void *, const void *, const ggml_cuda_mm_fusion_args_device, float *,
    const int, const int, const int, const int, const int, const int, const uint3, const uint3);''')
        probe.write_text('\n'.join(declarations) + '\n')
        command = ['nvcc', '--ptx', '-std=c++17', '-O3', f'-arch=compute_{args.arch}',
                   '-I' + str(work), '-I' + str(source / 'ggml/include'),
                   '-I' + str(source / 'ggml/src'), '-I' + str(header.parent), str(probe)]
        needs_wait = args.arch != '89'
        for fixed in [False, True]:
            (work / header.name).write_text(original if fixed else original.replace('ggml_cuda_pdl_sync();', ''))
            output = work / ('fixed.ptx' if fixed else 'baseline.ptx')
            subprocess.run(command + ['-o', str(output)], check=True)
            ptx = output.read_text()
            if not fixed and needs_wait:
                try:
                    check(ptx, needs_wait)
                except AssertionError as error:
                    assert 'expected one PDL wait' in str(error), str(error)
                    print(f'sm_{args.arch} baseline: missing wait detected', flush=True)
                else:
                    raise AssertionError('Regression check accepted the unfixed kernel')
            else:
                count = check(ptx, needs_wait)
                print(f'sm_{args.arch} {"fixed" if fixed else "baseline"}: {count} variants pass', flush=True)


if __name__ == '__main__':
    main()
