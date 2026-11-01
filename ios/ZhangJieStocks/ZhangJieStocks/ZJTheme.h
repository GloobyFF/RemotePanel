#import <UIKit/UIKit.h>

static inline UIColor *ZJHex(unsigned hex) {
    return [UIColor colorWithRed:((hex >> 16) & 255) / 255.0
                           green:((hex >> 8) & 255) / 255.0
                            blue:(hex & 255) / 255.0
                           alpha:1];
}

static inline UIColor *ZJBG(void) { return ZJHex(0x0B1220); }
static inline UIColor *ZJCard(void) { return ZJHex(0x16233A); }
static inline UIColor *ZJUp(void) { return ZJHex(0xF0444C); }
static inline UIColor *ZJDown(void) { return ZJHex(0x1EAE5A); }
static inline UIColor *ZJFlat(void) { return ZJHex(0x9AA4B2); }
static inline UIColor *ZJText(void) { return [UIColor whiteColor]; }
static inline UIColor *ZJDim(void) { return ZJHex(0x9AA4B2); }

static inline UIColor *ZJMove(double n) {
    if (n > 0.0001) return ZJUp();
    if (n < -0.0001) return ZJDown();
    return ZJFlat();
}

static inline NSNumberFormatter *ZJGroupedFormatter(void) {
    static NSNumberFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSNumberFormatter alloc] init];
        fmt.numberStyle = NSNumberFormatterDecimalStyle;
        fmt.minimumFractionDigits = 2;
        fmt.maximumFractionDigits = 2;
        fmt.usesGroupingSeparator = YES;
    });
    return fmt;
}

static inline NSString *ZJGrouped(double n) {
    return [ZJGroupedFormatter() stringFromNumber:@(fabs(n))] ?: @"0.00";
}

static inline NSString *ZJSigned(double n) {
    NSString *body = ZJGrouped(n);
    if (n > 0.00005) return [@"+" stringByAppendingString:body];
    if (n < -0.00005) return [@"-" stringByAppendingString:body];
    return body;
}

static inline NSString *ZJPct(double n) {
    return [NSString stringWithFormat:@"%@%%", ZJSigned(n)];
}

static inline NSString *ZJSharesText(double n) {
    if (fabs(n - round(n)) < 0.001) return [NSString stringWithFormat:@"%.0f", n];
    return [NSString stringWithFormat:@"%.2f", n];
}

static inline UILabel *ZJLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.textColor = color;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.35;
    label.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    return label;
}
