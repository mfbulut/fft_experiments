package main

import "core:math"
import "core:math/cmplx"

import rl "vendor:raylib"

IMG_SIZE  :: 512
FFT_SIZE  :: 512
SCREEN_W  :: 1024
SCREEN_H  :: 512

bit_rev_table : [FFT_SIZE]u32
twiddle_table : [FFT_SIZE/2]complex64

work_buf      : [IMG_SIZE * IMG_SIZE]complex64
spectrum_data : [IMG_SIZE * IMG_SIZE]complex64
input_pixels  : [IMG_SIZE * IMG_SIZE]rl.Color
output_pixels : [IMG_SIZE * IMG_SIZE]rl.Color
spectrum_img  : [IMG_SIZE * IMG_SIZE]rl.Color

tex_output    : rl.Texture
tex_spectrum  : rl.Texture
tex_filter    : rl.RenderTexture2D

init_fft :: proc() {
    bits := u32(math.log2(f32(FFT_SIZE)))
    for i in 0..<FFT_SIZE {
        rev : u32 = 0
        val := u32(i)
        for j in 0..<bits {
            rev = (rev << 1) | (val & 1)
            val = val >> 1
        }
        bit_rev_table[i] = rev
    }

    for i in 0..<FFT_SIZE/2 {
        angle := -2.0 * math.PI * f64(i) / f64(FFT_SIZE)
        twiddle_table[i] = complex64(complex(math.cos(angle), math.sin(angle)))
    }
}

fft :: proc(data: []complex64) #no_bounds_check {
    for i in 0..<FFT_SIZE {
        target := bit_rev_table[i]
        if u32(i) < target {
            data[i], data[target] = data[target], data[i]
        }
    }

    n :: FFT_SIZE
    for length := 2; length <= n; length <<= 1 {
        step := n / length
        half_len := length / 2
        for i := 0; i < n; i += length {
            for k := 0; k < half_len; k += 1 {
                w := twiddle_table[k * step]
                u := data[i + k]
                v := data[i + k + half_len] * w
                data[i + k] = u + v
                data[i + k + half_len] = u - v
            }
        }
    }
}

process_image_fft :: proc(img: ^rl.Image) #no_bounds_check {
    rl.ImageResize(img, IMG_SIZE, IMG_SIZE)
    rl.ImageFormat(img, .UNCOMPRESSED_GRAYSCALE)
    pixels := cast([^]u8)img.data

    for i in 0..<IMG_SIZE*IMG_SIZE {
        val := f32(pixels[i]) / 255.0
        spectrum_data[i] = complex(val, 0)
        c := u8(pixels[i])
        input_pixels[i] = {c, c, c, 255}
    }

    row_buf: [FFT_SIZE]complex64
    for y in 0..<IMG_SIZE {
        for x in 0..<IMG_SIZE {
            row_buf[x] = spectrum_data[y * IMG_SIZE + x]
        }
        fft(row_buf[:])
        for x in 0..<IMG_SIZE {
            spectrum_data[y * IMG_SIZE + x] = row_buf[x]
        }
    }

    col_buf: [FFT_SIZE]complex64
    for x in 0..<IMG_SIZE {
        for y in 0..<IMG_SIZE {
            col_buf[y] = spectrum_data[y * IMG_SIZE + x]
        }
        fft(col_buf[:])
        for y in 0..<IMG_SIZE {
            spectrum_data[y * IMG_SIZE + x] = col_buf[y]
        }
    }

    update_spectrum_visual()
}

update_spectrum_visual :: proc() #no_bounds_check {
    max_mag: f32 = 0.0
    for i in 0..<IMG_SIZE*IMG_SIZE {
        mag := abs(spectrum_data[i])
        if mag > 0 { mag = math.log(1.0 + mag, 2) }
        if mag > max_mag do max_mag = mag
    }

    for y in 0..<IMG_SIZE {
        for x in 0..<IMG_SIZE {
            sx := (x + IMG_SIZE/2) % IMG_SIZE
            sy := (y + IMG_SIZE/2) % IMG_SIZE
            idx := sy * IMG_SIZE + sx

            mag := abs(spectrum_data[idx])
            val := (math.log(1.0 + mag, 2) / max_mag) * 255.0
            c := u8(clamp(val, 0, 255))
            spectrum_img[y * IMG_SIZE + x] = {c, c, c, 255}
        }
    }
    rl.UpdateTexture(tex_spectrum, raw_data(spectrum_img[:]))
}

