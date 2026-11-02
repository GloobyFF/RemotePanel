#import "RPChime.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

/* 16-bit mono WAV built in memory. Each note is a sine plus a quiet octave, with a
   short attack and exponential decay so it reads as a bell, not a buzzer. */
static NSData *RPChimeWAV(const double (*notes)[3], int count, double total, double gain, double decay) {
    const int rate = 22050;
    const int n = (int)(rate * total);
    NSMutableData *pcm = [NSMutableData dataWithLength:(NSUInteger)n * 2];
    int16_t *s = pcm.mutableBytes;
    for (int i = 0; i < n; i++) {
        double t = (double)i / rate, v = 0;
        for (int k = 0; k < count; k++) {
            double dt = t - notes[k][1];
            if (dt < 0 || dt > notes[k][2]) continue;
            double env = MIN(1.0, dt / 0.004) * exp(-dt * decay);
            v += env * (0.78 * sin(2 * M_PI * notes[k][0] * dt) + 0.16 * sin(4 * M_PI * notes[k][0] * dt));
        }
        v = MAX(-1.0, MIN(1.0, v * gain));
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

@implementation RPChime

static AVAudioPlayer *gArrival;
static AVAudioPlayer *gNudge;
static AVAudioPlayer *gTap;

+ (void)prepare {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const double ding[2][3] = { { 1318.5, 0.00, 0.50 }, { 1046.5, 0.28, 0.75 } };  // E6 → C6
        const double tick[1][3] = { { 1567.98, 0.00, 0.22 } };                          // G6, short
        const double tock[2][3] = { { 1568.0, 0.00, 0.07 }, { 2093.0, 0.00, 0.045 } }; // click
        gArrival = [[AVAudioPlayer alloc] initWithData:RPChimeWAV(ding, 2, 1.05, 0.6, 6.0) error:nil];
        gNudge = [[AVAudioPlayer alloc] initWithData:RPChimeWAV(tick, 1, 0.26, 0.42, 6.0) error:nil];
        gTap = [[AVAudioPlayer alloc] initWithData:RPChimeWAV(tock, 2, 0.10, 0.72, 28.0) error:nil];
        [gArrival prepareToPlay];
        [gNudge prepareToPlay];
        [gTap prepareToPlay];
    });
}

+ (void)play:(AVAudioPlayer *)p {
    if (!p) return;
    // Playback + MixWithOthers: sounds with the mute switch on, and does not stop a
    // video that is playing with sound.
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [s setActive:YES error:nil];
    p.currentTime = 0;
    [p play];
}

+ (void)arrival {
    [self prepare];
    [self play:gArrival];
}

+ (void)nudge {
    [self prepare];
    [self play:gNudge];
}

+ (void)tap {
    [self prepare];
    [self play:gTap];
}

+ (BOOL)isQuietHours {
    NSInteger h = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[NSDate date]];
    return h >= 22 || h < 7;
}

@end
