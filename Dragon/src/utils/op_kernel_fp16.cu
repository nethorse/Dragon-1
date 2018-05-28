#ifdef WITH_CUDA

#include <cmath>

#include "core/context_cuda.h"
#include "core/tensor.h"
#include "utils/cuda_device.h"
#include "utils/op_kernel.h"
#include "utils/math_functions.h"
#include "utils/cast.h"

namespace dragon {

namespace kernel {

template <typename T>
__global__ void _EmptyHalf() {}

template<> void Empty<float16, CUDAContext>() {
    _EmptyHalf<float16> << <1, 1 >> >();
    CUDA_POST_KERNEL_CHECK;
}

/******************** activation.relu ********************/

#ifdef WITH_CUDA_FP16
template <typename T>
__global__ void _ReluHalf(const int count, const half* x, const half slope, half* y) {
    const half kZero = __float2half(0.f);
    CUDA_KERNEL_LOOP(idx, count) {
#if __CUDA_ARCH__ >= 530
        y[idx] = __hgt(x[idx], kZero) ? x[idx] : __hmul(x[idx], slope);
#endif
    }
}

template <typename T>
__global__ void _ReluHalf2(const int count, const half2* x, const half2 slope, half2* y) {
    const half2 kZero = __float2half2_rn(0.f);
    CUDA_KERNEL_LOOP(idx, count) {
#if __CUDA_ARCH__ >= 530
        y[idx] = __hbgt2(x[idx], kZero) ? x[idx] : __hmul2(x[idx], slope);
#endif
    }
}
#endif

template<> void Relu<float16, CUDAContext>(const int count,
                                           const float16* x,
                                           const float slope,
                                           float16* y) {
#ifdef WITH_CUDA_FP16
    if (count % 2 == 0) 
        _ReluHalf2<half2> << < GET_BLOCKS(count), CUDA_NUM_THREADS >> > (count / 2,
                                                 reinterpret_cast<const half2*>(x),
                                                  dragon_cast<half2, float>(slope),
                                                      reinterpret_cast<half2*>(y));
    else
        _ReluHalf<half> << < GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                           reinterpret_cast<const half*>(x),
                                            dragon_cast<half, float>(slope),
                                                reinterpret_cast<half*>(y));
    CUDA_POST_KERNEL_CHECK;
#else
    CUDA_FP16_NOT_COMPILED;
#endif
}

/******************** arithmetic.affine ********************/

#ifdef WITH_CUDA_FP16
template <typename T>
__global__ void _AffineWithOBiasHalf(const int count,
                                     const int scale_dim,
                                     const int inner_dim,
                                     const half* x,
                                     const half* alpha,
                                     half* y) {
    CUDA_KERNEL_LOOP(idx, count) {
#if __CUDA_ARCH__ >= 530
        const int scale_idx = (idx / inner_dim) % scale_dim;
        y[idx] = __hmul(alpha[scale_idx], x[idx]);
#endif
    }
}

template <typename T>
__global__ void _AffineWithBiasHalf(const int count,
                                    const int scale_dim,
                                    const int inner_dim,
                                    const half* x,
                                    const half* alpha,
                                    const half* beta,
                                    half* y) {
    CUDA_KERNEL_LOOP(idx, count) {
#if __CUDA_ARCH__ >= 530
        const int scale_idx = (idx / inner_dim) % scale_dim;
        y[idx] = __hadd(__hmul(alpha[scale_idx], x[idx]), beta[scale_idx]);
#endif
    }
}
#endif

template<> void Affine<float16, CUDAContext>(const int count,
                                             const int outer_dim,
                                             const int scale_dim,
                                             const int inner_dim,
                                             const float16* x,
                                             const float16* alpha,
                                             const float16* beta,
                                             const float16* beta_multiplier,
                                             float16* y) {
#ifdef WITH_CUDA_FP16
    if (beta != nullptr) {
        _AffineWithBiasHalf<float> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                 scale_dim, inner_dim,
                                                     reinterpret_cast<const half*>(x),
                                                 reinterpret_cast<const half*>(alpha),
                                                  reinterpret_cast<const half*>(beta),
                                                          reinterpret_cast<half*>(y));
    } else {
        _AffineWithOBiasHalf<float> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                  scale_dim, inner_dim,
                                                      reinterpret_cast<const half*>(x),
                                                  reinterpret_cast<const half*>(alpha),
                                                           reinterpret_cast<half*>(y));
    }
    CUDA_POST_KERNEL_CHECK;
