#import <Foundation/Foundation.h>

@interface RPNet : NSObject
+ (NSData *)syncGET:(NSString *)urlString
              proxy:(NSString *)proxy
            headers:(NSDictionary *)headers
            timeout:(NSTimeInterval)timeout
              error:(NSError **)error;
+ (NSData *)syncPOST:(NSString *)urlString
                body:(NSData *)body
               proxy:(NSString *)proxy
             headers:(NSDictionary *)headers
             timeout:(NSTimeInterval)timeout
               error:(NSError **)error;
+ (void)GET:(NSString *)urlString
      proxy:(NSString *)proxy
    headers:(NSDictionary *)headers
    timeout:(NSTimeInterval)timeout
 completion:(void (^)(NSData *data, NSError *error))completion;
@end
