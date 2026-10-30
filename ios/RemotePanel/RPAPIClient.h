#import <Foundation/Foundation.h>

typedef void (^RPAPIClientHandler)(NSDictionary *state, NSError *error);

@interface RPAPIClient : NSObject
@property (nonatomic, copy) NSString *baseURL;
- (instancetype)initWithBaseURL:(NSString *)baseURL;
- (void)fetchStateWithCompletion:(RPAPIClientHandler)completion;
- (void)requestPath:(NSString *)path method:(NSString *)method body:(NSDictionary *)body completion:(RPAPIClientHandler)completion;
- (NSURL *)URLForPath:(NSString *)path;
@end