#else
    CUDA_FP16_NOT_COMPILED;
#endif
}

/******************** misc.astype ********************/

#ifdef WITH_CUDA_FP16
__global__ void _TypeHalf2Float(const int count, const half* a, float* b) {
    CUDA_KERNEL_LOOP(idx, count) {
        b[idx] = __half2float(a[idx]);
    }
}
__global__ void _TypeFloat2Half(const int count, const float* a, half* b) {
    CUDA_KERNEL_LOOP(idx, count) {
        b[idx] = __float2half(a[idx]);
    }
}

__global__ void _TypeHalf2Half(const int count, const half* a, half* b) {
    CUDA_KERNEL_LOOP(idx, count) {
        b[idx] = a[idx];
    }
}
#endif

#define DEFINE_TYPE_DISABLE_FP16(type) \
    template <> void TypeA2B<float16, type, CUDAContext>(const int count, \
                                                         const float16* a, \
                                                         type* b) { \
        LOG(FATAL) << "CUDAContext has not implemented: float16 -> " \
                   << TypeMetaToString(TypeMeta::Make<type>()); \
    } \
    template <> void TypeA2B<type, float16, CUDAContext>(const int count, \
                                                         const type* a, \
                                                         float16* b) { \
        LOG(FATAL) << "CUDAContext has not implemented: " \
                   << TypeMetaToString(TypeMeta::Make<type>()) << " -> float16"; \
    }

#define DEFINE_TYPE_ENABLE_FP16_FP32 \
    template <> void TypeA2B<float16, float, CUDAContext>(const int count, \
                                                          const float16* a, \
                                                          float* b) { \
        _TypeHalf2Float << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count, \
                                      reinterpret_cast<const half*>(a), b); \
        CUDA_POST_KERNEL_CHECK; \
    } \
    template <> void TypeA2B<float, float16, CUDAContext>(const int count, \
                                                          const float* a, \
                                                          float16* b) { \
        _TypeFloat2Half << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count, \
                                            a, reinterpret_cast<half*>(b)); \
        CUDA_POST_KERNEL_CHECK; \
    }

#ifdef WITH_CUDA_FP16
template <> void TypeA2B<float16, float16, CUDAContext>(const int count,
                                                        const float16* a,
                                                        float16* b) {
    _TypeHalf2Half << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                     reinterpret_cast<const half*>(a),
                                          reinterpret_cast<half*>(b));
    CUDA_POST_KERNEL_CHECK;
}
DEFINE_TYPE_ENABLE_FP16_FP32;
DEFINE_TYPE_DISABLE_FP16(double);
DEFINE_TYPE_DISABLE_FP16(int);
DEFINE_TYPE_DISABLE_FP16(int64_t);
DEFINE_TYPE_DISABLE_FP16(uint8_t);
#else
template <> void TypeA2B<float16, float16, CUDAContext>(const int count,
                                                        const float16* a,
                                                        float16* b) {
    LOG(FATAL) << "CUDAContext has not implemented: float16 -> float16";
}
DEFINE_TYPE_DISABLE_FP16(float);
DEFINE_TYPE_DISABLE_FP16(double);
DEFINE_TYPE_DISABLE_FP16(int);
DEFINE_TYPE_DISABLE_FP16(int64_t);
DEFINE_TYPE_DISABLE_FP16(uint8_t);
#endif

/******************** misc.image_data ********************/

#ifdef WITH_CUDA_FP16
template <typename Tx, typename Ty>
__global__ void _ImageDataHalf_NCHW(const int count,
                                    const int N, const int C,
                                    const int H, const int W,
                                    const float* mean_values,
                                    const float* std_values,
                                    const Tx* x, 
                                    Ty* y) {
    CUDA_KERNEL_LOOP(idx, count) {
        const int w = idx % W;
        const int h = (idx / W) % H;
        const int c = (idx / W / H) % C;
        const int n = idx / W / H / C;
        float raw_value = x[((n * H + h) * W + w) * C + c];
        if (mean_values != nullptr) raw_value -= mean_values[c];
        if (std_values != nullptr) raw_value /= std_values[c];
        y[idx] = __float2half(raw_value);
    }
}

