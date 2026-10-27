#include <SDL3/SDL.h>
#include <libavcodec/avcodec.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_PCM_S16LE);
    if (!codec) { fprintf(stderr, "PCM decoder unavailable\n"); return 1; }
    AVCodecContext *ctx = avcodec_alloc_context3(codec);
    ctx->sample_rate = 48000;
    ctx->ch_layout = (AVChannelLayout) AV_CHANNEL_LAYOUT_STEREO;
    if (avcodec_open2(ctx, codec, NULL) < 0) return 2;
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    if (av_new_packet(packet, 4800 * 4) < 0) return 3;
    memset(packet->data, 0, packet->size);
    if (avcodec_send_packet(ctx, packet) < 0 || avcodec_receive_frame(ctx, frame) < 0 || frame->nb_samples != 4800) return 4;
    if (!SDL_Init(SDL_INIT_AUDIO)) { fprintf(stderr, "SDL init: %s\n", SDL_GetError()); return 5; }
    SDL_AudioSpec spec = { .format = SDL_AUDIO_S16, .channels = 2, .freq = 48000 };
    SDL_AudioStream *stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, NULL, NULL);
    if (!stream) { fprintf(stderr, "Output: %s\n", SDL_GetError()); return 6; }
    unsigned char silence[48000];
    memset(silence, 0, sizeof(silence));
    if (!SDL_PutAudioStreamData(stream, silence, sizeof(silence)) || !SDL_ResumeAudioStreamDevice(stream)) return 7;
    SDL_Delay(500);
    int queued = SDL_GetAudioStreamQueued(stream);
    if (queued < 0 || queued >= (int) sizeof(silence)) { fprintf(stderr, "Output did not consume queued samples: %d\n", queued); return 8; }
    printf("PASS: FFmpeg decoded 4,800 stereo PCM samples; SDL %s output consumed silent PCM (%d bytes left). No microphone opened.\n", SDL_GetCurrentAudioDriver(), queued);
    SDL_DestroyAudioStream(stream); SDL_Quit();
    av_frame_free(&frame); av_packet_free(&packet); avcodec_free_context(&ctx);
    return 0;
}
