#import "RPAPIClient.h"

@interface RPAPIClient ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *inflight;
@end

@implementation RPAPIClient

- (instancetype)initWithBaseURL:(NSString *)baseURL {
    self = [super init];
    if (self) {
        _baseURL = [baseURL copy] ?: @"http://192.168.28.12:9121";
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 12.0;
        cfg.timeoutIntervalForResource = 20.0;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (NSURL *)URLForPath:(NSString *)path {
    if (path.length == 0) return nil;
    if ([path hasPrefix:@"http://"] || [path hasPrefix:@"https://"]) {
        return [NSURL URLWithString:path];
    }
    NSString *base = self.baseURL ?: @"";
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length-1];
    if (![path hasPrefix:@"/"]) path = [@"/" stringByAppendingString:path];
    return [NSURL URLWithString:[base stringByAppendingString:path]];
}

- (void)requestPath:(NSString *)path method:(NSString *)method body:(NSDictionary *)body completion:(RPAPIClientHandler)completion {
    NSURL *url = [self URLForPath:path];
    if (!url) {
        if (completion) completion(nil, [NSError errorWithDomain:@"RPAPI" code:1 userInfo:@{NSLocalizedDescriptionKey: @"bad url"}]);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method.length ? method : @"GET";
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    req.timeoutInterval = 12.0;
    if (body) {
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&err];
        if (err || !data) {
            if (completion) completion(nil, err);
            return;
        }
        req.HTTPBody = data;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = nil;
        NSError *err = error;
        if (!err && data.length) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
            if ([obj isKindOfClass:[NSDictionary class]]) json = obj;
            else if (!err) err = [NSError errorWithDomain:@"RPAPI" code:2 userInfo:@{NSLocalizedDescriptionKey: @"not dict"}];
        }
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (!err && http && http.statusCode >= 400) {
            err = [NSError errorWithDomain:@"RPAPI" code:http.statusCode userInfo:@{NSLocalizedDescriptionKey: @"request failed"}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(json, err);
        });
    }];
    [task resume];
}

- (void)fetchStateWithCompletion:(RPAPIClientHandler)completion {
    [self.inflight cancel];
    NSURL *url = [self URLForPath:@"/api/h5/state?rotate=1"];
    if (!url) {
        if (completion) completion(nil, [NSError errorWithDomain:@"RPAPI" code:1 userInfo:@{NSLocalizedDescriptionKey:@"bad url"}]);
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.inflight = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = nil;
        NSError *err = error;
        if (!err && data) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
            if ([obj isKindOfClass:[NSDictionary class]]) json = obj;
            else if (!err) err = [NSError errorWithDomain:@"RPAPI" code:2 userInfo:@{NSLocalizedDescriptionKey:@"not dict"}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            (void)self;
            if (completion) completion(json, err);
        });
    }];
    [self.inflight resume];
}

@end
