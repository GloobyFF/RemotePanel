#import "RPTheme.h"
#import <CoreText/CoreText.h>

@implementation RPTheme

+ (void)registerFonts {
    NSArray *names = @[
        @"fusion-pixel-12px-proportional-zh_hans.ttf",
        @"fusion-pixel-12px-proportional-latin.ttf",
        @"fusion-pixel-12px-monospaced-zh_hans.ttf",
        @"ark-pixel-16px-proportional-zh_cn.ttf",
        @"ark-pixel-12px-proportional-zh_cn.ttf",
        @"zpix.ttf",
        @"weathericons-regular-webfont.ttf"
    ];
    NSString *fontsDir = [[NSBundle mainBundle] resourcePath];
    NSArray *dirs = @[
        [fontsDir stringByAppendingPathComponent:@"fonts"],
        fontsDir
    ];
    for (NSString *file in names) {
        for (NSString *dir in dirs) {
            NSString *path = [dir stringByAppendingPathComponent:file];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
            CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
            CTFontManagerRegisterFontsForURL(url, kCTFontManagerScopeProcess, NULL);
            break;
        }
    }
}

+ (CGFloat)contentScale { return 2.0; }

static UIColor *RPHex(unsigned hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xff) / 255.0
                           green:((hex >> 8) & 0xff) / 255.0
                            blue:(hex & 0xff) / 255.0
                           alpha:alpha];
}

// Monday = 0 ... Sunday = 6. Columns: bg, card, border, accent.
static const unsigned RPWeekPalette[7][4] = {
    { 0x142D78, 0x1D4EC4, 0x8EE7FF, 0x5EF0FF },
    { 0x0C3A2C, 0x146B48, 0x8CFFC4, 0x5DFFB0 },
    { 0x24124C, 0x4A2490, 0xD4B4FF, 0xC9A0FF },
    { 0x3A220C, 0x6A3C14, 0xFFD090, 0xFFC15A },
    { 0x3A1230, 0x7A2458, 0xFFB4D4, 0xFF7AB6 },
    { 0x0C3044, 0x145878, 0x9AD8FF, 0x5EC8FF },
    { 0x241C0C, 0x4A3A18, 0xF0D090, 0xF0C14A },
};

+ (NSInteger)dayIndex {
    NSInteger wd = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:[NSDate date]];
    if (wd == 1) return 6;
    if (wd < 2 || wd > 7) return 0;
    return wd - 2;
}

+ (NSString *)dayName {
    NSArray *names = @[@"周一", @"周二", @"周三", @"周四", @"周五", @"周六", @"周日"];
    return names[[self dayIndex]];
}

+ (UIColor *)bg { return RPHex(RPWeekPalette[[self dayIndex]][0], 1); }
+ (UIColor *)card { return RPHex(RPWeekPalette[[self dayIndex]][1], 0.96); }
+ (UIColor *)cardBorder { return RPHex(RPWeekPalette[[self dayIndex]][2], 1); }
+ (UIColor *)text { return [UIColor colorWithRed:1 green:1 blue:1 alpha:1]; }
+ (UIColor *)textDim { return RPHex(RPWeekPalette[[self dayIndex]][2], 1); }
+ (UIColor *)accent { return RPHex(RPWeekPalette[[self dayIndex]][3], 1); }
+ (UIColor *)ok { return [UIColor colorWithRed:0x3d/255.0 green:1 blue:0x8a/255.0 alpha:1]; }
+ (UIColor *)warn { return [UIColor colorWithRed:1 green:0xe1/255.0 blue:0x3a/255.0 alpha:1]; }
+ (UIColor *)bad { return [UIColor colorWithRed:1 green:0x4d/255.0 blue:0x6a/255.0 alpha:1]; }
+ (UIColor *)tintBlue { return [UIColor colorWithRed:0x1a/255.0 green:0x6f/255.0 blue:0xe8/255.0 alpha:0.96]; }
+ (UIColor *)tintPurple { return [UIColor colorWithRed:0x7b/255.0 green:0x3f/255.0 blue:0xf2/255.0 alpha:0.96]; }
+ (UIColor *)tintOrange { return [UIColor colorWithRed:0xf0/255.0 green:0x6a/255.0 blue:0x12/255.0 alpha:0.96]; }
+ (UIColor *)tintPink { return [UIColor colorWithRed:0xe4/255.0 green:0x37/255.0 blue:0x8c/255.0 alpha:0.96]; }
+ (UIColor *)tintTeal { return [UIColor colorWithRed:0x0e/255.0 green:0x8f/255.0 blue:0x86/255.0 alpha:0.96]; }
+ (UIColor *)tintGreen { return [UIColor colorWithRed:0x14/255.0 green:0x94/255.0 blue:0x4f/255.0 alpha:0.96]; }

+ (UIColor *)cardTint:(NSInteger)index {
    NSArray *tints = @[[self tintTeal], [self tintBlue], [self tintPurple], [self tintOrange], [self tintPink], [self tintGreen]];
    NSInteger n = (index + [self dayIndex]) % tints.count;
    return tints[n];
}

+ (CGFloat)snap:(CGFloat)size {
    CGFloat s = round(size);
    if (s < 10) s = 10;
    return s;
}

+ (UIFont *)fontNamed:(NSString *)name size:(CGFloat)size fallback:(UIFont *)fb {
    UIFont *f = [UIFont fontWithName:name size:[self snap:size]];
    return f ?: fb;
}

+ (UIFont *)title:(CGFloat)size {
    UIFont *f = [self fontNamed:@"Fusion Pixel 12px Prop zh_hans" size:size fallback:nil];
    if (!f) f = [self fontNamed:@"Zpix" size:size fallback:nil];
    if (!f) f = [UIFont boldSystemFontOfSize:[self snap:size]];
    return f;
}
+ (UIFont *)body:(CGFloat)size {
    UIFont *f = [self fontNamed:@"Fusion Pixel 12px Prop zh_hans" size:size fallback:nil];
    if (!f) f = [self fontNamed:@"Zpix" size:size fallback:nil];
    if (!f) f = [UIFont systemFontOfSize:[self snap:size]];
    return f;
}
+ (UIFont *)mono:(CGFloat)size {
    UIFont *f = [self fontNamed:@"Fusion Pixel 12px Mono zh_hans" size:size fallback:nil];
    if (!f) f = [self title:size];
    return f;
}
+ (UIFont *)hero:(CGFloat)size {
    UIFont *f = [self fontNamed:@"Ark Pixel 16px Prop zh_cn" size:size fallback:nil];
    if (!f) f = [self title:size];
    return f;
}
+ (UIFont *)small:(CGFloat)size {
    UIFont *f = [self fontNamed:@"Ark Pixel 12px Prop zh_cn" size:size fallback:nil];
    if (!f) f = [self body:size];
    return f;
}
+ (UIFont *)weatherIcon:(CGFloat)size {
    UIFont *f = [self fontNamed:@"Weather Icons" size:size fallback:nil];
    if (!f) f = [self title:size];
    return f;
}
+ (UIFont *)readable:(CGFloat)size {
    return [UIFont systemFontOfSize:[self snap:size]];
}

@end
