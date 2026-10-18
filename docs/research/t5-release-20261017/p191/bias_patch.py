p = 'src/llama-kv-cache.cpp'
s = open(p, encoding='utf-8').read()


def rep(a, b, n=1):
    global s
    assert s.count(a) == n, (a[:70], s.count(a))
    s = s.replace(a, b)


rep('''// stride=N (P190, 0 = off): every N-th 256-position block of the far part stays visible (a sparse sample of the far context)
''', '''// stride=N (P190, 0 = off): every N-th 256-position block of the far part stays visible (a sparse sample of the far context)
// bias=1 (P191, f16 mask only): those far blocks get a +log(N) mask bias, so each stands for the N blocks it samples
''')
rep('''    int32_t stride = 0;
    std::vector<int> dense; // layers that keep the dense mask''', '''    int32_t stride = 0;
    int32_t bias   = 0;
    std::vector<int> dense; // layers that keep the dense mask''')
rep('''                if (k == "stride") { c.stride = std::max(0, v); }''', '''                if (k == "stride") { c.stride = std::max(0, v); }
                if (k == "bias")   { c.bias   = v; }''')
rep('''"%s: prefill window on (experimental): window %d, sink %d, tail %d, stride %d, dense layers %zu\\n", __func__,
            c.window, c.sink, c.tail, c.stride, c.dense.size());''', '''"%s: prefill window on (experimental): window %d, sink %d, tail %d, stride %d, bias %d, dense layers %zu\\n", __func__,
            c.window, c.sink, c.tail, c.stride, c.bias, c.dense.size());''')
rep('''    int32_t stride = 0;
    int32_t pmax = -1;''', '''    int32_t stride = 0;
    float   bias   = 0.0f; // mask value of a sampled far cell (f16 mask)
    int32_t pmax = -1;''')
rep('''    st.stride = c.stride;
    return st;''', '''    st.stride = c.stride;
    st.bias   = c.bias && c.stride > 1 ? logf((float) c.stride) : 0.0f;
    return st;''')
rep('''                if (pw.on && p0 >= pw.sink && p0 + pw.w < p1 && !(pw.stride > 0 && (p0 >> 8) % pw.stride == 0)) {
                    goto skip;
                }

                if (alibi) {
                    data[idst + j] = llama_cast<T>(static_cast<float>(-std::abs(p0 - p1)));
                } else {
                    data[idst + j] = mask_keep;
                }''', '''                const bool pw_far = pw.on && p0 >= pw.sink && p0 + pw.w < p1;
                if (pw_far && !(pw.stride > 0 && (p0 >> 8) % pw.stride == 0)) {
                    goto skip;
                }

                if (alibi) {
                    data[idst + j] = llama_cast<T>(static_cast<float>(-std::abs(p0 - p1)));
                } else if (pw_far && pw.bias != 0.0f) {
                    data[idst + j] = llama_cast<T>(pw.bias);
                } else {
                    data[idst + j] = mask_keep;
                }''')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
