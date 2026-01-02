package main

main :: proc() {
    init_fft()

    samples := decode_audio("song.mp3")
    spectrogram := make_spectogram(samples)

    save_spectogram(spectrogram)
}