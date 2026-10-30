#import <Foundation/Foundation.h>

extern NSString * const RPProxyDefaultsKey;
extern NSString * const RPSourceURLPrefix;
extern NSString * const RPSourceProxyPrefix;
extern NSString * const RPVpsURLKey;
extern NSString * const RPVpsTokenKey;
extern NSString * const RPVpsProxyKey;
extern NSString * const RPPageEnabledPrefix;
extern NSString * const RPRefreshPrefix;
extern NSString * const RPTickerURLKey;
extern NSString * const RPTickerProxyKey;
extern NSString * const RPHelloKeyKey;
extern NSString * const RPHelloModelKey;
extern NSString * const RPFeedProgressNotification;

NSDictionary *RPLocalSourceDefaults(void);
NSString *RPLocalDefaultProxy(void);
NSString *RPLocalDefaultVPSURL(void);
NSString *RPLocalDefaultVPSToken(void);
NSString *RPLocalDefaultHelloKey(void);
NSString *RPLocalDefaultHelloModel(void);
BOOL RPLocalDefaultUseProxy(NSString *pid);
NSTimeInterval RPLocalDefaultTTL(NSString *feedKey);
NSTimeInterval RPLocalTTL(NSString *feedKey);
NSString *RPLocalFeedKeyForPage(NSString *pid);
NSArray *RPLocalRefreshChoices(void);
NSArray *RPLocalRefreshChoiceTitles(void);
NSInteger RPLocalRefreshChoiceIndex(NSTimeInterval ttl);
NSArray *RPLocalPageCatalog(void);

@interface RPLocalFeed : NSObject
+ (instancetype)sharedFeed;
- (void)refreshWithCompletion:(void (^)(NSDictionary *state, NSError *error))completion;
- (NSArray *)activityLog;
- (NSArray *)tickerMessages;
@end
