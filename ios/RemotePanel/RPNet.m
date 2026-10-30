#import "RPNet.h"
#import <Security/SecureTransport.h>
#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <netdb.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

static const NSUInteger kRPMaxBody = 2 * 1024 * 1024;

static NSString *RPTLSMessage(OSStatus st) {
    switch (st) {
        case errSSLUnknownRootCert: return @"系统不信任这张证书";
        case errSSLNoRootCert: return @"系统没有对应的根证书";
        case errSSLXCertChainInvalid: return @"证书链无效";
        case errSSLHostNameMismatch: return @"证书域名不符";
        case errSSLCertExpired: return @"证书已过期";
        case errSSLPeerProtocolVersion: return @"对方不支持 TLS 1.2";
        case errSSLPeerHandshakeFail: return @"对方中断了 TLS 握手";
        case errSSLClosedAbort: return @"连接在握手时被断开";
        case errSSLBadCipherSuite: return @"没有共同的加密方式";
        default: return [NSString stringWithFormat:@"TLS 握手失败 (%d)", (int)st];
    }
}

static NSError *RPErr(NSInteger code, NSString *msg) {
    return [NSError errorWithDomain:@"RPNet" code:code userInfo:@{NSLocalizedDescriptionKey: msg ?: @"请求失败"}];
}

static void RPSetError(NSError **error, NSError *err) {
    if (error) *error = err;
}

static BOOL RPWriteRaw(int fd, const void *buf, size_t len) {
    const uint8_t *p = buf;
    while (len) {
        ssize_t n = write(fd, p, len);
        if (n < 0) {
            if (errno == EINTR) continue;
            return NO;
        }
        if (n == 0) return NO;
        p += n;
        len -= (size_t)n;
    }
    return YES;
}

static ssize_t RPReadRaw(int fd, void *buf, size_t len) {
    for (;;) {
        ssize_t n = read(fd, buf, len);
        if (n < 0 && errno == EINTR) continue;
        return n;
    }
}

static BOOL RPWaitSocket(int fd, BOOL forWrite) {
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    struct timeval tv;
    tv.tv_sec = 20;
    tv.tv_usec = 0;
    int rc = forWrite ? select(fd + 1, NULL, &fds, NULL, &tv) : select(fd + 1, &fds, NULL, NULL, &tv);
    return rc > 0;
}

/* iOS 9 SecureTransport returns paramErr (-50) if a custom read returns a
   short buffer. Fill the exact count it asked for, or stop only on EOF. */
