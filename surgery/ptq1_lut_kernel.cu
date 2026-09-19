// Standalone Ada PTQ1_0 surgery probe.
// Compiles without the llama.cpp tree. Checks LUT trit peel vs the
// serial *3 peel, then times both on a 4070-shaped GEMV (27B / 128).

#include <cuda_runtime.h>
#include <cstdio>
#include <cstdint>
#include <vector>
#include <cstdlib>

#define CUDA_OK(expr) do { \
    cudaError_t _e = (expr); \
    if (_e != cudaSuccess) { \
        std::fprintf(stderr, "cuda %s:%d %s\n", __FILE__, __LINE__, cudaGetErrorString(_e)); \
        std::exit(1); \
    } \
} while (0)

__device__ __constant__ unsigned short ptq1_0_lut[256] = {
       0,    0,  256,  512,   64,  320,  576,  128,  384,  640,   16,  272,  528,   80,  336,  592,
     144,  400,  656,   32,   32,  288,  544,   96,  352,  608,  160,  416,  672,    4,  260,  516,
      68,  324,  580,  132,  388,  644,   20,  276,  276,  532,   84,  340,  596,  148,  404,  660,
      36,  292,  548,  100,  356,  612,  164,  420,  676,    8,  264,  520,  520,   72,  328,  584,
     136,  392,  648,   24,  280,  536,   88,  344,  600,  152,  408,  664,   40,  296,  552,  552,
     104,  360,  616,  168,  424,  680,    1,  257,  513,   65,  321,  577,  129,  385,  641,   17,
     273,  529,   81,   81,  337,  593,  145,  401,  657,   33,  289,  545,   97,  353,  609,  161,
     417,  673,    5,  261,  517,   69,  325,  325,  581,  133,  389,  645,   21,  277,  533,   85,
     341,  597,  149,  405,  661,   37,  293,  549,  101,  357,  357,  613,  165,  421,  677,    9,
     265,  521,   73,  329,  585,  137,  393,  649,   25,  281,  537,   89,  345,  601,  601,  153,
     409,  665,   41,  297,  553,  105,  361,  617,  169,  425,  681,    2,  258,  514,   66,  322,
     578,  130,  130,  386,  642,   18,  274,  530,   82,  338,  594,  146,  402,  658,   34,  290,
     546,   98,  354,  610,  162,  162,  418,  674,    6,  262,  518,   70,  326,  582,  134,  390,
     646,   22,  278,  534,   86,  342,  598,  150,  406,  406,  662,   38,  294,  550,  102,  358,
     614,  166,  422,  678,   10,  266,  522,   74,  330,  586,  138,  394,  650,  650,   26,  282,
     538,   90,  346,  602,  154,  410,  666,   42,  298,  554,  106,  362,  618,  170,  426,  682,
};

__device__ __forceinline__ int dp4a(int a, int b, int c) {
#if __CUDA_ARCH__ >= 610
    return __dp4a(a, b, c);
#else
    char4 aa = *reinterpret_cast<char4 *>(&a);
    char4 bb = *reinterpret_cast<char4 *>(&b);
    return c + aa.x*bb.x + aa.y*bb.y + aa.z*bb.z + aa.w*bb.w;
#endif
}

__device__ __forceinline__ int trits4_mul3(uint32_t packed, int t) {
    uint32_t v_lo = (packed & 0xFFu) | ((packed >> 8) & 0xFFu) << 16;
    uint32_t v_hi = ((packed >> 16) & 0xFFu) | ((packed >> 24) & 0xFFu) << 16;
    for (int i = 0; i <= t; ++i) {
        uint32_t w_lo = v_lo * 3;
        uint32_t w_hi = v_hi * 3;
        v_lo = w_lo & 0x00FF00FFu;
        v_hi = w_hi & 0x00FF00FFu;
        if (i == t) {
            const int raw = __byte_perm(w_lo, w_hi, 0x7531);
            return __vsub4(raw, 0x01010101);
        }
    }
    return 0;
}

