// Holds N MiB of VRAM until a stop file exists, so a server on the same card sees roughly what a smaller card has.
//   ballast.exe <MiB> <stop-file>
#include <cuda_runtime.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>

int main(int argc, char ** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: ballast <MiB> <stop-file>\n");
        return 1;
    }
    const size_t mib = (size_t) atoll(argv[1]);
    void * p = nullptr;
    if (cudaMalloc(&p, mib << 20) != cudaSuccess || cudaMemset(p, 1, mib << 20) != cudaSuccess) {
        fprintf(stderr, "cudaMalloc/cudaMemset of %zu MiB failed\n", mib);
        return 1;
    }
    cudaDeviceSynchronize();
    printf("holding %zu MiB\n", mib);
    fflush(stdout);
    for (;;) {
        if (FILE * f = fopen(argv[2], "r")) {
            fclose(f);
            break;
        }
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    cudaFree(p);
    return 0;
}
