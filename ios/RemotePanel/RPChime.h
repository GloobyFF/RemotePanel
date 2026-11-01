#import <Foundation/Foundation.h>

/** Notice sounds for the 公告 (✉) messages. Generated in code, no sound files.
    Plays through the speaker even with the side switch on mute. */
@interface RPChime : NSObject
/** Two-tone "ding-dong" when a new message arrives. */
+ (void)arrival;
/** One short soft beep, for the every-10-minutes unread reminder. */
+ (void)nudge;
/** 22:00–7:00 local time: show the banner but stay silent. */
+ (BOOL)isQuietHours;
@end
