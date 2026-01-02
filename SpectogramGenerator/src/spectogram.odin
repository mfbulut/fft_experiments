package main

import "core:math"
import "core:mem"

HOP_SIZE :: FFT_SIZE / 2
window_buf: [FFT_SIZE]f32

make_spectogram :: proc(samples: [dynamic]f32) ->  [][IMAGE_H]f32 #no_bounds_check {
    image_w := (len(samples) - FFT_SIZE) / HOP_SIZE
    spectrogram := make([][IMAGE_H]f32, image_w)

    for x in 0..<image_w {
        offset := x * HOP_SIZE
        mem.copy(&window_buf[0], &samples[offset], FFT_SIZE * size_of(f32))

        fft(window_buf)

        for freq_idx in 0..<IMAGE_H {
            freq := complex_buf[freq_idx]
            mag := math.sqrt(real(freq) * real(freq) + imag(freq) * imag(freq))
            spectrogram[x][freq_idx] = mag
        }
    }

    return spectrogram
}


import stbi "vendor:stb/image"
IMAGE_H  :: FFT_SIZE / 2

save_spectogram :: proc(spectrogram: [][IMAGE_H]f32) #no_bounds_check {
    image_w := len(spectrogram)
    pixels := make([]u32, image_w * IMAGE_H)

    for x in 0..<image_w {
        for freq_idx in 0..<IMAGE_H {
            mag := spectrogram[x][freq_idx]
            intensity := u8(clamp(mag * 20.0, 0, 255))

            r, g, b: u8
            if intensity < 85 {
                r = 0; g = 0; b = intensity * 3
            } else if intensity < 170 {
                r = 0; g = (intensity - 85) * 3; b = 255 - (intensity - 85) * 3
            } else {
                r = (intensity - 170) * 3; g = 255 - (intensity - 170) * 3; b = 0
            }

            color := u32(r) | (u32(g) << 8) | (u32(b) << 16) | (0xFF << 24)
            y := (IMAGE_H - 1) - freq_idx
            pixels[y * image_w + x] = color
        }
    }

    stbi.write_png("spectrogram.png", i32(image_w), IMAGE_H, 4, raw_data(pixels), i32(image_w * 4))
}