static OSStatus RPSSLRead(SSLConnectionRef connection, void *data, size_t *dataLength) {
    int fd = (int)(intptr_t)connection;
    uint8_t *p = data;
    size_t want = *dataLength;
    size_t got = 0;
    while (got < want) {
        ssize_t n = read(fd, p + got, want - got);
        if (n > 0) {
            got += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        *dataLength = got;
        if (got > 0) return noErr;
        return n == 0 ? errSSLClosedGraceful : errSSLClosedAbort;
    }
    return noErr;
}

static OSStatus RPSSLWrite(SSLConnectionRef connection, const void *data, size_t *dataLength) {
    int fd = (int)(intptr_t)connection;
    const uint8_t *p = data;
    size_t left = *dataLength;
    while (left) {
        ssize_t n = write(fd, p, left);
        if (n > 0) {
            p += (size_t)n;
            left -= (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        *dataLength = 0;
        return errSSLClosedAbort;
    }
    return noErr;
}

static int RPConnectAddr(struct addrinfo *ai, NSTimeInterval timeout) {
    int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    if (fd < 0) return -1;
    int nosig = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, sizeof(nosig));
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    int rc = connect(fd, ai->ai_addr, ai->ai_addrlen);
    if (rc < 0 && errno != EINPROGRESS) {
        close(fd);
        return -1;
    }
    fd_set wfds;
    FD_ZERO(&wfds);
    FD_SET(fd, &wfds);
    struct timeval tv;
    tv.tv_sec = (time_t)MAX(3, timeout);
    tv.tv_usec = 0;
    rc = select(fd + 1, NULL, &wfds, NULL, &tv);
    int soerr = 0;
    socklen_t sl = sizeof(soerr);
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
    if (rc <= 0 || soerr != 0) {
        close(fd);
        return -1;
    }
    fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
    return fd;
}

static int RPConnectHost(NSString *host, NSInteger port, NSTimeInterval timeout) {
    if (host.length == 0 || port <= 0) return -1;
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    struct addrinfo *res = NULL;
    if (getaddrinfo(host.UTF8String, [[NSString stringWithFormat:@"%ld", (long)port] UTF8String], &hints, &res) != 0) return -1;
    int fd = -1;
    for (int pass = 0; pass < 2 && fd < 0; pass++) {
        for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
            BOOL v6 = ai->ai_family == AF_INET6;
            if ((pass == 0 && v6) || (pass == 1 && !v6)) continue;
            fd = RPConnectAddr(ai, timeout);
            if (fd >= 0) break;
        }
    }
    freeaddrinfo(res);
    return fd;
}

static BOOL RPReadFull(int fd, void *buf, size_t len) {
    uint8_t *p = buf;
    while (len) {
        ssize_t n = RPReadRaw(fd, p, len);
        if (n <= 0) return NO;
        p += n;
        len -= (size_t)n;
    }
    return YES;
}

static BOOL RPSOCKS5(int fd, NSString *host, NSInteger port) {
    uint8_t greet[3] = {0x05, 0x01, 0x00};
    if (!RPWriteRaw(fd, greet, sizeof(greet))) return NO;
    uint8_t greetr[2] = {0};
    if (!RPReadFull(fd, greetr, sizeof(greetr)) || greetr[0] != 0x05 || greetr[1] != 0x00) return NO;
    NSData *name = [host dataUsingEncoding:NSUTF8StringEncoding];
    if (name.length == 0 || name.length > 255) return NO;
    NSMutableData *req = [NSMutableData data];
    uint8_t hdr[4] = {0x05, 0x01, 0x00, 0x03};
    [req appendBytes:hdr length:4];
    uint8_t nlen = (uint8_t)name.length;
    [req appendBytes:&nlen length:1];
    [req appendData:name];
    uint8_t pb[2] = {(uint8_t)((port >> 8) & 0xff), (uint8_t)(port & 0xff)};
    [req appendBytes:pb length:2];
    if (!RPWriteRaw(fd, req.bytes, req.length)) return NO;
    uint8_t resp[4] = {0};
    if (!RPReadFull(fd, resp, sizeof(resp)) || resp[1] != 0x00) return NO;
    if (resp[3] == 0x01) {
        uint8_t skip[6];
        return RPReadFull(fd, skip, sizeof(skip));
    }
    if (resp[3] == 0x04) {
        uint8_t skip[18];
        return RPReadFull(fd, skip, sizeof(skip));
    }
    if (resp[3] == 0x03) {
        uint8_t ln = 0;
        if (!RPReadFull(fd, &ln, 1)) return NO;
        uint8_t skip[255 + 2];
        return RPReadFull(fd, skip, (size_t)ln + 2);
    }
    return NO;
}

static BOOL RPHTTPConnect(int fd, NSString *host, NSInteger port) {
    NSString *msg = [NSString stringWithFormat:@"CONNECT %@:%ld HTTP/1.1\r\nHost: %@:%ld\r\nProxy-Connection: keep-alive\r\n\r\n", host, (long)port, host, (long)port];
    NSData *bytes = [msg dataUsingEncoding:NSUTF8StringEncoding];
    if (!RPWriteRaw(fd, bytes.bytes, bytes.length)) return NO;
    NSMutableData *buf = [NSMutableData data];
    while (buf.length < 4096) {
        uint8_t tmp[512];
        ssize_t n = RPReadRaw(fd, tmp, sizeof(tmp));
        if (n <= 0) return NO;
        [buf appendBytes:tmp length:(NSUInteger)n];
        NSRange end = [buf rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0, buf.length)];
        if (end.location == NSNotFound) continue;
        NSString *head = [[NSString alloc] initWithBytes:buf.bytes length:end.location encoding:NSISOLatin1StringEncoding];
        NSArray *parts = [head componentsSeparatedByString:@" "];
        return parts.count >= 2 && [parts[1] integerValue] >= 200 && [parts[1] integerValue] < 300;
    }
    return NO;
}

