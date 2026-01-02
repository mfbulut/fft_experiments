package main

import "core:math"
import "core:mem"
import "base:intrinsics"
import sdl "vendor:sdl3"

WINDOW_W :: 1280
WINDOW_H :: 720
HISTOGRAM_HEIGHT :: 200
WATERFALL_HEIGHT :: WINDOW_H - HISTOGRAM_HEIGHT

FFT_SIZE :: 1024
FFT_BITS :: 10 // log2(1024)
BIN_MIN  :: 0
BIN_MAX  :: 255

// FFT_SIZE :: 2048
// FFT_BITS :: 11 // log2(1024)
// BIN_MIN  :: 0
// BIN_MAX  :: 639

HOP_SIZE :: FFT_SIZE / 2

BIN_COUNT      :: BIN_MAX - BIN_MIN + 1
BIN_SIZE       :: WINDOW_W / BIN_COUNT
GAIN           :: 100.0
WATERFALL_ROWS :: WATERFALL_HEIGHT / BIN_SIZE

window:            ^sdl.Window
renderer:          ^sdl.Renderer
waterfall_texture: ^sdl.Texture

twiddles    : [FFT_SIZE / 2]complex64
hann_window : [FFT_SIZE]f32
bit_rev_idx : [FFT_SIZE]u32
audio_buf   : [FFT_SIZE]f32
complex_buf : [FFT_SIZE]complex64

waterfall_cursor: i32 = 0

main :: proc() {
    if !sdl.Init({.VIDEO, .AUDIO}) do return

    sdl.CreateWindowAndRenderer("FFT Visualizer", WINDOW_W, WINDOW_H, {.RESIZABLE}, &window, &renderer)
    sdl.SetRenderLogicalPresentation(renderer, WINDOW_W, WINDOW_H, .LETTERBOX)
    sdl.SetRenderVSync(renderer, 1)

    waterfall_texture = sdl.CreateTexture(renderer, .RGBA8888, .TARGET, WINDOW_W, WATERFALL_HEIGHT)

    #no_bounds_check for i in 0..<FFT_SIZE {
        hann_window[i] = 1.0 - math.cos(2 * math.PI * f32(i) / (FFT_SIZE - 1))
        bit_rev_idx[i] = intrinsics.reverse_bits(u32(i)) >> (32 - FFT_BITS)
    }

    #no_bounds_check for i in 0..<FFT_SIZE/2 {
        angle := -2.0 * math.PI * f32(i) / f32(FFT_SIZE)
        twiddles[i] = complex(math.cos(angle), math.sin(angle))
    }

    desired_spec := sdl.AudioSpec{ format = .F32, channels = 1, freq = 44100 }
    stream := sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_RECORDING, &desired_spec, nil, nil)
    sdl.ResumeAudioStreamDevice(stream)

    event: sdl.Event

    mainloop: for {
        for sdl.PollEvent(&event) {
            if event.type == .QUIT do break mainloop
        }

        for sdl.GetAudioStreamAvailable(stream) >= HOP_SIZE * size_of(f32) {
            mem.copy(&audio_buf[0], &audio_buf[HOP_SIZE], HOP_SIZE * size_of(f32))
            sdl.GetAudioStreamData(stream, &audio_buf[HOP_SIZE], HOP_SIZE * size_of(f32))

            #no_bounds_check for i in 0..<FFT_SIZE {
                complex_buf[bit_rev_idx[i]] = complex(audio_buf[i] * hann_window[i] * 2.0, 0)
            }

            fft(complex_buf[:])
            update_waterfall(complex_buf[BIN_MIN:BIN_MAX])
        }

        sdl.SetRenderDrawColor(renderer, 5, 5, 10, 255)
        sdl.RenderClear(renderer)

        draw_histogram(complex_buf[BIN_MIN:BIN_MAX])

        cursor_y := f32(waterfall_cursor * BIN_SIZE)

        src1 := sdl.FRect{0, cursor_y, WINDOW_W, WATERFALL_HEIGHT - cursor_y}
        dst1 := sdl.FRect{0, f32(HISTOGRAM_HEIGHT), WINDOW_W, WATERFALL_HEIGHT - cursor_y}
        sdl.RenderTexture(renderer, waterfall_texture, &src1, &dst1)

        src2 := sdl.FRect{0, 0, WINDOW_W, cursor_y}
        dst2 := sdl.FRect{0, f32(HISTOGRAM_HEIGHT) + (WATERFALL_HEIGHT - cursor_y), WINDOW_W, cursor_y}
        sdl.RenderTexture(renderer, waterfall_texture, &src2, &dst2)

        sdl.RenderPresent(renderer)
    }
}

fft :: proc(data: []complex64) #no_bounds_check {
    n :: FFT_SIZE
    for length := 2; length <= n; length <<= 1 {
        step := n / length
        for i := 0; i < n; i += length {
            for k := 0; k < length / 2; k += 1 {
                w := twiddles[k * step]
                u := data[i + k]
                v := data[i + k + length / 2] * w
                data[i + k] = u + v
                data[i + k + length / 2] = u - v
            }
        }
    }
}

rect_buf : [BIN_COUNT]sdl.FRect
draw_histogram :: proc(freqs: []complex64) {
    sdl.SetRenderDrawColor(renderer, 100, 200, 255, 255)
    for freq, i in freqs {
        mag := math.sqrt(real(freq) * real(freq) + imag(freq) * imag(freq))
        h := min(mag * 50.0, f32(HISTOGRAM_HEIGHT))
        rect_buf[i] =  sdl.FRect{ f32(i) * BIN_SIZE, f32(HISTOGRAM_HEIGHT) - h, BIN_SIZE, h }
    }
    sdl.RenderFillRects(renderer, raw_data(rect_buf[:]), len(rect_buf))
}

update_waterfall :: proc(freqs: []complex64) {
    sdl.SetRenderTarget(renderer, waterfall_texture)

    waterfall_cursor = (waterfall_cursor - 1 + WATERFALL_ROWS) % WATERFALL_ROWS
    y_pos := f32(waterfall_cursor * BIN_SIZE)

    for freq, i in freqs {
        mag := math.sqrt(real(freq) * real(freq) + imag(freq) * imag(freq))
        intensity := u8(math.clamp(mag * GAIN, 0, 255))

        r, g, b: u8
        if intensity < 85 {
            r = 0; g = 0; b = intensity * 3
        } else if intensity < 170 {
            r = 0; g = (intensity - 85) * 3; b = 255 - (intensity - 85) * 3
        } else {
            r = (intensity - 170) * 3; g = 255 - (intensity - 170) * 3; b = 0
        }

        sdl.SetRenderDrawColor(renderer, r, g, b, 255)
        rect := sdl.FRect{ x = f32(i) * BIN_SIZE, y = y_pos, w = BIN_SIZE + 1, h = BIN_SIZE }
        sdl.RenderFillRect(renderer, &rect)
    }

    sdl.SetRenderTarget(renderer, nil)
}