__device__ __forceinline__ int trits4_lut(uint32_t packed, int t) {
    const unsigned short l0 = ptq1_0_lut[(packed      ) & 0xFFu];
    const unsigned short l1 = ptq1_0_lut[(packed >>  8) & 0xFFu];
    const unsigned short l2 = ptq1_0_lut[(packed >> 16) & 0xFFu];
    const unsigned short l3 = ptq1_0_lut[(packed >> 24) & 0xFFu];
    const int s = t + t;
    const int raw =
        ((l0 >> s) & 3)        |
        ((l1 >> s) & 3) <<  8  |
        ((l2 >> s) & 3) << 16  |
        ((l3 >> s) & 3) << 24;
    return __vsub4(raw, 0x01010101);
}

__global__ void check_lut(const uint32_t * packed, int * mismatch) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= 256) return;
    const uint32_t p = packed[i];
    for (int t = 0; t < 5; ++t) {
        const int a = trits4_mul3(p, t);
        const int b = trits4_lut(p, t);
        if (a != b) {
            atomicAdd(mismatch, 1);
        }
    }
}

// Decode-shaped: one activation vector, many PTQ1 rows. Each thread owns a row.
template <int USE_LUT>
__global__ void gemv_ptq1(const uint32_t * __restrict__ qs, const int8_t * __restrict__ act,
                          int * __restrict__ out, int rows) {
    const int row = blockIdx.x * blockDim.x + threadIdx.x;
    if (row >= rows) return;
    const uint32_t * q = qs + row * 6; // 24 bytes = 6 uint32
    int sum = 0;
    // 4 groups x 5 trit steps x 4 weights = 80
    #pragma unroll
    for (int g = 0; g < 4; ++g) {
        const uint32_t packed = q[g];
        unsigned short l0=0,l1=0,l2=0,l3=0;
        if (USE_LUT) {
            l0 = ptq1_0_lut[(packed      ) & 0xFFu];
            l1 = ptq1_0_lut[(packed >>  8) & 0xFFu];
            l2 = ptq1_0_lut[(packed >> 16) & 0xFFu];
            l3 = ptq1_0_lut[(packed >> 24) & 0xFFu];
        }
        #pragma unroll
        for (int t = 0; t < 5; ++t) {
            int w;
            if (USE_LUT) {
                const int s = t + t;
                const int raw =
                    ((l0 >> s) & 3) | ((l1 >> s) & 3) << 8 |
                    ((l2 >> s) & 3) << 16 | ((l3 >> s) & 3) << 24;
                w = __vsub4(raw, 0x01010101);
            } else {
                w = trits4_mul3(packed, t);
            }
            const int e = t * 16 + 4 * g;
            const char4 c = *reinterpret_cast<const char4 *>(act + e);
            int u;
            *reinterpret_cast<char4 *>(&u) = c;
            sum = dp4a(w, u, sum);
        }
    }
    out[row] = sum;
}

static float bench(void (*fn)(const uint32_t*, const int8_t*, int*, int),
                   const uint32_t * qs, const int8_t * act, int * out, int rows, int reps) {
    fn<<<(rows+255)/256, 256>>>(qs, act, out, rows);
    CUDA_OK(cudaDeviceSynchronize());
    cudaEvent_t a,b;
    CUDA_OK(cudaEventCreate(&a));
    CUDA_OK(cudaEventCreate(&b));
    CUDA_OK(cudaEventRecord(a));
    for (int i = 0; i < reps; ++i) {
        fn<<<(rows+255)/256, 256>>>(qs, act, out, rows);
    }
    CUDA_OK(cudaEventRecord(b));
    CUDA_OK(cudaEventSynchronize(b));
    float ms = 0;
    CUDA_OK(cudaEventElapsedTime(&ms, a, b));
    cudaEventDestroy(a);
    cudaEventDestroy(b);
    return ms / reps;
}