static BOOL RPExtract(NSData *raw, BOOL eof, NSData **bodyOut, NSInteger *statusOut, NSString **locationOut, BOOL *doneOut) {
    *doneOut = NO;
    NSData *sep = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange hr = [raw rangeOfData:sep options:0 range:NSMakeRange(0, raw.length)];
    if (hr.location == NSNotFound) return YES;
    NSString *head = [[NSString alloc] initWithBytes:raw.bytes length:hr.location encoding:NSISOLatin1StringEncoding] ?: @"";
    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    if (lines.count) {
        NSArray *parts = [lines[0] componentsSeparatedByString:@" "];
        if (parts.count >= 2) *statusOut = [parts[1] integerValue];
    }
    NSInteger contentLength = -1;
    BOOL chunked = NO;
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:colon.location] lowercaseString];
        NSString *val = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([key isEqualToString:@"content-length"]) contentLength = [val integerValue];
        if ([key isEqualToString:@"transfer-encoding"] && [[val lowercaseString] rangeOfString:@"chunked"].location != NSNotFound) chunked = YES;
        if ([key isEqualToString:@"location"]) *locationOut = val;
    }
    NSUInteger bodyStart = NSMaxRange(hr);
    if (chunked) {
        NSMutableData *out = [NSMutableData data];
        NSUInteger i = bodyStart;
        NSData *nl = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        while (i < raw.length) {
            NSRange lineEnd = [raw rangeOfData:nl options:0 range:NSMakeRange(i, raw.length - i)];
            if (lineEnd.location == NSNotFound) return YES;
            NSString *hex = [[NSString alloc] initWithBytes:(const uint8_t *)raw.bytes + i length:lineEnd.location - i encoding:NSASCIIStringEncoding];
            NSString *hexOnly = [[hex componentsSeparatedByString:@";"] firstObject];
            hexOnly = [hexOnly stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            char *end = NULL;
            unsigned long sz = strtoul(hexOnly.UTF8String ?: "", &end, 16);
            if (end == hexOnly.UTF8String) return NO;
            i = NSMaxRange(lineEnd);
            if (sz == 0) {
                *bodyOut = out;
                *doneOut = YES;
                return YES;
            }
            if (i + sz + 2 > raw.length) return YES;
            [out appendBytes:(const uint8_t *)raw.bytes + i length:sz];
            i += sz + 2;
        }
        return YES;
    }
    if (contentLength >= 0) {
        if (raw.length < bodyStart + (NSUInteger)contentLength) return YES;
        *bodyOut = [raw subdataWithRange:NSMakeRange(bodyStart, (NSUInteger)contentLength)];
        *doneOut = YES;
        return YES;
    }
    if (eof) {
        *bodyOut = bodyStart <= raw.length ? [raw subdataWithRange:NSMakeRange(bodyStart, raw.length - bodyStart)] : [NSData data];
        *doneOut = YES;
    }
    return YES;
}

