// Kernel timeline of single-token decode steps (CUDA graphs on, as in the serve), from CUPTI activity records.
// CUPTI activity tracing needs no GPU performance-counter permission.
//   decode_trace.exe <model.gguf> <out.csv> [n_skip=64] [n_trace=64] [ctx=8192] [cupti dll] [tokens per step=1]
// out.csv: one line per kernel: step, start_ns, end_ns, grid x/y, threads per block, name. Steps are separated by host markers.
#include "llama.h"

#include <cupti_activity.h>
#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

typedef CUptiResult (CUPTIAPI * p_register)(CUpti_BuffersCallbackRequestFunc, CUpti_BuffersCallbackCompleteFunc);
typedef CUptiResult (CUPTIAPI * p_enable)(CUpti_ActivityKind);
typedef CUptiResult (CUPTIAPI * p_next)(uint8_t *, size_t, CUpti_Activity **);
typedef CUptiResult (CUPTIAPI * p_flush)(uint32_t);
typedef CUptiResult (CUPTIAPI * p_ts)(uint64_t *);

static p_next g_next;
struct krec { uint64_t start, end; std::string name; int gx, gy, block; };
static std::vector<krec> g_recs;
static std::mutex g_mu;

static void CUPTIAPI buf_req(uint8_t ** buf, size_t * size, size_t * max_records) {
    *size = 8 << 20;
    *buf = (uint8_t *) _aligned_malloc(*size, 8);
    *max_records = 0;
}

static void CUPTIAPI buf_done(CUcontext, uint32_t, uint8_t * buf, size_t, size_t valid) {
    CUpti_Activity * rec = nullptr;
    std::lock_guard<std::mutex> lk(g_mu);
    while (g_next(buf, valid, &rec) == CUPTI_SUCCESS) {
        if (rec->kind == CUPTI_ACTIVITY_KIND_CONCURRENT_KERNEL || rec->kind == CUPTI_ACTIVITY_KIND_KERNEL) {
            auto * k = (CUpti_ActivityKernel13 *) rec;
            g_recs.push_back({ k->start, k->end, k->name ? k->name : "?", k->gridX, k->gridY, k->blockX * k->blockY * k->blockZ });
        }
    }
    _aligned_free(buf);
}

int main(int argc, char ** argv) {
    if (argc < 3) { fprintf(stderr, "usage: decode_trace model.gguf out.csv [n_skip] [n_trace] [ctx] [cupti.dll]\n"); return 1; }
    const int n_skip  = argc > 3 ? atoi(argv[3]) : 64;
    const int n_trace = argc > 4 ? atoi(argv[4]) : 64;
    const int n_ctx   = argc > 5 ? atoi(argv[5]) : 8192;
    const char * dll  = argc > 6 ? argv[6] : "cupti64_2026.3.1.dll";
    const int n_step  = argc > 7 ? atoi(argv[7]) : 1;  // 3 = the shape of a draft-2 verification step

    HMODULE h = LoadLibraryA(dll);
    if (!h) { fprintf(stderr, "cannot load %s\n", dll); return 1; }
    auto reg   = (p_register) GetProcAddress(h, "cuptiActivityRegisterCallbacks");
    auto en    = (p_enable)   GetProcAddress(h, "cuptiActivityEnable");
    auto dis   = (p_enable)   GetProcAddress(h, "cuptiActivityDisable");
    auto flush = (p_flush)    GetProcAddress(h, "cuptiActivityFlushAll");
    auto ts    = (p_ts)       GetProcAddress(h, "cuptiGetTimestamp");
    g_next     = (p_next)     GetProcAddress(h, "cuptiActivityGetNextRecord");
    if (!reg || !en || !dis || !flush || !g_next || !ts) { fprintf(stderr, "missing CUPTI symbols\n"); return 1; }

    llama_backend_init();
    auto mp = llama_model_default_params();
    mp.n_gpu_layers = 999;
    llama_model * model = llama_model_load_from_file(argv[1], mp);
    if (!model) { fprintf(stderr, "model load failed\n"); return 1; }
    auto cp = llama_context_default_params();
    cp.n_ctx = n_ctx; cp.n_batch = cp.n_ubatch = n_step > 512 ? n_step : 512; cp.n_seq_max = 1;  // n_step 1024 = one prefill micro-batch of the serve
    cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
    cp.type_k = GGML_TYPE_Q8_0; cp.type_v = GGML_TYPE_Q8_0;
    llama_context * ctx = llama_init_from_model(model, cp);
    if (!ctx) { fprintf(stderr, "context failed\n"); return 1; }
    const llama_vocab * vocab = llama_model_get_vocab(model);

    std::string prompt = "Write a long, detailed essay about the history of the transistor.";
    std::vector<llama_token> toks(512);
    int n = llama_tokenize(vocab, prompt.c_str(), (int) prompt.size(), toks.data(), (int) toks.size(), true, true);
    toks.resize(n);
    if (llama_decode(ctx, llama_batch_get_one(toks.data(), n))) { fprintf(stderr, "prefill failed\n"); return 1; }

    llama_sampler * smpl = llama_sampler_init_greedy();
    std::vector<uint64_t> marks;  // CUPTI timestamp before each traced step, and one after the last
    llama_token t = llama_sampler_sample(smpl, ctx, -1);
    LARGE_INTEGER f, a, b; QueryPerformanceFrequency(&f);
    for (int i = 0; i < n_skip + n_trace; i++) {
        if (i == n_skip) {
            reg(buf_req, buf_done);
            en(CUPTI_ACTIVITY_KIND_CONCURRENT_KERNEL);
            QueryPerformanceCounter(&a);
        }
        if (i >= n_skip) { uint64_t x; ts(&x); marks.push_back(x); }
        std::vector<llama_token> step(n_step, t);
        if (llama_decode(ctx, llama_batch_get_one(step.data(), n_step))) { fprintf(stderr, "decode failed at %d\n", i); return 1; }
        t = llama_sampler_sample(smpl, ctx, -1);  // reads the logits, so the step is finished
    }
    QueryPerformanceCounter(&b);
    { uint64_t x; ts(&x); marks.push_back(x); }
    dis(CUPTI_ACTIVITY_KIND_CONCURRENT_KERNEL);
    flush(1);
    const double wall_ms = 1000.0 * (b.QuadPart - a.QuadPart) / f.QuadPart;
    fprintf(stderr, "traced %d steps: %.3f ms per step wall (%.1f tok/s), %zu kernels\n", n_trace, wall_ms / n_trace,
        1000.0 * n_trace / wall_ms, g_recs.size());

    std::sort(g_recs.begin(), g_recs.end(), [](const krec & x, const krec & y) { return x.start < y.start; });
    FILE * o = fopen(argv[2], "w");
    fprintf(o, "step,start_ns,end_ns,grid_x,grid_y,block,name\n");
    size_t s = 0;
    for (auto & r : g_recs) {
        while (s + 1 < marks.size() && r.start >= marks[s + 1]) s++;
        std::string nm = r.name; for (auto & c : nm) if (c == ',') c = ';';
        fprintf(o, "%zu,%llu,%llu,%d,%d,%d,%s\n", s, (unsigned long long) r.start, (unsigned long long) r.end, r.gx, r.gy,
            r.block, nm.c_str());
    }
    fclose(o);
    llama_sampler_free(smpl);
    llama_free(ctx);
    llama_model_free(model);
    return 0;
}