int main() {
    int dev = 0;
    cudaDeviceProp prop{};
    CUDA_OK(cudaGetDeviceProperties(&prop, dev));
    std::printf("gpu=%s sm=%d.%d mem=%zuMiB\n", prop.name, prop.major, prop.minor, prop.totalGlobalMem>>20);

    std::vector<uint32_t> host_p(256);
    for (int i = 0; i < 256; ++i) {
        host_p[i] = (uint32_t)i | ((uint32_t)(255-i)<<8) | ((uint32_t)((i*3)&255)<<16) | ((uint32_t)((i*7)&255)<<24);
    }
    uint32_t * d_p = nullptr;
    int * d_mis = nullptr;
    CUDA_OK(cudaMalloc(&d_p, 256*4));
    CUDA_OK(cudaMalloc(&d_mis, 4));
    CUDA_OK(cudaMemcpy(d_p, host_p.data(), 256*4, cudaMemcpyHostToDevice));
    CUDA_OK(cudaMemset(d_mis, 0, 4));
    check_lut<<<1,256>>>(d_p, d_mis);
    CUDA_OK(cudaDeviceSynchronize());
    int mis = 0;
    CUDA_OK(cudaMemcpy(&mis, d_mis, 4, cudaMemcpyDeviceToHost));
    std::printf("lut_vs_mul3_mismatches=%d\n", mis);
    if (mis) return 2;

    // ~27B hidden 5120, 64 blocks * a few linears ≈ treat as 80k rows of 128
    const int rows = 81920;
    std::vector<uint32_t> qs(rows * 6);
    std::vector<int8_t> act(128);
    for (size_t i = 0; i < qs.size(); ++i) qs[i] = (uint32_t)(i * 1103515245u + 12345u);
    for (int i = 0; i < 128; ++i) act[i] = (int8_t)((i * 17) - 64);

    uint32_t * d_qs = nullptr;
    int8_t * d_act = nullptr;
    int * d_out = nullptr;
    CUDA_OK(cudaMalloc(&d_qs, qs.size()*4));
    CUDA_OK(cudaMalloc(&d_act, 128));
    CUDA_OK(cudaMalloc(&d_out, rows*4));
    CUDA_OK(cudaMemcpy(d_qs, qs.data(), qs.size()*4, cudaMemcpyHostToDevice));
    CUDA_OK(cudaMemcpy(d_act, act.data(), 128, cudaMemcpyHostToDevice));

    auto k_mul = [](const uint32_t * q, const int8_t * a, int * o, int r) {
        gemv_ptq1<0><<<(r+255)/256, 256>>>(q, a, o, r);
    };
    auto k_lut = [](const uint32_t * q, const int8_t * a, int * o, int r) {
        gemv_ptq1<1><<<(r+255)/256, 256>>>(q, a, o, r);
    };

    const int reps = 50;
    const float ms_mul = bench(+[](const uint32_t * q, const int8_t * a, int * o, int r){ gemv_ptq1<0><<<(r+255)/256,256>>>(q,a,o,r); },
                               d_qs, d_act, d_out, rows, reps);
    const float ms_lut = bench(+[](const uint32_t * q, const int8_t * a, int * o, int r){ gemv_ptq1<1><<<(r+255)/256,256>>>(q,a,o,r); },
                               d_qs, d_act, d_out, rows, reps);
    (void)k_mul; (void)k_lut;
    const double bytes = (double)rows * 24.0;
    std::printf("rows=%d mul3_ms=%.3f lut_ms=%.3f mul3_GBps=%.1f lut_GBps=%.1f speedup=%.2fx\n",
                rows, ms_mul, ms_lut, bytes/ms_mul/1e6, bytes/ms_lut/1e6, ms_mul/ms_lut);
    return 0;
}