static NSData *RPExchange(int fd, BOOL tls, NSString *peerName, NSString *hostHeader, NSString *path, NSString *method, NSData *bodyData, NSDictionary *headers, NSInteger *status, NSString **location, NSError **error) {
    SSLContextRef ssl = NULL;
    if (tls) {
        ssl = SSLCreateContext(kCFAllocatorDefault, kSSLClientSide, kSSLStreamType);
        if (!ssl) {
            RPSetError(error, RPErr(10, @"TLS 初始化失败"));
            return nil;
        }
        SSLSetIOFuncs(ssl, RPSSLRead, RPSSLWrite);
        SSLSetConnection(ssl, (SSLConnectionRef)(intptr_t)fd);
        SSLSetProtocolVersionMin(ssl, kTLSProtocol12);
        /* iOS 9.3 has no ISRG Root X1 / the 2024+ intermediates. System trust
           aborts the handshake for almost every current HTTPS host. */
        SSLSetSessionOption(ssl, kSSLSessionOptionBreakOnServerAuth, true);
        const char *peer = peerName.UTF8String ?: "";
        SSLSetPeerDomainName(ssl, peer, strlen(peer));
        OSStatus st = noErr;
        int authPasses = 0;
        for (;;) {
            st = SSLHandshake(ssl);
            if (st == errSSLWouldBlock) {
                if (!RPWaitSocket(fd, NO)) {
                    st = errSSLClosedAbort;
                    break;
                }
                continue;
            }
            if (st == errSSLPeerAuthCompleted || st == errSSLServerAuthCompleted) {
                if (++authPasses > 4) break;
                continue;
            }
            break;
        }
        if (st != noErr) {
            CFRelease(ssl);
            RPSetError(error, RPErr(st, RPTLSMessage(st)));
            return nil;
        }
    }
    NSString *userAgent = @"RemotePanel/2.0";
    if ([headers[@"User-Agent"] isKindOfClass:[NSString class]] && [(NSString *)headers[@"User-Agent"] length]) {
        userAgent = headers[@"User-Agent"];
    }
    NSString *verb = method.length ? method : @"GET";
    NSMutableString *req = [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@\r\nUser-Agent: %@\r\nAccept: */*\r\nConnection: close\r\n", verb, path.length ? path : @"/", hostHeader, userAgent];
    __block BOOL hasType = NO;
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSString class]]) return;
        NSString *lower = [key lowercaseString];
        if ([lower isEqualToString:@"user-agent"] || [lower isEqualToString:@"content-length"]) return;
        if ([lower isEqualToString:@"content-type"]) hasType = YES;
        [req appendFormat:@"%@: %@\r\n", key, obj];
    }];
    if (bodyData.length && !hasType) [req appendString:@"Content-Type: application/json\r\n"];
    if (bodyData.length) [req appendFormat:@"Content-Length: %lu\r\n", (unsigned long)bodyData.length];
    [req appendString:@"\r\n"];
    NSMutableData *reqBytes = [NSMutableData dataWithData:[req dataUsingEncoding:NSUTF8StringEncoding]];
    if (bodyData.length) [reqBytes appendData:bodyData];
    BOOL wrote = NO;
    if (ssl) {
        const uint8_t *p = reqBytes.bytes;
        size_t left = reqBytes.length;
        wrote = YES;
        while (left) {
            size_t processed = 0;
            OSStatus st = SSLWrite(ssl, p, left, &processed);
            if (st != noErr || processed == 0) { wrote = NO; break; }
            p += processed;
            left -= processed;
        }
    } else {
        wrote = RPWriteRaw(fd, reqBytes.bytes, reqBytes.length);
    }
    if (!wrote) {
        if (ssl) CFRelease(ssl);
        RPSetError(error, RPErr(11, @"发送请求失败"));
        return nil;
    }
    NSMutableData *raw = [NSMutableData data];
    NSData *body = nil;
    BOOL done = NO;
    NSInteger code = 0;
    NSString *loc = nil;
    while (raw.length < kRPMaxBody) {
        uint8_t tmp[8192];
        ssize_t n = -1;
        if (ssl) {
            size_t processed = 0;
            OSStatus st = SSLRead(ssl, tmp, sizeof(tmp), &processed);
            if (processed > 0) n = (ssize_t)processed;
            else if (st == errSSLWouldBlock) continue;
            else if (st == noErr || st == errSSLClosedGraceful || st == errSSLClosedNoNotify) n = 0;
            else {
                if (ssl) CFRelease(ssl);
                RPSetError(error, RPErr(st, [NSString stringWithFormat:@"读取中断 (%d)，已有 %lu 字节", (int)st, (unsigned long)raw.length]));
                return nil;
            }
        } else {
            if (!RPWaitSocket(fd, NO)) n = -1;
            else n = RPReadRaw(fd, tmp, sizeof(tmp));
        }
        BOOL eof = n <= 0;
        if (n > 0) [raw appendBytes:tmp length:(NSUInteger)n];
        BOOL ok = RPExtract(raw, eof, &body, &code, &loc, &done);
        if (!ok) {
            if (ssl) CFRelease(ssl);
            RPSetError(error, RPErr(12, @"响应无法解析"));
            return nil;
        }
        if (done || eof) break;
    }
    if (ssl) CFRelease(ssl);
    *status = code;
    if (location) *location = loc;
    if (!done) {
        RPSetError(error, RPErr(13, [NSString stringWithFormat:@"响应不完整（收到 %lu 字节）", (unsigned long)raw.length]));
        return nil;
    }
    return body ?: [NSData data];
}

static NSData *RPFetch(NSString *urlString, NSString *method, NSData *bodyData, NSString *proxy, NSDictionary *headers, NSTimeInterval timeout, NSInteger redirects, NSError **error) {
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        RPSetError(error, RPErr(1, @"接口地址无效"));
        return nil;
    }
    NSString *host = url.host;
    NSInteger port = url.port ? url.port.integerValue : ([scheme isEqualToString:@"https"] ? 443 : 80);
    NSString *path = url.path.length ? url.path : @"/";
    if (url.query.length) path = [path stringByAppendingFormat:@"?%@", url.query];
    BOOL tls = [scheme isEqualToString:@"https"];
    NSString *hostHeader = host;
    if ((tls && port != 443) || (!tls && port != 80)) {
        hostHeader = [NSString stringWithFormat:@"%@:%ld", host, (long)port];
    }
    int fd = -1;
    NSURL *proxyURL = proxy.length ? [NSURL URLWithString:proxy] : nil;
    NSString *pscheme = proxyURL.scheme.lowercaseString ?: @"";
    if (proxy.length && proxyURL.host.length == 0) {
        RPSetError(error, RPErr(2, @"代理地址无效"));
        return nil;
    }
    if (proxyURL.host.length) {
        NSInteger pport = proxyURL.port ? proxyURL.port.integerValue : ([pscheme hasPrefix:@"socks"] ? 1080 : 8080);
        fd = RPConnectHost(proxyURL.host, pport, timeout);
        if (fd < 0) {
            RPSetError(error, RPErr(3, @"代理连不上"));
            return nil;
        }
        BOOL tunneled = [pscheme hasPrefix:@"socks"] ? RPSOCKS5(fd, host, port) : RPHTTPConnect(fd, host, port);
        if (!tunneled) {
            close(fd);
            RPSetError(error, RPErr(4, @"代理隧道失败"));
            return nil;
        }
    } else {
        fd = RPConnectHost(host, port, timeout);
        if (fd < 0) {
            RPSetError(error, RPErr(5, @"网站连不上"));
            return nil;
        }
    }
    NSInteger status = 0;
    NSString *location = nil;
    NSData *body = RPExchange(fd, tls, host, hostHeader, path, method, bodyData, headers, &status, &location, error);
    close(fd);
    if (!body) return nil;
    if (status >= 300 && status < 400 && location.length && redirects < 4) {
        NSURL *next = [NSURL URLWithString:location relativeToURL:url];
        if (next.absoluteString.length) return RPFetch(next.absoluteString, method, bodyData, proxy, headers, timeout, redirects + 1, error);
    }
    if (status >= 400 || status == 0) {
        RPSetError(error, RPErr(status ?: 6, [NSString stringWithFormat:@"HTTP %ld", (long)status]));
        return nil;
    }
    if (body.length == 0) {
        RPSetError(error, RPErr(7, @"空响应"));
        return nil;
    }
    return body;
}

@implementation RPNet

+ (NSData *)syncGET:(NSString *)urlString
              proxy:(NSString *)proxy
            headers:(NSDictionary *)headers
            timeout:(NSTimeInterval)timeout
              error:(NSError **)error {
    NSTimeInterval limit = timeout > 0 ? timeout : 20;
    return RPFetch(urlString, @"GET", nil, proxy, headers, limit, 0, error);
}

+ (NSData *)syncPOST:(NSString *)urlString
                body:(NSData *)body
               proxy:(NSString *)proxy
             headers:(NSDictionary *)headers
             timeout:(NSTimeInterval)timeout
               error:(NSError **)error {
    NSTimeInterval limit = timeout > 0 ? timeout : 40;
    return RPFetch(urlString, @"POST", body ?: [NSData data], proxy, headers, limit, 0, error);
}

+ (void)GET:(NSString *)urlString
      proxy:(NSString *)proxy
    headers:(NSDictionary *)headers
    timeout:(NSTimeInterval)timeout
 completion:(void (^)(NSData *data, NSError *error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *err = nil;
        NSData *data = [self syncGET:urlString proxy:proxy headers:headers timeout:timeout error:&err];
        if (completion) completion(data, err);
    });
}

@end
