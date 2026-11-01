#import "ZJChime.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

/*
 The chime is generated once as a 16-bit mono WAV in memory: two sine notes
 (E6 then C6, a "ding-dong"), each with a short attack and an exponential decay
 so it sounds like a bell rather than a beep. No sound file has to be added to
 the Xcode project.
 */
static NSData *ZJChimeWAV(void) {
    const int rate = 22050;
    const double notes[2][3] = { { 1318.5, 0.00, 0.55 }, { 1046.5, 0.32, 0.80 } }; // Hz, start s, length s
    const double total = 1.12;
    const int n = (int)(rate * total);
    NSMutableData *pcm = [NSMutableData dataWithLength:(NSUInteger)n * 2];
    int16_t *s = pcm.mutableBytes;
    for (int i = 0; i < n; i++) {
        double t = (double)i / rate;
        double v = 0;
        for (int k = 0; k < 2; k++) {
            double dt = t - notes[k][1];
            if (dt < 0 || dt > notes[k][2]) continue;
            double env = MIN(1.0, dt / 0.008) * exp(-dt * 5.5);
            // Fundamental plus a quiet octave for a brighter bell.
            v += env * (0.75 * sin(2 * M_PI * notes[k][0] * dt) + 0.18 * sin(4 * M_PI * notes[k][0] * dt));
        }
        v *= 0.55;
        if (v > 1) v = 1;
        if (v < -1) v = -1;
        s[i] = (int16_t)(v * 32000);
    }
    uint32_t dataLen = (uint32_t)pcm.length;
    NSMutableData *wav = [NSMutableData data];
    void (^u32)(uint32_t) = ^(uint32_t x) { [wav appendBytes:&x length:4]; };
    void (^u16)(uint16_t) = ^(uint16_t x) { [wav appendBytes:&x length:2]; };
    [wav appendBytes:"RIFF" length:4]; u32(36 + dataLen);
    [wav appendBytes:"WAVE" length:4];
    [wav appendBytes:"fmt " length:4]; u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16);
    [wav appendBytes:"data" length:4]; u32(dataLen);
    [wav appendData:pcm];
    return wav;
}

@implementation ZJChime

static AVAudioPlayer *gPlayer;
static NSInteger gLeft;
static NSInteger gToken;

+ (AVAudioPlayer *)player {
    if (!gPlayer) {
        // Playback category: rings even when the side switch is set to mute,
        // which a wall-mounted iPad very often is.
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        gPlayer = [[AVAudioPlayer alloc] initWithData:ZJChimeWAV() error:nil];
        gPlayer.volume = 1.0;
        [gPlayer prepareToPlay];
    }
    return gPlayer;
}

+ (void)ring:(NSInteger)times {
    if (gLeft > 0) return;
    gLeft = MAX(1, times);
    NSInteger token = ++gToken;
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [self playNext:token];
}

+ (void)playNext:(NSInteger)token {
    if (token != gToken || gLeft <= 0) return;
    gLeft -= 1;
    AVAudioPlayer *p = [self player];
    p.currentTime = 0;
    [p play];
    if (gLeft > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self playNext:token];
        });
    }
}

+ (void)stop {
    gToken += 1;
    gLeft = 0;
    [gPlayer stop];
}

@end