template <typename Tx, typename Ty>
__global__ void _ImageDataHalf_NHWC(const int count,
                                    const int N, const int C,
                                    const int H, const int W,
                                    const float* mean_values,
                                    const float* std_values,
                                    const Tx* x, 
                                    Ty* y) {
    CUDA_KERNEL_LOOP(idx, count) {
        const int c = idx % C;
        float raw_value = x[idx];
        if (mean_values != nullptr) raw_value -= mean_values[c];
        if (std_values != nullptr) raw_value /= std_values[c];
        y[idx] = __float2half(raw_value);
    }
}
#endif

template <> void ImageData<float, float16, CUDAContext>(const int count,
                                                        const int N, const int C,
                                                        const int H, const int W,
                                                        const float* mean_values,
                                                        const float* std_values,
                                                        const string& data_format,
                                                        const float* x,
                                                        float16* y) {
#ifdef WITH_CUDA_FP16
    if (data_format == "NCHW") {
        _ImageDataHalf_NCHW<float, half> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                                 N, C, H, W,
                                                                                mean_values,
                                                                                 std_values,
                                                                                          x,
                                                                reinterpret_cast<half*>(y));
    } else if (data_format == "NHWC") {
        _ImageDataHalf_NHWC<float, half> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                                 N, C, H, W,
                                                                                mean_values,
                                                                                 std_values,
                                                                                          x,
                                                                reinterpret_cast<half*>(y));

    } else LOG(FATAL) << "Unknown data format: " << data_format;
    CUDA_POST_KERNEL_CHECK;
#else
    CUDA_FP16_NOT_COMPILED;
#endif
}

template <> void ImageData<uint8_t, float16, CUDAContext>(const int count,
                                                          const int N, const int C,
                                                          const int H, const int W,
                                                          const float* mean_values,
                                                          const float* std_values,
                                                          const string& data_format,
                                                          const uint8_t* x,
                                                          float16* y) {
#ifdef WITH_CUDA_FP16
    if (data_format == "NCHW") {
        _ImageDataHalf_NCHW<uint8_t, half> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                                   N, C, H, W,
                                                                                  mean_values,
                                                                                   std_values,
                                                                                            x,
                                                                  reinterpret_cast<half*>(y));
    } else if (data_format == "NHWC") {
        _ImageDataHalf_NHWC<uint8_t, half> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                                   N, C, H, W,
                                                                                  mean_values,
                                                                                   std_values,
                                                                                            x,
                                                                  reinterpret_cast<half*>(y));

    } else LOG(FATAL) << "Unknown data format: " << data_format;
    CUDA_POST_KERNEL_CHECK;
#else
    CUDA_FP16_NOT_COMPILED;
#endif
}

/******************** ndarray.concat ********************/

template <typename T>
__global__ void _ConcatHalf(const int count,
                            const int outer_dim,
                            const int inner_dim,
                            const int x_concat_dim,
                            const int y_concat_dim,
                            const int concat_offset,
                            const T* x,
                            T* y) {
    CUDA_KERNEL_LOOP(idx, count) {
        const int tmp = x_concat_dim * inner_dim;
        const int outer_idx = idx / tmp;
        const int concat_idx = idx % tmp;
        const int y_idx = (outer_idx * y_concat_dim + concat_offset)
                                     * inner_dim + concat_idx;
        y[y_idx] = x[idx];
    }
}

template <> void Concat<float16, CUDAContext>(const int count,
                                              const int outer_dim,
                                              const int inner_dim,
                                              const int x_concat_dim,
                                              const int y_concat_dim,
                                              const int concat_offset,
                                              const float16* x,
                                              float16* y,
                                              CUDAContext* context) {
#ifdef WITH_CUDA_FP16
    _ConcatHalf<half> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                               outer_dim,
                                                               inner_dim,
                                                            x_concat_dim,
                                                            y_concat_dim,
                                                           concat_offset,
                                        reinterpret_cast<const half*>(x),
                                             reinterpret_cast<half*>(y));
    CUDA_POST_KERNEL_CHECK;