reconstruct_image :: proc() #no_bounds_check {
    img_mask := rl.LoadImageFromTexture(tex_filter.texture)
    defer rl.UnloadImage(img_mask)
    mask_pixels := cast([^]rl.Color)img_mask.data

    for y in 0..<IMG_SIZE {
        for x in 0..<IMG_SIZE {
            sx := (x + IMG_SIZE/2) % IMG_SIZE
            sy := (y + IMG_SIZE/2) % IMG_SIZE

            data_idx := sy * IMG_SIZE + sx
            view_idx := y * IMG_SIZE + x

            mask_val := f32(mask_pixels[view_idx].r) / 255.0
            work_buf[data_idx] = spectrum_data[data_idx] * complex(mask_val, 0)
        }
    }

    col_buf: [FFT_SIZE]complex64
    for x in 0..<IMG_SIZE {
        for y in 0..<IMG_SIZE {
            col_buf[y] = conj(work_buf[y * IMG_SIZE + x])
        }
        fft(col_buf[:])
        for y in 0..<IMG_SIZE {
            work_buf[y * IMG_SIZE + x] = conj(col_buf[y])
        }
    }

    row_buf: [FFT_SIZE]complex64
    for y in 0..<IMG_SIZE {
        for x in 0..<IMG_SIZE {
            row_buf[x] = conj(work_buf[y * IMG_SIZE + x])
        }
        fft(row_buf[:])
        for x in 0..<IMG_SIZE {
            val := conj(row_buf[x])
            r := real(val) / (f32(IMG_SIZE * IMG_SIZE))
            c := u8(clamp(r * 255.0, 0, 255))
            output_pixels[y * IMG_SIZE + x] = {c, c, c, 255}
        }
    }
    rl.UpdateTexture(tex_output, raw_data(output_pixels[:]))
}

main :: proc() {
    rl.InitWindow(SCREEN_W, SCREEN_H, "Image FFT | Drag & Drop Images To Start")
    rl.SetTargetFPS(144)

    init_fft()

    img_blank := rl.GenImageColor(IMG_SIZE, IMG_SIZE, rl.BLACK)
    tex_output = rl.LoadTextureFromImage(img_blank)
    tex_spectrum = rl.LoadTextureFromImage(img_blank)

    tex_filter = rl.LoadRenderTexture(IMG_SIZE, IMG_SIZE)

    needs_reconstruction := false
    brush_size : f32 = 30.0

    for !rl.WindowShouldClose() {
        if rl.IsFileDropped() {
            dropped := rl.LoadDroppedFiles()
            if dropped.count > 0 {
                img := rl.LoadImage(dropped.paths[0])
                process_image_fft(&img)
                rl.UnloadImage(img)

                rl.BeginTextureMode(tex_filter)
                rl.ClearBackground(rl.WHITE)
                rl.EndTextureMode()

                reconstruct_image()
            }
            rl.UnloadDroppedFiles(dropped)
        }

        wheel := rl.GetMouseWheelMove()
        if wheel != 0.0 {
            brush_size += wheel * 5.0
            if brush_size < 1.0 do brush_size = 1.0
            if brush_size > 200.0 do brush_size = 200.0
        }

        mouse_pos := rl.GetMousePosition()
        if mouse_pos.x >= f32(IMG_SIZE) {
            local_x := mouse_pos.x - f32(IMG_SIZE)
            local_y := mouse_pos.y

            if rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT) {
                rl.BeginTextureMode(tex_filter)
                color := rl.IsMouseButtonDown(.LEFT) ? rl.BLACK : rl.WHITE
                rl.DrawCircleV({local_x, local_y}, brush_size, color)
                rl.EndTextureMode()
                needs_reconstruction = true
            }
        }

        if needs_reconstruction && rl.IsMouseButtonUp(.LEFT) && rl.IsMouseButtonUp(.RIGHT) {
            reconstruct_image()
            needs_reconstruction = false
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.DARKGRAY)

        rl.DrawTexture(tex_output, 0, 0, rl.WHITE)
        rl.DrawTexture(tex_spectrum, IMG_SIZE, 0, rl.WHITE)

        rl.BeginBlendMode(.MULTIPLIED)
        src_rect := rl.Rectangle{0, 0, f32(tex_filter.texture.width), -f32(tex_filter.texture.height)}
        dst_rect := rl.Rectangle{f32(IMG_SIZE), 0, f32(IMG_SIZE), f32(IMG_SIZE)}
        rl.DrawTexturePro(tex_filter.texture, src_rect, dst_rect, {0,0}, 0, rl.WHITE)
        rl.EndBlendMode()

        if mouse_pos.x >= f32(IMG_SIZE) && mouse_pos.x < SCREEN_W && mouse_pos.y >= 0 && mouse_pos.y < SCREEN_H {
            rl.DrawCircleLines(i32(mouse_pos.x), i32(mouse_pos.y), brush_size, rl.RED)
        }

        rl.EndDrawing()
    }
}