package main

import "core:math"
import "base:intrinsics"

FFT_SIZE :: 1024
FFT_BITS :: 10

twiddle_table : [FFT_SIZE / 2]complex64
hann_table    : [FFT_SIZE]f32
bit_rev_table : [FFT_SIZE]u32
complex_buf   : [FFT_SIZE]complex64

init_fft :: proc() #no_bounds_check {
    for i in 0..<FFT_SIZE {
        hann_table[i] = 1.0 - math.cos(2 * math.PI * f32(i) / (FFT_SIZE - 1))
        bit_rev_table[i] = intrinsics.reverse_bits(u32(i)) >> (32 - FFT_BITS)
    }

    for i in 0..<FFT_SIZE/2 {
        angle := -2.0 * math.PI * f32(i) / FFT_SIZE
        twiddle_table[i] = complex(math.cos(angle), math.sin(angle))
    }
}

fft :: proc(data: [FFT_SIZE]f32) #no_bounds_check {
    for i in 0..<FFT_SIZE {
        complex_buf[bit_rev_table[i]] = data[i] * hann_table[i]
    }

    n :: FFT_SIZE
    for length := 2; length <= n; length <<= 1 {
        step := n / length
        for i := 0; i < n; i += length {
            for k := 0; k < length / 2; k += 1 {
                w := twiddle_table[k * step]
                u := complex_buf[i + k]
                v := complex_buf[i + k + length / 2] * w
                complex_buf[i + k] = u + v
                complex_buf[i + k + length / 2] = u - v
            }
        }
    }
}