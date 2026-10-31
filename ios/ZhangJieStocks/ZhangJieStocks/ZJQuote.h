#import <Foundation/Foundation.h>

@interface ZJQuote : NSObject
+ (NSString *)codeForToken:(NSString *)token;
+ (void)refreshNow:(void (^)(BOOL ok, NSString *error))done;
@end