#else
    CUDA_FP16_NOT_COMPILED;
#endif
}

template <typename T>
__global__ void _ConcatGradHalf(const int count,
                                const int outer_dim,
                                const int inner_dim,
                                const int x_concat_dim,
                                const int y_concat_dim,
                                const int concat_offset,
                                const T* dy,
                                T* dx) {
    CUDA_KERNEL_LOOP(idx, count) {
        const int tmp = x_concat_dim * inner_dim;
        const int outer_idx = idx / tmp;
        const int concat_idx = idx % tmp;
        const int y_idx = (outer_idx * y_concat_dim + concat_offset)
                                     * inner_dim + concat_idx;
        dx[idx] = dy[y_idx];
    }
}

template <> void ConcatGrad<float16, CUDAContext>(const int count,
                                                  const int outer_dim,
                                                  const int inner_dim,
                                                  const int x_concat_dim,
                                                  const int y_concat_dim,
                                                  const int concat_offset,
                                                  const float16* dy,
                                                  float16* dx,
                                                  CUDAContext* context) {
#ifdef WITH_CUDA_FP16
    _ConcatGradHalf<half> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                   outer_dim,
                                                                   inner_dim,
                                                                x_concat_dim,
                                                                y_concat_dim,
                                                               concat_offset,
                                           reinterpret_cast<const half*>(dy),
                                                reinterpret_cast<half*>(dx));
    CUDA_POST_KERNEL_CHECK;
#else
    CUDA_FP16_NOT_COMPILED;
#endif
}

/******************** ndarray.transpose ********************/

template <typename T>
__global__ void _TransposeHalf(const int count,
                               const int ndim,
                               const int* order,
                               const int* old_steps,
                               const int* new_steps,
                               const T* x,
                               T* y) {
    CUDA_KERNEL_LOOP(idx, count) {
       int x_idx = 0, y_idx = idx;
       for (int j = 0; j < ndim; ++j) {
           int k = order[j];
           x_idx += (y_idx / new_steps[j]) * old_steps[k];
           y_idx %= new_steps[j];
       }
       y[idx] = x[x_idx];
   }
}

template <> void Transpose<float16, CUDAContext>(const int count,
                                                 const int ndim,
                                                 const int* order,
                                                 const int* old_steps,
                                                 const int* new_steps,
                                                 const float16* x,
                                                 float16* y) {
#ifdef WITH_CUDA_FP16
    _TransposeHalf<half> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                       ndim,
                                                                      order,
                                                                  old_steps,
                                                                  new_steps,
                                           reinterpret_cast<const half*>(x),
                                                reinterpret_cast<half*>(y));
    CUDA_POST_KERNEL_CHECK;
#else
    CUDA_FP16_NOT_COMPILED;
#endif
}

template <typename T>
__global__ void _TransposeGradHalf(const int count,
                                   const int ndim,
                                   const int* order,
                                   const int* old_steps,
                                   const int* new_steps,
                                   const T* dy,
                                   T* dx) {
    CUDA_KERNEL_LOOP(idx, count) {
        int x_idx = 0, y_idx = idx;
        for (int j = 0; j < ndim; ++j) {
            int k = order[j];
            x_idx += (y_idx / new_steps[j]) * old_steps[k];
            y_idx %= new_steps[j];
        }
        dx[x_idx] = dy[idx];
    }
}

template <> void TransposeGrad<float16, CUDAContext>(const int count,
                                                     const int ndim,
                                                     const int* order,
                                                     const int* old_steps,
                                                     const int* new_steps,
                                                     const float16* dy,
                                                     float16* dx) {
#ifdef WITH_CUDA_FP16
    _TransposeGradHalf<half> << <GET_BLOCKS(count), CUDA_NUM_THREADS >> >(count,
                                                                           ndim,
                                                                          order,
                                                                      old_steps,
                                                                      new_steps,
                                              reinterpret_cast<const half*>(dy),
                                                   reinterpret_cast<half*>(dx));
    CUDA_POST_KERNEL_CHECK;
#else
    CUDA_FP16_NOT_COMPILED;
#endif
}

}    // namespace kernel

}    // namespace dragon

#endif // WITH_CUDA