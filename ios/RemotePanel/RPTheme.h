#import <UIKit/UIKit.h>

@interface RPTheme : NSObject
+ (void)registerFonts;
+ (UIColor *)bg;
+ (UIColor *)card;
+ (UIColor *)cardBorder;
+ (UIColor *)text;
+ (UIColor *)textDim;
+ (UIColor *)accent;
+ (UIColor *)ok;
+ (UIColor *)warn;
+ (UIColor *)bad;
+ (UIColor *)tintBlue;
+ (UIColor *)tintPurple;
+ (UIColor *)tintOrange;
+ (UIColor *)tintPink;
+ (UIColor *)tintTeal;
+ (UIColor *)tintGreen;
+ (UIFont *)title:(CGFloat)size;
+ (UIFont *)body:(CGFloat)size;
+ (UIFont *)mono:(CGFloat)size;
+ (UIFont *)hero:(CGFloat)size;
+ (UIFont *)small:(CGFloat)size;
+ (UIFont *)weatherIcon:(CGFloat)size;
+ (CGFloat)snap:(CGFloat)size;
/** Content-page scale (~2x legacy sizes). Pass intended visual size. */
+ (CGFloat)contentScale;
+ (UIColor *)cardTint:(NSInteger)index;
+ (NSString *)dayName;
@end
