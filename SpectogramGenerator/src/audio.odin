package main

import ma "vendor:miniaudio"

SAMPLE_RATE :: 44100
// SAMPLE_RATE :: 8000

decode_audio :: proc(filename: cstring) -> (samples: [dynamic]f32) {
    decoder: ma.decoder
    config := ma.decoder_config_init(ma.format.f32, 1, SAMPLE_RATE)

    if ma.decoder_init_file(filename, &config, &decoder) != .SUCCESS {
        return nil
    }
    defer ma.decoder_uninit(&decoder)

    frame_count: u64
    result := ma.decoder_get_length_in_pcm_frames(&decoder, &frame_count)

    if result != .SUCCESS || frame_count == 0 {
        samples = make([dynamic]f32, 0, SAMPLE_RATE * 60)
        chunk: [4096]f32
        for {
            frames_read: u64
            ma.decoder_read_pcm_frames(&decoder, raw_data(chunk[:]), len(chunk), &frames_read)
            if frames_read == 0 do break
            for i in 0..<int(frames_read) {
                append(&samples, chunk[i])
            }
        }
    } else {
        samples = make([dynamic]f32, frame_count)
        frames_read: u64
        ma.decoder_read_pcm_frames(&decoder, raw_data(samples[:]), frame_count, &frames_read)
        resize(&samples, int(frames_read))
    }

    return samples
}