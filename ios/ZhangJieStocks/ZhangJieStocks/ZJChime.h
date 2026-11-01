#import <Foundation/Foundation.h>

/** Alert sound for price alerts. Plays through the speaker even with the mute switch on. */
@interface ZJChime : NSObject
/** Play the two-tone chime `times` times, about 1.2 s apart. Ignored while one is playing. */
+ (void)ring:(NSInteger)times;
+ (void)stop;
@end
